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
