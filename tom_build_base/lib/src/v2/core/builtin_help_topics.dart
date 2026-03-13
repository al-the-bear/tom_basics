/// Built-in help topics available to all Tom CLI tools.
///
/// These topics are automatically registered when tools opt in.
/// Use [defaultHelpTopics] to get all built-in topics.
/// Use [masterYamlHelpTopics] for topics specific to tools with a master YAML.
library;

import 'help_topic.dart';

/// All built-in help topics that apply to every tool.
///
/// Tools can include these in their [ToolDefinition.helpTopics].
const List<HelpTopic> defaultHelpTopics = [placeholdersHelpTopic];

/// Help topics for tools that use a `{tool}_master.yaml` configuration file.
///
/// These topics are automatically injected by [ToolRunner] when it detects
/// that the tool has multi-command mode and a master YAML file.
/// Individual tools do NOT need to add these to their `helpTopics` list.
///
/// Covers: defines, macros, pipelines, wiring.
const List<HelpTopic> masterYamlHelpTopics = [
  definesHelpTopic,
  macrosHelpTopic,
  pipelinesHelpTopic,
  wiringHelpTopic,
];

// ─────────────────────────────────────────────────────────────
// PLACEHOLDERS
// ─────────────────────────────────────────────────────────────

/// Help topic documenting placeholder and environment variable usage.
const placeholdersHelpTopic = HelpTopic(
  name: 'placeholders',
  summary: 'Variable substitution in commands and config files',
  content: _placeholdersContent,
);

