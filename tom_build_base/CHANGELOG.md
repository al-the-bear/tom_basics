## 2.6.32

### Added

- **Shell completion delivery (`--completion <shell>`)** — every tool built on
  the v2 `ToolRunner` now accepts a global `--completion bash|zsh|fish` option
  that prints a shell completion script generated from the tool's own command
  and option definitions, then exits. Intercepted early (alongside
  `--dump-definitions`), so it runs anywhere without traversal. An unknown shell
  prints an error and exits non-zero. The generation itself
  (`CompletionGenerator`) already existed; this wires it into the framework so
  the capability is delivered uniformly with no per-tool code. See
  `doc/cli_shell_completion.md`.
- **`BuildOrderComputer.computeBuildOrderResult`** — a cycle-aware variant of
  `computeBuildOrder` returning a `BuildOrderResult` (the ordered paths, or the
  names of the projects participating in a dependency cycle). `computeBuildOrder`
  is retained and now delegates to it.
- **`ToolRunner.normalizeArgs`** — the legacy single-dash flag normalization
  (`-help` → `--help`, `-version` → `--version`, at any position) that `run`
  already applied internally is now exposed as a public static method. Tools
  that pre-parse arguments *before* delegating to `run` (e.g. testkit's `--tui`
  detection, issuekit's pre-token help/version early-exit) can call the shared
  method instead of carrying their own duplicate helper. Covered by BB-RUN-67.
- **Canonical `OutputFormat` / `OutputSpec`** (`src/v2/core/output_format.dart`,
  exported from `tom_build_base_v2.dart`) — the shared CLI output-format enum
  (`plain`/`csv`/`json`/`md`, with `text`/`markdown` aliases) and the
  `<format>[:<file>]` spec parser that testkit and issuekit each duplicated.
  `OutputSpec` carries `format` + optional `filePath` (with `hasFile` and a
  `defaultSpec` of plain→stdout), splits at the first colon so file paths may
  contain colons, and treats a trailing empty file part (`csv:`) as "no file".
  Consumers migrate onto it (issuekit's `filename` field reconciled to
  `filePath`) once published. Covered by BB-OUT-1..10.

### Changed

- **Build-order traversal now reports dependency cycles instead of silently
  falling back to scan order.** Previously a circular dependency made
  `computeBuildOrder` return `null`, which `BuildBase.traverse` swallowed with
  `?? []`, so build-order mode quietly proceeded in scan order. It now emits a
  clear `stderr` warning naming the projects involved in the cycle before
  falling back, so callers can trust (and debug) execution-order semantics.
- **Pipeline `shell`/`stdin` dry-run previews now carry a `[DRY RUN]`
  indicator.** `ToolPipelineExecutor._runShell`/`_runStdin` previewed a dry-run
  step under the same `[PIPELINE:shell]`/`[PIPELINE:stdin]` marker used for
  verbose real runs, so the only cue that a step was skipped was the *absence*
  of execution output — ambiguous, since a real command may also be silent.
  Dry-run previews are now prefixed `[DRY RUN] [PIPELINE:shell] …` /
  `[DRY RUN] [PIPELINE:stdin] …`, consistent with the mklink/versioner
  executors' `[DRY RUN]` precedent; verbose real runs keep the bare marker.
  Covered by BB-PLX-6/BB-PLX-7.

### Fixed

- **`--project` path guards now also cover command-level patterns.** The
  within-root and existence guards (`validateProjectPathsWithinRoot`,
  `validateProjectPathsExist`) were only applied to the global
  `cliArgs.projectPatterns`, so a bad path passed *after* the command
  (`tool :cmd --project sub/nonexistent`, which lands in
  `commandArgs[cmd].projectPatterns`) slipped past both guards — an
  out-of-root or non-existent path scanned, matched nothing, and exited `0`.
  Both guard sites now validate the combined global + per-command pattern list
  via a shared `_guardProjectPaths` helper, preserving the
  within-root-before-existence ordering. Covered by BB-RUN-63..66.

## 2.6.31

### Fixed

- **Nested tool output is no longer swallowed in the traversal path** — when a
  host tool (e.g. `buildkit`) ran a wired nested tool during project traversal,
  `NestedToolExecutor` captured the child's stdout/stderr and only echoed it
  when `--verbose` was set, the child failed, or the output happened to contain
  the words "error"/"warn"/"fail". On a quiet, successful run this hid all
  legitimate output: a flag like `--show-cache-status` ran correctly but its
  report never reached the terminal, making the option look like a no-op, and
  per-file progress was invisible. The executor now streams the child's
  stdout/stderr live (via `runBinaryStreaming`/`inheritStdio`), matching how the
  pipeline path already runs nested tools (`ToolPipelineExecutor._runToolCommand`).
  Failure is determined by the child's exit code.

## 2.6.30

### Fixed

- **Non-existent `--project` path now fails loudly instead of exiting 0** —
  passing a non-glob `--project` *path* that does not exist (e.g.
  `--project _build/nonexistent`) previously scanned, matched nothing, and
  exited `0` with no output, masking the typo (the bug #19 regression that
  `dependencies_test`'s DEP_ERR01 guards). `ToolRunner` now validates such
  path patterns up front via the new `validateProjectPathsExist` and returns a
  failure with a clear `project path not found: …` message. Project ids,
  names, and glob path patterns are unaffected — they may legitimately match
  zero projects and are never existence-checked.

## 2.6.29

### Fixed

- **Pipeline rejects unknown/unprefixed commands with a clear stdout error** — a
  pipeline command that is neither a built-in tool command (prefixed with the
  tool name) nor an explicitly allowed `shell` / `shell-scan` / `stdin` /
  `print` command — e.g. a bare `rm -rf /` — must never reach process
  execution. The pipeline parser already rejected such commands, but the
  `FormatException` it threw escaped to **stderr** as an unhandled error
  (exit 255) and its message read "Unsupported pipeline command prefix",
  surfacing nothing actionable on stdout. The message is now reworded to
  "Unknown command \"…\" … Only built-in tool commands … are allowed", and
  `ToolRunner` catches the `FormatException` at the pipeline-invocation site,
  writing the rejection to stdout (`Error: …`) and returning a failure result
  (non-zero exit) instead of crashing. Covered by new `pipeline_config`
  (`BB-PLC-11`) and `tool_runner` (`BB-RUN-58`) tests; satisfies
  `tom_build_kit`'s `SEC_CMD01`.

## 2.6.28

### Fixed

- **`--scan` now rejects paths outside the workspace** — `--scan` names the real
  directory the traversal walks (`Directory(scan)`: a relative value resolves
  against the current directory, an absolute value is used as-is), so either an
  absolute path like `/tmp` or a relative `../../sibling` could escape the
  workspace. Previously such a scan returned an empty result and exit `0`,
  masking that the tool was pointed at a location it must not walk. The new
  `validateScanPathWithinRoot` helper (`workspace_utils.dart`) canonicalises both
  the scan path and the execution root (resolving symlinks so a symlinked temp
  root is not confused with its real target) and requires the scan to equal or be
  contained within the root; both `ToolRunner` project-traversal paths now reject
  an out-of-root scan before scanning with a clear `Error: scan path is outside
  the workspace ...` message and a non-zero exit. Covered by new `workspace_utils`
  regression tests.

## 2.6.27

### Fixed

- **`--project` now rejects absolute paths outside the workspace** — a `--project`
  pattern is a filter resolved against the scanned tree (project id, project name,
  folder-name glob, or relative path), all of which are contained by construction.
  The one way to escape the workspace is an **absolute path** that resolves outside
  the execution root. Previously such a path silently matched nothing and the tool
  exited `0`, looking like a successful no-op while actually being pointed at a path
  it must never operate on. The new `validateProjectPathsWithinRoot` helper
  (`workspace_utils.dart`) checks every absolute `--project` pattern against the
  resolved execution/workspace root; the `ToolRunner` traversal paths now reject an
  out-of-root path before any scanning with a clear `Error: project path is outside
  the workspace ...` message and a non-zero exit. Covered by new `workspace_utils`
  regression tests.

## 2.6.26

### Fixed

- **`ztmp` scratch directory is no longer scanned for projects** — `ztmp` is the workspace's canonical gitignored scratch dir, but the recursive project scanner descended into it and discovered stale full-project copies (e.g. `ztmp/d4gen199`, `ztmp/refgen112`) left over from debugging. Those carry outdated dependency constraints, so `:pubupdate` and the build pipeline picked up versions far behind the published ones. `ztmp` is now in `kAlwaysSkipDirectories` and the repository-id lookup ignore set, and the **non-recursive** scan branch now honors `kAlwaysSkipDirectories` too (it previously only skipped dot- and `zom_`-prefixed dirs). Covered by a new `workspace_utils` regression test.

## 2.6.25

### Added

- **Shared end-of-run summary block for every `tom_build_base` tool** — `ToolResult.renderRunSummary()` produces a single, consistent errors/skips report so outcomes are easy to read after a long run, instead of each tool re-implementing its own footer. The block lists a `=== Skipped ===` section (deliberately skipped items) above either a `=== Errors ===` section naming every failed item with an `N error(s) in M project(s).` tally, or the clean `Done. No errors.` footer when nothing failed. It returns an empty string when no items were processed (e.g. `--version`/`--help`/single-shot commands), so callers can print it unconditionally without a spurious footer. New `ItemResult.skipped(...)` constructor + `ItemResult.skipped` flag distinguish a configured/conditional skip (a non-failing success that never affects the exit code) from real work; the runner preserves the flag when tagging results. Covered by regression tests `SUMM01`–`SUMM13`.

## 2.6.24

### Fixed

- **Non-ASCII tool/subprocess output now renders correctly on Windows** — added a UTF-8 console + process-output guard (`console_encoding.dart`). `ProcessRunner.run`/`runShell` and the shell executor now capture raw bytes and decode them as UTF-8 (`decodeProcessOutput`, tolerating malformed sequences) instead of relying on the host's ANSI code page, which previously turned UTF-8 diagnostics such as `dart compile`'s "für" into double-mojibake ("fÃƒÂ¼r"). `ToolRunner.run` calls `enableUtf8Console()` at startup, which switches the Windows console code pages to UTF-8 (`CP_UTF8`, the `chcp 65001` equivalent via kernel32) and routes the `stdout`/`stderr` sinks through UTF-8. No-op on non-Windows hosts and idempotent. Streaming decoders now tolerate malformed bytes so a single bad chunk no longer aborts the rest of the stream. Covered by regression tests `ENC01`–`ENC09`.

## 2.6.23

### Fixed

- **Per-command value options no longer shadowed by colliding global flags** — a command that declares its own value-bearing option (e.g. versioner's `--version <v>` override) now receives the value when invoked as `buildkit :versioner --version 9.9.9`, instead of the token being captured by the global `--version` print-version flag. A bare `--version` (no value) still prints the tool version. Covered by regression tests `BB-CLI-93`–`BB-CLI-95`.

## 2.6.22

### Fixed

- **`--help` no longer advertises macros/defines/pipelines in an ineligible context** — the runtime macro / persistent define help appendix is now gated on `_isMacroDefineFeatureEligible()` (a `<tool>_master.yaml` exists in the workspace), matching the gating already applied to the commands themselves. Previously the appendix was shown whenever the tool was `multiCommand`, even with no master yaml present, misleading users about unavailable features.
- **`--project <absolute path>` now matches the target project on every platform** — `FilterPipeline` project matching previously only recognised path patterns containing `/`, and never compared a folder's full path. A `--project` argument given as an absolute filesystem path (e.g. `versioner --project C:\repo\_build` on Windows, or any absolute POSIX path) therefore matched zero projects. Project/path matching is now separator-agnostic (`/` and `\` are equivalent) and absolute paths are compared against each folder's own path (case-insensitively on Windows). Covered by regression tests `BB-FLT-41`–`BB-FLT-44`.

## 2.6.21

### Fixed

- **Nested mode executes per-project logic** — `_runNestedMode` and `_runNestedCommand` now create a `CommandContext` from CWD and call `execute()` instead of the no-op `executeWithoutTraversal()`. This fixes nested tools (e.g., d4rtgen called via buildkit) silently doing nothing.

## 2.6.20

### Fixed

- **Cross-platform path display** — `CommandContext.relativePath` now always uses forward slashes, preventing backslash stripping by console markdown on Windows.

## 2.6.19

### Added

- **`ItemResult.commandName`** — Optional field to track which command produced each result (e.g., `'runner'`, `'compiler'`). Populated by `ToolRunner` when executing command chains.

### Changed

- **Compact tool output** — `ToolRunner` now always prints one-line-per-command status (`  -> :cmd message`) instead of verbose multi-line output. Project headers (`>>> path`) are always shown.
- **Nested tool output buffering** — `NestedToolExecutor` buffers subprocess stdout/stderr and only displays on error, signal words, or `--verbose` mode.

## 2.6.18

### Changed

- **Project-name alias matching** — Project resolution and filtering now treat `pubspec.yaml` `name` as a first-class project-name alias alongside `tom_project.yaml` and `buildkit.yaml` metadata.
- **Workspace boundary markers** — `tom_workspace.yaml` is no longer used as a workspace boundary marker; workspace boundary detection now relies on `buildkit_master.yaml`.

## 2.6.14

### Added

- **`print` pipeline prefix** — Added a dedicated `print <message>` command prefix for pipelines to emit resolved messages without shell invocation.
- **Mklink executor API** — Added dcli-backed symlink execution support (`MkLinkExecutor`) for reusable cross-platform link creation in tool implementations.

### Changed

- **Pipeline help examples** — Updated built-in help topic examples to use `print` for message output instead of shell-based echo commands.

## 2.6.13

### Changed

- **Repository ID lookup source** — `RepositoryIdLookup` now reads `repository_id` and `name` from `tom_repository.yaml` files in the workspace instead of using a hardcoded ID map.
- **Module filter resolution** — `--modules` and `--skip-modules` resolution now uses workspace metadata (`tom_repository.yaml`) via execution-root-aware lookup.

### Added

- **Lookup cache controls** — Added `RepositoryIdLookup.clearCache()` for test/runtime cache invalidation when repository metadata changes.

## 2.6.12

### Fixed

- **Bootstrap environment bypass** — `TOM_BOOTSTRAP_ALLOW_MISSING_SETUP=1` environment variable now correctly bypasses `required-environment` checks in `ToolRunner.run()`. This allows `bootstrap_binaries.sh` to run the versioner step even when optional binaries (astgen, reflector) are not yet installed. The `:doctor` command always runs full checks regardless of the bypass.

## 2.6.6

### Fixed

- **FolderScanner recursive semantics** — The `recursive` flag now correctly controls recursion **inside project directories** only. Non-project (container) directories are always traversed to find projects, which is the fundamental purpose of scanning. Previously, `recursive: false` (the default) stopped all descent after the scan root, meaning nested projects inside container directories were never found.

### Documentation

- Corrected `FolderScanner.scan()` doc to explain that `recursive` controls descent into project folders (containing `pubspec.yaml`), not overall directory traversal.
- Corrected `CliArgs.toProjectTraversalInfo()` doc: hardcoded default is `recursive: false`, and clarified that non-project directories are always traversed regardless of the flag.

## 2.6.5

### Fixed

- **Pipeline nested workspace discovery** — `_discoverNestedWorkspaces` now skips `test/`, `build/`, `node_modules/`, and `example/` directories when searching for nested workspaces to delegate pipeline execution to. Previously, `buildkit_master.yaml` files inside test fixtures (e.g., `test/fixtures/`) were incorrectly treated as real nested workspaces, causing pipeline delegation failures.

## 2.6.4

### Fixed

- **Nature parsing in tool wiring** — `ToolDefinitionSerializer.fromYamlMap()` now correctly parses `works_with_natures` and `required_natures` fields from `--dump-definitions` YAML output. Previously, these fields were only serialized (via `toYaml()`) but not parsed when deserializing, causing nested tool commands to fail with "has no nature configuration" errors during wiring.

### Added

- **Private helpers** — Added `_stringToType()` to convert nature type names ("DartProjectFolder", "FsFolder", etc.) back to `Type` objects, and `_parseNaturesList()` to parse YAML lists to `Set<Type>`.

## 2.6.3

- **`versionString` support** — Added optional `versionString` field to `ToolDefinition` for custom version display format. When set, `--version` will output this string instead of the default "name version" format.

## 2.6.2

- **Build fixes** — Minor fixes for tool compilation.

## 2.6.1

- **Fix:** Added missing `WorkspaceScanner` export to both barrel files (`tom_build_base.dart` and `tom_build_base_v2.dart`)

## 2.6.0

### Breaking Changes

- **Removed V1 API** — The following V1 classes, functions, and files have been removed:
  - `ConfigLoader`, `LoadedConfig`, `PlaceholderDefinition`, `PlaceholderContext`, `resolvePlaceholders()` (config_loader.dart)
  - `ConfigMerger` (config_merger.dart)
  - `ProcessingResult` — V1 version removed (processing_result.dart); V2 `ToolResult`/`ItemResult` remains
  - `isPathContained()`, `validatePathContainment()` (path_utils.dart)
  - `isBuildYamlBuilderDefinition()`, `hasBuildYamlConsumerConfig()`, `isBuildYamlBuilderEnabled()`, `getBuildYamlBuilderOptions()` (build_yaml_utils.dart)
  - `showVersions()`, `ShowVersionsResult`, `ShowVersionsOptions`, `readPubspecVersion()` (show_versions.dart)
  - `bin/show_versions.dart` CLI tool
- **Unified barrel** — `tom_build_base.dart` now exports the full API (framework + utility classes). The `tom_build_base_v2.dart` barrel is still available for backwards compatibility.
- **Retained utility classes** — `TomBuildConfig`, `hasTomBuildConfig()`, `ProcessRunner`, `ToolLogger`, `yamlToMap()`, `yamlListToList()`, `toStringList()` remain available.

## 2.5.16

### Added

- **Comprehensive help topics** — Added `definesHelpTopic`, `macrosHelpTopic`, `pipelinesHelpTopic`, `wiringHelpTopic` as built-in help topics. All multiCommand tools automatically expose these via `help defines`, `help macros`, `help pipelines`, `help wiring`.
- **`--modes` in global help** — Added `--modes` to `commonOptions` so it appears in `--help` output for all tools.
- **`{TOOL}` placeholder in help topics** — `generateTopicHelp()` now replaces `{TOOL}` with the tool name in help topic content.
- **Placeholder resolution in pipeline shell/stdin** — `shell` and `stdin` pipeline commands now resolve standard `%{...}` placeholders (root, current-os, current-platform, etc.) before execution. `shell-scan` already had full placeholder support.

### Changed

- **Pipeline help** — Converted hardcoded pipeline help from `tool_runner.dart` to a proper `HelpTopic`. Updated documentation to use correct `%{...}` placeholder syntax.
- **Macro/define help routing** — `help defines` and `help macros` now show comprehensive topic documentation instead of brief command summaries.
- **Help appendix** — Global help appendix now lists all 5 help topics (defines, macros, pipelines, placeholders, wiring).

## 2.5.15

### Added

- **`cli_arg_parser.dart`** — Added `--modes` as a recognized global CLI flag. Accepts comma-separated mode names (e.g., `--modes DEV` or `--modes DEV,CI`). Parsed into `CliArgs.modes` as `List<String>`.
- **`tool_runner.dart`** — `@[name]` define placeholders are now resolved per-folder during traversal. Defines are loaded from `{tool}_master.yaml` (default + mode-specific sections based on `--modes`), then merged with per-project `buildkit.yaml` defines (project overrides master). Resolution happens after `%{name}` placeholder resolution and before executor execution.
- **`tool_runner.dart`** — Per-project `buildkit.yaml` define loading: project-level `buildkit.yaml` files can override master defines via `defines:` or `{tool}: defines:` sections, including mode-specific `{MODE}-defines:` sections.

## 2.5.14

### Fixed

- **`macro_expansion.dart`** — Missing positional arguments (`$1`–`$9`) in macros are now treated as empty strings instead of throwing `MacroExpansionException`. This allows macros like `@vc` to be invoked without arguments even when the macro value contains placeholders.

## 2.5.13

### Improved

- **`tool_runner.dart`** — When `:macro`, `:define`, `:defines`, `:undefine`, `:unmacro`, or `:macros` commands are used but `{tool}_master.yaml` cannot be found, a clear error message is shown explaining which file is missing and the detected workspace root. Previously these commands silently fell through to "Unknown command".
- **`tool_runner.dart`** — Help text for macro/define/pipeline commands is now shown even when the master yaml is missing, so users can understand how to set things up.

## 2.5.12

### Fixed

- **`tool_runner.dart`** — Macro expansion (`@macroName`) now actually works. The `expandMacros()` function from `macro_expansion.dart` was never called during `run()`, so `@macro` invocations were passed through unparsed. Expansion now happens before arg parsing, after loading persisted macros.

## 2.5.11

### Added

- **`tool_definition.dart`** — Added `versionString` property to `ToolDefinition` for custom `--version` output. When provided, this string (typically from versioner-generated code) is shown instead of the default "name vX.X.X" format.
- **`tool_runner.dart`** — `:define` and `:undefine` commands now support `-m MODE` or `--mode MODE` flag for mode-specific defines (e.g., `buildkit :define -m DEV DEBUG=true`).
- **`tool_runner.dart`** — `:defines` command now lists all defines including mode-specific ones (e.g., `DEV-defines:`, `CI-defines:`).
- **`tool_runner.dart`** — Macros now stored in `{tool}_master.yaml` under `macros:` section instead of separate `{tool}_macros.yaml` file.
- **`tool_runner.dart`** — Defines stored under `{tool}:` section in master.yaml with structure: `{tool}: defines:` for default and `{tool}: {MODE}-defines:` for mode-specific.

### Changed

- **`cli_arg_parser.dart`** — Extended special-case greedy argument handling to include `:undefine` command (all args after `:undefine` are treated as positional to allow `-m MODE name` syntax).

## 2.5.10

### Fixed

- **`tool_runner.dart`** — Runtime macros (`:macro`, `:macros`, `:unmacro`) now persist to `{workspace_root}/{tool_name}_macros.yaml`. Previously, macros defined in one `buildkit` invocation were lost in the next invocation because they were stored only in an in-memory map. The file is written on every `add`/`remove` and loaded lazily on the first macro operation of each invocation; it is deleted automatically when the last macro is removed.

## 2.5.9

### Fixed

- **`cli_arg_parser.dart`** — `:command` tokens appearing after a `:macro` or `:define` command are now treated as positional arguments (part of the macro value) rather than being dispatched as separate commands. Previously, `buildkit :macro vc=:v $1 :comp $2` would execute `:comp` immediately and store only `:v` as the macro value. Now the full token sequence is captured as the value.

## 2.5.6

### Fixed

- **`cli_arg_parser.dart`** — Global navigation/feature flags (`--dry-run`, `--verbose`, `-n`, `-v`, `--force`, `--list`, etc.) now route to global state regardless of whether they appear before or after a command name. Previously `buildkit :compiler --dry-run` was silently ignored; now it works identically to `buildkit --dry-run :compiler`.

## 2.5.5

### Added

- **`tool_runner.dart`** — Added required-environment validation support from `<tool>_master.yaml` (including `buildkit_master.yaml` fallback for `buildkit`), with checks for environment variables, folders, binaries, and caret-version constraints.
- **`tool_runner.dart`** — Added doctor-mode execution flow for tools: doctor requests now print requirement warnings/errors and return success/failure based on hard requirement violations.

### Fixed

- **`tool_runner.dart`** — Normalized doctor token detection so both `doctor` and `:doctor` forms are recognized consistently in positional and command argument paths.

## 2.5.4

### Fixed

- **`cli_arg_parser.dart`** — Fixed short option abbreviation collision when multiple commands share the same abbreviation (e.g. `-c` used by both `runner` and `execute`). `_shortToLong` now prioritizes the current command's options before falling through to all commands.

## 2.5.3

### Changed

- **`execute_placeholder.dart`** — Migrated placeholder syntax from `${...}` to `%{...}` to avoid shell variable expansion (`${}`) and YAML comment stripping (`#{}` after whitespace). All regex patterns, error messages, and help text updated.
- **`builtin_help_topics.dart`** — Updated all placeholder documentation to use `%{...}` syntax.

## 2.5.2

### Changed

- **`repository_id_lookup.dart`** — Removed `CRPT` (tom_module_crypto) and `COM` (tom_module_communication) repository IDs after module consolidation into tom_module_basics.

## 2.5.1

### Fixed

- **`builtin_help_topics.dart`** — Escaped `*` in placeholders help topic context reference table to prevent console_markdown from consuming it as italic markup.

## 2.5.0

### Added

- **`console_markdown_zone.dart`** — Central console_markdown integration via Dart zones. Provides `runWithConsoleMarkdown()` (async) and `runWithConsoleMarkdownSync()` to wrap CLI tool execution in a zone that renders markdown syntax (`**bold**`, `<cyan>text</cyan>`, etc.) to ANSI escape codes.
- **`console_markdown_zone.dart`** — `ConsoleMarkdownSink` wrapper class for `StringSink` that applies `.toConsole()` rendering to all writes, enabling markdown rendering on `stdout`/`stderr` sinks.
- **`console_markdown_zone.dart`** — `isConsoleMarkdownActive` getter and `kConsoleMarkdownZoneKey` zone key for double-processing detection. Prevents nested zones (e.g. when tom_d4rt_dcli already wraps output).
- **`tool_runner.dart`** — `ToolRunner` now automatically wraps its output sink with `ConsoleMarkdownSink` when running inside a console_markdown zone, so all `output.writeln()` calls render markdown.
- **`pubspec.yaml`** — Added `console_markdown: ^0.0.3` dependency.

## 2.4.0

### Added

- **`execute_placeholder.dart`** — `resolveCommand()` now accepts `skipUnknown` parameter. When true, unrecognized placeholders are left as-is instead of throwing, enabling multi-phase resolution (e.g., general placeholders first, then compiler-specific ones).
- **`execute_placeholder.dart`** — Added `ExecutePlaceholderContext.fromCommandContext()` factory for easy creation from traversal's `CommandContext`.
- **`cli_arg_parser.dart`** — Added `CliArgs.withResolvedStrings()` method to create a copy with placeholders resolved in positional args, extra options, and per-command options.
- **`tool_runner.dart`** — ToolRunner now automatically resolves general placeholders (`${folder}`, `${dart.name}`, etc.) in all CLI args per folder during traversal, giving universal placeholder support to all commands.
- **`tom_build_base_v2.dart`** — Exported `execute_placeholder.dart` from the v2 barrel.

## 2.3.0

### Added

- **`help_topic.dart`** — New `HelpTopic` class for named help sections (topic content, summary, name).
- **`builtin_help_topics.dart`** — Built-in `placeholdersHelpTopic` with comprehensive placeholder documentation.
- **`tool_definition.dart`** — Added `helpTopics` field and `findHelpTopic()` method.
- **`help_generator.dart`** — Added `generateTopicHelp()` and "Help Topics" section in tool help.
- **`special_commands.dart`** — Help topic lookup in `handleSpecialCommands()` and `generatePlainToolHelp()`.
- **`tool_runner.dart`** — Help topic lookup before "Unknown command" error.

## 2.2.0

### Added

- **`filter_pipeline.dart`** — Added `_matchesRelativePath()` and `_isPathPattern()` for path-based pattern matching in `--exclude-projects` and `--project` filters. Patterns containing `/` (e.g., `core/tom_core_kernel`) are now matched against relative paths using glob matching, enabling directory-scoped project exclusion.
- **`filter_pipeline.dart`** — Updated `matchesProjectPattern()` to accept optional `executionRoot` parameter for path-based matching.
- **`tool_runner.dart`** — `ToolRunner.run()` now handles bare `version` as a positional arg (in addition to `--version`/`-V`), consistent with `handleSpecialCommands`.
- **`help_generator.dart`** — `generateCommandHelp()` now includes a "Common Options" section showing `--help`, `--verbose`, and `--dry-run`.
- **`tool_runner.dart`** — Per-command `matchesProjectPattern()` calls now pass `executionRoot` for path-based pattern support.

## 2.1.0

### Added

- **`navigation_bridge.dart`** — Re-introduces `WorkspaceNavigationArgs`, `addNavigationOptions()`, `preprocessRootFlag()`, `parseNavigationArgs()`, `resolveExecutionRoot()`, `isVersionCommand()`, `isHelpCommand()` as v2-clean code (dart:io only, no DCli dependency). These bridge the `package:args` ArgParser to the v2 traversal system for tools that use `ArgParser` for global option parsing.
- Exported from both `tom_build_base.dart` and `tom_build_base_v2.dart` barrels.

## 2.0.0

### Breaking Changes — V1 Navigation System Removed

Deleted the entire v1 project navigation/discovery system:

- **`workspace_mode.dart`** — `WorkspaceNavigationArgs`, `ExecutionMode`, `addNavigationOptions()`, `parseNavigationArgs()`, `preprocessRootFlag()`, `resolveExecutionRoot()`, and related helpers are removed.
- **`project_discovery.dart`** — `ProjectDiscovery` class (including `scanForProjects()`, `resolveProjectPatterns()`, `hasSkipFile()`, `getSkipFileName()`, `applyModulesFilter()`, `findGitRepositories()`, `filterByModules()`, `resolveModulePaths()`) is removed.
- **`project_navigator.dart`** — `ProjectNavigator`, `NavigationConfig`, `NavigationResult`, `NavigationDefaults` are removed.
- **`project_scanner.dart`** — `ProjectScanner` class is removed.

### Migration

All these APIs have v2 replacements in `tom_build_base_v2.dart`:

| Removed V1 API | V2 Replacement |
|----------------|----------------|
| `WorkspaceNavigationArgs` | `CliArgs` (from `cli_arg_parser.dart`) |
| `addNavigationOptions` / `parseNavigationArgs` | `CliArgParser` + `OptionDefinition` |
| `ProjectDiscovery.scanForProjects` | `FolderScanner` + `BuildBase.traverse` |
| `ProjectNavigator.navigate` | `BuildBase.traverse` |
| `ProjectScanner` | `FolderScanner` |
| `ProjectDiscovery.hasSkipFile` | `FolderScanner` skip logic |
| `ProjectDiscovery.applyModulesFilter` | `FilterPipeline` module filtering |

### Preserved APIs

- **`findWorkspaceRoot()`** — Moved to `workspace_utils.dart` (exported from both barrels). Same API, now uses `dart:io` instead of DCli.
- **`kBuildkitMasterYaml`**, **`kTomWorkspaceYaml`**, **`kTomCodeWorkspace`**, **`kBuildkitSkipYaml`** — Constants moved to `workspace_utils.dart`.
- **`isWorkspaceBoundary()`** — Moved to `workspace_utils.dart`.
- All shared utility files (`build_config.dart`, `config_loader.dart`, `config_merger.dart`, `tool_logging.dart`, `path_utils.dart`, `processing_result.dart`, `yaml_utils.dart`, `build_yaml_utils.dart`, `show_versions.dart`) are unchanged.

### Internal

- `show_versions.dart` — Migrated from `ProjectDiscovery`/`ProjectScanner` to inline directory scanning with `dart:io` and `glob`.
- Removed v1-specific tests (10 tests removed; 547 remaining tests pass).

## 1.15.0

### Breaking Changes

- **Renamed `--all` / `-a` to `--no-skip`** — The global CLI option that ignores skip markers (`tom_skip.yaml`, `*_skip.yaml`) has been renamed from `--all` / `-a` to `--no-skip` (no abbreviation). This resolves conflicts with per-command `-a/--all` options in buildkit tools (dependencies, publisher, gitcommit, gitbranch).

### Features

- **`--no-skip` flag in v1 system** — Added `noSkip` field to `WorkspaceNavigationArgs`, wired through `addNavigationOptions()`, `parseNavigationArgs()`, `ProjectDiscovery.scanForProjects()`, and `ProjectNavigator`. Both v1 (buildkit ArgParser) and v2 (CliArgs) systems now support `--no-skip`.

- **`--no-skip` in `projectTraversalOptions`** — Added to the standard v2 option definitions for consistent help output.

## 1.14.0

### Features

- **`AnchorWalker` class** — New utility for walking up the directory tree to find workspace/repository root "anchor" directories. Anchors are identified by `.git` (directory or file), `tom_workspace.yaml`, or `buildkit_master.yaml` markers. Enables reusable upward-search logic for tools like `goto`.

## 1.13.0

### Features

- **`--all` / `-a` flag** — New CLI option to traverse into folders that would normally be skipped (subworkspaces, `tom_skip.yaml`, `<tool>_skip.yaml`). Skip messages still print but traversal continues. *(Renamed to `--no-skip` in 1.15.0)*

- **Skip messages to stderr** — FolderScanner now always prints skip messages to stderr when encountering workspace boundaries or skip marker files: "Skipping subworkspace: \<folder\>", "Skipping - tom_skip.yaml found: \<folder\>", "Skipping - \<tool\>_skip.yaml found: \<folder\>".

### Bug Fixes

- **`allGlobalOptions` dedup precedence** — Fixed option deduplication to use first-wins (`putIfAbsent`) instead of last-wins. User-defined `globalOptions` now correctly take precedence over `commonOptions` defaults.

### Code Quality

- Fixed `unnecessary_brace_in_string_interps` lint issues in `completion_generator.dart`.
- Fixed `curly_braces_in_flow_control_structures` lint issues in `nature_detector.dart`.

## 1.12.0

### Features

- **`BuildkitFolder.projectName`** — BuildkitFolder nature now reads the `name` field from `buildkit.yaml`, enabling project name matching for buildkit-configured projects.

- **`--project` ID and name matching** — FilterPipeline now matches `--project` values against project IDs and names from both `tom_project.yaml` and `buildkit.yaml`:
  - `TomBuildFolder`: matches `project_id` and `short-id` fields
  - `BuildkitFolder`: matches `id` and `name` fields
  - Case-insensitive matching

- **`handleSpecialCommands()`** — New utility function for tools to handle `help` and `version` commands consistently without custom parsing.

- **`BuildOrderComputer`** — Topological sort (Kahn's algorithm) moved from tom_build_kit to tom_build_base. Available for any tool that needs dependency-ordered traversal.

### Breaking Changes

- **Nature filtering is now mandatory** — `BuildBase.traverse()` throws `ArgumentError` if neither `requiredNatures` nor `worksWithNatures` is configured. Previously, `null` `requiredNatures` silently visited all folders. Tools that want all folders must now set `requiredNatures: {FsFolder}` or `worksWithNatures: {FsFolder}` explicitly.

- **ToolRunner validates nature config** — `ToolRunner._runWithTraversal()` returns `ToolResult.failure` with an error message before traversal starts if no nature configuration is present on the command.

### Bug Fixes

- **Nature detection before filter application** — Fixed `BuildBase.traverse()` to detect folder natures before applying project filters. Previously, `applyProjectFilters()` was called before `detectNatures()`, causing ID/name-based `--project` matching to always fail.

- **`tom_project.yaml` field name** — `NatureDetector._createTomProjectNature()` now reads `project_id` (underscore) in addition to `short-id` (hyphen) from `tom_project.yaml`.

### Internal

- **ToolLogger / ProcessRunner** — Central logging infrastructure with `--verbose` support for consistent tool output.

---

## 1.11.0

### Features

- **Command prefix matching** — `findCommand()` now supports unambiguous command prefixes.
  - `:vers` matches `:versioner` if no other command starts with "vers"
  - `:co` is ambiguous if both `:compiler` and `:config` exist, returns null
  - Exact matches (name or alias) always take priority over prefix matches
  - `findCommandsWithPrefix()` returns all commands matching a prefix (for error messages)

- **Improved error messages** — When a prefix is ambiguous, tool shows all matching commands.

---

## 1.10.0

### Features

- **ExecutePlaceholderResolver** — New placeholder resolution system for execute commands.
  - Path placeholders: `${root}`, `${folder}`, `${folder.name}`, `${folder.relative}`
  - Platform placeholders: `${current-os}`, `${current-arch}`, `${current-platform}`
  - Nature existence (boolean): `${dart.exists}`, `${flutter.exists}`, `${git.exists}`, etc.
  - Nature attributes: `${dart.name}`, `${dart.version}`, `${git.branch}`, etc.
  - Ternary syntax: `${condition?(true-value):(false-value)}` for boolean placeholders
  - `checkCondition()` for filtering based on boolean placeholders

- **ExecutePlaceholderContext** — Context class holding folder, root, and natures for resolution.

- **UnresolvedPlaceholderException** — Exception thrown when placeholder cannot be resolved.

---

## 1.9.0

### Breaking Changes

- **Default traversal behavior changed**:
  - Default is now `--scan . -R --not-recursive` (workspace mode, single directory)
  - Previously defaulted to current directory without workspace root detection
  - Use `-r` flag to explicitly enable recursive traversal

### Features

- **Traversal cascade**: CLI options > buildkit_master.yaml navigation > hardcoded defaults
- **Explicit CLI tracking**: `scanExplicitlySet` and `recursiveExplicitlySet` fields in CliArgs
- **TraversalDefaults class**: Loads navigation defaults from buildkit_master.yaml
- **Git mode validation**: `toGitTraversalInfo()` now returns null if git mode not specified
- **WorkspaceScanner**: Unified scanning API with FolderScanner + NatureDetector
- **Top repository navigation** (`-T, --top-repo`): Traverse up to find topmost git repo
- **DartProjectFolder.isPublishable**: Check if package can be published to pub.dev

### Classes Modified

- `CliArgs` — Added `scanExplicitlySet`, `recursiveExplicitlySet` fields
- `TraversalDefaults` — New class for config defaults with `fromMap()` factory
- `ToolRunner._runWithTraversal()` — Loads defaults, applies cascade, validates git mode
- `_ParseState` — Tracks explicit CLI options

---

## 1.11.0

### Features

- **WorkspaceScanner** — Unified scanning API combining FolderScanner + NatureDetector.
  - `scan()` returns `ScanResults` with type-safe `byNature<T>()` filtering.
  - `findGitRepos()`, `findDartProjects()`, `findPublishable()` — Nature-based queries.
  - `findGitRepoPaths()`, `findDartProjectPaths()`, `findPublishablePaths()` — Path convenience methods.
  - `FolderContext` provides folder + natures together with `hasNature<T>()`, `getNature<T>()`.

- **DartProjectFolder.isPublishable** — New getter to check if package can be published to pub.dev.

### Exports

- V2 traversal API now exported from main barrel: `WorkspaceScanner`, `GitFolder`, `DartProjectFolder`, etc.

---

## 1.10.0

### Features

- **Top repository navigation** (`-T, --top-repo`) — New git traversal option.
  - Traverses UP the directory tree to find the topmost (outermost) git repository.
  - Uses that repository as the root for subsequent traversal.
  - Can be combined with `-i` (inner-first-git) or `-o` (outer-first-git).
  - Added `GitRepoFinder.findTopRepo()` method for upward git repo discovery.
  - Example: `buildkit -T -i :compile` — finds top repo, then processes inner repos first.

### Classes Modified

- `CliArgs` — Added `topRepo` field.
- `WorkspaceNavigationArgs` — Added `topRepo` field and updated execution mode detection.
- `GitRepoFinder` — Added `findTopRepo(String startPath)` method.
- `ProjectNavigator` — Integrated `topRepo` option in navigation.
- `CliArgParser` — Added parsing for `-T` and `--top-repo` flags.
- `OptionDefinition` — Added `top-repo` to `gitTraversalOptions`.

---

## 1.9.0

### Features

- **DCli integration** — Refactored file operations to use DCli library for improved code readability.
  - `File(path).existsSync()` → `exists(path)`
  - `File(path).readAsStringSync()` → `read(path).toParagraph()`
  - `Directory(path).listSync()` → `find('*', types: [Find.directory])`
  - Improved directory filtering with DCli's `find()` type filtering.

### Dependencies

- Added `dcli` package as dependency for file and directory operations.

### Files Refactored

- `build_config.dart` — Config file loading
- `build_yaml_utils.dart` — Build.yaml utilities
- `config_loader.dart` — Configuration loading with placeholders
- `project_discovery.dart` — Project discovery and scanning
- `project_scanner.dart` — Project validation and scanning
- `show_versions.dart` — Version display functionality
- `workspace_mode.dart` — Workspace navigation utilities

---

## 1.8.0

### Features

- **`ConfigLoader` class** — New unified configuration loader with mode processing and placeholder resolution.
  - Loads `{basename}_master.yaml` (workspace) and `{basename}.yaml` (project) configuration files.
  - Processes mode-prefixed keys (e.g., `DEV-target`, `CI-enabled`) with merging behavior.
  - Resolves `@[...]` define placeholders from the `defines:` section.
  - Resolves `@{...}` tool placeholders (project-path, project-name, workspace-root, etc.).
  - Custom tool placeholders via `PlaceholderDefinition`.

- **Mode system** — Workspace-wide configuration dimensions.
  - `--modes` CLI option to override active modes (e.g., `--modes=DEV,CI`).
  - Mode sources: CLI option (highest) → `tom_workspace.yaml` default.
  - UPPERCASE mode prefixes merge in order, later modes override earlier.

- **Skip file system** — Directory-level skip markers.
  - `tom_skip.yaml` — Skips directory for ALL tools.
  - `{basename}_skip.yaml` — Skips directory for specific tool only.
  - Skip reason readable from YAML `reason:` field.

- **`resolvePlaceholders()` function** — Standalone placeholder resolution utility.
  - Supports `@[...]` defines, `@{...}` tool placeholders.
  - Environment variable resolution with `$VAR` and `$[VAR]` syntax.
  - Recursive resolution (max depth 10).

### API Changes

- New `config_loader.dart` exported from `tom_build_base.dart`.
- `WorkspaceNavigationArgs.modes` — New field for active modes.
- `addNavigationOptions()` registers `--modes` option.
- `parseNavigationArgs()` parses modes as comma-separated, uppercased values.
- `ProjectNavigator` accepts optional `toolBasename` parameter for tool-specific skip files.
- `ProjectDiscovery.hasSkipFile(basename)` — Updated signature with basename parameter.
- `ProjectDiscovery.getSkipFileName(basename)` — Returns tool-specific skip filename.
- `ProjectDiscovery.globalSkipFileName` — Constant for `tom_skip.yaml`.
- **v2 `FolderScanner`** — Now supports tool-specific skip files:
  - Constructor accepts `toolBasename` parameter (defaults to 'buildkit').
  - Checks for `tom_skip.yaml` (global skip for all tools).
  - Checks for `{toolBasename}_skip.yaml` (tool-specific skip).
  - New `skipFilename` getter returns tool-specific skip filename.
  - New `kTomSkipYaml` constant exported.

## 1.7.1

- Changelog update for 1.7.0 features.

## 1.7.0

### Features

- **`ProjectNavigator` class** — New unified project navigation and discovery class that can be shared across CLI tools. Supports all navigation modes: project patterns, directory scanning, git-based traversal.
- **`NavigationConfig` class** — Configurable opt-in/opt-out for navigation features (path exclude, name exclude, modules filter, skip files, master config defaults, build order, git traversal).
- **`NavigationDefaults` class** — Navigation defaults loaded from master config.
- **`NavigationResult` class** — Result container with discovered paths and metadata.
- **Build order sorting** — `ProjectNavigator.sortByBuildOrder()` uses Kahn's algorithm for dependency-based topological sorting.
- **Git repository discovery** — `ProjectNavigator.findGitRepositories()` recursively scans for `.git` folders.
- **Static filter methods** — `filterByPath()`, `filterByName()`, `filterSkippedProjects()`, `hasSkipFile()`.
- **Master config loading** — `loadNavigationDefaults()` and `loadMasterExcludeProjects()` static methods.

### API Changes

- New `project_navigator.dart` exported from `tom_build_base.dart`.
- `kBuildkitSkipYaml` constant now exported from `workspace_mode.dart`.
- `toStringList()` utility added to `yaml_utils.dart`.

## 1.6.0

### Features

- **`--no-recursive` support** — The `--recursive` flag is now negatable. Pass `--no-recursive` to suppress recursion when applied via `buildkit.yaml` or parent directories.
- **`--no-build-order` support** — The `--build-order` flag is now negatable. Pass `--no-build-order` to skip dependency-based sorting.
- **`recursiveExplicitlySet` field** — `WorkspaceNavigationArgs` now tracks whether the `-r, --recursive` flag was explicitly set by the user, allowing downstream tools to distinguish between defaulted and explicit values.

### API Changes

- `WorkspaceNavigationArgs.recursiveExplicitlySet` — New boolean field indicating explicit user setting.
- `parseNavigationArgs()` now uses `wasParsed('recursive')` to detect explicit usage.
- `withDefaults()` and `withProjectModeDefaults()` respect explicit settings and don't override them.

## 1.5.0

### Features

- **`--modules` / `-m` navigation option** — New include filter to limit project discovery to specific git modules (repositories). Comma-separated list of module names (e.g., `--modules tom_module_d4rt,tom_module_basics`). Use "root" or "tom" to reference the main repository.
- **`ProjectDiscovery.findGitRepositories()`** — Static method to discover all git repositories in a workspace.
- **`ProjectDiscovery.resolveModulePaths()`** — Resolve module names to absolute paths.
- **`ProjectDiscovery.filterByModules()`** — Filter project list to only those within specified modules.
- **`ProjectDiscovery.applyModulesFilter()`** — Convenience method combining resolution and filtering.

### API Changes

- `WorkspaceNavigationArgs` now includes a `modules` field (List<String>).
- `addNavigationOptions()` registers the `-m, --modules` option.
- `parseNavigationArgs()` parses the modules option as comma-separated values.
- Help text updated with modules documentation.

## 1.3.2

### Internal

- **Config filename standardization** — Updated all code references from `tom_build.yaml` to `buildkit.yaml`. The `TomBuildConfig.projectFilename` constant was already correct; this release ensures `hasTomBuildConfig()` and `ProjectDiscovery.getProjectRecursiveSetting()` use the constant instead of hardcoded strings.

## 1.3.0

### Features

- **`yamlToMap()` utility** — Public function to recursively convert `YamlMap` to plain `Map<String, dynamic>`. Eliminates private YAML-to-Map conversion duplicated across build tools.
- **`yamlListToList()` utility** — Companion function to recursively convert `YamlList` to plain `List<dynamic>`.

### Internal

- Replaced private `_convertYamlToMap` in `build_config.dart` and `_yamlToMap`/`_yamlListToList` in `build_yaml_utils.dart` with the shared public utilities.

## 1.2.0

### Features

- **`show_versions` CLI tool** — New executable in `bin/show_versions.dart`. Run via `dart run tom_build_base:show_versions [workspace-path]` or install globally with `dart pub global activate tom_build_base`.
- **`showVersions()` library function** — Importable API in `lib/src/show_versions.dart` that discovers projects and reads their pubspec versions. Returns a structured `ShowVersionsResult`.
- **`readPubspecVersion()` helper** — Reusable function to read the `version:` field from any project's `pubspec.yaml`.

### Improvements

- Example file now delegates to the library function instead of reimplementing the logic.

## 1.1.0

### Improvements

- **Comprehensive example** — Rewrote the example as a `show_versions` CLI tool that exercises every library feature: config loading & merging, project scanning & discovery, build.yaml utilities, path validation, and result tracking.
- **Updated user guide** — Complete rewrite of `doc/build_base_user_guide.md` with accurate API signatures, `ConfigMerger` documentation, `ProjectDiscovery` section, and an API quick-reference table.
- **Updated README** — Refreshed usage examples to cover `ConfigMerger`, `ProjectDiscovery`, and all `build.yaml` utility functions.

## 1.0.0

### Features

- **TomBuildConfig**: Unified configuration loading from `tom_build.yaml` files with support for project paths, glob patterns, scan directories, recursive traversal, exclusion patterns, and tool-specific options.
- **ProjectScanner**: Directory traversal with configurable project validation. Finds subprojects, scans directories recursively, supports glob-based project matching, and applies exclusion patterns.
- **ProjectDiscovery**: Advanced project discovery with proper scan vs recursive semantics. Scans until it hits a project boundary; recursive mode also looks inside found projects for nested projects. Supports comma-separated glob patterns with brace group handling.
- **build.yaml utilities**: Detect builder definitions (`isBuildYamlBuilderDefinition`) vs consumer configurations (`hasBuildYamlConsumerConfig`) — so CLI tools can skip packages that define builders and only process consumer packages.
- **Path utilities**: Path containment validation (`isPathContained`) and multi-path validation (`validatePathContainment`) for security.
- **ProcessingResult**: Simple success/failure/file-count tracking for batch operations.
- **Multi-project support**: `--project` option accepts comma-separated lists and glob patterns (e.g., `tom_*`, `xternal/tom_module_*/*`).
- **`--list` flag support**: Tools can list discovered projects without processing.
