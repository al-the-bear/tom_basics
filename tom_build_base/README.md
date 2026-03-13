# Tom Build Base

Unified CLI framework for workspace traversal, tool definition, pipeline execution, and build configuration.

This package provides the foundation that Tom CLI build tools (like `buildkit`, `testkit`, `d4rtgen`, etc.) use to define commands, discover projects, and traverse directory structures.

## Features

- **Declarative tool definition** — `ToolDefinition`, `CommandDefinition`, `OptionDefinition` for structured CLI tools
- **Automatic help generation** — `--help`, `help <command>`, `help <topic>` with consistent formatting
- **Built-in traversal** — Project and git traversal with folder nature detection
- **Pipelines, macros, defines** — Multi-command tools get pipelines, runtime macros, and persistent defines automatically
- **Pipeline print prefix** — `print <message>` emits one resolved message without shell execution noise
- **Nested tool wiring** — Declarative integration of external tool binaries
- **Configuration loading** — `TomBuildConfig` for reading `buildkit.yaml` and `buildkit_master.yaml`
- **YAML utilities** — `yamlToMap()`, `yamlListToList()`, `toStringList()` for converting YAML nodes
- **Cross-platform symlink API** — `MkLinkExecutor` and dcli-backed `createSymLink()` integration for tool commands

## Installation

```yaml
dependencies:
  tom_build_base: ^2.6.0
```

## Quick Start

```dart
import 'package:tom_build_base/tom_build_base.dart';

const myTool = ToolDefinition(
  name: 'mytool',
  description: 'My custom build tool',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  commands: [
    CommandDefinition(
      name: 'build',
      description: 'Build the project',
      requiredNatures: {DartProjectFolder},
    ),
  ],
);

void main(List<String> args) async {
  final runner = ToolRunner(
    tool: myTool,
    executors: {
      'build': CallbackExecutor(
        onExecute: (context, args) async {
          print('Building ${context.name}');
          return ItemResult.success(path: context.path, name: context.name);
        },
      ),
    },
  );
  final result = await runner.run(args);
  exit(result.success ? 0 : 1);
}
```

## Configuration Format

Tom build tools use a two-tier configuration pattern:

### buildkit_master.yaml (workspace root)

```yaml
navigation:                   # shared defaults for all tools
  scan: .
  recursive: true
  exclude: [.git, build]

mytool:                       # tool-specific workspace defaults
  verbose: false
```

### buildkit.yaml (inside a project)

```yaml
mytool:
  verbose: true               # overrides workspace default
```

## Pipeline Prefixes

Pipeline commands support these execution prefixes:

- `shell <cmd>` — execute a shell command
- `shell-scan <cmd>` — execute once per traversed project
- `stdin <cmd>` — execute with multiline stdin content
- `print <msg>` — print exactly once after placeholder resolution
- `{TOOL} <cmd>` — delegate to tool command execution

## Documentation

- [build_base_user_guide.md](doc/build_base_user_guide.md) — Complete user guide with API reference
- [cli_tools_navigation.md](doc/cli_tools_navigation.md) — CLI navigation options and implementation guide

## License

BSD 3-Clause License — see [LICENSE](LICENSE) for details.

Author: Alexis Kyaw ([LinkedIn](https://www.linkedin.com/in/nickmeinhold/))