const _placeholdersContent = r'''
**Placeholders**

Three separate placeholder systems are used depending on context:

  %{...}    Command placeholders — resolved in commands during traversal
  @{...}    Config placeholders — resolved in YAML config files
  @[...]    Define placeholders — user-defined values in YAML config files

Each system is independent and uses its own syntax.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<cyan>**COMMAND PLACEHOLDERS  %{...}**</cyan>

  Resolved per folder during workspace traversal in :execute, :compiler,
  and other commands that run shell commands.

  <cyan>Syntax:</cyan>
    %{name}                Simple placeholder
    %{cond?(yes):(no)}     Ternary (boolean placeholders only)

  <cyan>Path Placeholders</cyan>

    %{root}                Workspace root (absolute path)
    %{folder}              Current folder (absolute path)
    %{folder.name}         Folder basename
    %{folder.relative}     Folder relative to workspace root

  <cyan>Platform Placeholders</cyan>

    %{current-os}          Operating system (linux, macos, windows)
    %{current-arch}        Architecture (x64, arm64, armhf)
    %{current-platform}    Combined (darwin-arm64, linux-x64, etc.)

  <cyan>Compiler Placeholders</cyan> (buildkit :compiler only)

    %{file}                Source file path
    %{file.path}           Source file path (alias)
    %{file.name}           Source file name without extension
    %{file.basename}       Source file basename with extension
    %{file.extension}      Source file extension
    %{file.dir}            Source file directory
    %{target-os}           Target OS (linux, macos, windows)
    %{target-arch}         Target arch (x64, arm64, armhf)
    %{target-platform}     Target for dart compile (linux, macos, windows)
    %{target-platform-vs}  Target slug (linux-x64, darwin-arm64, etc.)
    %{current-platform-vs} Current platform slug

  <cyan>Nature Detection (boolean)</cyan>

    %{dart.exists}             true if Dart project (pubspec.yaml)
    %{flutter.exists}          true if Flutter project
    %{package.exists}          true if Dart package (has lib/src/)
    %{console.exists}          true if Dart console app (has bin/)
    %{git.exists}              true if git repository
    %{typescript.exists}       true if TypeScript project
    %{vscode-extension.exists} true if VS Code extension
    %{buildkit.exists}         true if has buildkit.yaml
    %{tom-project.exists}      true if has tom_project.yaml

  <cyan>Nature Attributes</cyan>

    %{dart.name}           Project name from pubspec.yaml
    %{dart.version}        Version from pubspec.yaml
    %{dart.publishable}    true if publishable to pub.dev (boolean)
    %{flutter.platforms}   Comma-separated platform list
    %{flutter.isPlugin}    true if Flutter plugin (boolean)
    %{git.branch}          Current branch name
    %{git.isSubmodule}     true if git submodule (boolean)
    %{git.hasChanges}      true if uncommitted changes (boolean)
    %{git.remotes}         Comma-separated remote list
    %{vscode.name}         Extension name
    %{vscode.version}      Extension version

  <cyan>Ternary Expressions</cyan>

    Boolean placeholders support conditional substitution:

      %{dart.exists?(dart project):(not dart)}
      %{git.hasChanges?(DIRTY):(clean)}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<cyan>**CONFIG PLACEHOLDERS  @{...}**</cyan>

  Resolved in YAML config files (buildkit.yaml, testkit.yaml,
  issuekit.yaml, etc.) during config loading. Available in both
  master and project config files.

  <cyan>Built-in Config Placeholders</cyan>

    @{project-path}        Absolute path to the current project folder
    @{project-name}        Folder basename of the current project
    @{workspace-root}      Absolute path to the workspace root
    @{tool-name}           Name of the current tool (e.g. buildkit)
    @{tool-version}        Version of the current tool

  Tools may register additional custom @{...} placeholders via the
  ConfigLoader.toolPlaceholders mechanism.

  <cyan>Resolution</cyan>

    Config placeholders are resolved AFTER mode filtering and BEFORE
    the config is parsed into commands. They are recursive — a resolved
    value may contain further @{...} placeholders (max depth 10).

  <cyan>Example</cyan> (buildkit.yaml)

    compiler:
      binaryPath: @{workspace-root}/tom_binaries/@{tool-name}
      outputDir: @{project-path}/build/bin

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<cyan>**DEFINE PLACEHOLDERS  @[...]**</cyan>

  User-defined values declared in the defines: section of YAML config
  files. They act as reusable constants within that config file.

  <cyan>Syntax</cyan>

    defines:
      my-var: some-value
      output: /tmp/results

  Reference anywhere else in the same file:

    @[my-var]     → some-value
    @[output]     → /tmp/results

  <cyan>Resolution Order</cyan>

    1. Project config defines override master config defines
    2. Mode-prefixed defines are applied when that mode is active
       (e.g. DEV-defines: for development mode)
    3. @[...] placeholders are resolved before @{...} placeholders

  <cyan>Example</cyan> (buildkit.yaml)

    defines:
      bin-root: @{workspace-root}/tom_binaries
      arch: darwin-arm64
    compiler:
      binaryPath: @[bin-root]/@[arch]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<yellow>**ENVIRONMENT VARIABLES**</yellow>

  Environment variables are resolved in YAML config files and shell
  commands. Two syntaxes are supported:

    $VAR_NAME             Standard syntax (word-boundary delimited)
    $[VAR_NAME]           Bracket syntax (explicit boundaries)

  The bracket syntax $[VAR] is useful when the variable is followed
  by text that could be part of the name:

    $[HOME]backup         → /Users/me/backup
    $HOMEbackup           → (tries to resolve $HOMEbackup — wrong)

  In buildkit.yaml compiler commands, env vars are resolved twice:
  1. Before execution by the compiler executor ($VAR regex)
  2. By the shell when running the command (sh -c)

  Environment variables do NOT use curly braces — %{...} is reserved
  for command placeholders. Use $VAR or $[VAR] for env vars.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<yellow>**RECURSIVE RESOLUTION**</yellow>

  All config placeholder types support recursive resolution — a
  resolved value may itself contain placeholders that get resolved
  in subsequent passes (max depth: 10).

  <cyan>@[...] define chains</cyan>

    defines:
      base: /opt/tools
      bin:  @[base]/bin         → /opt/tools/bin
      app:  @[bin]/myapp        → /opt/tools/bin/myapp

  <cyan>@{...} in resolved @[...] values</cyan>

    @[...] defines are resolved first, then @{...} config placeholders.
    This means a define value can contain @{...} references:

    defines:
      out: @{workspace-root}/build
    compiler:
      outputDir: @[out]/@{project-name}    → <workspace>/build/<project>

  <cyan>Resolution order in config files</cyan>

    1. Mode filtering (DEV-, CI-, etc.)
    2. @[...] define placeholders (recursive, depth ≤ 10)
    3. @{...} config placeholders (recursive, depth ≤ 10)
    4. $VAR / $[VAR] environment variables (single pass)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<green>**CONTEXT REFERENCE**</green>

  Where each placeholder type is available:

    ┌────────────────────────┬──────────┬──────────┬──────────┐
    │ Placeholder            │ Commands │ Config   │ Compiler │
    ├────────────────────────┼──────────┼──────────┼──────────┤
    │ %{path/platform/nature}│   ✓      │          │   ✓      │
    │ %{file/target}         │          │          │   ✓      │
    │ @{tool placeholders}   │          │   ✓      │          │
    │ @[defines]             │          │   ✓      │          │
    │ $VAR / $[VAR]          │   ✓ (\*)  │   ✓      │   ✓      │
    └────────────────────────┴──────────┴──────────┴──────────┘
    (\*) resolved by shell, not by the tool

<green>**EXAMPLES**</green>

  Execute command with placeholders:
    buildkit :execute "echo %{folder.name} on %{current-platform}"

  Conditional execution:
    buildkit :execute --condition dart.exists "dart analyze"

  Ternary in commands:
    buildkit :execute "echo %{dart.exists?(Dart: %{dart.name}):(not Dart)}"

  Config file with all placeholder types:
    defines:
      arch: darwin-arm64
    compiler:
      binaryPath: @{workspace-root}/tom_binaries/@[arch]
      commands:
        - mkdir -p $TOM_BINARY_PATH/%{target-platform-vs}
        - dart compile exe %{file} -o $TOM_BINARY_PATH/%{target-platform-vs}/%{file.name}
''';

