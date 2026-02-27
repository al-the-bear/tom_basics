# Tool Inheritance and Nesting Design

> Design document for extending `tom_build_base` to support tool composition,
> command inheritance, and nested tool execution.

## Status

Draft — February 2026

## Problem Statement

The Tom toolchain has multiple CLI tools built on `tom_build_base`:

- **buildkit** — multi-command build orchestration (`:versioner`, `:compiler`, `:runner`, `:cleanup`, etc.)
- **testkit** — multi-command test tracking (`:test`, `:baseline`, `:status`, `:diff`, etc.)
- **d4rtgen** — single-command bridge generator (reads `buildkit.yaml` `d4rtgen:` section)
- **astgen** — single-command AST generator (reads `buildkit.yaml` `astgen:` section)
- **issuekit** — multi-command issue tracking
- **findproject** — single-command project finder

All share the same `tom_build_base` infrastructure (`ToolDefinition`, `ToolRunner`,
`CommandExecutor`, traversal, placeholders, `buildkit.yaml` config). But today there
is **no mechanism** for:

1. A new tool to inherit commands from an existing tool
2. A tool to embed another tool as a command (nested execution)

This document defines the design for both capabilities.

---

## Part A: Tool Inheritance (Extend/Override Commands)

### Use Case

A new tool wants to be "buildkit plus extras" — keep most commands, remove some,
replace others, and add new ones.

**Example:** A `tom` super-tool that has all buildkit commands plus d4rtgen and
astgen, but removes `:dcli` and replaces `:runner` with a custom version.

### Current Limitation

`ToolDefinition` is a `const`-constructible immutable class. All fields are `final`.
There is no `copyWith`, no builder, no merge. Creating a derived tool requires
re-declaring every field from scratch.

`ToolRunner` takes a flat `Map<String, CommandExecutor>` and a `ToolDefinition`.
There's no composition API.

### Proposed Solution: `copyWith` + `mergeExecutors`

#### 1. Add `copyWith` to `ToolDefinition`

```dart
class ToolDefinition {
  // ... existing fields ...

  /// Create a modified copy of this tool definition.
  ToolDefinition copyWith({
    String? name,
    String? description,
    String? version,
    ToolMode? mode,
    NavigationFeatures? features,
    List<OptionDefinition>? globalOptions,
    List<CommandDefinition>? commands,
    String? defaultCommand,
    String? helpFooter,
    List<HelpTopic>? helpTopics,
    Set<Type>? requiredNatures,
    Set<Type>? worksWithNatures,
  }) {
    return ToolDefinition(
      name: name ?? this.name,
      description: description ?? this.description,
      version: version ?? this.version,
      mode: mode ?? this.mode,
      features: features ?? this.features,
      globalOptions: globalOptions ?? this.globalOptions,
      commands: commands ?? this.commands,
      defaultCommand: defaultCommand ?? this.defaultCommand,
      helpFooter: helpFooter ?? this.helpFooter,
      helpTopics: helpTopics ?? this.helpTopics,
      requiredNatures: requiredNatures ?? this.requiredNatures,
      worksWithNatures: worksWithNatures ?? this.worksWithNatures,
    );
  }
}
```

#### 2. Command List Manipulation Helpers

Static utilities (or extension methods) on `List<CommandDefinition>`:

```dart
extension CommandListOps on List<CommandDefinition> {
  /// Remove commands by name.
  List<CommandDefinition> without(Set<String> names) =>
      where((c) => !names.contains(c.name)).toList();

  /// Replace a command by name (keeps position).
  List<CommandDefinition> replacing(
    String name,
    CommandDefinition replacement,
  ) =>
      map((c) => c.name == name ? replacement : c).toList();

  /// Add commands (appends).
  List<CommandDefinition> plus(List<CommandDefinition> additions) =>
      [...this, ...additions];
}
```

#### 3. Usage Pattern

```dart
// Derive a new tool from buildkit
final superTool = buildkitTool.copyWith(
  name: 'supertool',
  version: '1.0.0',
  commands: buildkitTool.commands
      .without({'dcli', 'findproject'})           // remove
      .replacing('runner', myCustomRunnerCommand)  // replace
      .plus([d4rtgenCommand, astgenCommand]),       // add
);

// Merge executor maps
final executors = {
  ...createBuildkitExecutors(/* ... */),
  'd4rtgen': d4rtgenExecutor,
  'astgen': astgenExecutor,
}..remove('dcli')
 ..remove('findproject')
 ..['runner'] = MyCustomRunnerExecutor();

final runner = ToolRunner(tool: superTool, executors: executors);
```

