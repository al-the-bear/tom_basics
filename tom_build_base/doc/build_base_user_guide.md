# Tom Build Base User Guide

This guide explains how to use `tom_build_base` to create CLI tools that integrate with the `buildkit.yaml` and `build.yaml` configuration patterns used in Tom workspaces.

## Overview

`tom_build_base` provides shared infrastructure for Tom build tools:

- **Configuration loading** — `TomBuildConfig` for reading `buildkit.yaml` and `buildkit_master.yaml`
- **Configuration merging** — `ConfigMerger` for combining workspace and project settings
- **Build.yaml utilities** — detect builder definitions vs consumers, read options
- **Project scanning** — `ProjectScanner` for directory traversal with custom validators
- **Project discovery** — `ProjectDiscovery` for glob-based resolution and workspace search
- **Project navigation** — `ProjectNavigator` for unified navigation with configurable features
- **Path validation** — `isPathContained`, `validatePathContainment` for security
- **Result tracking** — `ProcessingResult` for batch success/failure/file counting

## Installation

```yaml
dependencies:
  tom_build_base: ^1.1.0
```

```dart
import 'package:tom_build_base/tom_build_base.dart';
```

---

## Configuration

### Two-Tier Configuration Pattern

Tom tools use a **workspace-level** master config (`buildkit_master.yaml`) and **project-level** configs (`buildkit.yaml`). Each file contains sections keyed by tool name.

```yaml
# buildkit_master.yaml (workspace root)
navigation:                     # shared defaults for all tools
  scan: .
  recursive: true
  exclude: [.git, build, node_modules]

show_versions:                  # tool-specific section
  verbose: false
```

```yaml
# buildkit.yaml (inside a project)
show_versions:
  verbose: true                 # overrides workspace default
```

### Loading Configuration

```dart
const toolKey = 'show_versions';
final basePath = Directory.current.path;

// Load workspace-level config
final masterConfig = TomBuildConfig.loadMaster(
  dir: basePath,
  toolKey: toolKey,
);

// Load project-level config
final projectConfig = TomBuildConfig.load(
  dir: basePath,
  toolKey: toolKey,
);
```

The `navigation:` section in the master file provides shared defaults (scan, recursive, exclude, recursion-exclude) that are automatically merged as fallbacks for every tool section.

### TomBuildConfig Properties

| Property | Type | Description |
|----------|------|-------------|
| `project` | `String?` | Single project directory path |
| `projects` | `List<String>` | Glob patterns for project discovery |
| `scan` | `String?` | Root directory to scan |
| `config` | `String?` | Explicit config file path |
| `recursive` | `bool` | Recurse into found projects |
| `exclude` | `List<String>` | Glob patterns to exclude projects |
| `excludeProjects` | `List<String>` | Exclusions matched against directory basename only |
| `recursionExclude` | `List<String>` | Directories to skip during recursive traversal |
| `verbose` | `bool` | Enable detailed output |
| `toolOptions` | `Map<String, dynamic>` | All raw options from the tool section |

### Merging Configurations

Use `TomBuildConfig.merge()` to combine master and project configs:

```dart
final config = (masterConfig != null && projectConfig != null)
    ? masterConfig.merge(projectConfig)     // project overrides master
    : projectConfig ?? masterConfig ?? const TomBuildConfig();
```

### Checking for Configuration

```dart
// Does this project have a show_versions: section in buildkit.yaml?
if (hasTomBuildConfig(projectPath, 'show_versions')) {
  print('Has tool config');
}

// Does the config specify any project navigation options?
if (config.hasProjectOptions) {
  print('Has project/scan/config options');
}
```

---

## ConfigMerger

`ConfigMerger` provides three strategies for combining workspace and project values. Use it when your tool has its own config structure beyond `TomBuildConfig`.

### Section Lists — Project Replaces Workspace

For "what to do" definitions where the project provides a complete replacement.

```dart
final modules = ConfigMerger.mergeSections(
  workspaceModules,   // ['core']
  projectModules,     // ['core', 'extra']
);
// → ['core', 'extra']  (project wins because it's non-empty)
```

### Additive Lists — Union of Both

For guard/filter lists where both levels contribute (deduplication preserved).

```dart
final excludes = ConfigMerger.mergeAdditive(
  ['build', 'node_modules'],  // workspace
  ['coverage', 'build'],      // project
);
// → ['build', 'node_modules', 'coverage']  (union, no duplicates)
```

### Scalar Values — Project Overrides Workspace

