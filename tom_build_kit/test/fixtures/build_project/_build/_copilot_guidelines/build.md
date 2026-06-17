# Build Guidelines for _build

The `_build` project compiles all Tom workspace binaries using `build.sh`.

## Quick Start

```bash
cd _build

# Build all tools
./build.sh --all

# Build specific tools
./build.sh tom,d4rt,dcli

# Build a single tool
./build.sh tom

# List available tools
./build.sh --list
```

## Important: Code Generation

**Tools with build_runner dependencies (tom, d4rt, dcli, tom_bs) require `.g.dart` files to be deleted before each build** to ensure fresh version info and bridges. The `build.sh` script handles this automatically. For versioned projects, the build cache is also cleared to avoid stale build counters.

**Note:** Only `.g.dart` files must be deleted. Other generated files (e.g., `dartscript.dart`, `*_bridges.dart`) are overwritten by build_runner.

### Files Deleted Before Generation

Each tool has `.g.dart` files that must be deleted to trigger regeneration:

| Project | Deleted Files (`.g.dart` only) | Extra Cleanup |
|---------|-------------------------------|
| tom_build_cli | `lib/src/tom_d4rt/version.versioner.dart`, `lib/src/d4rt_library_bridges/bridges_trigger.g.dart` | `.dart_tool/build` |
| tom_dartscript_bridges | `lib/src/cli/version.versioner.dart`, `lib/src/d4rt_library_bridges/bridges_trigger.g.dart` | `.dart_tool/build` |
| tom_d4rt_dcli | `lib/src/d4rt_library_bridges/bridges_trigger.g.dart` | — |
| tom_vscode_bridge | `lib/src/d4rt_bridges/bridges_trigger.g.dart`, `lib/src/version.versioner.dart` | `.dart_tool/build` |

### Build Dependencies

When building a tool, all upstream projects with `build.yaml` must have their generated files regenerated:

```
tom    → tom_build_cli → tom_dartscript_bridges → tom_d4rt_dcli
d4rt   →                 tom_dartscript_bridges → tom_d4rt_dcli  
dcli   →                                          tom_d4rt_dcli
tom_bs → tom_vscode_bridge → tom_dartscript_bridges → tom_d4rt_dcli
```

The `build.sh` script:
1. Deletes generated files in all required projects
2. Runs `dart run build_runner build` in each project
3. Compiles the final binary

**Duplicate generation is avoided** - if building multiple tools that share dependencies (e.g., `tom,d4rt,dcli`), each project is regenerated only once.

---

## Building tom

The tom CLI (TomD4rt) integrates the D4rt REPL with Tom workspace commands.

### Using build.sh (Recommended)

```bash
cd _build
./build.sh tom
```

This automatically:
1. Deletes generated files in tom_build_cli, tom_dartscript_bridges, tom_d4rt_dcli
2. Runs build_runner in all three projects
3. Compiles `bin/tom.dart` to `~/.tom/bin/{platform}/tom`

### Manual Build

If you need to build manually:

```bash
# 1. Regenerate tom_d4rt_dcli
cd tom/xternal/tom_module_d4rt/tom_d4rt_dcli
rm -f lib/src/d4rt_library_bridges/bridges_trigger.g.dart
dart pub get && dart run build_runner build --delete-conflicting-outputs

# 2. Regenerate tom_dartscript_bridges
cd tom/dartscript/tom_dartscript_bridges
rm -f lib/src/cli/version.versioner.dart lib/src/d4rt_library_bridges/bridges_trigger.g.dart
dart pub get && dart run build_runner build --delete-conflicting-outputs

# 3. Regenerate tom_build_cli
cd tom/devops/tom_build_cli
rm -f lib/src/tom_d4rt/version.versioner.dart lib/src/d4rt_library_bridges/bridges_trigger.g.dart
dart pub get && dart run build_runner build --delete-conflicting-outputs

# 4. Compile from _build
cd _build
dart pub get
dart compile exe bin/tom.dart -o ~/.tom/bin/darwin-arm64/tom
```

### What Gets Generated for tom