### Implementation Scope

- Add `copyWith` to `ToolDefinition` — ~20 lines
- Add `CommandListOps` extension — ~15 lines
- Both go in `tom_build_base`, no changes needed in consuming tools
- Fully backward-compatible (additive only)

---

## Part B: Nested Tool Execution (Embed External Binaries)

### Use Case

A tool wants to offer commands that actually delegate to an external binary.
The external tool is **not** a code-level dependency — it's a compiled binary
on the PATH.

**Example:** `buildkit :test` should shell out to `testkit :test`, forwarding
relevant global and command-specific options.

### Two Cases

#### Case 1: Embedding a Single-Command Tool

External tool has no commands — it's invoked as `d4rtgen [options]`.

**Syntax in host tool:** `buildkit :d4rtgen` → shells out to `d4rtgen [forwarded-options]`

#### Case 2: Embedding a Multi-Command Tool

External tool has its own commands — it's invoked as `testkit :test [options]`.

**Syntax in host tool:** `buildkit :test` → shells out to `testkit :test [forwarded-options]`

### Design: Wrapper Executors

Two new `CommandExecutor` subclasses in `tom_build_base`:

#### `NestedStandaloneExecutor`

For embedding a single-command tool (no sub-commands).

```dart
/// Executor that delegates to an external single-command tool binary.
///
/// The external tool has no commands — it runs on the current project
/// folder using its own traversal or in nested mode.
class NestedStandaloneExecutor extends CommandExecutor {
  /// Name of the external binary (must be on PATH).
  final String binary;

  /// Global options to forward from host tool to nested tool.
  ///
  /// These are option names from the host tool's CliArgs that map
  /// directly to the nested tool's global options.
  /// Example: ['verbose', 'dry-run', 'scan', 'recursive']
  final List<String> forwardGlobalOptions;

  /// Additional fixed arguments always passed to the nested tool.
  /// Example: ['--nested'] to signal nested mode.
  final List<String> fixedArgs;

  NestedStandaloneExecutor({
    required this.binary,
    this.forwardGlobalOptions = const [],
    this.fixedArgs = const [],
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final cmdArgs = _buildArgs(args, context);
    return _runBinary(binary, cmdArgs, context.path);
  }
}
```

#### `NestedMultiCommandExecutor`

For embedding a specific command from a multi-command tool.

```dart
/// Executor that delegates to a specific command of an external
/// multi-command tool binary.
///
/// Example: Embedding testkit's :test command inside buildkit as
/// `buildkit :test` → `testkit :test [options]`.
class NestedMultiCommandExecutor extends CommandExecutor {
  /// Name of the external binary (must be on PATH).
  final String binary;

  /// Command name in the external tool (e.g., 'test' → ':test').
  final String nestedCommand;

  /// Global options to forward from host tool to nested tool.
  final List<String> forwardGlobalOptions;

  /// Command-specific options to forward.
  ///
  /// Maps host command option names to nested tool option names.
  /// Use identical names for 1:1 forwarding.
  /// Example: {'test-args': 'test-args', 'comment': 'comment'}
  final Map<String, String> forwardCommandOptions;

  /// Additional fixed arguments always passed to the nested tool.
  final List<String> fixedArgs;

  NestedMultiCommandExecutor({
    required this.binary,
    required this.nestedCommand,
    this.forwardGlobalOptions = const [],
    this.forwardCommandOptions = const {},
    this.fixedArgs = const [],
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final cmdArgs = _buildArgs(args, context);
    return _runBinary(binary, [':$nestedCommand', ...cmdArgs], context.path);
  }
}
```

### Binary Pre-Check

Both executors share a critical requirement: **verify the binary exists before
any commands run**. If a user runs `buildkit :cleanup :versioner :test` and
`testkit` is not installed, we should fail immediately — not after cleanup and
versioner have already executed.

This is handled at the `ToolRunner` level, not per-executor:

```dart
/// Check that all nested executors have their binaries available.
///
/// Called once before any command execution begins.
/// Returns a list of missing binaries, or empty if all are available.
List<String> validateNestedBinaries() {
  final missing = <String>[];
  for (final entry in executors.entries) {
    final executor = entry.value;
    if (executor is NestedStandaloneExecutor) {
      if (!_isBinaryOnPath(executor.binary)) {
        missing.add('${entry.key}: requires "${executor.binary}"');
      }
    } else if (executor is NestedMultiCommandExecutor) {
      if (!_isBinaryOnPath(executor.binary)) {
        missing.add('${entry.key}: requires "${executor.binary}"');
      }
    }
  }
  return missing;
}
```

The `ToolRunner.run()` method calls this before executing any command:

```dart
Future<ToolResult> run(List<String> args) async {
  final cliArgs = parser.parse(args);

  // ... help/version handling ...

  // Pre-check: validate all nested binaries are available
  // Only check binaries for commands actually being invoked
  final requestedCommands = cliArgs.commands.toSet();
  final missingBinaries = validateNestedBinaries(
    onlyCommands: requestedCommands,
  );
  if (missingBinaries.isNotEmpty) {
    output.writeln('Error: Missing required tool binaries:');
    for (final msg in missingBinaries) {
      output.writeln('  - $msg');
    }
    return ToolResult.failure('Missing nested tool binaries');
  }

  // ... proceed with execution ...
}
```

The check is scoped to only the commands being invoked. Running
`buildkit :cleanup :versioner` should not fail just because `testkit` isn't
installed, since `:test` isn't being called.

### Option Forwarding

Both executors build a CLI argument list for the nested binary:

```dart
List<String> _buildArgs(CliArgs hostArgs, CommandContext context) {
  final args = <String>[...fixedArgs];

  // Forward global options
  for (final optName in forwardGlobalOptions) {
    final value = hostArgs.extraOptions[optName];
    if (value == true) {
      args.add('--$optName');
    } else if (value is String && value.isNotEmpty) {
      args.addAll(['--$optName', value]);
    } else if (value is List && value.isNotEmpty) {
      for (final v in value) {
        args.addAll(['--$optName', v.toString()]);
      }
    }
    // Also check standard CliArgs fields
    if (optName == 'verbose' && hostArgs.verbose) args.add('--verbose');
    if (optName == 'dry-run' && hostArgs.dryRun) args.add('--dry-run');
    if (optName == 'force' && hostArgs.force) args.add('--force');
    if (optName == 'list' && hostArgs.listOnly) args.add('--list');
  }

  // Forward command-specific options (multi-command only)
  if (this is NestedMultiCommandExecutor) {
    final nested = this as NestedMultiCommandExecutor;
    final cmdArgs = hostArgs.commandArgs[nested.nestedCommand];
    if (cmdArgs != null) {
      for (final entry in nested.forwardCommandOptions.entries) {
        final hostOpt = entry.key;
        final nestedOpt = entry.value;
        final value = cmdArgs.options[hostOpt];
        if (value == true) {
          args.add('--$nestedOpt');
        } else if (value is String && value.isNotEmpty) {
          args.addAll(['--$nestedOpt', value]);
        }
      }
    }
  }

  // Pass nested mode indicator and project path
  args.addAll(['--scan', context.path, '--not-recursive']);

  return args;
}
```

**Key point:** The nested tool receives `--scan <project-path> --not-recursive`,
which makes it operate on just the single project folder that the host tool's
traversal is currently processing. This avoids the nested tool doing its own
full workspace traversal.

### Concrete Example: `buildkit :test`

#### 1. Command Definition (in buildkit_tool.dart)

```dart
const testCommand = CommandDefinition(
  name: 'test',
  description: 'Run tests via testkit (delegates to testkit :test)',
  aliases: ['t'],
  options: [
    OptionDefinition(
      name: 'test-args',
      description: 'Arguments passed to dart test',
    ),
    OptionDefinition(
      name: 'comment',
      description: 'Comment for test run',
    ),
  ],
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  requiresTraversal: true,
);
```

#### 2. Executor Registration (in buildkit_executors.dart)