```dart
// Simple override
final verbose = ConfigMerger.mergeScalar(false, true);
// → true  (project wins)

// With explicit-check callback
final output = ConfigMerger.mergeScalar<String?>(
  'lib/src/version.versioner.dart',
  null,
  isExplicit: (v) => v != null,
);
// → 'lib/src/version.versioner.dart'  (project is null, so workspace wins)

// Nullable convenience
final prefix = ConfigMerger.mergeNullable('v', null);
// → 'v'

// Map merge (project keys override workspace keys)
final opts = ConfigMerger.mergeMaps(
  {'a': 1, 'b': 2},
  {'b': 99, 'c': 3},
);
// → {'a': 1, 'b': 99, 'c': 3}
```

---

## Build.yaml Utilities

These helpers inspect `build.yaml` files (the standard `build_runner` format) and let you distinguish builder-*definition* packages from builder-*consumer* packages.

| Function | Returns | Purpose |
|----------|---------|---------|
| `isBuildYamlBuilderDefinition(dirPath)` | `bool` | Has `builders:` section (skip these) |
| `hasBuildYamlConsumerConfig(dirPath, builderName)` | `bool` | Has `targets.$default.builders.{name}` |
| `isBuildYamlBuilderEnabled(dirPath, builderName)` | `bool` | Is the builder enabled (default `true`)? |
| `getBuildYamlBuilderOptions(dirPath, builderName)` | `Map?` | Extract `options` map for a builder |

### Example

```dart
// Skip builder definition packages
if (isBuildYamlBuilderDefinition(projectPath)) return;

// Check consumer configuration
const builder = 'tom_version_builder:version_builder';

if (hasBuildYamlConsumerConfig(projectPath, builder)) {
  final enabled = isBuildYamlBuilderEnabled(projectPath, builder);
  final options = getBuildYamlBuilderOptions(projectPath, builder);
  final output = options?['output'] ?? 'lib/src/version.versioner.dart';
}
```

---

## Path Validation

Prevent directory-traversal attacks by ensuring user-supplied paths stay inside the workspace.

```dart
// Single path check
if (isPathContained(targetPath, workspaceRoot)) {
  // safe
}

// Validate all configured paths at once
final error = validatePathContainment(
  project: config.project,
  projects: config.projects,
  scan: config.scan,
  config: config.config,
  basePath: workspaceRoot,
);
if (error != null) {
  stderr.writeln('Path error: $error');
  exit(1);
}
```

---

## Project Scanning — ProjectScanner

`ProjectScanner` walks directories to find projects that match a `ProjectValidator`.

### Creating a Scanner

```dart
final scanner = ProjectScanner(
  toolKey: 'mytool',
  basePath: workspaceRoot,
  verbose: true,
  log: (msg) => print('[scan] $msg'),
  // Optional: custom validator (default checks pubspec.yaml + build config)
  projectValidator: (dirPath, toolKey) =>
      File('$dirPath/pubspec.yaml').existsSync(),
);
```

### Finding Projects

```dart
// Recursive directory scan
final projects = scanner.scanForProjects(workspaceRoot, excludePatterns);

// Immediate subprojects only
final subs = scanner.findSubprojects(projectDir, excludePatterns);

// Glob-based matching
final matched = scanner.findProjectsByGlob(['tom_*', 'xternal/**'], []);

// Apply exclusions to an existing list
final filtered = scanner.applyExclusions(paths, ['zom_*', 'build']);
```

### Custom Project Validation

```dart
bool myValidator(String dirPath, String toolKey) {
  if (!File('$dirPath/pubspec.yaml').existsSync()) return false;
  if (isBuildYamlBuilderDefinition(dirPath)) return false;
  return hasTomBuildConfig(dirPath, toolKey);
}

final scanner = ProjectScanner(
  toolKey: 'mytool',
  basePath: workspaceRoot,
  projectValidator: myValidator,
);
```

---

## Project Discovery — ProjectDiscovery

`ProjectDiscovery` offers advanced glob-based resolution with workspace-wide searching.

### Scan vs Recursive Behaviour

- **Scan**: walks subfolders until a project is found, then stops (project is a boundary).
- **Recursive**: also looks *inside* found projects for nested projects (e.g., test projects).

### Resolving Patterns

```dart
final discovery = ProjectDiscovery(verbose: true);

// Comma-separated patterns, brace-group aware
final projects = await discovery.resolveProjectPatterns(
  'tom_*,xternal/tom_module_*/*',
  basePath: workspaceRoot,
  projectFilter: (path) => !isBuildYamlBuilderDefinition(path),
);
```

### Scanning a Directory

```dart
final found = await discovery.scanForProjects(
  workspaceRoot,
  recursive: true,
  toolKey: 'mytool',
  recursionExclude: ['**/build/**', 'node_modules'],
);
```

### Skip Files and Workspace Root

