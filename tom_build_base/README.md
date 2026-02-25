# Tom Build Base

Shared infrastructure for Tom build tools — configuration loading, project scanning, path validation, and `build.yaml` utilities.

This package provides the common foundation that Tom CLI build tools (like `tom_d4rt_generator`, `tom_version_builder`, etc.) use to discover projects, load configuration, and traverse directory structures.

## Features

- **Configuration loading** — Two-tier config from `buildkit_master.yaml` (workspace) and `buildkit.yaml` (project), with automatic merging
- **Configuration merging** — `ConfigMerger` with additive, scalar, nullable, section, and map merge strategies
- **Project scanning** — `ProjectScanner` for directory traversal with custom validators, glob matching, and exclusions
- **Project discovery** — `ProjectDiscovery` for workspace-wide scanning with proper scan-vs-recursive semantics
- **Project navigation** — `ProjectNavigator` for unified navigation with configurable feature opt-in/opt-out
- **build.yaml utilities** — Detect builder definitions vs consumers, read options and enabled flags
- **Path validation** — `isPathContained` and `validatePathContainment` for directory-traversal protection
- **YAML utilities** — `yamlToMap()`, `yamlListToList()`, and `toStringList()` for converting YAML nodes
- **Result tracking** — `ProcessingResult` for batch success/failure/file counting

## Installation

```yaml
dependencies:
  tom_build_base: ^1.7.0
```

## Included CLI Tool — `show_versions`

The package ships a ready-to-use CLI tool that discovers Dart projects and prints their versions:

```bash
# Run from a workspace
dart run tom_build_base:show_versions [workspace-path]

# Or install globally
dart pub global activate tom_build_base
show_versions [workspace-path]
```

The same logic is available as an importable function:

```dart
final result = await showVersions(ShowVersionsOptions(basePath: '.'));
for (final entry in result.versions.entries) {
  print('${basename(entry.key)}: ${entry.value}');
}
```

## Usage

### Loading and Merging Configuration

```dart
import 'package:tom_build_base/tom_build_base.dart';

const toolKey = 'show_versions';

// Load workspace-level master config
final master = TomBuildConfig.loadMaster(dir: basePath, toolKey: toolKey);

// Load project-level config
final project = TomBuildConfig.load(dir: basePath, toolKey: toolKey);

// Merge (project overrides master)
final config = (master != null && project != null)
    ? master.merge(project)
    : project ?? master ?? const TomBuildConfig();
```

### Merging Custom Options

```dart
// Additive — union of both lists (deduped)
final excludes = ConfigMerger.mergeAdditive(workspaceExcludes, projectExcludes);

// Scalar — project overrides workspace
final verbose = ConfigMerger.mergeScalar(false, true);

// Map — project keys override, workspace keys preserved
final opts = ConfigMerger.mergeMaps({'a': 1}, {'b': 2});
```

### Scanning for Projects

```dart
final scanner = ProjectScanner(
  toolKey: toolKey,
  basePath: workspacePath,
  projectValidator: (dir, key) => File('$dir/pubspec.yaml').existsSync(),
);

// Recursive scan
final projects = scanner.scanForProjects(workspacePath, config.exclude);

// Glob-based matching
final matched = scanner.findProjectsByGlob(['tom_*', 'xternal/**'], []);

// Apply exclusions to an existing list
final filtered = scanner.applyExclusions(projects, ['zom_*']);
```

### Project Discovery (Glob Patterns)

```dart
final discovery = ProjectDiscovery(verbose: true);

// Resolve comma-separated glob patterns
final found = await discovery.resolveProjectPatterns(
  'tom_*,xternal/tom_module_*/*',
  basePath: workspacePath,
);
```

### Project Navigation (Unified)

For CLI tools, `ProjectNavigator` provides unified navigation with configurable features:

```dart
import 'package:tom_build_base/tom_build_base.dart';

// Create navigator with tool-specific config
final navigator = ProjectNavigator(
  config: NavigationConfig(
    usePathExclude: true,       // Apply --exclude patterns
    useNameExclude: true,       // Apply --exclude-projects
    useModulesFilter: true,     // Apply --modules filter
    useSkipFiles: true,         // Skip buildkit_skip.yaml dirs
    useMasterConfigDefaults: true, // Load from buildkit_master.yaml
    useBuildOrder: true,        // Sort by dependency order
    useGitTraversal: true,      // Support --inner-first-git / --outer-first-git
    projectFilter: (path) => File('$path/pubspec.yaml').existsSync(),
  ),
  verbose: true,
);

// Navigate using parsed navigation args
final result = await navigator.navigate(navArgs, basePath: executionRoot);

if (result.hasError) {
  print('Error: ${result.errorMessage}');
  return;
}

for (final project in result.paths) {
  // Process each project
}
```

Use `NavigationConfig.all()` for full features or `NavigationConfig.minimal()` for basic discovery.

### Detecting Builder Definitions

```dart
// Skip packages that define builders
if (isBuildYamlBuilderDefinition(projectPath)) return;

// Check consumer configuration and options
if (hasBuildYamlConsumerConfig(projectPath, 'my_package:my_builder')) {
  final enabled = isBuildYamlBuilderEnabled(projectPath, 'my_package:my_builder');
  final options = getBuildYamlBuilderOptions(projectPath, 'my_package:my_builder');
}
```

### Path Validation

```dart
final error = validatePathContainment(
  project: config.project,
  projects: config.projects,
  scan: config.scan,
  config: config.config,
  basePath: workspaceRoot,
);
if (error != null) exit(1);
```

### Result Tracking

```dart
final result = ProcessingResult();
result.addSuccess(3);   // 3 files processed
result.addFailure();
print('Total: ${result.totalCount}, Files: ${result.fileCount}');
exit(result.hasFailures ? 1 : 0);
```

## Configuration Format

Tom build tools use a two-tier configuration pattern:

### buildkit_master.yaml (workspace root)

```yaml
navigation:                   # shared defaults for all tools
  scan: .
  recursive: true
  exclude: [.git, build]

show_versions:                # tool-specific workspace defaults
  verbose: false
```

### buildkit.yaml (inside a project)

```yaml
show_versions:
  verbose: true               # overrides workspace default
```

## Documentation

- [build_base_user_guide.md](doc/build_base_user_guide.md) — Complete user guide with API reference
- [cli_tools_navigation.md](doc/cli_tools_navigation.md) — CLI navigation options and implementation guide

## License

BSD 3-Clause License — see [LICENSE](LICENSE) for details.

Author: Alexis Kyaw ([LinkedIn](https://www.linkedin.com/in/nickmeinhold/))

