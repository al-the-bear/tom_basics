# CLI Tools and Workspace Navigation

This document describes the standard CLI patterns and workspace navigation options used by all Tom build tools.

## Overview

Tom build tools share a consistent set of command-line options for workspace traversal. This is provided by the `workspace_mode.dart` module in `tom_build_base`.

## Standard Commands

All Tom build tools support these command patterns:

### Help Command

```bash
<tool> help           # Show help
<tool> --help         # Show help
<tool> -h             # Show help (short form)
```

### Version Command

```bash
<tool> version        # Show version
<tool> --version      # Show version
<tool> -version       # Show version (legacy)
```

## Execution Modes

Tom tools operate in two execution modes:

### Project Mode (Default)

When run without explicit navigation options, tools operate in **project mode**:

- Works from the current directory
- Automatically applies: `--scan . --recursive --build-order`
- Processes the current project and its subprojects

```bash
# These are equivalent in project mode:
astgen
astgen --scan . --recursive --build-order
```

### Workspace Mode

When navigation options are provided, tools operate in **workspace mode**:

- Triggered by: `-R`, `-s <path>` (where path ≠ "."), `-i`, or `-o`
- Does NOT auto-apply defaults
- Processes exactly what you specify

```bash
# Workspace mode examples:
astgen -R                    # From detected workspace root
astgen -R /path/to/workspace # From specified workspace
astgen -s packages/          # Scan specific directory
astgen -i                    # Inner-first git mode
```

## Navigation Options

### Scanning and Traversal

| Option | Abbr | Description |
|--------|------|-------------|
| `--scan=<path>` | `-s` | Scan directory for projects |
| `--recursive` | `-r` | Scan directories recursively |
| `--build-order` | `-b` | Sort projects in dependency build order |
| `--project=<pattern>` | `-p` | Project(s) to run (comma-separated, globs supported) |

### Workspace Root

| Option | Abbr | Description |
|--------|------|-------------|
| `--root` | `-R` | Bare: auto-detect workspace root |
| `--root=<path>` | `-R` | Use specified path as workspace root |
| `--workspace-recursion` | `-w` | Shell out to sub-workspaces instead of skipping |

**Workspace detection** looks for these files (in order):
- `buildkit_master.yaml`
- `tom_workspace.yaml`
- `tom.code-workspace`

### Git Repository Traversal

| Option | Abbr | Description |
|--------|------|-------------|
| `--inner-first-git` | `-i` | Scan git repos, process innermost (deepest) first |
| `--outer-first-git` | `-o` | Scan git repos, process outermost (shallowest) first |
| `--top-repo` | `-T` | Find topmost git repo by traversing up (requires `-i` or `-o`) |

**Use cases:**
- `-i`: For commit/push operations (leaf repos first)
- `-o`: For pull/fetch operations (parent repos first)
- `-T`: Find and operate on the parent repository containing the current directory

The `--top-repo` flag traverses upward from the current directory to find the topmost git repository. It requires a git traversal mode (`-i` or `-o`) to be specified. This is useful when running from a nested subdirectory and you want to operate on the containing repository hierarchy.

```bash
# From inside a submodule, find all repos from the top
gitstatus -T -i
gitcommit -T -i -m "Update all"
```

### Exclusion Patterns

| Option | Abbr | Description |
|--------|------|-------------|
| `--exclude=<glob>` | `-x` | Exclude patterns (path-based globs) |
| `--exclude-projects=<pattern>` | | Exclude projects by name or path |
| `--recursion-exclude=<glob>` | | Exclude patterns during recursive scan |

**Pattern syntax:**
- `*` matches any characters except `/`
- `**` matches any characters including `/`
- Can be specified multiple times

```bash
# Examples:
astgen -R -x '**/test/**' -x '**/example/**'
astgen --exclude-projects='zom_*,test_*'
astgen --recursion-exclude='**/.git/**,**/node_modules/**'
```

## Implementation Guide

### Adding Navigation to Your Tool

There are two approaches for implementing navigation:

1. **ProjectNavigator** (recommended) — Unified navigation with configurable features
2. **Manual discovery** — Use `ProjectDiscovery` directly for custom control

### Using ProjectNavigator (Recommended)

