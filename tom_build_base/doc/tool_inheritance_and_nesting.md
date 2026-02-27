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

### 1b. `defaultIncludes` on ToolDefinition

A tool can declare default nested tool wiring directly in code, without
requiring a YAML file. This is useful when certain nested tools are always
part of the tool's design.

```dart
/// Describes how a nested tool is wired into a host tool.
///
/// Binary names are platform-independent — `.exe` is appended
/// automatically on Windows at resolution time.
class ToolWiringEntry {
  /// Binary name (without platform extension).
  final String binary;

  /// Whether this is a multi-command or standalone tool.
  final WiringMode mode;

  /// Command mapping: `{ hostName: nestedName }`.
  /// Required for multi-command tools. Null/empty for standalone tools
  /// (the host command name defaults to the binary name).
  final Map<String, String>? commands;

  const ToolWiringEntry({
    required this.binary,
    required this.mode,
    this.commands,
  });
}

enum WiringMode { multiCommand, standalone }
```

```dart
class ToolDefinition {
  // ... existing fields (including wiringFile) ...

  /// Default nested tools wired into this tool at the code level.
  ///
  /// These are always included regardless of YAML configuration.
  /// YAML `nested_tools:` entries are merged on top (YAML wins on conflict).
  ///
  /// - `null` (default): No code-level includes.
  /// - `[ToolWiringEntry(...)]`: Explicit wiring entries.
  final List<ToolWiringEntry>? defaultIncludes;

  const ToolDefinition({
    // ... existing parameters ...
    this.wiringFile,
    this.defaultIncludes,
  });
}
```

**Usage example:**

```dart
const buildkitTool = ToolDefinition(
  name: 'buildkit',
  // ...
  wiringFile: ToolDefinition.kAutoWiringFile,
  defaultIncludes: [
    ToolWiringEntry(
      binary: 'testkit',
      mode: WiringMode.multiCommand,
      commands: {
        'buildkittest': 'test',
        'buildkitbaseline': 'baseline',
      },
    ),
    ToolWiringEntry(
      binary: 'astgen',
      mode: WiringMode.standalone,
    ),
  ],
);
```

**Merge behavior:** When both `defaultIncludes` and YAML `nested_tools:`
define wiring for the same binary, the YAML entry takes precedence. This
allows overriding code-level defaults in the workspace configuration.

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

Every tool can dump its complete definition as YAML — tool metadata, all
natively-defined commands, options, and nature requirements. This serves
three purposes:

1. **Auto-discovery** — host tools call this to register nested commands
2. **Inspection** — developers run it to understand a tool's full structure
3. **Testing** — tests assert against the serialized definition

```dart
// In commonOptions:
OptionDefinition.flag(
  name: 'dump-definitions',
  description: 'Dump complete tool definition as YAML (tool info + all commands)',
),
```

**Behavior:**