```dart
'test': NestedMultiCommandExecutor(
  binary: 'testkit',
  nestedCommand: 'test',
  forwardGlobalOptions: ['verbose', 'dry-run'],
  forwardCommandOptions: {
    'test-args': 'test-args',
    'comment': 'comment',
  },
),
```

#### 3. User Experience

```bash
# Runs cleanup, versioner, then delegates to testkit for each project
buildkit :cleanup :versioner :test

# With options forwarded to testkit
buildkit :test --test-args="--name 'parser'"

# If testkit is not installed:
# Error: Missing required tool binaries:
#   - test: requires "testkit"
```

### Concrete Example: `buildkit :d4rtgen`

#### 1. Command Definition

```dart
const d4rtgenCommand = CommandDefinition(
  name: 'd4rtgen',
  description: 'Generate D4rt bridges (delegates to d4rtgen)',
  options: [
    OptionDefinition.flag(
      name: 'show',
      description: 'Show config details in list mode',
    ),
  ],
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  requiresTraversal: true,
);
```

#### 2. Executor Registration

```dart
'd4rtgen': NestedStandaloneExecutor(
  binary: 'd4rtgen',
  forwardGlobalOptions: ['verbose', 'dry-run', 'list'],
),
```

#### 3. User Experience

```bash
# Run d4rtgen in all projects that have d4rtgen config
buildkit -R :d4rtgen

# Combined pipeline
buildkit :d4rtgen :runner :compiler
```

---

## Shared Base: `_runBinary` Helper

Both executors use a shared helper to invoke the binary:

```dart
Future<ItemResult> _runBinary(
  String binary,
  List<String> args,
  String workingDirectory,
) async {
  final result = await Process.run(
    binary,
    args,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );

  final stdout = result.stdout.toString().trim();
  final stderr = result.stderr.toString().trim();

  if (stdout.isNotEmpty) print(stdout);
  if (stderr.isNotEmpty) print(stderr);

  if (result.exitCode == 0) {
    return ItemResult.success(path: workingDirectory);
  } else {
    return ItemResult.failure(
      path: workingDirectory,
      message: '$binary exited with code ${result.exitCode}',
    );
  }
}
```

---

## Binary Path Resolution

The `_isBinaryOnPath` check should:

1. Use `Process.runSync('which', [binary])` on macOS/Linux
2. Use `Process.runSync('where', [binary])` on Windows
3. Also check `$TOM_BINARY_PATH/<platform>/` and `$HOME/.tom/bin/<platform>/`
   for Tom-specific tool binaries

```dart
bool _isBinaryOnPath(String binary) {
  try {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(cmd, [binary]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
```

---

## Implementation Plan

### Phase 1: Tool Inheritance (Part A)

1. Add `copyWith` to `ToolDefinition`
2. Add `CommandListOps` extension
3. Add tests
4. Publish `tom_build_base`

### Phase 2: Nested Executors (Part B)

1. Create `NestedStandaloneExecutor` class
2. Create `NestedMultiCommandExecutor` class
3. Add `_runBinary` and `_isBinaryOnPath` helpers
4. Add `validateNestedBinaries` to `ToolRunner`
5. Add pre-check call in `ToolRunner.run()`
6. Add tests (mock binary execution)
7. Publish `tom_build_base`

### Phase 3: Buildkit Integration (consuming)

1. Add `:test` command definition to buildkit_tool.dart
2. Add `:d4rtgen` command definition
3. Register `NestedMultiCommandExecutor` / `NestedStandaloneExecutor`
4. Test end-to-end

---

## Open Questions

1. **Streaming vs buffered output** — Should nested tool output stream in
   real-time (using `Process.start`) or be buffered (`Process.run`)?
   Recommendation: Stream for interactive use, buffer when piped.

2. **Exit code propagation** — Should a nested tool failure stop the entire
   buildkit pipeline or just mark that project as failed? Current pipeline
   behavior is stop-on-failure, which seems correct here too.

3. **Nested tool version checking** — Should the host tool verify the nested
   tool's version is compatible? Could add a `minVersion` field to the
   executor config.

4. **Config passthrough** — Nested tools read their own `buildkit.yaml` sections.
   Should the host tool pre-validate that the config section exists for the
   current project, or let the nested tool handle missing config itself?
   Recommendation: Let the nested tool handle it — it knows its own config
   requirements best.
