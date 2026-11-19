# Implementation Hints — tom_build_base Integration

This document describes the relationship between `tom_build_kit` and the shared CLI infrastructure from `tom_build_base`.

## Overview

`tom_build_kit` provides the build tools for the Tom workspace:
- **versioner** — Generate version.versioner.dart files
- **bumpversion** — Bump pubspec.yaml versions
- **cleanup** — Remove generated files
- **compiler** — Cross-platform compilation
- **runner** — build_runner wrapper
- **dependencies** — Dependency visualization
- **buildsorter** — Build order sorting

All tools inherit from `ToolBase` (in `lib/src/commands/tool_base.dart`), which uses the shared infrastructure from `tom_build_base`.

## Critical Rule: tom_build_base Owns Shared CLI Functionality

If functionality logically belongs to `tom_build_base`, it must be implemented and released there first.

Mandatory workflow:

1. Modify `tom_build_base`.
2. Test it with a test tool created inside `tom_build_base` (or an existing one there).
3. Republish `tom_build_base`.
4. Update the `tom_build_base` version in all tools based on `tom_build_base`.
5. Run tests in all tools based on `tom_build_base`.

Hard constraints:

- Never add temporary downstream code in `tom_build_kit` for functionality that belongs to `tom_build_base`.
- Never implement stopgap copies in tool packages when the owning library is `tom_build_base`.
- If integration cannot be completed in one pass, explicitly tell the user and make an integration plan first.

## Dependencies on tom_build_base

### Workspace Navigation

All navigation options are provided by `tom_build_base`:

```dart
import 'package:tom_build_base/tom_build_base.dart';

// In createParser():
addNavigationOptions(parser);  // Adds -s, -r, -p, -R, -x, etc.

// In run():
final navArgs = parseNavigationArgs(results);
```

### CLI Commands

The base package provides standardized help/version detection:

```dart
// Delegates to tom_build_base
bool checkVersionArg(List<String> args) => isVersionCommand(args);
bool checkHelpArg(List<String> args) => isHelpCommand(args);
```

### Help Output

Standardized help output is generated using:

```dart
printUsageHeader();              // Tool name, usage patterns
printExecutionModesExplanation(); // Project/Workspace mode explanation
printUsageFooter();              // Common examples
```

### Project Discovery

```dart
final projects = await findProjectsFromNavArgs(navArgs, basePath: executionRoot);
```

## Tom Build Base Reference

See the following documentation in `tom_build_base`:

| Document | Description |
|----------|-------------|
| [cli_tools_navigation.md](../../tom_build_base/doc/cli_tools_navigation.md) | Standard CLI commands, execution modes, navigation options |
| [build_base_user_guide.md](../../tom_build_base/doc/build_base_user_guide.md) | Configuration loading, project discovery, workspace mode |

### Key Files in tom_build_base

| File | Purpose |
|------|---------|
| `lib/src/workspace_mode.dart` | Navigation args, execution modes, CLI helpers |
| `lib/src/project_discovery.dart` | Project scanning and pattern matching |
| `lib/src/build_config.dart` | TomBuildConfig loading || `lib/src/v2/core/tool_runner.dart` | Central command routing and runtime behaviors |
| `lib/src/v2/core/pipeline_config.dart` | Pipeline model, loader, prefix parser |
| `lib/src/v2/core/pipeline_executor.dart` | Pipeline execution engine (serial fail-fast) |
| `lib/src/v2/core/macro_expansion.dart` | Runtime macro expansion |
## Adding a New Tool

When creating a new tool:

1. **Extend ToolBase** — Inherit common functionality
2. **Override `toolKey`** — Used in buildkit.yaml configuration
3. **Override `toolDescription`** — Shown in help output
4. **Override `addToolOptions`** — Add tool-specific CLI options
5. **Override `isToolProject`** — Define project detection criteria
6. **Use `checkVersionArg/checkHelpArg`** — Handle version/help commands early
7. **Use `parseArgsWithExecutionMode`** — Parse args with navigation handling
8. **Use `printUsageHeader/printExecutionModesExplanation`** — Standardized help

Example template:

```dart
class MyTool extends ToolBase {
  @override
  String get toolKey => 'mytool';

  @override
  String get toolDescription => 'My tool description';

  @override
  Future<bool> run(List<String> args) async {
    if (checkVersionArg(args)) return true;
    if (checkHelpArg(args)) {
      _printUsage(createParser());
      return true;
    }
    // ... implementation
  }

  void _printUsage(ArgParser parser) {
    printUsageHeader();
    print('Options:');
    print(parser.usage);
    printExecutionModesExplanation();
    // ... tool-specific help
  }
}
```

## Version History

- **2026-02**: Added standardized CLI help/version support via tom_build_base
- **2026-02**: Pipeline execution engine migrated to `tom_build_base` (base-owned)
- **2026-02**: Macro/define command split: runtime macros (`:macro/:macros/:unmacro`) + persistent defines (`:define/:defines/:undefine`)
- **2026-02**: Entrypoint (`bin/buildkit.dart`) replaced with `ToolRunner` v2
- **2026-02**: Removed local pipeline files (`pipeline_config.dart`, `pipeline_executor.dart`, `pipeline_step.dart`)
- **2026-02**: `:execute` executor confirmed fully base-backed (extends `CommandExecutor`, uses base placeholder APIs)
## Debugging Traversal with :execute