```dart
// Check for tom_build_skip.yaml marker (stops traversal)
if (ProjectDiscovery.hasSkipFile(dirPath)) {
  print('Skipping: $dirPath');
}

// Find the workspace root by walking up to tom_workspace.yaml
final root = ProjectDiscovery.findWorkspaceRoot(Directory.current.path);
```

---

## Project Navigation — ProjectNavigator

`ProjectNavigator` provides unified project navigation with configurable feature opt-in/opt-out. It's designed for CLI tools that need consistent navigation behavior while supporting tool-specific customizations.

### Why Use ProjectNavigator?

- **Unified behavior** — All navigation features (scanning, filtering, git traversal, build order) in one place
- **Configurable** — Enable/disable features per tool via `NavigationConfig`
- **Consistent** — Same behavior across buildkit, testkit, and other tools
- **Complete** — Handles all standard navigation options from `WorkspaceNavigationArgs`

### Basic Usage

```dart
import 'package:tom_build_base/tom_build_base.dart';

// Create navigator with all features enabled
final navigator = ProjectNavigator(
  config: const NavigationConfig.all(),
  verbose: true,
);

// Navigate using parsed navigation args
final result = await navigator.navigate(
  navArgs,
  basePath: executionRoot,
);

if (result.hasError) {
  print('Error: ${result.errorMessage}');
  return;
}

for (final project in result.paths) {
  // Process each project
}
```

### NavigationConfig — Feature Control

`NavigationConfig` allows tools to opt-in or opt-out of navigation features:

```dart
// Full buildkit-style navigation (all features)
final config = NavigationConfig.all();

// Minimal navigation (just discovery, no filtering)
final config = NavigationConfig.minimal();

// Custom configuration
final config = NavigationConfig(
  usePathExclude: true,       // Apply --exclude patterns
  useNameExclude: true,       // Apply --exclude-projects patterns
  useModulesFilter: true,     // Apply --modules filter
  useRecursionExclude: true,  // Apply --recursion-exclude patterns
  useSkipFiles: true,         // Skip dirs with buildkit_skip.yaml
  useMasterConfigDefaults: true, // Load defaults from buildkit_master.yaml
  useBuildOrder: true,        // Sort by dependency order
  useGitTraversal: true,      // Support --inner-first-git/--outer-first-git
  projectFilter: _isTestableProject, // Custom project filter function
);
```

### Custom Project Filters

Filter projects by providing a callback function:

```dart
// Only process projects with test/ directories
bool _isTestableProject(String dirPath) {
  if (!File('$dirPath/pubspec.yaml').existsSync()) return false;
  return Directory('$dirPath/test').existsSync();
}

final navigator = ProjectNavigator(
  config: NavigationConfig(
    projectFilter: _isTestableProject,
    // ... other options
  ),
);
```

### Git Repository Traversal

For git-based operations (commit, push, pull):

```dart
final navigator = ProjectNavigator(
  config: const NavigationConfig.all(),
);

// --inner-first-git: deepest repos first (for commit/push)
// --outer-first-git: shallowest repos first (for pull/fetch)
final result = await navigator.navigate(navArgs, basePath: wsRoot);

if (result.isGitMode) {
  // result.paths contains git repository roots
  for (final repo in result.paths) {
    await runGitCommand(repo, 'commit', ['-m', 'Update']);
  }
}
```

### Build Order Sorting

Sort projects by dependency order (dependencies before dependents):

```dart
// Using navigator (respects navArgs.buildOrder)
final config = NavigationConfig(useBuildOrder: true);
final navigator = ProjectNavigator(config: config);
final result = await navigator.navigate(navArgs, basePath: root);

// Or use the static method directly
final sorted = navigator.sortByBuildOrder(projects);
if (sorted != null) {
  // sorted is in dependency order
} else {
  // circular dependency detected
}
```

### Static Filter Methods

`ProjectNavigator` provides static methods for filtering outside of navigation:

```dart
// Filter by path patterns (glob matching)
final filtered = ProjectNavigator.filterByPath(
  projects,
  ['**/test/**', '**/example/**'],
);

// Filter by project name patterns
final filtered = ProjectNavigator.filterByName(
  projects,
  ['zom_*', '*_test'],
  wsRoot,
);

// Remove projects with skip files
final filtered = ProjectNavigator.filterSkippedProjects(projects);

// Check for skip file
if (ProjectNavigator.hasSkipFile(dirPath)) {
  print('Skipping: $dirPath');
}
```

### Loading Master Config Defaults

```dart
// Load navigation defaults from buildkit_master.yaml
final defaults = ProjectNavigator.loadNavigationDefaults(basePath);
if (defaults != null) {
  print('Default scan: ${defaults.scan}');
  print('Recursive: ${defaults.recursive}');
  print('Exclude: ${defaults.exclude}');
}

// Load exclude-projects from master config
final excludeProjects = ProjectNavigator.loadMasterExcludeProjects(basePath);
```

