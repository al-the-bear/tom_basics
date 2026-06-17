# Tom Build Kit — Tools User Guide

Comprehensive reference for the individual build tools in the `tom_build_kit` package.

For the BuildKit pipeline orchestrator, see [buildkit_user_guide.md](buildkit_user_guide.md).

## Related Documentation

This package extends the shared infrastructure from **tom_build_base**:

- [CLI Tools Navigation](../../basics/tom_build_base/doc/cli_tools_navigation.md) — Standard CLI commands, execution modes, and navigation options
- [Build Base User Guide](../../basics/tom_build_base/doc/build_base_user_guide.md) — V2 Tool Framework, configuration loading, project discovery
- [Modes and Placeholders](../../basics/tom_build_base/doc/modes_and_placeholders.md) — Placeholder types, resolution order, and mode-specific defines
- [Multi-Workspace Pipelines, Macros, and Defines](../../basics/tom_build_base/doc/multiws_pipelines_macros_defines.md) — Pipeline system, runtime macros, persistent defines
- [Tool Inheritance and Nesting](../../basics/tom_build_base/doc/tool_inheritance_and_nesting.md) — copyWith patterns and nested tool wiring

---

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Common CLI Options](#common-cli-options)
  - [Version Flag](#version-flag)
  - [Project Discovery](#project-discovery)
  - [Exclusion Filtering](#exclusion-filtering)
- [Configuration Files](#configuration-files)
  - [buildkit_master.yaml](#bk_masteryaml)
  - [buildkit.yaml](#bkyaml)
  - [build.yaml](#buildyaml)
  - [buildkit_skip.yaml](#bk_skipyaml)
- [Config Merge Precedence](#config-merge-precedence)
- [Tools](#tools)
  - [Versioner](#versioner)
  - [BumpVersion](#bumpversion)
  - [Cleanup](#cleanup)
  - [Compiler](#compiler)
  - [Runner](#runner)
  - [Dependencies](#dependencies)
  - [Pub Get](#pub-get)
  - [Publisher](#publisher)
  - [DCli](#dcli)
  - [Execute](#execute)
- [Git Tools](#git-tools)
  - [Git Traversal Modes](#git-traversal-modes)
  - [GitStatus](#gitstatus)
  - [GitCommit](#gitcommit)
  - [GitPull](#gitpull)
  - [GitBranch](#gitbranch)
  - [GitTag](#gittag)
  - [GitClean](#gitclean)
  - [GitCheckout](#gitcheckout)
  - [GitReset](#gitreset)
  - [GitSync](#gitsync)

---

## Overview

Tom Build Kit provides seven CLI tools and additional built-in commands that share a common infrastructure for project discovery, argument parsing, and configuration loading:

| Tool | Binary | Purpose |
|------|--------|---------|
| **Versioner** | `versioner` | Generate `version.versioner.dart` files with build metadata |
| **BumpVersion** | `bumpversion` | Bump `pubspec.yaml` versions across projects |
| **Cleanup** | `cleanup` | Remove generated and temporary files with safety checks |
| **Compiler** | `compiler` | Cross-platform Dart compilation with pre/post-compile phases |
| **Runner** | `runner` | `build_runner` wrapper with builder filtering |
| **Dependencies** | `dependencies` | Dependency tree visualization |
| **Pub Get** | via `:pubget` | Run `dart pub get` across projects with output filtering |
| **Pub Update** | via `:pubupdate` | Run `dart pub upgrade` across projects with output filtering |
| **Publisher** | `publisher` | Show publishing status for all projects |
| **DCli** | via `:dcli` | Execute Dart scripts/expressions via dcli with path resolution |
| **Execute** | via `:execute` | Run shell commands in each folder with placeholder substitution |
| **GitStatus** | `gitstatus` | Show git status for all repositories |
| **GitCommit** | `gitcommit` | Commit and push all repositories |
| **GitPull** | `gitpull` | Pull latest from all repositories |
| **GitBranch** | `gitbranch` | Branch management across repositories |
| **GitTag** | `gittag` | Tag management across repositories |
| **GitClean** | `gitclean` | Clean untracked files from repositories |
| **GitCheckout** | `gitcheckout` | Checkout branches/tags across repositories |
| **GitReset** | `gitreset` | Reset repositories to specific state |
| **GitSync** | `gitsync` | Sync (fetch + merge/rebase) all repositories |

All tools (except Pub Get) inherit from `ToolBase`, sharing project discovery, exclusion filtering, and configuration loading. They can be invoked standalone or through the [BuildKit orchestrator](buildkit_user_guide.md).

---

## Installation

Each tool has a standalone executable:

```bash
dart run tom_build_kit:versioner [options]
dart run tom_build_kit:bumpversion [options]
dart run tom_build_kit:cleanup [options]
dart run tom_build_kit:compiler [options]
dart run tom_build_kit:runner [options]
dart run tom_build_kit:dependencies [options]
```

Or compile to native executables:

```bash
dart compile exe bin/versioner.dart -o versioner
dart compile exe bin/cleanup.dart -o cleanup
# etc.
```

Via the BuildKit orchestrator:

```bash
buildkit :versioner [options]
buildkit :cleanup [options]
```

---

## Common CLI Options

All ToolBase-derived tools share these options:

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Show help text |
| `--verbose` | `-v` | Verbose output |
| `--project <path>` | `-p` | Project directory or glob pattern |
| `--scan <dir>` | `-s` | Scan directory for projects |
| `--recursive` | `-r` | Scan recursively into subdirectories |
| `--exclude <pattern>` | `-x` | Exclude patterns — path-based globs (multi-option) |
| `--exclude-projects <pattern>` | — | Exclude projects by name or path (multi-option) |
| `--recursion-exclude <pattern>` | — | Exclude patterns during recursive scanning (multi-option) |
| `--list` | `-l` | List matching projects without processing them |
| `--show` | — | Show configuration for matched projects |
| `--dry-run` | `-n` | Show what would be done without making changes |
| `--modes <mode>` | — | Active modes for mode-specific defines (e.g., `DEV,CI`) |
| `--nested` | — | Run in nested mode — skip traversal, single-project execution |
| `--dump-definitions` | — | Dump complete tool definition as YAML |

All tools also support `help <topic>` to display built-in help topics (defines, macros, pipelines, placeholders, wiring). See the [BuildKit User Guide](buildkit_user_guide.md#help-topics) for details.

### Version Flag

All tools support `version`, `--version`, or `-version` as the **first** argument:

```bash
versioner --version
# Output: versioner 1.0.0+4.b54e489 (2026-02-07T09:54:50.320327Z) [Dart 3.10.4]
```

### Project Discovery

Tools find projects through three mechanisms:

**Single project:**

```bash
versioner --project ./my_package
versioner --project _build
```

**Glob pattern:**

```bash
versioner --project "tom_*"
versioner --project "xternal/tom_module_basics/*"
```

**Directory scan:**

```bash
versioner --scan . --recursive
versioner -s . -r
```

When neither `--project` nor `--scan` is specified, tools operate on the current directory.

### Exclusion Filtering

Three levels of exclusion are available:

**Path-based exclusion (`--exclude`):**

```bash
versioner --scan . -r --exclude "zom_*" --exclude "xternal/**"
```

**Project name/path exclusion (`--exclude-projects`):**

```bash
# By folder basename (no / in pattern)
versioner --scan . -r --exclude-projects "zom_*"

# By workspace-relative path (contains / or **)
versioner --scan . -r --exclude-projects "xternal/tom_module_basics/*"

# Both patterns combined
versioner --scan . -r --exclude-projects "zom_*" --exclude-projects "core/*"
```

Pattern type is auto-detected:

- Patterns without `/` or `**` → match **folder basename** only
- Patterns with `/` or `**` → match **workspace-relative path**

**Master YAML exclusion:** Additional `exclude-projects` patterns from the `navigation:` section of `buildkit_master.yaml` are merged automatically.

**Skip marker file:** Projects containing `buildkit_skip.yaml` are skipped. If a parent directory contains the skip file, all child projects are also skipped.

---

## Configuration Files

### buildkit_master.yaml

Workspace-level configuration file at the workspace root. Contains pipeline definitions and global navigation settings:

```yaml
# Global project exclusion
navigation:
  exclude-projects:
    - zom_*
    - "xternal/tom_module_d4rt/*"

# Pipeline definitions (see buildkit_user_guide.md)
buildkit:
  pipelines:
    build:
      core:
        - commands:
            - versioner
            - compiler

# Workspace-level tool defaults
versioner:
  variable-prefix: testDefault
  output: lib/src/version.versioner.dart
```

### buildkit.yaml

Project-level configuration file in each project directory. Overrides workspace defaults:

```yaml
# Versioner config
versioner:
  output: lib/src/version.versioner.dart
  includeGitCommit: true
  variable-prefix: tomTools

# Cleanup config
cleanup:
  cleanup:
    - build
    - .dart_tool/build
    - "**/*.g.dart"
  excludes:
    - lib/src/version.versioner.dart
  protected-folders:
    - lib/src

# Compiler config
compiler:
  scan: .
  recursive: true

# Build runner config
build_runner:
  command: build
  delete-conflicting: true
  include-builders:
    - tom_build_kit
```

### build.yaml

Standard `build_runner` configuration file. Used by the builder variants and read by CLI tools for per-project config:

```yaml
targets:
  $default:
    builders:
      tom_build_kit:version_builder:
        enabled: true
        options:
          output: lib/src/version.versioner.dart
          includeGitCommit: true

      tom_build_kit:compiler_builder:
        enabled: true
        options:
          compiles:
            - files: [bin/my_tool.dart]
              targets: [linux-x64, darwin-arm64]
              commandlines:
                - dart compile exe ${file} -o build/${file.name}_${target-platform-vs}

      tom_build_kit:cleanup_builder:
        enabled: true
        options:
          cleanup:
            - build
            - .dart_tool/build
          excludes:
            - lib/src/version.versioner.dart
```

### buildkit_skip.yaml

A marker file (contents are ignored). When present in a directory, that directory and all subdirectories are excluded from all tool processing.

```bash
# Exclude a submodule from all tools
touch xternal/tom_module_d4rt/buildkit_skip.yaml
```

---

## Config Merge Precedence

Configuration is loaded in layers. Higher-priority layers override lower-priority ones:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 (highest) | **CLI arguments** | Command-line flags and options |
| 2 | **Project `buildkit.yaml`** | Per-project overrides |
| 3 | **Project `build.yaml`** | Builder-specific options |
| 4 (lowest) | **Workspace `buildkit.yaml` / `buildkit_master.yaml`** | Workspace-level defaults |

**Merge rules:**

- **Scalar fields** (output, variable-prefix, command): higher priority wins when non-null
- **Boolean fields** (verbose, recursive): OR-combined; `includeGitCommit` uses caller's value
- **List fields** (exclude, protected-folders, recursion-exclude): merged additively (union of all levels)
- **Cleanup sections**, **compile sections**: higher priority wins if non-empty (not merged)

---

## Tools

### Versioner

Generates `version.versioner.dart` files with build metadata from `pubspec.yaml`, git state, and Dart SDK info.

**Usage:**

```bash
versioner [common-options] [tool-options]
buildkit :versioner [tool-options]
```

**Tool-specific options:**

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--output <path>` | `-o` | `lib/src/version.versioner.dart` | Output file path relative to project |
| `--no-git` | — | `false` | Skip git commit hash |
| `--version <ver>` | — | from pubspec | Override version string |
| `--variable-prefix <name>` | — | — | Prefix for generated class name |

**buildkit.yaml keys (`versioner:`):**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `output` | String | `lib/src/version.versioner.dart` | Output file path |
| `includeGitCommit` | bool | `true` | Include git commit hash |
| `version` | String | from pubspec | Override version string |
| `variable-prefix` | String | — | Prefix for generated class name |

**Generated output format:**

The class name is derived from the `variable-prefix`: prefix `tomTools` → class `TomToolsVersionInfo`. Without a prefix, the default is `TomVersionInfo`.

```dart
// GENERATED FILE - DO NOT EDIT
// Generated by versioner at 2026-02-07T09:54:50.320327Z

class TomToolsVersionInfo {
  TomToolsVersionInfo._();

  static const String version = '1.0.0';
  static const String buildTime = '2026-02-07T09:54:50.320327Z';
  static const String gitCommit = 'b54e489';
  static const int buildNumber = 4;
  static const String dartSdkVersion = '3.10.4';

  static String get versionShort => '$version+$buildNumber';
  static String get versionMedium =>
      '$version+$buildNumber.$gitCommit ($buildTime)';
  static String get versionLong =>
      '$version+$buildNumber.$gitCommit ($buildTime) [Dart $dartSdkVersion]';
}
```

**Build state:** The build number is tracked in `tom_build_state.json` in each project directory and auto-increments on each run.

**Config merge example:**

With workspace `buildkit_master.yaml`:

```yaml
versioner:
  variable-prefix: testDefault
```

And project `buildkit.yaml`:

```yaml
versioner:
  variable-prefix: tomTools
```

Running `versioner --project _build` uses `tomTools` (project overrides workspace).  
Running `versioner --project _build --variable-prefix myCustom` uses `myCustom` (CLI overrides both).

---

### BumpVersion

Bumps `pubspec.yaml` versions across multiple projects with optional versioner integration.

**Usage:**

```bash
bumpversion [common-options] [tool-options]
buildkit :bumpversion [tool-options]
```

**Tool-specific options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--minor <projects>` | — | Projects to bump minor version (comma-separated, multi-option) |
| `--major <projects>` | — | Projects to bump major version (comma-separated, multi-option) |
| `--versioner` | `false` | Run versioner after bumping to regenerate version files |

**Bump types:**

| Type | Example | Trigger |
|------|---------|---------|
| Patch (default) | `1.2.3` → `1.2.4` | All projects not listed in `--minor` or `--major` |
| Minor | `1.2.3` → `1.3.0` | `--minor my_package` |
| Major | `1.2.3` → `2.0.0` | `--major my_package` |

**Project matching:** The `--minor` and `--major` values match against the project's folder name or relative path suffix. Comma-separated lists are expanded.

**Build state reset:** After bumping, `tom_build_state.json` is reset to `buildNumber: 0` so the next versioner run starts fresh.

**Versioner integration:** With `--versioner`, automatically runs the versioner tool after bumping. The flags `--scan`, `--project`, `--recursive`, `--verbose`, `--dry-run`, and `--exclude` are forwarded.

**Examples:**

```bash
# Patch bump all discovered projects
bumpversion --scan . -r

# Minor bump for specific projects, patch for the rest
bumpversion --scan . -r --minor tom_core,tom_basics

# Major bump with versioner regeneration
bumpversion --project my_app --major my_app --versioner

# Dry run to see planned bumps
bumpversion --scan . -r --dry-run
```

---

### Cleanup

Removes generated and temporary files from Dart projects with two-pass safety checking and protected folder enforcement.

**Usage:**

```bash
cleanup [common-options] [tool-options]
buildkit :cleanup [tool-options]
```

**Tool-specific options:**

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--force` | `-f` | `false` | Skip safety check on file count |
| `--max-files <n>` | `-m` | `100` | Maximum files to delete without `--force` |

**buildkit.yaml keys (`cleanup:`):**

| Key | Type | Description |
|-----|------|-------------|
| `cleanup` | List | Cleanup sections (globs and per-section excludes) |
| `excludes` | List\<String\> | Global exclude patterns |
| `protected-folders` | List\<String\> | Additional folders to never delete from |

**Cleanup section formats:**

```yaml
cleanup:
  cleanup:
    # Simple glob string
    - build
    - .dart_tool/build
    - "**/*.freezed.dart"

    # Map with per-section excludes
    - globs: ["**/*.g.dart"]
      excludes: ["lib/src/version.versioner.dart"]

  excludes:
    - lib/src/version.versioner.dart

  protected-folders:
    - lib/src
```

**Safety features:**

| Feature | Description |
|---------|-------------|
| Two-pass operation | First pass collects files to delete; second pass deletes them |
| File count limit | Aborts if file count exceeds `--max-files` (default 100) unless `--force` is set |
| Protected folders | Built-in set (`.git`, `.github`, `lib`, `bin`) is never deleted from. `protected-folders` in config are additive — you can add but not reduce the built-in set |
| Dry-run | `--dry-run` lists files that would be deleted without deleting |

**Protected folder matching:**

- Single-segment names (e.g., `lib`) → matched against individual path segments
- Multi-segment paths (e.g., `lib/src`) → matched via glob pattern `**/{folder}/**`

**Examples:**

```bash
# Preview what would be deleted
cleanup --project _build --dry-run

# Delete with safety check
cleanup --project _build

# Force delete (skip file count limit)
cleanup --scan . -r --force

# Custom max-files threshold
cleanup --project _build --max-files 50
```

---

### Compiler

Cross-platform Dart compilation with configurable pre-compile and post-compile command sequences, placeholder resolution, and platform filtering.

**Usage:**

```bash
compiler [common-options] [tool-options]
buildkit :compiler [tool-options]
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--targets <list>` | `-t` | Target platforms to compile for (comma-separated) |
| `--executable <list>` | `-e` | Filter to specific executable file(s) (comma-separated) |

The `--executable` option filters which files are compiled. Only files whose basename matches one of the specified names will be processed:

```bash
# Compile only buildkit.dart
compiler --project _build --executable buildkit.dart

# Compile multiple specific files
compiler --project _build --executable buildkit.dart,compiler.dart

# Combine with target filtering
compiler --project _build --executable buildkit.dart --targets linux-x64
```

**Configuration** is read from `build.yaml` under the `tom_build_kit:compiler_builder:` key:

```yaml
targets:
  $default:
    builders:
      tom_build_kit:compiler_builder:
        enabled: true
        options:
          precompile:
            - platforms: [darwin-arm64]
              commandlines:
                - echo "Pre-compile for macOS ARM64"
          compiles:
            - files:
                - bin/my_tool.dart
              targets:
                - linux-x64
                - darwin-arm64
                - windows-x64
              commandlines:
                - dart compile exe ${file} -o build/${file.name}_${target-platform-vs} --target=${target-platform}
          postcompile:
            - commandlines:
                - echo "Build complete"
```

**Compilation phases:** `precompile` → `compiles` → `postcompile` (executed in order).

**Section types:**

| Section | Purpose | Key Fields |
|---------|---------|------------|
| `precompile` | Commands before compilation | `commandlines`, `platforms` |
| `compiles` | Compilation steps | `files`, `targets`, `commandlines`, `platforms` |
| `postcompile` | Commands after compilation | `commandlines`, `platforms` |

Each section also supports `command:` (built-in tool reference) as an alternative to `commandlines:` (mutually exclusive).

**Placeholders in command lines:**

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `${file}` / `${file.path}` | Source file path | `bin/my_tool.dart` |
| `${file.name}` | File name without extension | `my_tool` |
| `${file.basename}` | File name with extension | `my_tool.dart` |
| `${file.extension}` | File extension | `.dart` |
| `${file.dir}` | File directory | `bin` |
| `%{target-os}` | Target OS | `macos`, `linux`, `windows` |
| `%{target-arch}` | Target architecture | `x64`, `arm64` |
| `%{dart-target-os}` | Target OS for `dart compile --target-os` | `macos`, `linux`, `windows` |
| `%{dart-target-arch}` | Target arch for `dart compile --target-arch` | `x64`, `arm64`, `arm` |
| `%{target-platform}` | Dart target format | `macos-arm64` |
| `%{target-platform-vs}` | VS Code format | `darwin-arm64` |
| `%{current-os}` | Current OS | `macos` |
| `%{current-arch}` | Current architecture | `arm64` |
| `%{current-platform}` | Current platform (Dart format) | `macos-arm64` |
| `%{current-platform-vs}` | Current platform (VS Code format) | `darwin-arm64` |

Bracket format is also supported: `[file]`, `[target-os]`, `[target-platform-vs]`, etc.

> **`dart compile exe` cross-compilation:** Use `%{dart-target-os}` and `%{dart-target-arch}` for the `--target-os` and `--target-arch` flags. These are explicit placeholders — no flags are injected automatically. Example:
> ```yaml
> commandline:
>   - dart compile exe %{file} --target-os=%{dart-target-os} --target-arch=%{dart-target-arch} -o $TOM_BINARY_PATH/%{target-platform-vs}/%{file.name}
> ```

Environment variables are resolved using `$VAR` or `[VAR]` syntax: `$HOME`, `$USER`, `$PATH`, etc.

**Multi-line scripts and stdin piping:**

Command line entries support multi-line content using YAML literal block scalars (`|`). Multi-line commands are executed as a single script via `sh -c`:

```yaml
precompile:
  - commandlines:
      - |
        echo "Preparing build..."
        mkdir -p build/${target-platform-vs}
        if [ -f "build/cache" ]; then
          echo "Using cached artifacts"
        fi
```

Use the `stdin` prefix to pipe content to a command's stdin. The first line specifies the command; subsequent lines are the stdin content:

```yaml
precompile:
  - commandlines:
      - |
        stdin dcli
        import 'dart:io';
        void main() {
          print('Pre-compile setup via DartScript');
        }
```

> **Note:** Variable expansion (`${file}`, `${target-os}`, etc.) is applied to the command line only, not to stdin content. This avoids conflicts with language-specific `$` syntax (e.g., Dart string interpolation).

**Platform filtering:**

Two independent platform filters exist:

- **`platforms:`** on a section → restricts which **host OS** the section runs on
- **`targets:`** on a compile section → restricts which **target platforms** are compiled for
- **`--targets` CLI option** → further restricts the `targets:` list

```yaml
precompile:
  - platforms: [darwin-arm64, darwin-x64]    # Only runs on macOS
    commandlines:
      - codesign --remove-signature build/my_tool
```

Platform aliases: `macos`/`darwin`, `linux`, `windows`/`win32`. Glob patterns are supported: `darwin-*`, `linux-*`.

**Examples:**

```bash
# Compile all configured targets
compiler --project _build

# Compile only for Linux x64
compiler --project _build --targets linux-x64

# Compile only specific executables
compiler --project _build --executable buildkit.dart

# Compile specific files for specific target
compiler --project _build --executable buildkit.dart,compiler.dart --targets linux-x64

# Dry-run to see planned commands
compiler --project _build --dry-run

# Show compiler config
compiler --project _build --show
```

---

### Runner

`build_runner` wrapper with multi-project scanning and builder include/exclude filtering.

**Usage:**

```bash
runner [common-options] [tool-options]
buildkit :runner [tool-options]
```

**Tool-specific options:**

| Flag | Short | Default | Description |
|------|-------|---------|-------------|
| `--command <cmd>` | `-c` | `build` | Build runner command: `build`, `watch`, or `clean` |
| `--include-builders <list>` | `-i` | — | Include only these builders (multi-option) |
| `--exclude-builders <list>` | — | — | Exclude these builders (multi-option) |
| `--config <name>` | — | — | Build runner config name |
| `--release` | — | `false` | Build in release mode |
| `--delete-conflicting` | — | `true` | Delete conflicting outputs (negatable) |

**buildkit.yaml keys (`build_runner:`):**

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `command` | String | `build` | Build runner command |
| `delete-conflicting` | bool | `true` | Delete conflicting outputs |
| `config` | String | — | Build runner config name |
| `release` | bool | `false` | Release mode |
| `include-builders` | List\<String\> | — | Builder include filter |
| `exclude-builders` | List\<String\> | — | Builder exclude filter |

**Builder filter precedence (3 levels):**

| Priority | Source |
|----------|--------|
| 1 (highest) | CLI: `--include-builders` / `--exclude-builders` |
| 2 | Project `buildkit.yaml` → `build_runner` section |
| 3 (lowest) | Workspace `buildkit.yaml` → `build_runner` section |

The effective filter level is the **first level** with a non-empty include or exclude list.

**build.yaml builder filter config:**

An additional builder filter can be configured per-project in `build.yaml` under the `tom_build_kit:` key:

```yaml
tom_build_kit:
  build_runner:
    include-builders:
      - json_serializable
      - freezed
```

**Builder matching** uses fuzzy substring matching: `json_serializable` matches `json_serializable:json_serializable` and vice versa. Non-matching builders are disabled via `--define=<builder>=enabled=false`.

**Project detection:** Runner only processes projects that have **both** `pubspec.yaml` and `build.yaml`.

**Examples:**

```bash
# Build with code generation
runner --project _build

# Clean build artifacts
runner --project _build --command clean

# Only run json_serializable builder
runner --project _build --include-builders json_serializable

# Show runner config and builder list
runner --project _build --show

# Dry-run to see planned build_runner command
runner --project _build --dry-run
```

---

### Dependencies

Dependency tree visualization for Dart projects. Reads `pubspec.yaml` and `pubspec_overrides.yaml`.

**Usage:**

```bash
dependencies [common-options] [tool-options]
buildkit :dependencies [tool-options]
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--dev` | `-d` | Show only dev dependencies |
| `--all` | `-a` | Show all dependency types (normal + dev) |
| `--deep` | `-D` | Show recursive dependency tree |

**No YAML configuration.** This tool has no config keys in `buildkit.yaml` — it works on any project with a `pubspec.yaml`.

**Output format:**

```text
my_package (my_package):
  -> path: ^1.9.0
  -> yaml: ^3.1.0
  +> test: ^1.25.0
  +> lints: ^4.0.0
  -> tom_core: path: ../core/tom_core [override: path ../core/tom_core]
```

| Prefix | Meaning |
|--------|---------|
| `->` | Normal dependency |
| `+>` | Dev dependency |
| `[override: ...]` | Dependency override applied |

**Dependency source formats:** Version constraints (`^1.0.0`), `path: ../pkg`, `git: url @ref (path)`, `sdk: flutter`, `hosted: ...`, `any`.

**Deep mode (`--deep`):**

- Recursively resolves sub-dependencies for path dependencies
- Displays indented tree with transitive dependencies
- Detects and marks circular references with `(circular)`
- Only path dependencies can be resolved for subtrees (hosted/git deps don't have local pubspec files)

**Examples:**

```bash
# Show normal dependencies
dependencies --project _build

# Show dev dependencies only
dependencies --project _build --dev

# Show all dependencies
dependencies --project _build --all

# Recursive dependency tree
dependencies --project _build --deep

# Deep mode with dev deps
dependencies --project _build --deep --dev
```

---

### Pub Get

Runs `dart pub get` across multiple projects with filtered output and summary reporting.

> **Note:** Pub Get is not a `ToolBase` subclass. It has its own argument parser and is only available as a BuildKit command (`:pubget` / `:pubgetall`), not as a standalone binary.

**Usage:**

```bash
buildkit :pubget [options]
buildkit :pubgetall [options]    # Shortcut for :pubget --scan . --recursive
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Show help |
| `--errors` | `-e` | Only show projects with errors |
| `--updates` | `-u` | Only show projects with available updates |
| `--upgrades` | `-U` | Only show projects with incompatible upgrades |
| `--verbose` | `-v` | Show detailed output |
| `--recursive` | `-R` | Scan directories recursively (uppercase R) |
| `--scan <dir>` | `-s` | Scan directory for projects |
| `--project <path>` | `-p` | Project(s) to process |

**Output:** Shows per-project results with `📦` headers and a summary with total, succeeded, failed, with-updates, and with-incompatible-upgrades counts. Filters (`--errors`, `--updates`, `--upgrades`) are OR-combined.

**Examples:**

```bash
# Run pub get on all workspace projects
buildkit :pubgetall

# Show only projects with errors
buildkit :pubgetall --errors

# Run pub get on specific project
buildkit :pubget --project _build
```

---

### Pub Update

Runs `dart pub upgrade` across multiple projects with filtered output and summary reporting.

> **Note:** Pub Update is not a `ToolBase` subclass. It has its own argument parser and is only available as a BuildKit command (`:pubupdate` / `:pubupdateall`), not as a standalone binary.

**Usage:**

```bash
buildkit :pubupdate [options]
buildkit :pubupdateall [options]    # Shortcut for :pubupdate --scan . --recursive
```

**Options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Show help |
| `--errors` | `-e` | Only show projects with errors |
| `--changes` | `-c` | Only show projects with changed packages |
| `--major-versions` | | Allow upgrading to latest resolvable versions (major versions) |
| `--verbose` | `-v` | Show detailed output |
| `--recursive` | `-R` | Scan directories recursively (uppercase R) |
| `--scan <dir>` | `-s` | Scan directory for projects |
| `--project <path>` | `-p` | Project(s) to process |

**Output:** Shows per-project results with `📦` headers and a summary with total, succeeded, failed, and with-package-changes counts. Filters (`--errors`, `--changes`) are OR-combined.

**Examples:**

```bash
# Upgrade all workspace projects
buildkit :pubupdateall

# Show only projects with errors
buildkit :pubupdateall --errors

# Show only projects with changed packages
buildkit :pubupdateall --changes

# Upgrade to major versions
buildkit :pubupdateall --major-versions

# Upgrade specific project
buildkit :pubupdate --project _build
```

---

### Publisher

Shows publishing status for all Dart projects in the workspace, including version synchronization status across the dependency tree.

**Usage:**

```bash
publisher [common-options]    # Standalone
buildkit :publisher           # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--show-unpublished` | — | Also show unpublished projects |
| `--check-pub-dev` | — | Check against pub.dev versions |

**Output includes:**

- Current version from `pubspec.yaml`
- Whether project is publishable (`publish_to: none`)
- Dependencies on workspace projects
- Version sync status with dependencies

**Examples:**

```bash
# Show publishing status for all projects
publisher --scan . -r

# Check specific project
publisher --project my_package

# Include unpublished projects
publisher --show-unpublished

# Via buildkit
buildkit :publisher
```

---

### DCli

Executes Dart scripts or expressions via the dcli runtime. Unlike other built-in commands, dcli spawns an external process.

> **Note:** DCli is not a `ToolBase` subclass. It is only available as a BuildKit command (`:dcli`), not as a standalone binary within tom_build_kit. The dcli binary must be installed separately (see [tom_d4rt_dcli](../../xternal/tom_module_d4rt/tom_d4rt_dcli/)).

**Usage:**

```bash
buildkit :dcli <file|expression> [-init-source <file>] [-no-init-source]
bk :dcli <file|expression> [-init-source <file>] [-no-init-source]
```

**Options (only these are allowed in buildkit context):**

| Flag | Description |
|------|-------------|
| `-init-source <file>` | Use custom init source file for dcli |
| `-no-init-source` | Do not load custom init source |

**Path notations:**

| Notation | Resolves To | Example |
|----------|-------------|---------|
| `~w/path` | Workspace root | `~w/tool/setup.dart` |
| `~s/path` | `_scripts/` folder | `~s/build_hook.dart` |
| `::name` | `_scripts/bin/` folder | `::poll_binaries` |

If the filename has no extension, `.dart` is automatically appended.

**Expression mode:** If the argument is wrapped in double quotes, it is treated as a Dart expression and always executed (no file existence check).

**Optional script pattern:** For file targets, the command is only executed if the file exists. If not found, the step is silently skipped (returns success). This enables optional per-project build scripts.

**Examples:**

```bash
# Run a workspace-level script (only if it exists)
bk :dcli ~s/build_hook.dart

# Run a script from _scripts/bin/
bk :dcli ::poll_binaries

# Run per-project optional script
bk :dcli build_step.dart

# Run a Dart expression in every project
bk :dcli "print(DateTime.now())"

# Skip init source loading
bk :dcli ~s/init.dart -no-init-source
```

**In pipeline configuration:**

```yaml
buildkit:
  pipelines:
    build:
      precore:
        - commands:
            - dcli ~s/build_hook.dart -no-init-source
      core:
        - commands:
            - versioner
            - compiler
```

**In compiler precompile/postcompile:**

```yaml
compiler:
  precompile:
    - command: dcli ~s/pre_compile.dart
  postcompile:
    - command: dcli ~s/post_compile.dart -no-init-source
```

**Stdin alternative:** For inline Dart code without a script file, use the stdin piping mechanism with `dcli --stdin`:

```yaml
core:
  - commands:
      - |
        stdin dcli --stdin
        print("Hello from inline Dart!");
```

---

### Execute

Execute arbitrary shell commands in each traversed folder with placeholder support.

**Aliases:** `exec`, `x`

#### Basic Usage

```bash
# via buildkit (recommended)
buildkit -i :execute "echo ${folder.name}"

# with condition filtering
buildkit -i :execute --condition dart.exists "dart pub get"
```

#### Command Options

| Option | Description |
|--------|-------------|
| `-c, --condition` | Boolean placeholder condition to filter folders |

#### Placeholders

The execute command supports placeholder substitution in the command string:

**Path Placeholders:**
- `${root}` — Workspace root path
- `${folder}` — Current folder absolute path
- `${folder.name}` — Current folder name (last segment)
- `${folder.relative}` — Folder path relative to root

**Platform Placeholders:**
- `${current-os}` — Operating system (linux, macos, windows)
- `${current-arch}` — Architecture (x64, arm64, etc.)
- `${current-platform}` — Combined platform (linux-x64, macos-arm64, etc.)

**Nature Existence (Boolean):**
- `${dart.exists}` — true if folder has pubspec.yaml
- `${flutter.exists}` — true if folder has flutter project
- `${git.exists}` — true if folder is a git repository

**Dart Attributes (requires dart.exists):**
- `${dart.name}` — Package name from pubspec.yaml
- `${dart.version}` — Version from pubspec.yaml
- `${dart.publishable}` — Whether package can be published

**Git Attributes (requires git.exists):**
- `${git.branch}` — Current branch name
- `${git.remote}` — Remote URL
- `${git.dirty}` — Whether repo has uncommitted changes

#### Ternary Expressions

Use ternary syntax for conditional command construction:

```bash
${condition?(true-value):(false-value)}
```

**Examples:**

```bash
# Output different text based on publishability
buildkit -i :execute "echo ${dart.publishable?(Ready to publish):(Not publishable)}"

# Conditionally run commands
buildkit -i :execute --condition dart.exists "echo ${flutter.exists?(Flutter project: ${dart.name}):(Dart package: ${dart.name})}"

# Skip action with empty false branch
buildkit -i :execute "echo ${git.dirty?(needs commit):()}"
```

#### Examples

```bash
# Echo folder name in all git repos
buildkit -i :execute "echo ${folder.name}"

# Run dart pub get only in dart projects
buildkit -i :execute --condition dart.exists "dart pub get"

# Check git status only in git repos
buildkit -i :execute --condition git.exists "git status --short"

# Show project summary
buildkit -i :execute --condition dart.exists "echo ${dart.name} v${dart.version}: ${dart.publishable?(pub ready):(local only)}"

# Dry-run to preview commands
buildkit -i --dry-run :execute "echo Processing ${folder.name}"
```

---

## Git Tools

Tom Build Kit includes a suite of git management tools for multi-repository workspaces. These tools scan for git repositories (including submodules) and execute git operations across all of them.

All git tools share common characteristics:

- **Repository discovery:** Automatically finds `.git` directories and `.git` files (submodules)
- **Traversal order:** Requires explicit traversal direction via `-i` or `-o` flags
- **Consistent output:** Repository names prefixed to output for identification
- **BuildKit integration:** Available as both standalone binaries and buildkit commands

### Git Traversal Modes

Git tools require explicit traversal order to ensure correct operation with nested repositories (parent repos and submodules):

| Flag | Short | Name | Order |
|------|-------|------|-------|
| `--inner-first-git` | `-i` | Inner-first | Deepest (innermost) repositories processed first |
| `--outer-first-git` | `-o` | Outer-first | Shallowest (outermost) repositories processed first |

**Choosing the correct traversal mode:**

| Tool | Recommended | Reasoning |
|------|-------------|-----------|
| `gitstatus` | Either | Read-only operation, order doesn't affect outcome |
| `gitcommit` | Inner-first (`-i`) | Commit submodules first so parent records updated hashes |
| `gitpull` | Outer-first (`-o`) | Pull parent first to get correct submodule references |
| `gitbranch` | Inner-first (`-i`) | Create branches in submodules first for consistency |
| `gittag` | Inner-first (`-i`) | Tag submodules first so parent can reference tagged versions |
| `gitclean` | Inner-first (`-i`) | Clean innermost repos first (safer cleanup order) |
| `gitcheckout` | Outer-first (`-o`) | Checkout parent first to get correct submodule refs |
| `gitreset` | Outer-first (`-o`) | Reset parent first to get authoritative refs |
| `gitsync` | Outer-first (`-o`) | Sync parent first before syncing submodules |

**Standalone binaries auto-inject the recommended flag** when run without explicit traversal mode.

---

### GitStatus

Shows git status for all repositories in the workspace, including uncommitted changes, unpushed commits, current branch, and stash count.

**Usage:**

```bash
gitstatus -i [options]        # Inner-first (standalone auto-injects -i)
gitstatus -o [options]        # Outer-first
buildkit :gitstatus -i        # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--details` | `-d` | Show file-level details (changed files, unpushed commits) |
| `--fetch` | — | Fetch from remote before checking status |
| `--stash` | — | Include stash information |

**Examples:**

```bash
# Check all repos with default inner-first ordering
gitstatus

# Show detailed file changes
gitstatus --details

# Fetch and check status
gitstatus --fetch

# Via buildkit with outer-first ordering
buildkit :gitstatus -o --details
```

---

### GitCommit

Commits and pushes all repositories with pending changes. Uses inner-first traversal to ensure submodules are committed before their parent repositories.

**Usage:**

```bash
gitcommit [options]           # Standalone (auto-injects -i)
buildkit :gitcommit -i        # Via buildkit (requires -i)
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--message <msg>` | `-m` | Commit message (required or prompts) |
| `--push` | — | Push after committing (default: true) |
| `--no-push` | — | Commit without pushing |
| `--add-all` | `-a` | Stage all changes before commit |

**Examples:**

```bash
# Commit all repos with message
gitcommit -m "Fix bug in parser"

# Commit and add all changes
gitcommit -a -m "Update dependencies"

# Commit without pushing
gitcommit --no-push -m "WIP changes"

# Via buildkit
buildkit :gitcommit -i -m "Release v1.0.0"
```

---

### GitPull

Pulls latest changes from remote for all repositories. Uses outer-first traversal to pull parent repositories first, ensuring submodule references are updated correctly.

**Usage:**

```bash
gitpull [options]             # Standalone (auto-injects -o)
buildkit :gitpull -o          # Via buildkit (requires -o)
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--rebase` | `-r` | Rebase instead of merge |
| `--ff-only` | — | Only fast-forward merges |
| `--remote <name>` | — | Remote name (default: origin) |

**Examples:**

```bash
# Pull all repos
gitpull

# Pull with rebase
gitpull --rebase

# Fast-forward only
gitpull --ff-only

# Via buildkit
buildkit :gitpull -o --rebase
```

---

### GitBranch

Manages branches across all repositories: list, create, switch, and delete branches.

**Usage:**

```bash
gitbranch -i [options]        # Standalone (auto-injects -i)
buildkit :gitbranch -i        # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--create <name>` | `-c` | Create and switch to new branch |
| `--switch <name>` | `-s` | Switch to existing branch |
| `--delete` | `-d` | Delete the branch specified by `--branch` |
| `--branch <name>` | `-b` | Branch name for delete operation |
| `--list-branches` | — | List all branches in each repo |

**Examples:**

```bash
# Show current branch in all repos
gitbranch

# Create and switch to feature branch
gitbranch --create feature/new-ui

# Switch to main branch
gitbranch --switch main

# Delete a branch
gitbranch --delete --branch old-feature

# List all branches
gitbranch --list-branches
```

---

### GitTag

Manages tags across all repositories: list, create, and delete tags.

**Usage:**

```bash
gittag -i [options]           # Standalone (auto-injects -i)
buildkit :gittag -i           # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--create <name>` | `-c` | Create a new tag |
| `--delete <name>` | `-d` | Delete a tag |
| `--message <msg>` | `-m` | Annotated tag message (creates annotated tag) |
| `--push` | — | Push tags to remote |
| `--list-tags` | — | List all tags |

**Examples:**

```bash
# List tags in all repos
gittag --list-tags

# Create lightweight tag
gittag --create v1.0.0

# Create annotated tag with message
gittag --create v1.0.0 --message "Release version 1.0.0"

# Create and push tag
gittag --create v1.0.0 --push

# Delete a tag
gittag --delete v0.9.0
```

---

### GitClean

Cleans untracked files from all repositories. Uses inner-first traversal for safer cleanup order.

**Usage:**

```bash
gitclean -i [options]         # Standalone (auto-injects -i)
buildkit :gitclean -i         # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--directories` | `-d` | Also remove untracked directories |
| `--force` | `-f` | Force removal (required for actual deletion) |
| `--ignored` | `-x` | Also remove ignored files |

**Dry-run by default:** Without `--force`, shows what would be removed without deleting.

**Examples:**

```bash
# Preview what would be cleaned
gitclean

# Actually remove untracked files
gitclean --force

# Remove untracked files and directories
gitclean --force --directories

# Also remove ignored files
gitclean --force --ignored
```

---

### GitCheckout

Checks out branches or tags across all repositories. Uses outer-first traversal to checkout parent repos first, ensuring submodule references match.

**Usage:**

```bash
gitcheckout -o <ref> [options]   # Standalone (auto-injects -o)
buildkit :gitcheckout -o <ref>   # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--branch <name>` | `-b` | Branch to checkout |
| `--tag <name>` | `-t` | Tag to checkout |
| `--create` | `-c` | Create branch if it doesn't exist |

**Examples:**

```bash
# Checkout main branch
gitcheckout --branch main

# Checkout a tag
gitcheckout --tag v1.0.0

# Checkout or create branch
gitcheckout --branch feature/new --create

# Via buildkit
buildkit :gitcheckout -o --branch develop
```

---

### GitReset

Resets repositories to a specific state. Uses outer-first traversal to reset parent repos first.

**Usage:**

```bash
gitreset -o [options]         # Standalone (auto-injects -o)
buildkit :gitreset -o         # Via buildkit
```

**Tool-specific options:**

| Flag | Description |
|------|-------------|
| `--soft` | Soft reset (keep changes staged) |
| `--mixed` | Mixed reset (unstage changes, keep in working tree) — default |
| `--hard` | Hard reset (discard all changes) |
| `--commit <ref>` | Commit/ref to reset to (default: HEAD) |

**Examples:**

```bash
# Soft reset to HEAD
gitreset --soft

# Hard reset all repos
gitreset --hard

# Reset to specific commit
gitreset --hard --commit HEAD~3

# Reset to a tag
gitreset --hard --commit v1.0.0
```

---

### GitSync

Syncs (fetch + merge/rebase) all repositories with their remotes. Uses outer-first traversal to sync parent repos before submodules.

**Usage:**

```bash
gitsync -o [options]          # Standalone (auto-injects -o)
buildkit :gitsync -o          # Via buildkit
```

**Tool-specific options:**

| Flag | Short | Description |
|------|-------|-------------|
| `--rebase` | `-r` | Rebase instead of merge after fetch |
| `--prune` | — | Prune deleted remote branches |
| `--remote <name>` | — | Remote name (default: origin) |

**Examples:**

```bash
# Sync all repos (fetch + merge)
gitsync

# Sync with rebase
gitsync --rebase

# Sync and prune deleted branches
gitsync --prune

# Via buildkit
buildkit :gitsync -o --rebase --prune
```
