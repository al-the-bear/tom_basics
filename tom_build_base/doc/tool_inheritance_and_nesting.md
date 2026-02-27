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

## Part B: Nested Tool Execution (Declarative Wiring)

### Use Case

A tool wants to offer commands that actually delegate to an external binary.
The external tool is **not** a code-level dependency — it's a compiled binary
on the PATH.

**Example:** `buildkit :test` should shell out to `testkit :test`, forwarding
relevant command-specific options. Buildkit handles traversal; testkit executes
in the project folder.

### Design Principles

1. **Wiring-only YAML** — The host tool's master YAML declares *how* to wire
   nested tools (binary name, command mapping, renames). No option definitions,
   no nature filters — those come from the nested tool itself.
2. **Auto-discovery via `--dump-definitions`** — Every tom_build_base tool can
   self-describe its commands, options, and nature requirements. The host tool
   queries this at startup to auto-configure.
3. **`--nested` flag** — Tells a nested tool to skip traversal and run in
   single-project mode. Prevents nested-nested recursion.
4. **No fallback** — Each tool's wiring file is independent. `buildkit_master.yaml`
   is for buildkit only; `testkit_master.yaml` is for testkit only. No cross-tool
   fallback.

---

### 1. `wiringFile` on ToolDefinition

A new field on `ToolDefinition` declares whether a tool supports hosting
nested tools, and which file contains the wiring configuration.

```dart
class ToolDefinition {
  // ... existing fields ...

  /// File that contains nested tool wiring configuration.
  ///
  /// - `null` (default): Tool does not host nested tools.
  ///   Most tools use this (d4rtgen, astgen, findproject).
  /// - `''` (empty / [kAutoWiringFile]): Convention-based discovery.
  ///   Looks for `{toolname}_master.yaml` in the workspace root.
  ///   Example: buildkit → `buildkit_master.yaml`.
  /// - `'testkit_master.yaml'`: Explicit filename.
  ///   Looks for this exact file in the workspace root.
  ///
  /// Ignored when `--nested` is active (no nested-nested).
  final String? wiringFile;

  /// Sentinel value for convention-based wiring file discovery.
  static const kAutoWiringFile = '';

  const ToolDefinition({
    // ... existing parameters ...
    this.wiringFile,
  });
}
```

**Semantics:**

| `wiringFile` value | Meaning | Example tool |
|---|---|---|
| `null` (default) | No nested tool hosting | d4rtgen, astgen, findproject |
| `''` (`kAutoWiringFile`) | Convention: `{toolname}_master.yaml` | buildkit |
| `'testkit_master.yaml'` | Explicit custom file | testkit (if it hosts d4rtgen) |

**No fallback.** If `wiringFile` resolves to `testkit_master.yaml` and that
file doesn't exist, there are simply no nested tools. It does NOT fall back to
`buildkit_master.yaml`.

---

### 2. `--nested` Flag in commonOptions

Added to `commonOptions` in tom_build_base so every tool understands it:

```dart
// In commonOptions:
OptionDefinition.flag(
  name: 'nested',
  description: 'Run in nested mode (skip traversal, single-project)',
),
```

**Effect in ToolRunner:**

```dart
Future<ToolResult> run(List<String> args) async {
  final cliArgs = parser.parse(args);

  // Nested mode: skip traversal, skip wiring, execute in cwd only
  if (cliArgs.nested) {
    return _runNestedMode(cliArgs);
  }

  // Normal mode: load wiring (if wiringFile is set), then traverse
  if (tool.wiringFile != null) {
    _loadAndRegisterNestedTools(cliArgs);
  }

  // ... proceed with normal traversal + dispatch ...
}
```

When `--nested` is active:
- ToolRunner skips its own traversal
- ToolRunner skips wiring file loading (no nested-nested)
- The tool executes its command directly in the current working directory

---

### 3. `--dump-definitions` Flag in commonOptions

