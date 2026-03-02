# Tom Build Base User Guide

This guide explains how to use `tom_build_base` to create CLI tools that integrate with Tom workspace configuration patterns.

## Related Documentation

- [CLI Tools Navigation](cli_tools_navigation.md) — Standard navigation options, help topics, execution modes
- [Modes and Placeholders](modes_and_placeholders.md) — Mode system and all placeholder types
- [Multi-Workspace Pipelines, Macros, and Defines](multiws_pipelines_macros_defines.md) — Pipeline execution, runtime macros, persistent defines
- [Tool Inheritance and Nesting](tool_inheritance_and_nesting.md) — Tool composition and nested tool wiring

---

## Overview

`tom_build_base` provides a declarative CLI tool framework for building workspace tools.

### Tool Framework

The declarative tool framework based on `ToolDefinition`, `CommandDefinition`, `OptionDefinition`, and `ToolRunner`. Features:

- **Declarative tool definition** — Define tools, commands, and options as immutable data structures
- **Automatic help generation** — `--help`, `help <command>`, `help <topic>` with consistent formatting
- **Built-in traversal** — Project and git traversal handled by the framework
- **Pipelines, macros, defines** — Multi-command tools get pipelines, runtime macros, and persistent defines automatically
- **Nested tool wiring** — Declarative integration of external tool binaries
- **Help topics** — Built-in topics (defines, macros, pipelines, placeholders, wiring) auto-injected for multi-command tools
- **Folder natures** — Type-safe project classification (DartProject, GitRepo, FlutterProject, etc.)
- **Console markdown** — Zone-based ANSI markdown rendering for all output

### Utility Classes

Standalone utility classes used by tools for configuration loading and process execution:

- **Configuration loading** — `TomBuildConfig` for reading `buildkit.yaml` and `buildkit_master.yaml`
- **Process execution** — `ProcessRunner` for running external processes with logging
- **YAML utilities** — `yamlToMap()`, `yamlListToList()`, `toStringList()` for converting YAML nodes

## Installation

```yaml
dependencies:
  tom_build_base: ^2.6.0
```

```dart
import 'package:tom_build_base/tom_build_base.dart';

// Or for explicit V2 import (same content):
import 'package:tom_build_base/tom_build_base_v2.dart';
```

---

## Tool Framework

The tool framework lets you define tools declaratively. The framework handles argument parsing, help generation, traversal, mode/placeholder resolution, pipelines, macros, defines, and nested tool wiring.

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

All tools automatically include these options (from `commonOptions`):

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

All tools support console markdown for formatted output:

```dart
import 'package:tom_build_base/tom_build_base.dart';

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

## Utility Classes

### Configuration — TomBuildConfig

Tom tools use a **workspace-level** master config (`buildkit_master.yaml`) and **project-level** configs (`buildkit.yaml`). Each file contains sections keyed by tool name.

```yaml
# buildkit_master.yaml (workspace root)
navigation:                     # shared defaults for all tools
  scan: .
  recursive: true
  exclude: [.git, build, node_modules]

mytool:                         # tool-specific section
  verbose: false
```

```yaml
# buildkit.yaml (inside a project)
mytool:
  verbose: true                 # overrides workspace default
```

### Loading Configuration

```dart
const toolKey = 'mytool';
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
// Does this project have a specific tool section in buildkit.yaml?
if (hasTomBuildConfig(projectPath, 'mytool')) {
  print('Has tool config');
}