- `tom_build_cli/lib/src/tom_d4rt/version.versioner.dart` - Version info (version, build time, git commit)
- `tom_build_cli/lib/src/tom_d4rt/dartscript.dart` - Bridge registration (TomBuildCliBridges)
- Plus all bridges from tom_dartscript_bridges and tom_d4rt_dcli

---

## Building d4rt

The d4rt CLI (tom_dartscript_bridges) is the full D4rt REPL with all Tom Framework bridges.

### Using build.sh (Recommended)

```bash
cd _build
./build.sh d4rt
```

This automatically:
1. Deletes generated files in tom_dartscript_bridges, tom_d4rt_dcli
2. Runs build_runner in both projects
3. Compiles `bin/d4rt.dart` to `~/.tom/bin/{platform}/d4rt`

### Manual Build

```bash
# 1. Regenerate tom_d4rt_dcli
cd tom/xternal/tom_module_d4rt/tom_d4rt_dcli
rm -f lib/src/d4rt_library_bridges/bridges_trigger.g.dart
dart pub get && dart run build_runner build --delete-conflicting-outputs

# 2. Regenerate tom_dartscript_bridges
cd tom/dartscript/tom_dartscript_bridges
rm -f lib/src/cli/version.versioner.dart lib/src/d4rt_library_bridges/bridges_trigger.g.dart
dart pub get && dart run build_runner build --delete-conflicting-outputs

# 3. Compile from _build
cd _build
dart pub get
dart compile exe bin/d4rt.dart -o ~/.tom/bin/darwin-arm64/d4rt
```

### What Gets Generated for d4rt

- `tom_dartscript_bridges/lib/src/cli/version.versioner.dart` - Version info (version, build time, git commit, build number)
- Bridge registration code for D4rt scripting
- Plus all bridges from tom_d4rt_dcli

---

## Building dcli

The dcli CLI (tom_d4rt_dcli) is the base REPL with only dcli package bridges.

### Using build.sh (Recommended)

```bash
cd _build
./build.sh dcli
```

This automatically:
1. Deletes generated files in tom_d4rt_dcli
2. Runs build_runner in tom_d4rt_dcli
3. Compiles `bin/dcli.dart` to `~/.tom/bin/{platform}/dcli`

### Alternative: Build from Standalone Project

dcli can also be built from its original project (includes build_runner):

```bash
cd tom/xternal/tom_module_d4rt/tom_d4rt_dcli
./compile.sh
```

### What Gets Generated for dcli

- `lib/src/d4rt_library_bridges/package_dcli_bridges.dart` - dcli package bridges
- `lib/src/d4rt_library_bridges/package_dcli_core_bridges.dart` - dcli_core bridges
- `lib/src/d4rt_library_bridges/package_dcli_terminal_bridges.dart` - dcli_terminal bridges
- `lib/src/d4rt_library_bridges/package_crypto_bridges.dart` - crypto bridges

### Version Management for dcli

Unlike d4rt and tom, dcli uses a simple const version in `lib/tom_d4rt_dcli.dart`:

```dart
const String dcliVersion = '0.1.0';
```

---

## Building tom_bs

The tom_bs binary (tom_vscode_bridge) is the VS Code Bridge server for D4rt integration. It communicates via stdio and is designed to be launched by the VS Code extension.

**Note:** When run directly, tom_bs starts and waits for input on stdio. It's a server process that expects commands from the VS Code extension.

### Using build.sh (Recommended)

```bash
cd _build
./build.sh tom_bs
```

This automatically:
1. Deletes `.g.dart` files in tom_d4rt_dcli, tom_dartscript_bridges, tom_vscode_bridge
2. Runs build_runner in all three projects
3. Compiles `bin/tom_bs.dart` to `~/.tom/bin/{platform}/tom_bs`

### What Gets Generated for tom_bs

- `tom_vscode_bridge/lib/d4rt_bridges.dart` - Barrel file for bridges
- `tom_vscode_bridge/lib/dartscript.dart` - Bridge registration (TomDartscriptBridgeBridges)
- `tom_vscode_bridge/lib/src/d4rt_bridges/tom_vscode_bridge_bridges.dart` - Package bridges
- `tom_vscode_bridge/lib/src/version.versioner.dart` - Version info (version, build time, git commit, build number)
- Plus all bridges from tom_dartscript_bridges and tom_d4rt_dcli

