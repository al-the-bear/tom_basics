param(
  [string]$Platform
)

$ErrorActionPreference = 'Stop'

# Run everything from the script directory so `dart` resolves this package's
# pubspec.yaml (mirrors `cd "$SCRIPT_DIR"` in bootstrap_binaries.sh).
Set-Location $PSScriptRoot

function Write-Warn($msg) {
  Write-Host "[warn] $msg" -ForegroundColor Yellow
}

function Ask-YesNo($prompt) {
  while ($true) {
    $r = Read-Host "$prompt [y/n]"
    if ($r -match '^(?i)y(es)?$') { return $true }
    if ($r -match '^(?i)n(o)?$') { return $false }
  }
}

function Detect-Platform {
  param([string]$InputPlatform)
  if ($InputPlatform) { return $InputPlatform }

  if ($IsWindows -or $env:OS -eq 'Windows_NT') {
    if ([Environment]::Is64BitOperatingSystem) { return 'win32-x64' }
    return 'win32-x86'
  }

  return 'win32-x64'
}

# Always use the real system git — never a buildkit-compiled wrapper that may
# have been placed in TOM_BINARY_PATH (which this script adds to PATH below).
# Check well-known install locations first, then fall back to PATH.
function Resolve-SystemGit {
  $candidates = @(
    'C:\Program Files\Git\cmd\git.exe',
    'C:\Program Files\Git\bin\git.exe',
    'C:\Program Files (x86)\Git\cmd\git.exe'
  )
  foreach ($c in $candidates) {
    if (Test-Path $c) { return $c }
  }
  $cmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  throw 'git not found on the system. Please install git first.'
}

$systemGit = Resolve-SystemGit

$Platform = Detect-Platform -InputPlatform $Platform
Write-Host "=== Bootstrap tom_build_kit binaries ($Platform) ==="

$userProfile = [Environment]::GetFolderPath('UserProfile')
$tacLink = Join-Path $userProfile 'tac'
$workspaceHint = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path

$envChanged = $false
$pathChanged = $false

if (-not (Test-Path $tacLink)) {
  Write-Warn "No $tacLink symlink exists."
  $target = Read-Host "Enter workspace directory for $tacLink [$workspaceHint]"
  if (-not $target) { $target = $workspaceHint }
  New-Item -ItemType SymbolicLink -Path $tacLink -Target $target | Out-Null
  Write-Host "Created symlink: $tacLink -> $target"
}

$tomBinaries = Join-Path $tacLink 'tom_binaries'
if (-not (Test-Path $tomBinaries)) {
  Write-Warn "No tom_binaries directory found in $tacLink"
  if (Ask-YesNo "Clone tom_binaries into $tomBinaries?") {
    & $systemGit clone https://github.com/al-the-bear/tom_binaries.git $tomBinaries
    if ($LASTEXITCODE -ne 0) { throw 'git clone of tom_binaries failed.' }
  } else {
    throw 'Aborted: tom_binaries repository is required.'
  }
}

$defaultTomBinaryPath = Join-Path $tomBinaries 'tom'
$tomBinaryPath = $env:TOM_BINARY_PATH
if (-not $tomBinaryPath) {
  Write-Warn 'TOM_BINARY_PATH is not defined.'
  if (Ask-YesNo "Set TOM_BINARY_PATH to $defaultTomBinaryPath for current user?") {
    setx TOM_BINARY_PATH "$defaultTomBinaryPath" | Out-Null
    $env:TOM_BINARY_PATH = $defaultTomBinaryPath
    $tomBinaryPath = $defaultTomBinaryPath
    $envChanged = $true
    Write-Warn 'User environment updated. Existing terminals/apps may need restart.'
  } else {
    throw 'Aborted: TOM_BINARY_PATH is required.'
  }
}