Every tool can self-describe its commands, options, and nature requirements:

```dart
// In commonOptions:
OptionDefinition.flag(
  name: 'dump-definitions',
  description: 'Output tool/command definitions as YAML for registration',
),
```

**Intercepted early in ToolRunner, before any traversal:**

```dart
if (cliArgs.dumpDefinitions) {
  final filter = cliArgs.positionalArgs; // optional command names
  final yaml = ToolDefinitionSerializer.toYaml(
    tool,
    commandFilter: filter.isEmpty ? null : filter,
  );
  print(yaml);
  return ToolResult.success();
}
```

**Example output of `testkit --dump-definitions test`:**

```yaml
name: testkit
mode: multi_command
required_natures: [dart_project]
commands:
  test:
    description: Run tests and add result column to the most recent baseline
    options:
      - { name: test-args, type: option, description: "Arguments forwarded to dart test" }
      - { name: fail-fast, type: flag, description: "Stop on first failure" }
      - { name: tags, type: multi, description: "Test tags to include" }
    works_with_natures: [dart_project]
  baseline:
    description: Create a new baseline CSV file with current test results
    options:
      - { name: test-args, type: option, description: "Arguments forwarded to dart test" }
    works_with_natures: [dart_project]
```

**Example output of `astgen --dump-definitions`:**

```yaml
name: astgen
mode: single_command
required_natures: [dart_project]
options:
  - { name: output, type: option, description: "Output directory" }
  - { name: force, type: flag, description: "Overwrite existing files" }
```

The `ToolDefinitionSerializer` walks the existing `ToolDefinition` →
`CommandDefinition` → `OptionDefinition` tree. All data is already there —
no new metadata needed.

---

### 4. Wiring YAML in `{tool}_master.yaml`

The wiring section is **purely about mapping** — which binary, which commands,
what to rename. No option definitions, no nature filters.

**Example in `buildkit_master.yaml`:**

```yaml
# Existing buildkit config (navigation, pipelines, etc.)
navigation:
  recursive: true
  exclude-projects: [zom_*]

buildkit:
  pipelines:
    build: [cleanup, versioner, runner, compiler]

# NEW: nested tool wiring
nested_tools:
  testkit:
    binary: testkit
    mode: multi_command
    commands:
      buildkittest: test       # :buildkittest in buildkit → :test in testkit
      buildkitbaseline: baseline  # :buildkitbaseline → :baseline in testkit
  buildkitAstgen:
    binary: astgen
    mode: standalone           # single-command tool, no :commands
  buildkitD4rtgen:
    binary: d4rtgen
    mode: standalone
```

**YAML structure per entry:**

| Field | Required | Values | Purpose |
|-------|----------|--------|---------|
| `binary` | Yes | String | Executable name on PATH |
| `mode` | Yes | `multi_command` / `standalone` | Whether tool has sub-commands |
| `commands` | If multi_command | Map of `host_name: nested_name` | Command mapping with renames |

That's it. Everything else is auto-discovered.

---

### 5. Startup Flow: Auto-Discovery

When ToolRunner loads wiring, it calls each nested tool's `--dump-definitions`
to get the full registration data:

```
ToolRunner.run()
  1. Parse CLI args
  2. If --nested: skip wiring, run single-project → return
  3. If --dump-definitions: serialize and print → return
  4. If tool.wiringFile != null:
     a. Resolve wiring file path (convention or explicit)
     b. Read nested_tools: section
     c. For each entry:
        - Verify binary exists (which/where)
        - Run: <binary> --dump-definitions [command-names]
        - Parse the YAML response
        - Build CommandDefinition objects (using host names from wiring)
        - Build NestedToolExecutor instances
        - Register in command + executor maps
  5. Validate all nested binaries are available for requested commands
  6. Proceed with normal traversal + dispatch
```

**Concrete example: buildkit startup with the YAML above:**