The `:execute` command is a powerful tool for testing and debugging navigation options before running actual commands. It executes arbitrary shell commands in each discovered project, showing you exactly which projects are selected and in what order.

### Placeholder-Based Diagnostics

The `:execute` command supports placeholders that provide detailed information about each traversed folder. Use these for diagnostic output:

#### Git Traversal Diagnostic

Shows all git repository information:

```bash
# Full git diagnostic with -i (inner-first) traversal
buildkit -T -i :execute 'echo "📂 ${folder.name} | Path: ${folder.relative} | Git: ${git.exists} | Branch: ${git.branch} | Changes: ${git.hasChanges} | Submodule: ${git.isSubmodule}"'

# Compact git info
buildkit -T -o :execute 'echo "${folder.name}: ${git.branch} [${git.hasChanges?(dirty):(clean)}]"'
```

#### Project Traversal Diagnostic

Shows Dart/Flutter project information:

```bash
# Full Dart project diagnostic with --condition to filter
buildkit -R --scan . -r :execute --condition dart.exists 'echo "📦 ${folder.name} | Name: ${dart.name} | Ver: ${dart.version} | Pub: ${dart.publishable}"'

# Flutter projects only
buildkit -R --scan . -r :execute --condition flutter.exists 'echo "${folder.name}: ${flutter.platforms} [${flutter.isPlugin?(plugin):(app)}]"'
```

### Available Placeholders

| Placeholder | Description |
|-------------|-------------|
| `${folder.name}` | Folder basename |
| `${folder.relative}` | Relative path from workspace root |
| `${folder}` | Absolute folder path |
| `${root}` | Workspace root path |
| `${git.exists}` | Boolean: is git repository |
| `${git.branch}` | Current git branch |
| `${git.hasChanges}` | Boolean: has uncommitted changes |
| `${git.isSubmodule}` | Boolean: is git submodule |
| `${dart.exists}` | Boolean: is Dart project |
| `${dart.name}` | Package name from pubspec.yaml |
| `${dart.version}` | Version from pubspec.yaml |
| `${dart.publishable}` | Boolean: publish_to not set to none |
| `${flutter.exists}` | Boolean: is Flutter project |
| `${flutter.platforms}` | Comma-separated platform list |
| `${flutter.isPlugin}` | Boolean: is Flutter plugin |
| `${current-os}` | Current OS (macos, linux, windows) |
| `${current-arch}` | Current architecture (arm64, x64) |
| `${current-platform}` | Platform string (darwin-arm64, linux-x64) |

### Ternary Placeholder Syntax

Use ternary syntax for conditional output:

```bash
# Show (dirty) or (clean) based on git.hasChanges
buildkit -T -i :execute 'echo "${folder.name}: ${git.hasChanges?(dirty):(clean)}"'

# Show (Pub) or (Internal) based on dart.publishable
buildkit -R -s . -r :execute --condition dart.exists 'echo "${dart.name}: ${dart.publishable?(Pub):(Internal)}"'
```

### Basic Usage

```bash
# Test which projects would be affected
buildkit -T -i :execute echo "Test"

# Show project paths
buildkit -s . -r :execute pwd

# Verify git traversal order
buildkit -T -o :execute echo "Repo: $(basename $(git rev-parse --show-toplevel 2>/dev/null || pwd))"
```

### Examples

```bash
# Debug -T (top-repo) with inner-first traversal
buildkit -T -i :execute echo "Project: ${PWD##*/}"

# Test --project filter
buildkit --project tom_build_* :execute echo "Found"

# Verify --exclude-projects filtering
buildkit -s . -r --exclude-projects "zom_*" :execute ls -la

# Test modules filter
buildkit -m basics :execute echo "In basics"
```

### Key Points

- `:execute` respects all navigation options (`-T`, `-i`, `-o`, `-s`, `-r`, `-p`, etc.)
- Output shows project name before command output for each project
- Use `--dry-run` with other commands first, then `:execute` to verify traversal
- Combine with `echo` for quick visibility checks

## Architecture Note: ToolRunner v2 Entrypoint (2026-02)

`bin/buildkit.dart` now uses `ToolRunner` from `tom_build_base` as the sole entrypoint.
All navigation options, help output, env checks, pipeline dispatch, and macro/define
commands are handled by the base runtime. The old `ArgParser`-based local option
duplication described in earlier documentation is no longer relevant.

**Current entrypoint (`bin/buildkit.dart`):**
```dart
final runner = ToolRunner(
  tool: buildkitTool,
  executors: createBuildkitExecutors(),
  verbose: true,
);
final result = await runner.run(args);
```

**Pipeline execution** is now base-owned (`ToolPipelineExecutor`):  
- Pipeline config loaded from `buildkit_master.yaml` via `ToolPipelineConfigLoader`
- Strict command prefixes: `buildkit`, `shell`, `shell-scan`
- Option precedence: command > invocation > pipeline `global-options`
- Multi-workspace traversal with disqualifying-option gating

**Removed local modules** (superseded by base):  
- `lib/src/pipeline_config.dart` → `tom_build_base` `ToolPipelineConfig`  
- `lib/src/pipeline_executor.dart` → `tom_build_base` `ToolPipelineExecutor`  
- `lib/src/pipeline_step.dart` → `tom_build_base` `PipelineStepConfig`