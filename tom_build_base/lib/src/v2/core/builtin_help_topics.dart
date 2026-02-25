/// Built-in help topics available to all Tom CLI tools.
///
/// These topics are automatically registered when tools opt in.
/// Use [defaultHelpTopics] to get all built-in topics.
library;

import 'help_topic.dart';

/// All built-in help topics.
///
/// Tools can include these in their [ToolDefinition.helpTopics].
const List<HelpTopic> defaultHelpTopics = [placeholdersHelpTopic];

/// Help topic documenting placeholder and environment variable usage.
const placeholdersHelpTopic = HelpTopic(
  name: 'placeholders',
  summary: 'Variable substitution in commands and config files',
  content: _placeholdersContent,
);

const _placeholdersContent = r'''
**Placeholders**

Three separate placeholder systems are used depending on context:

  ${...}    Command placeholders — resolved in commands during traversal
  @{...}    Config placeholders — resolved in YAML config files
  @[...]    Define placeholders — user-defined values in YAML config files

Each system is independent and uses its own syntax.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

<cyan>**COMMAND PLACEHOLDERS  ${...}**</cyan>

  Resolved per folder during workspace traversal in :execute, :compiler,
  and other commands that run shell commands.

  <cyan>Syntax:</cyan>
    ${name}                Simple placeholder
    ${cond?(yes):(no)}     Ternary (boolean placeholders only)

  <cyan>Path Placeholders</cyan>

    ${root}                Workspace root (absolute path)
    ${folder}              Current folder (absolute path)
    ${folder.name}         Folder basename
    ${folder.relative}     Folder relative to workspace root

  <cyan>Platform Placeholders</cyan>

    ${current-os}          Operating system (linux, macos, windows)
    ${current-arch}        Architecture (x64, arm64, armhf)
    ${current-platform}    Combined (darwin-arm64, linux-x64, etc.)

  <cyan>Compiler Placeholders</cyan> (buildkit :compiler only)

    ${file}                Source file path
    ${file.path}           Source file path (alias)
    ${file.name}           Source file name without extension
    ${file.basename}       Source file basename with extension
    ${file.extension}      Source file extension
    ${file.dir}            Source file directory
    ${target-os}           Target OS (linux, macos, windows)
    ${target-arch}         Target arch (x64, arm64, armhf)
    ${target-platform}     Target for dart compile (linux, macos, windows)
    ${target-platform-vs}  Target slug (linux-x64, darwin-arm64, etc.)
    ${current-platform-vs} Current platform slug

  <cyan>Nature Detection (boolean)</cyan>

    ${dart.exists}             true if Dart project (pubspec.yaml)
    ${flutter.exists}          true if Flutter project
    ${package.exists}          true if Dart package (has lib/src/)
    ${console.exists}          true if Dart console app (has bin/)
    ${git.exists}              true if git repository
    ${typescript.exists}       true if TypeScript project
    ${vscode-extension.exists} true if VS Code extension
    ${buildkit.exists}         true if has buildkit.yaml
    ${tom-project.exists}      true if has tom_project.yaml

  <cyan>Nature Attributes</cyan>

    ${dart.name}           Project name from pubspec.yaml
    ${dart.version}        Version from pubspec.yaml
    ${dart.publishable}    true if publishable to pub.dev (boolean)
    ${flutter.platforms}   Comma-separated platform list
    ${flutter.isPlugin}    true if Flutter plugin (boolean)
    ${git.branch}          Current branch name
    ${git.isSubmodule}     true if git submodule (boolean)
    ${git.hasChanges}      true if uncommitted changes (boolean)
    ${git.remotes}         Comma-separated remote list
    ${vscode.name}         Extension name
    ${vscode.version}      Extension version

  <cyan>Ternary Expressions</cyan>

    Boolean placeholders support conditional substitution:

      ${dart.exists?(dart project):(not dart)}
      ${git.hasChanges?(DIRTY):(clean)}

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

  Environment variables do NOT use curly braces — ${...} is reserved
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
    │ ${path/platform/nature}│   ✓      │          │   ✓      │
    │ ${file/target}         │          │          │   ✓      │
    │ @{tool placeholders}   │          │   ✓      │          │
    │ @[defines]             │          │   ✓      │          │
    │ $VAR / $[VAR]          │   ✓ (\*)  │   ✓      │   ✓      │
    └────────────────────────┴──────────┴──────────┴──────────┘
    (\*) resolved by shell, not by the tool

<green>**EXAMPLES**</green>

  Execute command with placeholders:
    buildkit :execute "echo ${folder.name} on ${current-platform}"

  Conditional execution:
    buildkit :execute --condition dart.exists "dart analyze"

  Ternary in commands:
    buildkit :execute "echo ${dart.exists?(Dart: ${dart.name}):(not Dart)}"

  Config file with all placeholder types:
    defines:
      arch: darwin-arm64
    compiler:
      binaryPath: @{workspace-root}/tom_binaries/@[arch]
      commands:
        - mkdir -p $TOM_BINARY_PATH/${target-platform-vs}
        - dart compile exe ${file} -o $TOM_BINARY_PATH/${target-platform-vs}/${file.name}
''';
