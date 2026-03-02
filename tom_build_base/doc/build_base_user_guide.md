# Tom Build Base User Guide

This guide explains how to use `tom_build_base` to create CLI tools that integrate with Tom workspace configuration patterns.

## Related Documentation

- [CLI Tools Navigation](cli_tools_navigation.md) — Standard navigation options, help topics, execution modes
- [Modes and Placeholders](modes_and_placeholders.md) — Mode system and all placeholder types
- [Multi-Workspace Pipelines, Macros, and Defines](multiws_pipelines_macros_defines.md) — Pipeline execution, runtime macros, persistent defines
- [Tool Inheritance and Nesting](tool_inheritance_and_nesting.md) — Tool composition and nested tool wiring

---

## Overview

`tom_build_base` provides two API tiers:

### V2 Framework (Recommended for New Tools)

The declarative tool framework based on `ToolDefinition`, `CommandDefinition`, `OptionDefinition`, and `ToolRunner`. Features:

- **Declarative tool definition** — Define tools, commands, and options as immutable data structures
- **Automatic help generation** — `--help`, `help <command>`, `help <topic>` with consistent formatting
- **Built-in traversal** — Project and git traversal handled by the framework
- **Pipelines, macros, defines** — Multi-command tools get pipelines, runtime macros, and persistent defines automatically
- **Nested tool wiring** — Declarative integration of external tool binaries
- **Help topics** — Built-in topics (defines, macros, pipelines, placeholders, wiring) auto-injected for multi-command tools
- **Folder natures** — Type-safe project classification (DartProject, GitRepo, FlutterProject, etc.)
- **Console markdown** — Zone-based ANSI markdown rendering for all output

### V1 API (Still Available)

The imperative API for tools that manage their own argument parsing and traversal:

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

```yaml
dependencies:
  tom_build_base: ^2.5.0
```

```dart
// V2 framework (recommended)
import 'package:tom_build_base/tom_build_base_v2.dart';

// V1 API + selected V2 classes
import 'package:tom_build_base/tom_build_base.dart';
```

---

## V2 Tool Framework

The V2 framework lets you define tools declaratively. The framework handles argument parsing, help generation, traversal, mode/placeholder resolution, pipelines, macros, defines, and nested tool wiring.

### Core Classes

| Class | Purpose |
|-------|---------|
| `ToolDefinition` | Declares tool name, version, mode, commands, options, features |
| `CommandDefinition` | Declares a command with options, nature requirements, aliases |
| `OptionDefinition` | Declares a CLI option (flag, option, or multi-option) |
| `ToolRunner` | Parses args, handles traversal, dispatches to executors |
| `CommandExecutor` | Abstract class for command execution logic |
| `CommandContext` | Context passed to executors (path, natures, traversal info) |
| `HelpTopic` | Named help topic with summary and content |
| `ToolResult` / `ItemResult` | Execution result containers |

### Defining a Tool

```dart
import 'package:tom_build_base/tom_build_base_v2.dart';

const myTool = ToolDefinition(
  name: 'mytool',
  description: 'My custom build tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,  // or singleCommand, hybrid
  features: NavigationFeatures(
    projectTraversal: true,
    gitTraversal: false,
    recursiveScan: true,
    verbose: true,
  ),
  globalOptions: [
    OptionDefinition.flag(
      name: 'force',
      abbr: 'f',
      description: 'Force operation without confirmation',
    ),
  ],
  commands: [
    CommandDefinition(
      name: 'build',
      description: 'Build the project',
      aliases: ['b'],
      options: [
        OptionDefinition.option(
          name: 'target',
          abbr: 't',
          description: 'Build target platform',
        ),
      ],
      requiredNatures: {DartProjectFolder},
    ),
    CommandDefinition(
      name: 'clean',
      description: 'Clean build artifacts',
      aliases: ['c'],
    ),
  ],
  helpTopics: [
    HelpTopic(
      name: 'config',
      summary: 'Configuration file format',
      content: 'Detailed help content here...',
    ),
  ],
);
```

### Tool Modes

| Mode | Description | Example |
|------|-------------|---------|
| `ToolMode.multiCommand` | Tool has named sub-commands (`:build`, `:clean`) | `buildkit`, `testkit` |
| `ToolMode.singleCommand` | Tool has one implicit command | `astgen`, `d4rtgen` |
| `ToolMode.hybrid` | Multi-command with a default single-command mode | |

### Navigation Features

`NavigationFeatures` controls which traversal capabilities are enabled:

| Feature | Default | Description |
|---------|---------|-------------|
| `projectTraversal` | `true` | Project scanning and discovery |
| `gitTraversal` | `false` | Git repository traversal (`-i`, `-o`, `-T`) |
| `recursiveScan` | `true` | Recursive directory scanning (`-r`) |
| `interactiveMode` | `false` | TUI/interactive mode support |
| `dryRun` | `false` | Dry-run mode (`-n`) |
| `jsonOutput` | `false` | JSON output mode |
| `verbose` | `true` | Verbose output (`-v`) |

Predefined configurations: `NavigationFeatures.all`, `NavigationFeatures.minimal`, `NavigationFeatures.projectTool`, `NavigationFeatures.gitTool`.

### Defining Options

```dart
// Flag (boolean)
OptionDefinition.flag(
  name: 'verbose',
  abbr: 'v',
  description: 'Enable verbose output',
  negatable: false,
)

// Option (single value)
OptionDefinition.option(
  name: 'config',
  abbr: 'c',
  description: 'Config file path',
  valueName: 'path',
  mandatory: false,
)

// Multi-option (repeated values)
OptionDefinition.multi(
  name: 'tags',
  description: 'Tags to include',
  valueName: 'tag',
)
```

### Command Executors

Implement `CommandExecutor` for each command:

```dart
class BuildExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final target = args.extraOptions['target'] as String?;
    
    // Access project info via natures
    if (context.isDartProject) {
      final dart = context.getNature<DartProjectFolder>();
      print('Building ${dart.projectName} v${dart.version}');
    }
    
    // Do work...
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: 'Built successfully',
    );
  }
}
```

**Built-in executor types:**

| Executor | Description |
|----------|-------------|
| `CallbackExecutor` | Wraps `Future<ItemResult> Function(CommandContext, CliArgs)` |
| `SyncExecutor` | Wraps synchronous `ItemResult Function(CommandContext, CliArgs)` |
| `ShellExecutor` | Runs a shell command string |
| `DartExecutor` | Runs a Dart function returning bool |
| `ListExecutor` | No-op executor for list-only commands |

### Running the Tool

```dart
void main(List<String> args) async {
  final runner = ToolRunner(
    tool: myTool,
    executors: {
      'build': BuildExecutor(),
      'clean': CallbackExecutor(
        onExecute: (context, args) async {
          // clean logic
          return ItemResult.success(path: context.path, name: context.name);
        },
      ),
    },
  );

  final result = await runner.run(args);
  exit(result.success ? 0 : 1);
}
```

### ToolRunner Execution Flow

`ToolRunner.run()` handles the complete lifecycle:

1. **Macro expansion** — `@macro` references expanded from `<tool>_macros.yaml`
2. **Argument parsing** — Via `CliArgParser` using the tool's option definitions
3. **`--dump-definitions`** — If requested, serialize tool definition as YAML and exit
4. **`--nested` mode** — If set, skip wiring and traversal, execute in current directory
5. **Lazy wiring** — Wire nested tools from `defaultIncludes` + YAML `nested_tools:`
6. **Help topic injection** — Auto-inject `masterYamlHelpTopics` for multi-command tools
7. **Help/version** — Handle `--help`, `--version`, `help <command>`, `help <topic>`
8. **Pipeline detection** — For multi-command tools, detect pipeline invocations
9. **Command routing** — Route to appropriate `CommandExecutor`
10. **Traversal** — Project or git traversal with nature detection
11. **Placeholder resolution** — `%{...}` and `@[...]` resolved per folder during traversal

### CommandContext

Executors receive a `CommandContext` with:

| Property | Type | Description |
|----------|------|-------------|
| `path` | `String` | Absolute path to current project/folder |
| `name` | `String` | Folder name |
| `relativePath` | `String` | Relative to execution root |
| `executionRoot` | `String` | Root of traversal |
| `natures` | `List<RunFolder>` | Detected folder natures |
| `traversal` | `BaseTraversalInfo?` | Traversal configuration |

**Nature access methods:**

```dart
context.isDartProject;                   // Quick check
context.isGitRepo;                       // Quick check
context.hasNature<FlutterProjectFolder>(); // Generic check
context.getNature<DartProjectFolder>();   // Get typed nature (throws if missing)
context.tryGetNature<GitFolder>();        // Get typed nature (null if missing)
```

### Folder Natures

Natures are auto-detected for each folder during traversal:

| Nature | Detection | Key Properties |
|--------|-----------|----------------|
| `DartProjectFolder` | `pubspec.yaml` exists | `projectName`, `version`, `dependencies` |
| `FlutterProjectFolder` | `pubspec.yaml` + Flutter SDK dep | `platforms`, `isPlugin` |
| `DartConsoleFolder` | `pubspec.yaml` + `bin/` entries | `executables` |
| `GitFolder` | `.git/` exists | `currentBranch`, `hasUncommittedChanges`, `remotes` |
| `VsCodeExtensionFolder` | `package.json` with VS Code engine | `extensionName`, `displayName` |
| `TypeScriptFolder` | `tsconfig.json` exists | `projectName`, `isNodeProject` |
| `BuildkitFolder` | `buildkit.yaml` exists | `config`, `projectId` |
| `BuildRunnerFolder` | `build.yaml` exists | `config` |
| `TomBuildFolder` | Various Tom config files | `projectName`, `shortId` |

### Common Options

All V2 tools automatically include these options (from `commonOptions`):

| Option | Abbr | Type | Description |
|--------|------|------|-------------|
| `--exclude` | `-x` | multi | Exclude patterns (path-based globs) |
| `--test` | | flag | Include test projects |
| `--test-only` | | flag | Process only test projects |
| `--execution-root` | `-R` | option | Execution root path |
| `--modes` | | multi | Active modes for mode-specific defines |
| `--verbose` | `-v` | flag | Enable verbose output |
| `--dry-run` | `-n` | flag | Show what would be done |
| `--help` | `-h` | flag | Show help |
| `--version` | | flag | Show version |
| `--nested` | | flag | Run in nested mode (skip traversal) |
| `--dump-definitions` | | flag | Dump tool definition as YAML |

Tools with `projectTraversal` enabled also get `projectTraversalOptions` (scan, recursive, build-order, project, etc.). Tools with `gitTraversal` enabled get `gitTraversalOptions` (inner-first-git, outer-first-git, top-repo, modules, etc.).

### Help Topics

Help topics provide contextual documentation accessible via `<tool> help <topic>`.

**Built-in topics (auto-injected for multi-command tools):**

| Topic | Constant | Available To |
|-------|----------|-------------|
| `placeholders` | `placeholdersHelpTopic` | All tools |
| `defines` | `definesHelpTopic` | Multi-command tools with `<tool>_master.yaml` |
| `macros` | `macrosHelpTopic` | Multi-command tools with `<tool>_master.yaml` |
| `pipelines` | `pipelinesHelpTopic` | Multi-command tools with `<tool>_master.yaml` |
| `wiring` | `wiringHelpTopic` | Multi-command tools with `<tool>_master.yaml` |

The `{TOOL}` placeholder in help topic content is automatically replaced with the current tool's name.

**Custom topics:**

```dart
const myTool = ToolDefinition(
  // ...
  helpTopics: [
    HelpTopic(
      name: 'config',
      summary: 'Configuration file format',
      content: '''
## {TOOL} Configuration

{TOOL} reads configuration from `{TOOL}_master.yaml` and project `{TOOL}.yaml`.
...
''',
    ),
  ],
);
```

### Tool Inheritance (copyWith)

Create derived tools by copying and modifying an existing definition:

```dart
final superTool = buildkitTool.copyWith(
  name: 'supertool',
  version: '1.0.0',
  commands: buildkitTool.commands
      .without({'dcli', 'findproject'})           // remove
      .replacing('runner', myCustomRunnerCommand)  // replace
      .plus([d4rtgenCommand, astgenCommand]),       // add
);
```

See [Tool Inheritance and Nesting](tool_inheritance_and_nesting.md) for the complete reference.

### Nested Tool Wiring

Host tools can embed external tool binaries as commands via declarative wiring:

```dart
const buildkitTool = ToolDefinition(
  name: 'buildkit',
  wiringFile: ToolDefinition.kAutoWiringFile,  // → buildkit_master.yaml
  defaultIncludes: [
    ToolWiringEntry(
      binary: 'testkit',
      mode: WiringMode.multiCommand,
      commands: {'buildkittest': 'test', 'buildkitbaseline': 'baseline'},
    ),
    ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
  ],
  // ...
);
```

YAML overrides in `<tool>_master.yaml`:

```yaml
nested_tools:
  testkit:
    binary: testkit
    mode: multi_command
    commands:
      buildkittest: test
      buildkitbaseline: baseline
```