```dart
import 'dart:io';
import 'package:args/args.dart';
import 'package:tom_build_base/tom_build_base.dart';

void main(List<String> args) async {
  // 1. Check for help/version commands first
  if (isHelpCommand(args)) {
    _printUsage();
    return;
  }
  if (isVersionCommand(args)) {
    print('MyTool $version');
    return;
  }

  // 2. Preprocess args for bare -R detection
  final (processedArgs, bareRoot) = preprocessRootFlag(args);

  // 3. Create parser with tool-specific options
  final parser = ArgParser()
    ..addOption('config', abbr: 'c', help: 'Config file path')
    ..addFlag('verbose', abbr: 'v', help: 'Verbose output')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');
  
  // 4. Add standard navigation options
  addNavigationOptions(parser);

  // 5. Parse arguments
  final results = parser.parse(processedArgs);
  
  if (results['help'] as bool) {
    _printUsage();
    return;
  }

  final verbose = results['verbose'] as bool;

  // 6. Parse navigation options
  final navArgs = parseNavigationArgs(results, bareRoot: bareRoot);
  
  // 7. Resolve execution root
  final executionRoot = resolveExecutionRoot(
    navArgs,
    currentDir: Directory.current.path,
  );

  // 8. Apply defaults if needed
  final effectiveNavArgs = navArgs.withDefaults();

  // 9. Create navigator with tool-specific config
  final navigator = ProjectNavigator(
    config: NavigationConfig(
      usePathExclude: true,
      useNameExclude: true,
      useModulesFilter: true,
      useRecursionExclude: true,
      useSkipFiles: true,
      useMasterConfigDefaults: true,
      useBuildOrder: effectiveNavArgs.buildOrder,
      useGitTraversal: true,
      projectFilter: _isValidProject,  // Optional: custom filter
    ),
    verbose: verbose,
  );

  // 10. Navigate to find projects
  final result = await navigator.navigate(
    effectiveNavArgs,
    basePath: executionRoot,
  );

  if (result.hasError) {
    stderr.writeln('Error: ${result.errorMessage}');
    exit(1);
  }

  // 11. Process projects
  for (final project in result.paths) {
    await processProject(project);
  }
}

bool _isValidProject(String dirPath) {
  return File('$dirPath/pubspec.yaml').existsSync();
}

void _printUsage() {
  print('MyTool - Does something useful');
  print('');
  print('Usage:');
  print('  mytool [options]');
  print('  mytool help');
  print('  mytool version');
  print('');
  print('Tool Options:');
  print('  -c, --config=<path>  Config file path');
  print('  -v, --verbose        Verbose output');
  print('  -h, --help           Show help');
  print('');
  printNavigationOptionsHelp();
}
```