$platformDir = Join-Path $tomBinaryPath $Platform
if (-not (Test-Path $platformDir)) {
  Write-Warn "Missing platform directory: $platformDir"
  if (Ask-YesNo "Create $platformDir?") {
    New-Item -ItemType Directory -Path $platformDir -Force | Out-Null
  } else {
    throw 'Aborted: platform output directory is required.'
  }
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if ($userPath -notlike "*$platformDir*") {
  Write-Warn "$platformDir is not in user PATH"
  if (Ask-YesNo "Add $platformDir to user PATH?") {
    $newPath = if ($userPath) { "$userPath;$platformDir" } else { $platformDir }
    setx PATH "$newPath" | Out-Null
    $env:Path = "$env:Path;$platformDir"
    $pathChanged = $true
    Write-Warn 'PATH updated for user profile. Existing terminals/apps may need restart.'
  }
}

Write-Host "Output directory: $platformDir"

# --- Resolve dependencies ------------------------------------------------
# Clear stale Dart tool cache to avoid errors from old package resolutions.
if (Test-Path '.dart_tool') {
  Write-Host 'Clearing stale .dart_tool cache...'
  Remove-Item -Recurse -Force '.dart_tool'
}

Write-Host 'Resolving dependencies...'
dart pub get
if ($LASTEXITCODE -ne 0) {
  throw 'dart pub get failed. Check pubspec.yaml and network connectivity.'
}

if (-not (Test-Path 'lib/src/version.versioner.dart')) {
@'
// GENERATED FILE - DO NOT EDIT
// Bootstrap stub - will be regenerated

class BuildkitVersionInfo {
  BuildkitVersionInfo._();
  static const String version = '0.0.0';
  static const String buildTime = '1970-01-01T00:00:00.000000Z';
  static const String gitCommit = 'bootstrap';
  static const int buildNumber = 0;
  static const String dartSdkVersion = 'unknown';
  static String get versionShort => '$version+$buildNumber';
  static String get versionMedium => '$version+$buildNumber.$gitCommit ($buildTime)';
  static String get versionLong => '$version+$buildNumber.$gitCommit ($buildTime) [Dart $dartSdkVersion]';
}
'@ | Set-Content -Path 'lib/src/version.versioner.dart' -Encoding UTF8
}

# Versioner is best-effort during bootstrap: a failure must not abort the build,
# we simply keep whatever version file already exists.
Write-Host 'Running versioner...'
$env:TOM_BOOTSTRAP_ALLOW_MISSING_SETUP = '1'
try {
  dart run bin/buildkit.dart --scan . --no-recursive :versioner --variable-prefix buildkit
  if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
} catch {
  Write-Warn "Versioner step failed during bootstrap ($_); continuing with existing version file."
} finally {
  Remove-Item Env:\TOM_BOOTSTRAP_ALLOW_MISSING_SETUP -ErrorAction SilentlyContinue
}

$tools = @('buildkit', 'findproject')
$compiled = 0
$failed = @()
Write-Host 'Compiling tools...'
foreach ($tool in $tools) {
  $entry = "bin/$tool.dart"
  if (-not (Test-Path $entry)) {
    Write-Warn "$entry not found, skipping"
    continue
  }
  $outName = if ($Platform -like 'win32-*') { "$tool.exe" } else { $tool }
  $outPath = Join-Path $platformDir $outName
  Write-Host "  Compiling $tool"
  # Native command failures don't honour $ErrorActionPreference, so check
  # $LASTEXITCODE explicitly and record (don't abort) so every tool is tried.
  try {
    dart compile exe $entry -o $outPath
    if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
    $compiled++
  } catch {
    Write-Warn "Failed to compile $tool ($_)"
    $failed += $tool
  }
}

# Create 'bk' convenience pointer for buildkit (symlink if allowed, else copy).
$buildkitOut = Join-Path $platformDir 'buildkit.exe'
$bkOut = Join-Path $platformDir 'bk.exe'
if ((Test-Path $buildkitOut) -and (-not (Test-Path $bkOut))) {
  try {
    New-Item -ItemType SymbolicLink -Path $bkOut -Target $buildkitOut -ErrorAction Stop | Out-Null
    Write-Host '  Created symlink: bk.exe -> buildkit.exe'
  } catch {
    Copy-Item $buildkitOut $bkOut
    Write-Host '  Created bk.exe (copy of buildkit.exe; symlink unavailable)'
  }
}

Write-Host ''
if ($failed.Count -gt 0) {
  Write-Host "=== Bootstrap INCOMPLETE: $compiled compiled, $($failed.Count) failed ($($failed -join ', ')) ===" -ForegroundColor Red
  Write-Host 'Check the errors above and retry.'
  exit 1
}
Write-Host '=== Bootstrap complete ==='
Write-Host "Compiled $compiled tools to $platformDir"

if ($envChanged -or $pathChanged) {
  Write-Host ''
  Write-Host '############################################################' -ForegroundColor Red
  Write-Host '# ALERT: Shell/environment settings were changed.          #' -ForegroundColor Red
  Write-Host '# Restart terminals and apps to ensure setup is available. #' -ForegroundColor Red
  Write-Host '############################################################' -ForegroundColor Red
}