1. Reads `buildkit_master.yaml` → finds `nested_tools:`
2. Entry `testkit`:
   - `which testkit` → `/usr/local/bin/testkit` ✓
   - Runs `testkit --dump-definitions test baseline`
   - Gets back: command `test` has options `test-args`, `fail-fast`, `tags`;
     requires `dart_project` nature
   - Creates `CommandDefinition(name: 'buildkittest', ...)` with those options
   - Creates `NestedToolExecutor(binary: 'testkit', nestedCommand: 'test', ...)`
   - Registers `:buildkittest` as a buildkit command
   - Same for `:buildkitbaseline`
3. Entry `buildkitAstgen`:
   - `which astgen` → found ✓
   - Runs `astgen --dump-definitions`
   - Gets back: standalone tool, options `output`, `force`; requires `dart_project`
   - Creates `CommandDefinition(name: 'buildkitAstgen', ...)` with those options
   - Creates `NestedToolExecutor(binary: 'astgen', mode: standalone, ...)`
   - Registers `:buildkitAstgen` as a buildkit command

---

### 6. Option Forwarding

When a nested command is invoked per-project, the host tool forwards only:

- **Command-specific options** — as parsed by the host tool under the host
  command name. These map 1:1 to the nested tool's command options (auto-
  discovered from `--dump-definitions`).
- **Behavioral global options** — `--verbose` and `--dry-run` only. These are
  universal across all tom_build_base tools.
- **`--nested`** — always added, to tell the nested tool to skip traversal.

**NOT forwarded:**

- Traversal options (`-s`, `-r`, `-R`, `-b`, `-p`, `--modules`, etc.) — the
  host tool owns traversal.
- Host-specific global options (`--list`, `--workspace-recursion`, `--tui`) —
  meaningless to the nested tool.

```dart
/// Build CLI args for the nested tool invocation.
List<String> _buildNestedArgs({
  required CliArgs hostArgs,
  required String hostCommandName,
  required String nestedCommand,  // null for standalone
  required bool isStandalone,
}) {
  final args = <String>['--nested'];

  // Forward behavioral globals
  if (hostArgs.verbose) args.add('--verbose');
  if (hostArgs.dryRun) args.add('--dry-run');

  // For multi-command tools, add the nested command
  if (!isStandalone) {
    args.add(':$nestedCommand');
  }

  // Forward command-specific options
  final perCmd = hostArgs.commandArgs[hostCommandName];
  if (perCmd != null) {
    for (final entry in perCmd.options.entries) {
      final name = entry.key;
      final value = entry.value;
      if (value == true) {
        args.add('--$name');
      } else if (value is String && value.isNotEmpty) {
        args.addAll(['--$name', value]);
      } else if (value is List) {
        for (final v in value) {
          args.addAll(['--$name', v.toString()]);
        }
      }
    }
  }

  return args;
}
```

**Example invocation chain:**

```bash
# User runs:
buildkit -s . -r -v :buildkittest --test-args="--name parser"

# Buildkit traverses projects, for each Dart project calls:
testkit --nested --verbose :test --test-args="--name parser"

# testkit sees --nested, skips traversal, runs :test in cwd
```

---

### 7. NestedToolExecutor

A single generic `CommandExecutor` subclass handles both standalone and
multi-command nested tools:

```dart
/// Executor that delegates to an external tool binary.
///
/// Created dynamically at startup from wiring YAML + --dump-definitions.
class NestedToolExecutor extends CommandExecutor {
  /// Name of the external binary (must be on PATH).
  final String binary;

  /// Command name in the external tool (e.g., 'test').
  /// Null for standalone tools.
  final String? nestedCommand;

  /// Whether this is a standalone (single-command) tool.
  final bool isStandalone;

  /// The host command name (may differ from nestedCommand due to renames).
  final String hostCommandName;

  NestedToolExecutor({
    required this.binary,
    required this.hostCommandName,
    this.nestedCommand,
    this.isStandalone = false,
  });

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final cmdArgs = _buildNestedArgs(
      hostArgs: args,
      hostCommandName: hostCommandName,
      nestedCommand: nestedCommand ?? '',
      isStandalone: isStandalone,
    );
    return _runBinary(binary, cmdArgs, context.path);
  }
}
```