---

## Building Multiple Tools

To build multiple tools efficiently:

```bash
cd _build
./build.sh tom,d4rt,dcli
```

The script optimizes by:
- Running each project's build_runner only once
- tom needs all three projects → regenerates all
- d4rt needs two projects → skips tom_build_cli
- dcli needs one project → skips tom_dartscript_bridges and tom_build_cli

---

## Other Tools

Other tools in `_build/bin/` compile directly without code generation:

| Tool | Description |
|------|-------------|
| ws_analyzer | Workspace analyzer |
| ws_prepper | Workspace preparation tool |
| doc_scanner | Documentation scanner |
| docspecs | DocSpecs validator |
| md2pdf | Markdown to PDF converter |
| md2latex | Markdown to LaTeX converter |
| reflect | Reflection generator CLI |
| deploy | Deployment tool |
| d4rt_gen | D4rt bridge generator |
| reflect_gen | Reflection generator |
| ledger_server | Ledger server |
| process_monitor | Process monitor tool |

To build any of these:

```bash
cd _build
./build.sh ws_analyzer
./build.sh md2pdf,docspecs
```

---

## Common Issues

- **Stale version info**: Use `build.sh` which deletes generated files automatically
- **Missing bridges**: If new bridged classes aren't available, ensure build_runner ran in all dependency projects
- **Compile errors about missing generated files**: Run `build.sh` which handles generation
- **Wrong git commit in version**: Commit changes before running `build.sh`

---

## Version Verification (Minimal Build Test)

After each build, every tool should be started once with the `--version` option to verify correct building. The `build.sh` script automatically performs this verification for tools that use the versioning builder (tom, d4rt, tom_bs).

### What Gets Verified

For versioned tools, the verification checks:

1. **Version string** - Matches the version in `pubspec.yaml`
2. **Build number** - Matches the build number in `tom_build_state.json`
3. **Timestamp** - Within 10 minutes of current UTC time (freshness check)

### Version Output Format

Versioned tools output their version in this format:

```
{name} {version}+{build}.{commit} ({timestamp}) [Dart {dart_version}]
```

Examples:
```bash
$ tom_bs --version
1.0.0+2.ef8358e (2026-02-03T11:25:19.544938Z) [Dart 3.10.4]

$ tom --version
Tom Interactive REPL 1.0.0+8.ef8358e (2026-02-03T11:26:17.773943Z) [Dart 3.10.4]

$ d4rt --version
D4rt Interactive REPL 1.0.0+52.ef8358e (2026-02-03T11:24:16.560838Z) [Dart 3.10.4]
```

### Manual Verification

You can manually verify any tool:

```bash
~/.tom/bin/darwin-arm64/tom --version
~/.tom/bin/darwin-arm64/d4rt --version
~/.tom/bin/darwin-arm64/tom_bs --version
```

### Timestamp Note

Version timestamps are in **UTC** (indicated by the `Z` suffix). The verification compares against current UTC time, allowing a 10-minute leeway to account for build duration.

---

## Architecture-Specific Binaries

All binaries with code generation are installed to `~/.tom/bin/{platform}/`:

| Platform | Location Pattern |
|----------|-----------------|
| macOS ARM64 | `~/.tom/bin/darwin-arm64/{binary}` |
| macOS x64 | `~/.tom/bin/darwin-x64/{binary}` |
| Linux x64 | `~/.tom/bin/linux-x64/{binary}` |
| Windows x64 | `~/.tom/bin/win32-x64/{binary}.exe` |

## Relationship Between Tools with Code Generation

- **dcli** (`tom_d4rt_dcli`) - Base REPL with only dcli package bridges
- **d4rt** (`tom_dartscript_bridges`) - Full REPL with all Tom Framework bridges
- **tom** (`tom_build_cli`) - Complete Tom CLI with workspace commands + D4rt REPL
- **tom_bs** (`tom_vscode_bridge`) - VS Code Bridge server for D4rt integration

If you modify `D4rtReplBase` in tom_d4rt_dcli, you'll need to rebuild all four tools.