// ─────────────────────────────────────────────────────────────
// DEFINES
// ─────────────────────────────────────────────────────────────

/// Help topic documenting the defines system.
const definesHelpTopic = HelpTopic(
  name: 'defines',
  summary: 'Persistent key-value defines in master and project YAML',
  content: _definesContent,
);

const _definesContent = r'''
<cyan>**Persistent Defines**</cyan>

  Defines are key-value pairs stored in {TOOL}_master.yaml that act as
  reusable constants. They are referenced in YAML config files as @[name]
  placeholders and resolved before commands are executed.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<green>**Manage Defines**</green>

  {TOOL} :define <name>=<value>           Add a default define
  {TOOL} :define -m DEV <name>=<value>    Add a mode-specific define
  {TOOL} :defines                         List all defines
  {TOOL} :undefine <name>                 Remove a default define
  {TOOL} :undefine -m DEV <name>          Remove a mode-specific define

<green>**YAML Structure**</green>

  Defines are stored in the tool section of {TOOL}_master.yaml:

    {TOOL}:
      defines:
        output-dir: build/release
        arch: darwin-arm64
      DEV-defines:
        output-dir: build/debug
        debug-flags: --enable-asserts
      CI-defines:
        output-dir: /tmp/ci-output

<green>**Mode-Specific Defines**</green>

  Modes allow different define values per environment. Activate modes
  with the --modes flag:

    {TOOL} --modes DEV :execute "echo @[output-dir]"
    {TOOL} --modes DEV,CI :build

  Mode defines are applied on top of default defines in order.
  Later modes override earlier ones.

  <cyan>Resolution order:</cyan>
    1. Default defines  (defines:)
    2. First mode       (DEV-defines: if --modes DEV,CI)
    3. Second mode      (CI-defines: if --modes DEV,CI)
    4. Project defines  (from buildkit.yaml per project)

<green>**Referencing Defines**</green>

  Use @[name] syntax anywhere in YAML config files:

    compiler:
      binaryPath: @[output-dir]/bin/@[arch]

  Defines are resolved recursively (max depth 10):

    defines:
      base: /opt/tools
      bin:  @[base]/bin      → /opt/tools/bin
      app:  @[bin]/myapp     → /opt/tools/bin/myapp

<green>**Project-Level Overrides**</green>

  Each project can override master defines in its buildkit.yaml:

    defines:
      output-dir: custom/path    # overrides master value

  Project-level mode defines also work:

    DEV-defines:
      debug-flags: --verbose     # overrides master DEV value

<green>**Resolution Context**</green>

  Defines (@[...]) are resolved AFTER config placeholders (@{...}):

    defines:
      out: @{workspace-root}/build
    compiler:
      outputDir: @[out]/@{project-name}

  This means a define value can contain @{...} config placeholders.
''';

// ─────────────────────────────────────────────────────────────
// MACROS
// ─────────────────────────────────────────────────────────────

/// Help topic documenting the macro system.
const macrosHelpTopic = HelpTopic(
  name: 'macros',
  summary: 'Runtime command-line macros with argument substitution',
  content: _macrosContent,
);