---

### 8. Binary Pre-Check

Before executing any command, ToolRunner validates that all nested binaries
required by the **requested** commands are available:

```dart
/// Check that nested tool binaries are available for requested commands.
///
/// Only checks binaries for commands that will actually be invoked.
/// Running `buildkit :cleanup :versioner` does not require testkit.
List<String> validateNestedBinaries({required Set<String> requestedCommands}) {
  final missing = <String>[];
  for (final cmdName in requestedCommands) {
    final executor = executors[cmdName];
    if (executor is NestedToolExecutor) {
      if (!_isBinaryOnPath(executor.binary)) {
        missing.add(':$cmdName requires "${executor.binary}" — not found');
      }
    }
  }
  return missing;
}
```

```dart
// In ToolRunner.run(), after wiring but before traversal:
final missingBinaries = validateNestedBinaries(
  requestedCommands: cliArgs.commands.toSet(),
);
if (missingBinaries.isNotEmpty) {
  output.writeln('Error: Missing required tool binaries:');
  for (final msg in missingBinaries) {
    output.writeln('  - $msg');
  }
  return ToolResult.failure('Missing nested tool binaries');
}
```

---

### 9. Concrete Example: Full Lifecycle

#### Wiring in `buildkit_master.yaml`

```yaml
nested_tools:
  testkit:
    binary: testkit
    mode: multi_command
    commands:
      buildkittest: test
      buildkitbaseline: baseline
  buildkitAstgen:
    binary: astgen
    mode: standalone
```

#### Startup

```
$ buildkit -s . -r :buildkittest --test-args="--name parser"

[startup] Loading wiring from buildkit_master.yaml...
[startup] testkit --dump-definitions test baseline
[startup]   → :buildkittest registered (testkit :test, natures: [dart_project])
[startup]   → :buildkitbaseline registered (testkit :baseline, natures: [dart_project])
[startup] astgen --dump-definitions
[startup]   → :buildkitAstgen registered (astgen standalone, natures: [dart_project])
[startup] Binary check: testkit ✓, astgen ✓
[traversal] Scanning . recursively...
```

#### Per-Project Execution

```
[tom_build_base] testkit --nested --verbose :test --test-args="--name parser"
  → testkit sees --nested, runs :test in tom_build_base/
  → Tests run, results tracked

[tom_build_kit] testkit --nested --verbose :test --test-args="--name parser"
  → testkit sees --nested, runs :test in tom_build_kit/
  → Tests run, results tracked
```

#### Error: Missing Binary

```
$ buildkit :buildkittest :cleanup

Error: Missing required tool binaries:
  - :buildkittest requires "testkit" — not found
```

#### Registration Workflow

```bash
# See what testkit offers:
$ testkit --dump-definitions
name: testkit
mode: multi_command
required_natures: [dart_project]
commands:
  test:
    description: Run tests and add result column to the most recent baseline
    options:
      - { name: test-args, type: option, ... }
    works_with_natures: [dart_project]
  baseline:
    description: Create a new baseline CSV file
    ...

# Add to buildkit_master.yaml: just the wiring
# nested_tools:
#   testkit:
#     binary: testkit
#     mode: multi_command
#     commands:
#       buildkittest: test
```

---

### 10. `_runBinary` Helper

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

### 11. Binary Path Resolution

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

Also checks `$HOME/.tom/bin/<platform>/` for Tom-specific tool binaries.

---

## Implementation Plan

### Phase 1: Tool Inheritance (Part A)