See [Tool Inheritance and Nesting](tool_inheritance_and_nesting.md) for the complete wiring reference.

### Console Markdown

All V2 tools support console markdown for formatted output:

```dart
import 'package:tom_build_base/tom_build_base_v2.dart';

void main(List<String> args) async {
  await runWithConsoleMarkdown(() async {
    final runner = ToolRunner(tool: myTool, executors: executors);
    final result = await runner.run(args);
    exit(result.success ? 0 : 1);
  });
}
```

This enables ANSI-colored formatting for headers (`## Title`), bold (`**text**`), inline code (`` `code` ``), and other markdown elements in all `print()` and `StringSink.writeln()` output within the zone.

---

## V1 API Reference

The V1 API is still available and used by tools that manage their own argument parsing and traversal. New tools should prefer the V2 framework above.

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

### V2 Framework

| Class / Function | Module | Purpose |
|------------------|--------|---------|
| `ToolDefinition` | v2/core/tool_definition | Declarative tool definition with commands and options |
| `CommandDefinition` | v2/core/command_definition | Command definition with options and nature requirements |
| `OptionDefinition` | v2/core/option_definition | CLI option definition (flag, option, multi) |
| `ToolRunner` | v2/core/tool_runner | Argument parsing, traversal, command dispatch |
| `CommandExecutor` | v2/core/command_executor | Abstract command execution interface |
| `CallbackExecutor` | v2/core/command_executor | Async callback-based executor |
| `SyncExecutor` | v2/core/command_executor | Synchronous callback-based executor |
| `ShellExecutor` | v2/core/command_executor | Shell command executor |
| `CommandContext` | v2/traversal/command_context | Per-project execution context with natures |
| `ToolResult` / `ItemResult` | v2/core/tool_runner | Execution result containers |
| `HelpTopic` | v2/core/help_topic | Named help topic with summary and content |
| `HelpGenerator` | v2/core/help_generator | Static help text generation methods |
| `CliArgs` / `CliArgParser` | v2/core/cli_arg_parser | Parsed arguments and parser |
| `ToolWiringEntry` | v2/core/tool_wiring_entry | Nested tool wiring configuration |
| `WiringLoader` | v2/core/wiring_loader | Resolves nested tool wiring |
| `NestedToolExecutor` | v2/core/nested_tool_executor | Executor that delegates to external binary |
| `ToolDefinitionSerializer` | v2/core/tool_definition_serializer | YAML serialization for `--dump-definitions` |
| `ToolPipelineExecutor` | v2/core/pipeline_executor | Pipeline step execution with placeholder resolution |
| `ToolPipelineConfig` | v2/core/pipeline_config | Pipeline YAML parsing |
| `expandMacros()` | v2/core/macro_expansion | `@macro` expansion with `$1`–`$9` and `$$` |
| `CompletionGenerator` | v2/core/completion_generator | Shell completion generation (bash, zsh, fish) |
| `NavigationFeatures` | v2/core/tool_definition | Feature flags for traversal capabilities |
| `commonOptions` | v2/core/option_definition | Standard global options for all V2 tools |
| `projectTraversalOptions` | v2/core/option_definition | Project traversal options |
| `gitTraversalOptions` | v2/core/option_definition | Git traversal options |
| `defaultHelpTopics` | v2/core/builtin_help_topics | Help topics for all tools (placeholders) |
| `masterYamlHelpTopics` | v2/core/builtin_help_topics | Help topics for multi-command tools (defines, macros, pipelines, wiring) |

### V2 Folder Natures

| Class | Module | Detection |
|-------|--------|-----------|
| `FsFolder` | v2/folder/fs_folder | Base folder wrapper |
| `RunFolder` | v2/folder/run_folder | Abstract nature base |
| `DartProjectFolder` | v2/folder/natures | `pubspec.yaml` |
| `FlutterProjectFolder` | v2/folder/natures | Flutter SDK dep |
| `DartConsoleFolder` | v2/folder/natures | `bin/` entries |
| `GitFolder` | v2/folder/natures | `.git/` directory |
| `VsCodeExtensionFolder` | v2/folder/natures | VS Code `package.json` |
| `TypeScriptFolder` | v2/folder/natures | `tsconfig.json` |
| `BuildkitFolder` | v2/folder/natures | `buildkit.yaml` |
| `BuildRunnerFolder` | v2/folder/natures | `build.yaml` |
| `TomBuildFolder` | v2/folder/natures | Tom config files |

### V1 API

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