const _macrosContent = r'''
<cyan>**Runtime Macros**</cyan>

  Macros are command-line shortcuts stored in {TOOL}_macros.yaml.
  They expand @name tokens in arguments to full command sequences
  with positional argument substitution.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<green>**Manage Macros**</green>

  {TOOL} :macro <name>=<value>      Add or update a macro
  {TOOL} :macros                    List all macros
  {TOOL} :unmacro <name>            Remove a macro

  Macros persist across invocations in {TOOL}_macros.yaml.

<green>**Invoke a Macro**</green>

  Use the @name prefix to invoke a macro:

    {TOOL} @mymacro [args...]

  Example:

    {TOOL} :macro bp=:build --project $1
    {TOOL} @bp tom_core         →  {TOOL} :build --project tom_core

<green>**Argument Placeholders**</green>

  Macro values can contain positional placeholders:

    $1 through $9        Positional arguments after @name
    $$                   All remaining arguments (rest/spread)

  <cyan>Positional example:</cyan>

    :macro vp=:versioner --project $1
    @vp tom_core --list    →  :versioner --project tom_core --list

  <cyan>Rest-args example:</cyan>

    :macro all=:execute $$
    @all --verbose --dry-run "echo hello"
    →  :execute --verbose --dry-run "echo hello"

  <cyan>Multiple positional:</cyan>

    :macro pair=:copy $1 $2
    @pair source.txt dest.txt    →  :copy source.txt dest.txt

  <cyan>Unused placeholders:</cyan>

    If a positional placeholder is not provided, it is replaced
    with an empty string. Extra arguments beyond the highest
    placeholder are appended.

<green>**Escaping**</green>

  To use a literal $1 in a macro value (not as a placeholder),
  escape it with a backslash:

    :macro literal=echo \$1 costs $1
    @literal 5    →  echo $1 costs 5

<green>**Nested Macros**</green>

  Macros can reference other macros in their value:

    :macro base=:build --release
    :macro full=@base --project $1

    @full tom_core    →  :build --release --project tom_core

<green>**Storage**</green>

  Macros are stored in {TOOL}_macros.yaml in the workspace root,
  separate from the master YAML. They are plain key-value pairs:

    bp: ":build --project $1"
    t: ":test --project $1"
    all: ":execute $$"
''';

// ─────────────────────────────────────────────────────────────
// PIPELINES
// ─────────────────────────────────────────────────────────────

/// Help topic documenting pipeline configuration.
const pipelinesHelpTopic = HelpTopic(
  name: 'pipelines',
  summary: 'Multi-step pipeline configuration in master YAML',
  content: _pipelinesContent,
);

const _pipelinesContent = r'''
<cyan>**Pipeline Configuration**</cyan>

  Pipelines are multi-step workflows defined in {TOOL}_master.yaml
  under a pipelines: key. Each pipeline has a name and can contain
  steps divided into three phases.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<green>**Pipeline Structure**</green>

    pipelines:
      my-pipeline:
        executable: true          # can be invoked directly (default: true)
        runBefore: [other-pipe]   # pipelines to run first
        runAfter:  [other-pipe]   # pipelines to run after
        global-options:           # default option values
          output: build/
        precore:                  # setup/validation steps
          - commands:
              - "print Starting..."
        core:                     # main steps
          - commands:
              - "shell dart pub get"
              - "{TOOL} :build"
        postcore:                 # cleanup/reporting steps
          - commands:
              - "print Done."

  <cyan>Phases</cyan>

    precore    Runs before the main work (setup, validation)
    core       The main pipeline steps
    postcore   Runs after the main work (cleanup, reporting)

  Each phase contains a list of step groups, where each group has a
  commands: list of command strings.

<green>**Command Prefixes**</green>

  Each command string starts with a prefix that determines execution:

    shell <cmd>          Run a shell command via /bin/bash -lc
    shell-scan <cmd>     Run in each scanned project folder
    {TOOL} <cmd>         Run a {TOOL} command (e.g. "{TOOL} :build")
    stdin <cmd>          Run with multi-line stdin input
    print <msg>          Print resolved text once

  All command types support standard %{...} placeholders.
  Run `{TOOL} help placeholders` for the complete reference.

  <cyan>Shell commands:</cyan>

    - commands:
        - "shell dart pub get"
      - "print Building on %{current-platform}"

  <cyan>Tool commands:</cyan>

    - commands:
        - "{TOOL} :build --release"
        - "{TOOL} :versioner --bump patch"

  <cyan>Shell-scan commands (per-project):</cyan>

    Shell-scan runs the command once per scanned project, with full
    project-level placeholder context:

    - commands:
        - "shell-scan echo %{folder.name} at %{folder}"
        - "shell-scan dart analyze %{folder}"

  <cyan>Stdin commands:</cyan>

    Multi-line input piped to a shell command:

    - commands:
        - |
          stdin cat -n
          line one
          line two

<green>**Placeholders in Pipeline Commands**</green>

  All pipeline commands (shell, shell-scan, stdin) resolve standard
  %{...} placeholders before execution:

    %{root}               Workspace root path
    %{folder}             Current folder (absolute)
    %{folder.name}        Folder basename
    %{folder.relative}    Folder path relative to workspace root
    %{current-os}         Operating system (linux, macos, windows)
    %{current-arch}       Architecture (x64, arm64)
    %{current-platform}   Platform string (darwin-arm64, linux-x64, etc.)

  Shell-scan commands additionally have access to nature-specific
  placeholders (e.g. %{dart.name}, %{dart.version}, %{git.branch})
  since they run in per-project traversal context.

  Run `{TOOL} help placeholders` for the full list.

<green>**Pipeline Invocation**</green>

    {TOOL} <pipeline-name>                Run a named pipeline
    {TOOL} <pipeline-name> --dry-run      Show commands without executing
    {TOOL} --list                         List available pipelines

  Pipelines are invoked by their name as a positional argument
  (without the : prefix used for commands).

<green>**Pipeline Dependencies**</green>

    runBefore: [setup, validate]
    runAfter:  [report]

  The framework executes dependent pipelines automatically.
  Circular dependencies are detected and rejected.

<green>**Nested Workspaces**</green>

  When a pipeline runs, the framework also discovers nested workspaces
  (sub-directories containing their own {TOOL}_master.yaml). For each
  nested workspace, the pipeline is delegated to a fresh {TOOL} process.

  Global traversal options (--project, --exclude, --root) disable
  nested-workspace delegation.

<green>**Global Options**</green>

  Pipelines can set default options via global-options:

    pipelines:
      release:
        global-options:
          output: dist/
          verbose: "true"
        core:
          - commands:
              - "shell dart compile exe %{file}"
''';