### NavigationResult

The `navigate()` method returns a `NavigationResult`:

| Property | Type | Description |
|----------|------|-------------|
| `paths` | `List<String>` | Discovered project/repo paths |
| `isGitMode` | `bool` | True if git traversal was used |
| `hasError` | `bool` | True if an error occurred |
| `errorMessage` | `String?` | Error message if `hasError` is true |

---

## Result Tracking — ProcessingResult

Track success/failure counts across batch operations.

```dart
final result = ProcessingResult();

for (final project in projects) {
  try {
    final files = processProject(project);
    result.addSuccess(files);   // count processed files
  } catch (_) {
    result.addFailure();
  }
}

// Merge results from a parallel workstream
result.merge(otherResult);

// Inspect
print('Total    : ${result.totalCount}');
print('Succeeded: ${result.successCount}');
print('Failed   : ${result.failureCount}');
print('Files    : ${result.fileCount}');
print('OK?      : ${result.isSuccess}');

exit(result.hasFailures ? 1 : 0);
```

---

## Included CLI Tool — `show_versions`

The package ships a ready-to-use tool in `bin/show_versions.dart`:

```bash
dart run tom_build_base:show_versions [workspace-path]
```

The underlying logic is the importable `showVersions()` function:

```dart
final result = await showVersions(ShowVersionsOptions(
  basePath: workspaceRoot,
  verbose: true,
  log: print,
));

for (final entry in result.versions.entries) {
  print('${p.basename(entry.key)}: ${entry.value}');
}

if (!result.isSuccess) exit(1);
```

`showVersions()` exercises the full library surface: config loading & merging, project scanning & discovery, build.yaml utilities, path validation, and result tracking.

See [example/tom_build_base_example.dart](../example/tom_build_base_example.dart) for a minimal usage example.

---

## Best Practices

1. **Skip builder definitions** — always call `isBuildYamlBuilderDefinition()` before processing.
2. **Support both config formats** — check `tom_build.yaml` first, fall back to `build.yaml`.
3. **Merge configs** — load master, load project, `master.merge(project)`.
4. **Validate paths** — call `validatePathContainment()` before any file I/O.
5. **Track results** — use `ProcessingResult` for consistent CI-friendly exit codes.
6. **Respect verbose** — honour `config.verbose` for debugging output.
7. **Use exit codes** — return `0` on success, `1` on failures.

---

## API Quick Reference

| Class / Function | Module | Purpose |
|------------------|--------|---------|
| `TomBuildConfig` | build_config | Load, merge, copy-with config |
| `TomBuildConfig.load()` | build_config | Read `tom_build.yaml` |
| `TomBuildConfig.loadMaster()` | build_config | Read `buildkit_master.yaml` |
| `hasTomBuildConfig()` | build_config | Check for tool section |
| `ConfigMerger` | config_merger | Static merge helpers |
| `ProjectScanner` | project_scanner | Directory-walk project finder |
| `ProjectDiscovery` | project_discovery | Glob / workspace-wide finder |
| `ProjectNavigator` | project_navigator | Unified navigation with config |
| `NavigationConfig` | project_navigator | Feature opt-in/opt-out |
| `NavigationDefaults` | project_navigator | Master config default values |
| `NavigationResult` | project_navigator | Navigation result container |
| `ProcessingResult` | processing_result | Batch result tracker |
| `isPathContained()` | path_utils | Single path containment |
| `validatePathContainment()` | path_utils | Multi-path validation |
| `showVersions()` | show_versions | Discover projects & read versions |
| `readPubspecVersion()` | show_versions | Read version from pubspec.yaml |
| `ShowVersionsResult` | show_versions | Structured result with versions map |
| `isBuildYamlBuilderDefinition()` | build_yaml_utils | Detect builder packages |
| `hasBuildYamlConsumerConfig()` | build_yaml_utils | Detect consumer config |
| `getBuildYamlBuilderOptions()` | build_yaml_utils | Read builder options |
| `isBuildYamlBuilderEnabled()` | build_yaml_utils | Check builder enabled flag |
| `WorkspaceNavigationArgs` | workspace_mode | Parsed navigation options |
| `addNavigationOptions()` | workspace_mode | Add nav options to ArgParser |
| `parseNavigationArgs()` | workspace_mode | Parse nav options from ArgResults |
| `resolveExecutionRoot()` | workspace_mode | Resolve workspace root |
| `findWorkspaceRoot()` | workspace_mode | Find workspace by traversing up |
| `toStringList()` | yaml_utils | Convert YAML to List<String> |