### Using ProjectDiscovery (Manual Approach)
```

### Generating Consistent Help Output

Use the helper functions to ensure consistent help text:

```dart
void _printUsage(ArgParser parser) {
  // Print header
  for (final line in getToolHelpHeader(
    toolName: 'Astgen',
    toolDescription: 'Converts Dart source files to serialized AST YAML files',
    usagePatterns: [
      'astgen [options]',
      'astgen help',
      'astgen version',
    ],
  )) {
    print(line);
  }

  // Print tool-specific options
  print('Tool Options:');
  print(parser.usage);  // ArgParser's built-in usage
  print('');

  // Print navigation options
  printNavigationOptionsHelp();

  // Print footer with examples
  for (final line in getToolHelpFooter(toolName: 'astgen')) {
    print(line);
  }
}
```

## API Reference

### Functions

| Function | Description |
|----------|-------------|
| `isHelpCommand(args)` | Check if first arg is a help command |
| `isVersionCommand(args)` | Check if first arg is a version command |
| `addNavigationOptions(parser)` | Add standard navigation options to ArgParser |
| `preprocessRootFlag(args)` | Detect bare `-R` and preprocess for parsing |
| `parseNavigationArgs(results, bareRoot)` | Parse navigation options from ArgResults |
| `resolveExecutionRoot(navArgs, currentDir)` | Resolve workspace root based on nav args |
| `findWorkspaceRoot(startPath)` | Find workspace root by traversing up |
| `isWorkspaceBoundary(dirPath)` | Check if directory has buildkit_master.yaml |
| `printNavigationOptionsHelp()` | Print navigation options help to stdout |
| `getNavigationOptionsHelpLines()` | Get navigation options help as list of strings |
| `getToolHelpHeader(...)` | Generate standard tool help header |
| `getToolHelpFooter(toolName)` | Generate standard tool help footer |

### Navigation Classes

| Class | Description |
|-------|-------------|
| `ProjectNavigator` | Unified project navigation with configurable features |
| `NavigationConfig` | Configuration for which features to enable |
| `NavigationDefaults` | Navigation defaults loaded from master config |
| `NavigationResult` | Result container with paths and metadata |
| `WorkspaceNavigationArgs` | Parsed navigation options container |
| `ExecutionMode` | Enum: `project` or `workspace` |

### NavigationConfig Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `usePathExclude` | `bool` | `true` | Apply `--exclude` patterns |
| `useNameExclude` | `bool` | `true` | Apply `--exclude-projects` patterns |
| `useModulesFilter` | `bool` | `true` | Apply `--modules` filter |
| `useRecursionExclude` | `bool` | `true` | Apply `--recursion-exclude` |
| `useSkipFiles` | `bool` | `true` | Skip dirs with `tom_skip.yaml` or `{basename}_skip.yaml` |
| `useMasterConfigDefaults` | `bool` | `true` | Load defaults from `{basename}_master.yaml` |
| `useBuildOrder` | `bool` | `true` | Sort by dependency order |
| `useGitTraversal` | `bool` | `true` | Support git-based traversal |
| `projectFilter` | `Function?` | `null` | Custom project filter callback |

### Skip Files

Skip files allow directories to be excluded from tool processing without command-line options.

| Skip File | Scope | Description |
|-----------|-------|-------------|
| `tom_skip.yaml` | **Global** | Skips directory for ALL tools |
| `{basename}_skip.yaml` | **Tool-specific** | Skips directory for one tool only |

**Tool-specific skip files:**

| Tool | Skip file |
|------|-----------|
| `buildkit` | `buildkit_skip.yaml` |
| `testkit` | `testkit_skip.yaml` |
| `issuekit` | `issuekit_skip.yaml` |
| `linkkit` | `linkkit_skip.yaml` |

**Resolution order:** When scanning a directory, tools check for:
1. `tom_skip.yaml` — if present, skip for ALL tools
2. `{basename}_skip.yaml` — if present, skip for this tool only

**Skip file format:** The file can be empty (presence is sufficient) or contain optional skip reasons:

```yaml
# Optional skip reason
reason: "Legacy project, not actively maintained"
```

### NavigationResult Properties

| Property | Type | Description |
|----------|------|-------------|
| `paths` | `List<String>` | Discovered project or repo paths |
| `isGitMode` | `bool` | True if git traversal was used |
| `hasError` | `bool` | True if an error occurred |
| `errorMessage` | `String?` | Error message if `hasError` is true |

### WorkspaceNavigationArgs Properties

| Property | Type | Description |
|----------|------|-------------|
| `scan` | `String?` | Scan directory path |
| `recursive` | `bool` | Recursive scanning enabled |
| `buildOrder` | `bool` | Sort by dependency order |
| `project` | `String?` | Project pattern(s) |
| `root` | `String?` | Explicit workspace root path |
| `bareRoot` | `bool` | True if bare `-R` was used |
| `workspaceRecursion` | `bool` | Shell out to sub-workspaces |
| `innerFirstGit` | `bool` | Inner-first git traversal |
| `outerFirstGit` | `bool` | Outer-first git traversal |
| `topRepo` | `bool` | Find topmost git repo by traversing up |
| `exclude` | `List<String>` | Exclude patterns |
| `excludeProjects` | `List<String>` | Excluded project names/paths |
| `recursionExclude` | `List<String>` | Recursion exclude patterns |
| `executionMode` | `ExecutionMode` | Computed: project or workspace |
| `isWorkspaceMode` | `bool` | True if in workspace mode |
| `isProjectMode` | `bool` | True if in project mode |

### WorkspaceNavigationArgs Methods

| Method | Description |
|--------|-------------|
| `withDefaults()` | Apply default scan/recursive/build-order if no explicit nav |
| `copyWith(...)` | Create modified copy |

## Tools Using This System

All these tools share identical navigation options:

| Tool | Package | Purpose |
|------|---------|---------|
| `buildkit` | tom_build_kit | Pipeline orchestration |
| `versioner` | tom_build_kit | Version file generation |
| `compiler` | tom_build_kit | Cross-platform compilation |
| `cleanup` | tom_build_kit | Clean generated files |
| `runner` | tom_build_kit | Build_runner wrapper |
| `bumpversion` | tom_build_kit | Bump pubspec versions |
| `dependencies` | tom_build_kit | Dependency tree visualization |
| `buildsorter` | tom_build_kit | Build order sorting |
| `astgen` | tom_d4rt_astgen | AST serialization |
| `d4rtgen` | tom_d4rt_generator | D4rt bridge generation |