// ─────────────────────────────────────────────────────────────
// WIRING
// ─────────────────────────────────────────────────────────────

/// Help topic documenting nested tool wiring.
const wiringHelpTopic = HelpTopic(
  name: 'wiring',
  summary: 'Nested tool integration via master YAML configuration',
  content: _wiringContent,
);

const _wiringContent = r'''
<cyan>**Tool Wiring**</cyan>

  Wiring lets a host tool ({TOOL}) incorporate commands from other
  standalone CLI tools. Wired commands appear in {TOOL}'s help and
  can be invoked as if they were native commands.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<green>**How Wiring Works**</green>

  1. The host tool defines a wiringFile (typically {TOOL}_master.yaml)
  2. Nested tools are listed in the nested_tools: section of that file
  3. At startup, {TOOL} queries each nested tool via --dump-definitions
  4. Wired commands appear as "Nested Commands" in {TOOL} --help

  Wired commands are delegated to the nested tool binary with the
  --nested flag, so nested tools run in single-project mode within
  the host tool's traversal context.

<green>**YAML Configuration**</green>

  In {TOOL}_master.yaml:

    nested_tools:
      testkit:
        binary: testkit
        mode: multi_command
        commands:
          buildkittest: test
          buildkitbaseline: baseline
      astgen:
        binary: astgen
        mode: standalone

  <cyan>Fields:</cyan>

    binary         Binary name to execute (resolved via PATH)
    mode           multi_command or standalone
    commands       Command name mapping (host-name: nested-name)

<green>**Multi-Command Wiring**</green>

  For multi-command tools, the commands: map connects host command
  names to nested tool command names:

    testkit:
      binary: testkit
      mode: multi_command
      commands:
        buildkittest: test          # {TOOL} :buildkittest → testkit :test
        buildkitbaseline: baseline  # {TOOL} :buildkitbaseline → testkit :baseline

  This allows the host tool to expose specific commands from nested
  tools under custom names.

<green>**Standalone Wiring**</green>

  Standalone tools are wired as a single command using the binary
  name as the command name:

    astgen:
      binary: astgen
      mode: standalone

  Invoke with: {TOOL} :astgen [args...]

<green>**Code-Level Wiring**</green>

  Tools can also define default wiring in code via defaultIncludes:

    ToolDefinition(
      name: 'buildkit',
      defaultIncludes: [
        ToolWiringEntry(
          binary: 'testkit',
          mode: WiringMode.multiCommand,
          commands: {'buildkittest': 'test'},
        ),
      ],
    )

  YAML nested_tools: entries override code-level defaults for the
  same binary name. This allows users to customize wiring without
  modifying tool source code.

<green>**Lazy Resolution**</green>

  Wiring is lazy — only the nested tools needed for the current
  invocation are queried. In help mode, all tools are queried but
  missing binaries produce warnings instead of errors.

<green>**Binary Resolution**</green>

  Nested tool binaries are resolved via PATH. On Windows, .exe is
  appended automatically. The binary must support --dump-definitions
  to report its command definitions to the host tool.

<green>**Verifying Wiring**</green>

    {TOOL} --help                   See wired commands under Nested Commands
    {TOOL} help :wired-cmd          Help for a specific wired command
    {TOOL} --dump-definitions       Full YAML dump including wired commands
''';