// Does the config specify any project navigation options?
if (config.hasProjectOptions) {
  print('Has project/scan/config options');
}
```

---

## Best Practices

1. **Define tools declaratively** — use `ToolDefinition` and `CommandDefinition` for consistent behavior.
2. **Use folder natures** — check `context.isDartProject` / `context.getNature<T>()` for type-safe project info.
3. **Merge configs** — load master, load project, `master.merge(project)`.
4. **Respect verbose** — honour `config.verbose` for debugging output.
5. **Use exit codes** — return `0` on success, `1` on failures.
6. **Use help topics** — add custom `HelpTopic` entries for tool-specific documentation.

---

## API Quick Reference

### Tool Framework

| Class / Function | Module | Purpose |
|------------------|--------|---------|
| `ToolDefinition` | core/tool_definition | Declarative tool definition with commands and options |
| `CommandDefinition` | core/command_definition | Command definition with options and nature requirements |
| `OptionDefinition` | core/option_definition | CLI option definition (flag, option, multi) |
| `ToolRunner` | core/tool_runner | Argument parsing, traversal, command dispatch |
| `CommandExecutor` | core/command_executor | Abstract command execution interface |
| `CallbackExecutor` | core/command_executor | Async callback-based executor |
| `SyncExecutor` | core/command_executor | Synchronous callback-based executor |
| `ShellExecutor` | core/command_executor | Shell command executor |
| `CommandContext` | traversal/command_context | Per-project execution context with natures |
| `ToolResult` / `ItemResult` | core/tool_runner | Execution result containers |
| `HelpTopic` | core/help_topic | Named help topic with summary and content |
| `HelpGenerator` | core/help_generator | Static help text generation methods |
| `CliArgs` / `CliArgParser` | core/cli_arg_parser | Parsed arguments and parser |
| `ToolWiringEntry` | core/tool_wiring_entry | Nested tool wiring configuration |
| `WiringLoader` | core/wiring_loader | Resolves nested tool wiring |
| `NestedToolExecutor` | core/nested_tool_executor | Executor that delegates to external binary |
| `ToolDefinitionSerializer` | core/tool_definition_serializer | YAML serialization for `--dump-definitions` |
| `ToolPipelineExecutor` | core/pipeline_executor | Pipeline step execution with placeholder resolution |
| `ToolPipelineConfig` | core/pipeline_config | Pipeline YAML parsing |
| `expandMacros()` | core/macro_expansion | `@macro` expansion with `$1`–`$9` and `$$` |
| `CompletionGenerator` | core/completion_generator | Shell completion generation (bash, zsh, fish) |
| `NavigationFeatures` | core/tool_definition | Feature flags for traversal capabilities |
| `commonOptions` | core/option_definition | Standard global options for all tools |
| `projectTraversalOptions` | core/option_definition | Project traversal options |
| `gitTraversalOptions` | core/option_definition | Git traversal options |
| `defaultHelpTopics` | core/builtin_help_topics | Help topics for all tools (placeholders) |
| `masterYamlHelpTopics` | core/builtin_help_topics | Help topics for multi-command tools (defines, macros, pipelines, wiring) |

### Folder Natures

| Class | Module | Detection |
|-------|--------|-----------|
| `FsFolder` | folder/fs_folder | Base folder wrapper |
| `RunFolder` | folder/run_folder | Abstract nature base |
| `DartProjectFolder` | folder/natures | `pubspec.yaml` |
| `FlutterProjectFolder` | folder/natures | Flutter SDK dep |
| `DartConsoleFolder` | folder/natures | `bin/` entries |
| `GitFolder` | folder/natures | `.git/` directory |
| `VsCodeExtensionFolder` | folder/natures | VS Code `package.json` |
| `TypeScriptFolder` | folder/natures | `tsconfig.json` |
| `BuildkitFolder` | folder/natures | `buildkit.yaml` |
| `BuildRunnerFolder` | folder/natures | `build.yaml` |
| `TomBuildFolder` | folder/natures | Tom config files |

### Utility Classes

| Class / Function | Module | Purpose |
|------------------|--------|---------|
| `TomBuildConfig` | build_config | Load, merge, copy-with config |
| `TomBuildConfig.load()` | build_config | Read `buildkit.yaml` |
| `TomBuildConfig.loadMaster()` | build_config | Read `buildkit_master.yaml` |
| `hasTomBuildConfig()` | build_config | Check for tool section |
| `ProcessRunner` | tool_logging | Run processes with logging |
| `ToolLogger` | tool_logging | Structured tool logging |
| `yamlToMap()` | yaml_utils | Convert YAML to `Map<String, dynamic>` |
| `yamlListToList()` | yaml_utils | Convert YAML to `List` |
| `toStringList()` | yaml_utils | Convert YAML to `List<String>` |