1. Add `copyWith` to `ToolDefinition`
2. Add `CommandListOps` extension
3. Add tests
4. Publish `tom_build_base`

### Phase 2: Core Infrastructure (Part B — tom_build_base)

1. Add `wiringFile` field to `ToolDefinition`
2. Add `--nested` flag to `commonOptions`
3. Add `--dump-definitions` flag to `commonOptions`
4. Implement `ToolDefinitionSerializer` (walks definition tree → YAML)
5. Implement `NestedToolExecutor` class
6. Implement wiring loader (reads YAML, calls `--dump-definitions`, registers)
7. Add `validateNestedBinaries` to `ToolRunner`
8. Wire into `ToolRunner.run()` flow (nested bypass, dump bypass, wiring load)
9. Add `_runBinary` and `_isBinaryOnPath` helpers
10. Add tests (mock binary execution)
11. Publish `tom_build_base`

### Phase 3: Buildkit Integration (consuming)

1. Set `wiringFile: ToolDefinition.kAutoWiringFile` on `buildkitTool`
2. Add `nested_tools:` section to workspace `buildkit_master.yaml`
3. Test end-to-end: `buildkit :buildkittest`, `buildkit :buildkitAstgen`

---

## Architecture Summary

```
                    ┌─────────────────────────────────┐
                    │         tom_build_base           │
                    │                                  │
                    │  ToolDefinition                  │
                    │    + wiringFile: String?          │
                    │    + copyWith(...)                │
                    │                                  │
                    │  commonOptions                   │
                    │    + --nested                    │
                    │    + --dump-definitions           │
                    │                                  │
                    │  ToolRunner                       │
                    │    + wiring loader               │
                    │    + nested mode bypass           │
                    │    + dump-definitions bypass      │
                    │    + validateNestedBinaries()     │
                    │                                  │
                    │  NestedToolExecutor               │
                    │  ToolDefinitionSerializer         │
                    └──────────────┬──────────────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                     │
    ┌─────────▼────────┐  ┌───────▼────────┐  ┌────────▼───────┐
    │     buildkit      │  │    testkit     │  │    d4rtgen     │
    │                   │  │               │  │               │
    │ wiringFile: ''    │  │ wiringFile:   │  │ wiringFile:   │
    │ (auto →           │  │   null        │  │   null        │
    │  buildkit_master) │  │ (no hosting)  │  │ (no hosting)  │
    │                   │  │               │  │               │
    │ Reads YAML:       │  │ Responds to:  │  │ Responds to:  │
    │  nested_tools:    │  │ --dump-defs   │  │ --dump-defs   │
    │   testkit: ...    │  │ --nested      │  │ --nested      │
    │   astgen: ...     │  │               │  │               │
    └───────────────────┘  └───────────────┘  └───────────────┘
```

---

## Open Questions

1. **Streaming vs buffered output** — Should nested tool output stream in
   real-time (using `Process.start`) or be buffered (`Process.run`)?
   Recommendation: Stream for interactive use, buffer when piped.

2. **Exit code propagation** — Should a nested tool failure stop the entire
   pipeline or just mark that project as failed? Current pipeline behavior
   is stop-on-failure, which seems correct here too.

3. **Version checking** — Should the host tool verify the nested tool's version
   is compatible? Could add `min_version:` to the wiring YAML. The
   `--dump-definitions` output already includes the tool version.

4. **Caching `--dump-definitions`** — Calling `--dump-definitions` at every
   startup adds latency. Should results be cached per binary+version?
   Recommendation: Yes, cache in `ztmp/` keyed by binary path + mtime.

5. **Config passthrough** — Nested tools read their own `buildkit.yaml`
   sections (e.g., `d4rtgen:` in the project's `buildkit.yaml`). The host
   tool does not need to know about this — the nested tool handles its own
   config requirements. However, the nature filter from `--dump-definitions`
   ensures buildikit only calls the nested tool on appropriate projects.