- Always dumps ALL natively-defined commands — no filtering, no positional args
- Does NOT include commands added via tool wiring (those are the host's concern)
- Includes full tool metadata (name, version, mode, features, natures)
- Includes all command definitions with their options, aliases, natures
- Includes global options (tool-specific ones, not the base common options)
- Intercepted early in ToolRunner, before any traversal or wiring

```dart
if (cliArgs.dumpDefinitions) {
  final yaml = ToolDefinitionSerializer.toYaml(tool);
  print(yaml);
  return ToolResult.success();
}
```

**Example output of `testkit --dump-definitions`:**

```yaml
name: testkit
version: 1.2.0
description: Test result tracking for Dart projects
mode: multi_command
features:
  project_traversal: true
  git_traversal: false
  recursive_scan: true
  interactive_mode: true
  dry_run: false
  verbose: true
required_natures: [dart_project]
global_options:
  - { name: tui, type: flag, description: "Run in TUI mode (interactive)" }
commands:
  test:
    description: Run tests and add result column to the most recent baseline
    aliases: [t]
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
  status:
    description: Show test status summary
    aliases: [s]
    works_with_natures: [dart_project]
  # ... all other native commands ...
```

**Example output of `astgen --dump-definitions`:**

```yaml
name: astgen
version: 0.5.0
description: AST generator for Dart projects
mode: single_command
features:
  project_traversal: true
  git_traversal: false
  recursive_scan: true
  verbose: true
required_natures: [dart_project]
global_options: []
options:
  - { name: output, type: option, description: "Output directory" }
  - { name: force, type: flag, description: "Overwrite existing files" }
```

**Example output of `buildkit --dump-definitions`:**

```yaml
name: buildkit
version: 3.1.0
description: Pipeline-based build orchestration tool
mode: multi_command
features:
  project_traversal: true
  git_traversal: true
  recursive_scan: true
  dry_run: true
  verbose: true
required_natures: []
global_options:
  - { name: list, abbr: l, type: flag, description: "List available pipelines and commands" }
  - { name: workspace-recursion, abbr: w, type: flag, description: "Shell out to sub-workspaces" }
commands:
  versioner:
    description: Manage project versions
    # ... all 40+ native commands ...
  # NOTE: nested tool commands (e.g. :buildkittest) are NOT included.
  # They exist only at runtime via wiring, not in the native definition.
```

The `ToolDefinitionSerializer` walks the existing `ToolDefinition` →
`CommandDefinition` → `OptionDefinition` tree. All data is already there —
no new metadata needed. The host tool parses the YAML response and picks
out only the commands it needs based on its wiring configuration.

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
| `binary` | Yes | String | Executable name (no `.exe` — added automatically on Windows) |
| `mode` | Yes | `multi_command` / `standalone` | Whether tool has sub-commands |
| `commands` | If multi_command | Map of `host_name: nested_name` | Command mapping with renames |

That's it. Everything else is auto-discovered.

---

### 5. Startup Flow: Lazy Wiring

Wiring is **demand-driven** — the host tool only queries nested tools that are
actually needed for the current invocation. This ensures:

- **No startup failures** when workspace binaries haven't been built yet
  (e.g., `buildkit :compiler` works even if testkit doesn't exist)
- **No unnecessary `--dump-definitions` calls** for tools not involved
  in the current command

#### Wiring Sources

The effective wiring is assembled from two sources:

1. **Code-level:** `tool.defaultIncludes` (if any)
2. **File-level:** `nested_tools:` from the resolved `wiringFile` (if file exists)

YAML entries override code entries when both define wiring for the same binary.

#### Flow

```
ToolRunner.run()
  1. Parse CLI args → determine requested commands
  2. If --nested: skip wiring, run single-project → return
  3. If --dump-definitions: serialize full tool definition → return
  4. Merge wiring sources:
     a. Start with tool.defaultIncludes (code-level)
     b. Overlay nested_tools: from wiringFile (file-level, wins on conflict)
     c. Build command → wiring lookup (which entry owns which host command)
  5. Determine which nested tools are needed:
     - Normal invocation: only tools providing commands in the request
     - Help/list mode: ALL wired tools are candidates
  6. For each needed tool:
     a. Resolve platform-aware binary name (append .exe on Windows)
     b. Check binary exists (which/where)
        - Help mode: skip missing binaries, mark commands as unavailable
        - Execution mode: fail immediately if binary is missing
     c. Run: <binary> --dump-definitions
     d. Parse full YAML response
     e. Extract commands listed in the wiring config
     f. Verify all wired commands exist in the dump
     g. Build CommandDefinition objects (host names, descriptions from dump)
     h. Build NestedToolExecutor instances
     i. Register in command + executor maps
  7. Proceed with normal traversal + dispatch (or help display)
```

#### Examples

**Only native commands — no nested tools queried:**

```
$ buildkit :compiler

[startup] Merging wiring: 2 code defaults + 0 YAML overrides → 3 wired commands
[startup] Commands requested: :compiler
[startup] No nested tools needed — skipping all --dump-definitions calls
[traversal] ...
```

**Mixed native + nested — only the needed tool is queried:**

```
$ buildkit -r :cleanup :buildkittest --test-args="--name parser"

[startup] Merging wiring: 2 code defaults + 0 YAML overrides → 3 wired commands
[startup] Commands requested: :cleanup, :buildkittest
[startup] Need testkit (provides :buildkittest) — querying
[startup] Skip astgen (no commands requested)
[startup] testkit --dump-definitions → 12 commands received
[startup] Wiring: buildkittest → test, buildkitbaseline → baseline
[startup] Binary check: testkit ✓
[traversal] ...
```

**Help mode — all tools queried, missing binaries tolerated:**

```
$ buildkit --help

[startup] Merging wiring: 2 code defaults + 0 YAML overrides → 3 wired commands
[startup] Help requested — attempting to wire all tools
[startup] testkit --dump-definitions → 12 commands received
[startup] astgen: binary not found — commands marked as unavailable
[help] ...
```

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

### 7. Help Integration

Wired commands appear in the host tool's help output alongside native commands.
When a user asks for detailed help on a wired command, the host tool delegates
to the nested tool.

#### Command list in `--help`

The general help output includes wired commands with descriptions obtained
from `--dump-definitions`. Commands are grouped by source:

```
Available commands:
  :cleanup          Cleanup build artifacts
  :versioner        Manage project versions
  :compiler         Compile project
  ... (native commands)

  Nested commands:
  :buildkittest     Run tests and add result column (via testkit)
  :buildkitbaseline Create a new baseline CSV file (via testkit)
  :buildkitAstgen   AST generator for Dart projects (via astgen)
```

If a binary is not found during help (lazy wiring tolerates this):

```
  :buildkitAstgen   [astgen not found — run buildkit :compiler first]
```

Descriptions come from the `--dump-definitions` output — specifically the
command's `description` field for multi-command tools, or the tool's
`description` field for standalone tools.

#### Detailed help: `<tool> help <command>`

When the user requests detailed help for a wired command, the host tool
delegates to the nested tool's own help system:

```bash
# For multi-command nested tools:
buildkit help buildkittest
# → Calls: testkit --nested help test
# Shows testkit's native help for the :test command

# For standalone nested tools:
buildkit help buildkitAstgen
# → Calls: astgen --nested --help
# Shows astgen's full help output
```

If the nested binary is not available:

```
Command :buildkitAstgen is provided by "astgen" (not found on PATH).
Build the binary first, then run: astgen --help
```

---

### 8. NestedToolExecutor

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

### 9. Binary Pre-Check

Binary validation is integrated into the lazy wiring flow (step 6b in
Section 5). Only binaries for **requested** commands are checked — and
in help mode, missing binaries are tolerated:

```dart
/// Resolve platform-aware binary name.
String _resolveBinary(String binary) =>
    Platform.isWindows ? '$binary.exe' : binary;

/// Check that nested tool binaries are available for requested commands.
///
/// Only checks binaries for commands that will actually be invoked.
/// Running `buildkit :cleanup :versioner` does not require testkit.
///
/// In help mode, [tolerateMissing] is true — missing binaries are
/// returned as warnings rather than errors.
List<String> validateNestedBinaries({
  required Set<String> requestedCommands,
  bool tolerateMissing = false,
}) {
  final missing = <String>[];
  for (final cmdName in requestedCommands) {
    final executor = executors[cmdName];
    if (executor is NestedToolExecutor) {
      final resolved = _resolveBinary(executor.binary);
      if (!_isBinaryOnPath(resolved)) {
        missing.add(':$cmdName requires "$resolved" — not found');
      }
    }
  }
  return missing;
}
```

```dart
// In ToolRunner.run(), after lazy wiring but before traversal:
final missingBinaries = validateNestedBinaries(
  requestedCommands: cliArgs.commands.toSet(),
  tolerateMissing: cliArgs.isHelpMode,
);
if (!cliArgs.isHelpMode && missingBinaries.isNotEmpty) {
  output.writeln('Error: Missing required tool binaries:');
  for (final msg in missingBinaries) {
    output.writeln('  - $msg');
  }
  return ToolResult.failure('Missing nested tool binaries');
}
```

---

### 10. Concrete Example: Full Lifecycle

#### Code-Level Defaults (from `buildkitTool`)

```dart
const buildkitTool = ToolDefinition(
  name: 'buildkit',
  wiringFile: ToolDefinition.kAutoWiringFile,
  defaultIncludes: [
    ToolWiringEntry(binary: 'testkit', mode: WiringMode.multiCommand,
        commands: {'buildkittest': 'test', 'buildkitbaseline': 'baseline'}),
    ToolWiringEntry(binary: 'astgen', mode: WiringMode.standalone),
  ],
  // ...
);
```

#### Optional YAML Override in `buildkit_master.yaml`

```yaml
# Only needed if overriding or extending code-level defaults
nested_tools:
  testkit:
    binary: testkit
    mode: multi_command
    commands:
      buildkittest: test
      buildkitbaseline: baseline
      buildkitstatus: status     # additional command not in code defaults
```

#### Startup (lazy — only needed tools queried)

```
$ buildkit -s . -r :buildkittest --test-args="--name parser"

[startup] Merging wiring: 2 code defaults + 1 YAML override → 4 wired commands
[startup] Commands requested: :buildkittest
[startup] Need testkit (provides :buildkittest) — querying
[startup] Skip astgen (no commands in current request)
[startup] testkit --dump-definitions
[startup]   Full dump received: 12 commands
[startup]   Wiring: buildkittest → test
[startup]   → :buildkittest registered (testkit :test, natures: [dart_project])
[startup] Binary check: testkit ✓
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

#### Native-Only Invocation (no nested tools needed)

```
$ buildkit :compiler

[startup] Merging wiring: 2 code defaults + 0 YAML overrides → 3 wired commands
[startup] Commands requested: :compiler
[startup] No nested tools needed — skipping all --dump-definitions calls
[traversal] Scanning . recursively...
```

No binary checks, no `--dump-definitions` calls. Works even if testkit
and astgen haven't been compiled yet.

#### Help Display

```
$ buildkit --help

[startup] Help requested — wiring all tools
[startup] testkit --dump-definitions → 12 commands
[startup] astgen: binary not found — marked as unavailable

buildkit 3.1.0 — Pipeline-based build orchestration tool

Usage: buildkit [options] :command [command-options]

Commands:
  :cleanup          Cleanup build artifacts
  :versioner        Manage project versions
  :compiler         Compile project
  ... (native commands)

  Nested commands:
  :buildkittest     Run tests and add result column (via testkit)
  :buildkitbaseline Create a new baseline CSV file (via testkit)
  :buildkitAstgen   [astgen not found — run buildkit :compiler first]
```

#### Registration Workflow

```bash
# Inspect what testkit offers (full dump — all commands, all options):
$ testkit --dump-definitions
name: testkit
version: 1.2.0
description: Test result tracking for Dart projects
mode: multi_command
features:
  project_traversal: true
  ...
required_natures: [dart_project]
global_options:
  - { name: tui, type: flag, description: "Run in TUI mode" }
commands:
  test:
    description: Run tests and add result column to the most recent baseline
    options:
      - { name: test-args, type: option, ... }
    works_with_natures: [dart_project]
  baseline:
    description: Create a new baseline CSV file
    ...
  status:
    description: Show test status summary
    ...
  # ... all 12 native commands listed ...

# Pick the commands you want and add wiring to buildkit_master.yaml:
# nested_tools:
#   testkit:
#     binary: testkit
#     mode: multi_command
#     commands:
#       buildkittest: test
#       buildkitbaseline: baseline
```

---

### 11. `_runBinary` Helper

Binary names are resolved to their platform-specific form before execution:

```dart
Future<ItemResult> _runBinary(
  String binary,
  List<String> args,
  String workingDirectory,
) async {
  final resolved = _resolveBinary(binary);
  final result = await Process.run(
    resolved,
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
      message: '$resolved exited with code ${result.exitCode}',
    );
  }
}
```

---

### 12. Binary Path Resolution and Platform Awareness

All binary names in both code-level `defaultIncludes` and YAML `nested_tools:`
are stored **without** platform extensions. The `.exe` suffix is appended
automatically on Windows at every resolution point:

```dart
/// Resolve a platform-specific binary name.
///
/// On Windows, appends `.exe` to the binary name.
/// On macOS/Linux, returns the name unchanged.
String _resolveBinary(String binary) =>
    Platform.isWindows ? '$binary.exe' : binary;

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

**Resolution points** (all use `_resolveBinary`):
- `validateNestedBinaries` — existence check
- `_runBinary` — actual process execution
- `--dump-definitions` calls during lazy wiring

This means wiring YAML, `ToolWiringEntry.binary`, and serialized definitions
all use platform-neutral names (`testkit`, not `testkit.exe`).

---

## Implementation Plan

### Phase 1: Tool Inheritance (Part A)

1. Add `copyWith` to `ToolDefinition`
2. Add `CommandListOps` extension
3. Add tests
4. Publish `tom_build_base`

### Phase 2: Core Infrastructure (Part B — tom_build_base)

1. Add `wiringFile` field to `ToolDefinition`
2. Add `defaultIncludes` field and `ToolWiringEntry` class
3. Add `--nested` flag to `commonOptions`
4. Add `--dump-definitions` flag to `commonOptions`
5. Implement `ToolDefinitionSerializer` (walks definition tree → YAML)
6. Implement `NestedToolExecutor` class
7. Implement lazy wiring loader (merges code + YAML, demand-driven `--dump-definitions`)
8. Add `_resolveBinary` platform helper (`.exe` on Windows)
9. Add `validateNestedBinaries` to `ToolRunner` (with help-mode tolerance)
10. Implement help integration (command list with descriptions, `help <cmd>` delegation)
11. Wire into `ToolRunner.run()` flow (nested bypass, dump bypass, lazy wiring, help)
12. Add `_runBinary` and `_isBinaryOnPath` helpers
13. Add tests (mock binary execution, platform resolution, help delegation)
14. Publish `tom_build_base`

### Phase 3: Buildkit Integration (consuming)

1. Set `wiringFile: ToolDefinition.kAutoWiringFile` on `buildkitTool`
2. Set `defaultIncludes: [...]` for testkit, astgen, d4rtgen
3. Add `nested_tools:` section to workspace `buildkit_master.yaml`
4. Test end-to-end: `buildkit :buildkittest`, `buildkit :buildkitAstgen`
5. Test lazy behavior: `buildkit :compiler` with missing nested binaries
6. Test help: `buildkit --help`, `buildkit help buildkittest`

---

## Architecture Summary

```
                    ┌──────────────────────────────────────┐
                    │            tom_build_base             │
                    │                                      │
                    │  ToolDefinition                      │
                    │    + wiringFile: String?              │
                    │    + defaultIncludes: [WiringEntry]?  │
                    │    + copyWith(...)                    │
                    │                                      │
                    │  ToolWiringEntry                      │
                    │    binary, mode, commands             │
                    │                                      │
                    │  commonOptions                       │
                    │    + --nested                        │
                    │    + --dump-definitions               │
                    │                                      │
                    │  ToolRunner                           │
                    │    + lazy wiring (demand-driven)      │
                    │    + nested mode bypass               │
                    │    + dump-definitions bypass          │
                    │    + help integration                 │
                    │    + validateNestedBinaries()         │
                    │    + _resolveBinary() (platform)      │
                    │                                      │
                    │  NestedToolExecutor                   │
                    │  ToolDefinitionSerializer             │
                    └────────────────┬─────────────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
    ┌─────────▼────────┐  ┌─────────▼────────┐  ┌──────────▼───────┐
    │     buildkit      │  │     testkit      │  │     d4rtgen      │
    │                   │  │                  │  │                  │
    │ wiringFile: ''    │  │ wiringFile: null  │  │ wiringFile: null │
    │ defaultIncludes:  │  │ (no hosting)     │  │ (no hosting)     │
    │   [testkit,       │  │                  │  │                  │
    │    astgen,        │  │ Responds to:     │  │ Responds to:     │
    │    d4rtgen]       │  │ --dump-defs      │  │ --dump-defs      │
    │                   │  │ --nested         │  │ --nested         │
    │ + YAML overrides  │  │                  │  │                  │
    └───────────────────┘  └──────────────────┘  └──────────────────┘
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
