# Tom Build Base — Test Coverage

This document lists all testable features across `tom_build_base` and tracks test implementation status.

## Status Legend

- ✅ Test implemented and passing
- ⬜ Test not yet implemented

---

## Overview

| # | Feature Area | Tests | Status | Test File | Details |
|---|-------------|-------|--------|-----------|---------|
| 1 | [Command Prefix Matching](#1-command-prefix-matching) | 24 | 24✅ | `v2/command_prefix_test.dart` | [→](#1-command-prefix-matching) |
| 2 | [Execute Placeholder Resolver](#2-execute-placeholder-resolver) | 55 | 55✅ | `v2/execute_placeholder_test.dart` | [→](#2-execute-placeholder-resolver) |
| 3 | [Macro Expansion](#3-macro-expansion) | 24 | 24✅ | `v2/macro_expansion_test.dart` | [→](#3-macro-expansion) |
| 4 | [CLI Argument Parser](#4-cli-argument-parser) | 96 | 96✅ | `v2/core/cli_arg_parser_test.dart` | [→](#4-cli-argument-parser) |
| 5 | [CommandDefinition](#5-commanddefinition) | 15 | 15✅ | `v2/core/command_definition_test.dart` | [→](#5-commanddefinition) |
| 6 | [Completion Generator](#6-completion-generator) | 30 | 30✅ | `v2/core/completion_generator_test.dart` | [→](#6-completion-generator) |
| 7 | [Features — Modes, Defines, Macros, Pipelines](#7-features--modes-defines-macros-pipelines) | 32 | 32✅ | `v2/core/features_test.dart` | [→](#7-features--modes-defines-macros-pipelines) |
| 8 | [Help Generator](#8-help-generator) | 33 | 33✅ | `v2/core/help_generator_test.dart` | [→](#8-help-generator) |
| 9 | [OptionDefinition](#9-optiondefinition) | 28 | 28✅ | `v2/core/option_definition_test.dart` | [→](#9-optiondefinition) |
| 10 | [ToolDefinition](#10-tooldefinition) | 55 | 55✅ | `v2/core/tool_definition_test.dart` | [→](#10-tooldefinition) |
| 11 | [ToolDefinition Serializer](#11-tooldefinition-serializer) | 19 | 19✅ | `v2/core/tool_definition_serializer_test.dart` | [→](#11-tooldefinition-serializer) |
| 12 | [Wiring Loader](#12-wiring-loader) | 17 | 17✅ | `v2/core/wiring_loader_test.dart` | [→](#12-wiring-loader) |
| 13 | [Pipeline Config](#13-pipeline-config) | 9 | 9✅ | `v2/core/pipeline_config_test.dart` | [→](#13-pipeline-config) |
| 14 | [Pipeline Executor](#14-pipeline-executor) | 4 | 4✅ | `v2/core/pipeline_executor_test.dart` | [→](#14-pipeline-executor) |
| 15 | [ToolRunner](#15-toolrunner) | 42 | 42✅ | `v2/core/tool_runner_test.dart` | [→](#15-toolrunner) |
| 16 | [ToolRunner — Nested Tools](#16-toolrunner--nested-tools) | 20 | 20✅ | `v2/core/tool_runner_nested_test.dart` | [→](#16-toolrunner--nested-tools) |
| 17 | [Nested Tool Executor](#17-nested-tool-executor) | 14 | 14✅ | `v2/core/nested_tool_executor_test.dart` | [→](#17-nested-tool-executor) |
| 18 | [Folder Scanner](#18-folder-scanner) | 17 | 17✅ | `v2/traversal/folder_scanner_test.dart` | [→](#18-folder-scanner) |
| 19 | [Nature Detector](#19-nature-detector) | 38 | 38✅ | `v2/traversal/nature_detector_test.dart` | [→](#19-nature-detector) |
| 20 | [Nature Filter](#20-nature-filter) | 20 | 20✅ | `v2/traversal/nature_filter_test.dart` | [→](#20-nature-filter) |
| 21 | [Filter Pipeline](#21-filter-pipeline) | 40 | 40✅ | `v2/traversal/filter_pipeline_test.dart` | [→](#21-filter-pipeline) |
| 22 | [Build Order](#22-build-order) | 12 | 12✅ | `v2/traversal/build_order_test.dart` | [→](#22-build-order) |
| 23 | [Traversal Info](#23-traversal-info) | 22 | 22✅ | `v2/traversal/traversal_info_test.dart` | [→](#23-traversal-info) |
| 24 | [Build Base Integration](#24-build-base-integration) | 22 | 22✅ | `v2/traversal/build_base_integration_test.dart` | [→](#24-build-base-integration) |
| 25 | [Comprehensive Traversal](#25-comprehensive-traversal) | 51 | 51✅ | `v2/traversal/traversal_comprehensive_test.dart` | [→](#25-comprehensive-traversal) |
| — | **Total** | **718** | **718✅** | | |

---

## 1. Command Prefix Matching

**Test file:** `test/v2/command_prefix_test.dart`

Tests for `ToolDefinition.findCommand` prefix matching logic.

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_CPM_01a–c | Exact name match (3 tests) | ✅ | `versioner`, `compiler`, `cleanup` match exactly. |
| BB_CPM_02a–c | Exact alias match (3 tests) | ✅ | Single-char, multi-char, and `clean` alias match. |
| BB_CPM_03a–d | Unambiguous name prefix (4 tests) | ✅ | `vers`, `version`, `dep`, `depen` resolve uniquely. |
| BB_CPM_04a–d | Ambiguous prefix returns null (4 tests) | ✅ | `co` → null, etc. Ambiguous prefixes handled. |
| BB_CPM_05a–d | `findCommandsWithPrefix` (4 tests) | ✅ | Returns all matching commands for a prefix. |
| BB_CPM_06a–b | Unknown command returns null (2 tests) | ✅ | `xyz`, empty string → null. |
| BB_CPM_07a–d | Exact match priority over prefix (4 tests) | ✅ | `run` matches `run` not `runner`. |

---

## 2. Execute Placeholder Resolver

**Test file:** `test/v2/execute_placeholder_test.dart`

Comprehensive tests for `ExecutePlaceholderResolver` — 55 tests covering all placeholder types.

### Path Placeholders (BB-EPH-01–04)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_EPH_01 | `%{root}` resolves to workspace root | ✅ | Absolute workspace root path. |
| BB_EPH_02 | `%{folder}` resolves to absolute path | ✅ | Current folder absolute path. |
| BB_EPH_03 | `%{folder.name}` resolves to basename | ✅ | Folder basename only. |
| BB_EPH_04 | `%{folder.relative}` resolves to relative path | ✅ | Path relative to workspace root. |

### Platform Placeholders (BB-EPH-05–07)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_EPH_05 | `%{current-os}` | ✅ | Operating system name. |
| BB_EPH_06 | `%{current-arch}` | ✅ | Architecture name. |
| BB_EPH_07 | `%{current-platform}` | ✅ | Combined os-arch platform. |

### Nature Existence (BB-EPH-08–11, 44–53)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_EPH_08–11 | `dart.exists`, `git.exists`, `flutter.exists`, `package.exists` | ✅ | Nature existence checks. |
| BB_EPH_44–53 | `console.exists`, `typescript.exists`, `vscode-extension.exists`, `buildkit.exists`, `tom-project.exists` + negatives | ✅ | All nature types covered. |

### Attribute Placeholders (BB-EPH-12–24)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_EPH_12–16 | Dart: `dart.name`, `dart.version`, `dart.sdk`, `dart.hasBuildRunner`, `dart.hasTests` | ✅ | Dart project attributes. |
| BB_EPH_17–20 | Git: `git.branch`, `git.commit`, `git.remote`, `git.isSubmodule` | ✅ | Git repository attributes. |
| BB_EPH_21–22 | Flutter: `flutter.platforms`, `flutter.isPlugin` | ✅ | Flutter project attributes. |
| BB_EPH_23–24 | VS Code: `vscode-extension.name`, `vscode-extension.publisher` | ✅ | VS Code extension attributes. |

### Convenience Aliases (BB-EPH-39–43)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_EPH_39–43 | `project-name`, `project-version` and variants | ✅ | Shorthand aliases for common properties. |

### Expression & Error Handling (BB-EPH-25–38, 54–55)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_EPH_25 | Unknown placeholder error | ✅ | Throws `UnresolvedPlaceholderException`. |
| BB_EPH_26–29 | Ternary expressions | ✅ | `%{condition?then:else}` evaluation. |
| BB_EPH_30–32 | Full command resolution | ✅ | Multiple placeholders in one command string. |
| BB_EPH_33–35 | Condition checking | ✅ | Condition evaluation for ternary logic. |
| BB_EPH_36, 55 | Placeholder help text | ✅ | Help topic content generation. |
| BB_EPH_37–38 | UnresolvedPlaceholderException | ✅ | Exception message and properties. |
| BB_EPH_54 | `skipUnknown` mode | ✅ | Leave unknown placeholders unchanged. |

---

## 3. Macro Expansion

**Test file:** `test/v2/macro_expansion_test.dart`

Tests for `MacroExpander` — positional placeholders ($1–$9), rest placeholder ($$), nested macros, and edge cases.

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_MAC_01 | Simple macro without placeholders (2 tests) | ✅ | Macro expansion without args. |
| BB_MAC_02 | Single placeholder `$1` (2 tests) | ✅ | First argument substitution. |
| BB_MAC_03 | Multiple placeholders `$1 $2` (2 tests) | ✅ | Multi-argument substitution. |
| BB_MAC_04 | Rest placeholder `$$` (2 tests) | ✅ | All remaining arguments. |
| BB_MAC_05 | Combined `$n` and `$$` | ✅ | Named + rest args together. |
| BB_MAC_06 | Nested macro expansion | ✅ | Macro referencing another macro. |
| BB_MAC_07 | Missing arguments use empty strings (3 tests) | ✅ | Graceful handling of missing args. |
| BB_MAC_08 | Undefined macro | ✅ | Returns original tokens unchanged. |
| BB_MAC_09 | Multiple macros in args | ✅ | Multiple macro invocations in one line. |
| BB_MAC_10 | `@` in middle of token is literal | ✅ | Not treated as macro prefix. |
| BB_MAC_11 | Quoted arguments with spaces (2 tests) | ✅ | Quoted args preserved as single arg. |
| BB_MAC_12 | Escaping | ✅ | Escape sequences in macros. |
| — | `getRequiredArgCount` (5 tests) | ✅ | Counts required arguments from placeholders. |

---

## 4. CLI Argument Parser

**Test file:** `test/v2/core/cli_arg_parser_test.dart`

Exhaustive tests for `CliArgs` — 96 tests covering option parsing, command extraction, bundled flags, and complex command lines.

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_CLI_1–5 | `CliArgs` constructor and defaults | ✅ | Default values, empty args. |
| BB_CLI_6–8 | `effectiveRecursive`, `isHelpOrVersion` | ✅ | Computed properties. |
| BB_CLI_9–12 | `toProjectTraversalInfo`, `toGitTraversalInfo` | ✅ | Traversal conversion. |
| BB_CLI_13–15 | `PerCommandArgs` | ✅ | Per-command option parsing. |
| BB_CLI_16–32 | Long options (`--help` through `--build-order`) | ✅ | All long option flags. |
| BB_CLI_33–44 | Short options (`-h` through `-f`) | ✅ | All abbreviations. |
| BB_CLI_45–49 | Bundled short options (`-rv`, `-rvb`) | ✅ | Combined flag bundles. |
| BB_CLI_50–55 | Commands parsing | ✅ | Command extraction from args. |
| BB_CLI_56–62 | Per-command options | ✅ | Options scoped to commands. |
| BB_CLI_63–68 | Positional arguments, extra/unknown | ✅ | Arg list handling edge cases. |
| BB_CLI_69–80 | Complex command lines (buildkit, testkit, git) | ✅ | Real-world scenarios. |
| BB_CLI_81–84 | Conflicting abbreviations (`-c`) | ✅ | Abbreviation collision handling. |
| BB_CLI_85–88 | Nested tool options | ✅ | Parent-child option passing. |
| BB_CLI_89–92 | Macro/define greedy positional parsing, `--modes` | ✅ | Modes flag and define parsing. |

---

## 5. CommandDefinition

**Test file:** `test/v2/core/command_definition_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_CMD_1–3 | GitTraversalOrder enum | ✅ | innerFirst, outerFirst, topRepo values. |
| BB_CMD_4–5 | Creation with required/all fields | ✅ | Constructor variants. |
| BB_CMD_6–8 | `allOptions` with/without traversal | ✅ | Option collection based on traversal. |
| BB_CMD_9–10 | Command option ordering | ✅ | Options maintain declaration order. |
| BB_CMD_11–13 | Usage string generation | ✅ | With/without aliases. |
| BB_CMD_14 | `toString` | ✅ | Debug string representation. |
| BB_CMD_15 | Required natures configuration | ✅ | Nature constraints. |

---

## 6. Completion Generator

**Test file:** `test/v2/core/completion_generator_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_CMP_1–10 | Bash completion | ✅ | Function, commands, options, no-commands tools. |
| BB_CMP_11–20 | Zsh completion | ✅ | Same coverage for zsh. |
| BB_CMP_21–30 | Fish completion | ✅ | Same coverage for fish. |

---

## 7. Features — Modes, Defines, Macros, Pipelines

**Test file:** `test/v2/core/features_test.dart`

Tests for the recently implemented features: modes, persistent defines, runtime macros, and pipelines.

### Modes

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_MOD_01 | `--modes` flag parsed correctly | ✅ | Single and comma-separated modes. |
| BB_MOD_02 | Mode-specific defines activated | ✅ | DEV mode activates DEV defines. |
| BB_MOD_03 | Multiple modes merge | ✅ | DEV,CI modes both applied. |
| BB_MOD_04 | No modes = global defines only | ✅ | Base behavior without modes. |

### Defines

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_DEF_01 | `:define key=value` adds persistent define | ✅ | Define command processing. |
| BB_DEF_02 | `:defines` lists all defines | ✅ | List command output. |
| BB_DEF_03 | `:undefine key` removes define | ✅ | Remove command processing. |
| BB_DEF_04 | Define placeholder `@{key}` resolution | ✅ | Substitution in YAML values. |

### Macros

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_MCR_01 | `:macro name=command` adds macro | ✅ | Macro definition. |
| BB_MCR_02 | `:macros` lists all macros | ✅ | List command output. |
| BB_MCR_03 | `:unmacro name` removes macro | ✅ | Remove command. |
| BB_MCR_04 | `@name` expands macro | ✅ | Macro invocation. |
| BB_MCR_05 | Macro with `$1` placeholder | ✅ | Positional argument substitution. |

### Execute Placeholders (in features context)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_PLH_02–04 | `folder.name`, `folder.relative`, `root` | ✅ | Path placeholders in execute context. |
| BB_PLH_05–06 | Dart property and ternary expressions | ✅ | Nature-aware placeholders. |
| BB_PLH_07–08 | `current-os`, `current-platform` | ✅ | Platform placeholders. |

### Pipelines

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_PIP_01 | Pipeline loads from master YAML | ✅ | Pipeline definition parsing. |
| BB_PIP_02 | Pipeline phases (precore, core, postcore) | ✅ | Phase ordering. |
| BB_PIP_03 | `shell:` command prefix | ✅ | Shell execution. |
| BB_PIP_04 | `shell-scan:` command prefix | ✅ | Shell with folder scanning. |
| BB_PIP_05 | `stdin:` command prefix | ✅ | Stdin piping. |
| BB_PIP_06 | `tool:` command prefix | ✅ | Nested tool execution. |
| BB_PIP_07 | Option precedence in pipelines | ✅ | Step options override pipeline. |
| BB_PIP_08 | Pipeline dry-run | ✅ | Preview without execution. |
| BB_PIP_09 | Multi-workspace pipeline | ✅ | Cross-workspace execution. |
| BB_PIP_10 | Pipeline step placeholder resolution | ✅ | `%{...}` in pipeline steps. |

---

## 8. Help Generator

**Test file:** `test/v2/core/help_generator_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_HLP_1–10 | Tool help output | ✅ | Name, version, description, usage, options, commands, aliases, hidden, footer, hint. |
| BB_HLP_11–20 | Command help output | ✅ | Name, description, aliases, options, traversal, per-command filters, examples, usage. |
| BB_HLP_21–33 | Summary help | ✅ | Basic usage, multi-command list, truncation, flag/option formatting, defaults. |

---

## 9. OptionDefinition

**Test file:** `test/v2/core/option_definition_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_OPT_1–7 | Flag options | ✅ | `.flag()` constructor, negatable, defaults. |
| BB_OPT_8–14 | Value options | ✅ | `.option()` constructor, abbreviations, allowed values. |
| BB_OPT_15–18 | Multi options | ✅ | `.multi()` constructor, multiple values. |
| BB_OPT_19–22 | `toString`, `usageString` | ✅ | Display formatting. |
| BB_OPT_23–25 | `isPerCommand` tagging | ✅ | Per-command vs global scope. |
| BB_OPT_26–28 | Standard traversal options | ✅ | Built-in option instances. |

---

## 10. ToolDefinition

**Test file:** `test/v2/core/tool_definition_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_TDF_1–8 | Construction and properties | ✅ | Name, description, version, mode, features. |
| BB_TDF_9–15 | Command lookup | ✅ | `findCommand`, `findCommandsWithPrefix`. |
| BB_TDF_16–22 | `isValidCommand`, hidden, default | ✅ | Command validation and defaults. |
| BB_TDF_23–30 | `allOptions`, `usageString` | ✅ | Option collection and display. |
| BB_TDF_31–40 | Single/multi-command modes | ✅ | Mode-specific behavior. |
| BB_TDF_41–48 | DSL builder API | ✅ | `ToolDefinition.build()` pattern. |
| BB_TDF_49–55 | `copyWith`, `CommandListOps` | ✅ | `.without()`, `.replacing()`, `.plus()`. |

---

## 11. ToolDefinition Serializer

**Test file:** `test/v2/core/tool_definition_serializer_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_SER_1–5 | Round-trip fidelity | ✅ | Serialize → deserialize preserves all fields. |
| BB_SER_6–10 | Minimal/full fields | ✅ | Handles sparse and complete definitions. |
| BB_SER_11–15 | Commands and options | ✅ | Nested structures serialize correctly. |
| BB_SER_16–19 | Nested tools, aliases, edge cases | ✅ | Complex definition scenarios. |

---

## 12. Wiring Loader

**Test file:** `test/v2/core/wiring_loader_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_WIR_1–5 | YAML loading | ✅ | Load wiring definitions from YAML files. |
| BB_WIR_6–10 | Command wiring | ✅ | Wire commands from parent to nested tools. |
| BB_WIR_11–14 | Option resolution | ✅ | Resolve options across wired tools. |
| BB_WIR_15–17 | Configuration merging | ✅ | Merge wiring config with tool definitions. |

---

## 13. Pipeline Config

**Test file:** `test/v2/core/pipeline_config_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_PPC_1–3 | Step definitions | ✅ | Pipeline step parsing from YAML. |
| BB_PPC_4–6 | Option inheritance | ✅ | Steps inherit pipeline options. |
| BB_PPC_7–9 | YAML pipeline configuration | ✅ | Full pipeline YAML loading. |

---

## 14. Pipeline Executor

**Test file:** `test/v2/core/pipeline_executor_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_PPE_1 | Step ordering | ✅ | Steps execute in declared order. |
| BB_PPE_2 | Error handling | ✅ | Step failures propagate correctly. |
| BB_PPE_3 | Dry-run behavior | ✅ | Preview without execution. |
| BB_PPE_4 | Multi-step execution | ✅ | Sequential step processing. |

---

## 15. ToolRunner

**Test file:** `test/v2/core/tool_runner_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_TRN_1–8 | Command dispatch | ✅ | Routing to correct command executors. |
| BB_TRN_9–14 | Option parsing | ✅ | Global and per-command options. |
| BB_TRN_15–20 | Help/version output | ✅ | `--help`, `--version`, `help <command>`. |
| BB_TRN_21–26 | Verbose/dry-run modes | ✅ | `--verbose`, `--dry-run` propagation. |
| BB_TRN_27–32 | Error handling | ✅ | Invalid commands, missing args. |
| BB_TRN_33–38 | Help topic dispatch | ✅ | `help <topic>` displays topic content. |
| BB_TRN_39–42 | Integration with ToolDefinition | ✅ | Full lifecycle with real definitions. |

---

## 16. ToolRunner — Nested Tools

**Test file:** `test/v2/core/tool_runner_nested_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_NTR_1–5 | Parent-child dispatch | ✅ | Parent routes to nested tool. |
| BB_NTR_6–10 | Option inheritance | ✅ | Parent options forwarded to child. |
| BB_NTR_11–15 | Nested help | ✅ | `help` for nested commands. |
| BB_NTR_16–20 | Multi-level hierarchies | ✅ | Deeply nested tool chains. |

---

## 17. Nested Tool Executor

**Test file:** `test/v2/core/nested_tool_executor_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_NTE_1–4 | Nested command resolution | ✅ | Find and execute nested commands. |
| BB_NTE_5–8 | Argument forwarding | ✅ | Args passed through to nested tool. |
| BB_NTE_9–11 | Error propagation | ✅ | Nested errors bubble up correctly. |
| BB_NTE_12–14 | Lazy loading | ✅ | Nested tools loaded on demand. |

---

## 18. Folder Scanner

**Test file:** `test/v2/traversal/folder_scanner_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_FSC_1–4 | Recursive scanning | ✅ | Deep directory scanning. |
| BB_FSC_5–8 | Non-recursive scanning | ✅ | Single-level scanning. |
| BB_FSC_9–12 | Exclusion patterns | ✅ | Glob-based dir exclusion during scan. |
| BB_FSC_13–15 | Hidden folder handling | ✅ | `.hidden` directories skipped. |
| BB_FSC_16–17 | Symlink behavior | ✅ | Symlinks not followed by default. |

---

## 19. Nature Detector

**Test file:** `test/v2/traversal/nature_detector_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_NAT_1–6 | Dart package/console/server detection | ✅ | `pubspec.yaml` presence and content. |
| BB_NAT_7–12 | Flutter app/plugin detection | ✅ | Flutter SDK dependency. |
| BB_NAT_13–18 | Git repo/submodule detection | ✅ | `.git/` presence. |
| BB_NAT_19–24 | TypeScript detection | ✅ | `package.json` / `tsconfig.json`. |
| BB_NAT_25–30 | VS Code extension detection | ✅ | `package.json` with VS Code fields. |
| BB_NAT_31–34 | BuildKit project detection | ✅ | `buildkit.yaml` / `buildkit_master.yaml`. |
| BB_NAT_35–38 | Tom project detection | ✅ | `tom_project.yaml` / `tom_master.yaml`. |

---

## 20. Nature Filter

**Test file:** `test/v2/traversal/nature_filter_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_NTF_1–5 | Required nature filtering | ✅ | Filter folders by required natures. |
| BB_NTF_6–10 | Glob pattern matching | ✅ | Glob-based folder selection. |
| BB_NTF_11–15 | Include/exclude combinations | ✅ | Combined filter logic. |
| BB_NTF_16–20 | Multi-nature conditions | ✅ | AND/OR nature requirements. |

---

## 21. Filter Pipeline

**Test file:** `test/v2/traversal/filter_pipeline_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_FPL_1–8 | Chaining multiple filters | ✅ | Sequential filter application. |
| BB_FPL_9–16 | Project/exclude glob patterns | ✅ | `--project` and `--exclude` globs. |
| BB_FPL_17–24 | Module filtering | ✅ | Module boundary handling. |
| BB_FPL_25–32 | Git-based traversal ordering | ✅ | Inner-first/outer-first git ordering. |
| BB_FPL_33–40 | Combined filter scenarios | ✅ | Real-world multi-filter pipelines. |

---

## 22. Build Order

**Test file:** `test/v2/traversal/build_order_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_BLD_1–4 | Topological sort | ✅ | Dependency-based ordering. |
| BB_BLD_5–8 | Cycle detection | ✅ | Circular dependency handling. |
| BB_BLD_9–12 | Independent package ordering | ✅ | Stable order for unrelated packages. |

---

## 23. Traversal Info

**Test file:** `test/v2/traversal/traversal_info_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_TVI_1–6 | Project traversal info construction | ✅ | Creation and defaults. |
| BB_TVI_7–12 | Git traversal info construction | ✅ | Git-specific traversal data. |
| BB_TVI_13–16 | Option merging | ✅ | CLI options merged into traversal info. |
| BB_TVI_17–22 | Serialization | ✅ | Traversal info to/from serialized form. |

---

## 24. Build Base Integration

**Test file:** `test/v2/traversal/build_base_integration_test.dart`

Full integration test using filesystem fixtures — end-to-end workspace scanning, detection, filtering, and ordering.

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_INT_1–6 | Scanning with detection | ✅ | Scan + auto-detect natures. |
| BB_INT_7–12 | Filtering with natures | ✅ | Filter scanned results by nature. |
| BB_INT_13–17 | Build ordering | ✅ | Dependencies resolved + sorted. |
| BB_INT_18–22 | End-to-end traversal | ✅ | Full pipeline: scan → detect → filter → order. |

---

## 25. Comprehensive Traversal

**Test file:** `test/v2/traversal/traversal_comprehensive_test.dart`

51 tests covering complex workspace scenarios — the most thorough traversal test suite.

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BB_CTV_1–10 | Complex workspace structures | ✅ | Multi-level, mixed project types. |
| BB_CTV_11–20 | Nested git repos | ✅ | Submodules, overlapping repos. |
| BB_CTV_21–30 | Mixed project types | ✅ | Dart + Flutter + TypeScript + VS Code. |
| BB_CTV_31–40 | Module boundaries | ✅ | Module inclusion/exclusion. |
| BB_CTV_41–45 | Skip files | ✅ | Various skip file scenarios. |
| BB_CTV_46–51 | Edge cases | ✅ | Empty dirs, symlinks, special chars. |

---

## Test Gaps & Potential Additions

The current test suite is comprehensive. Areas where additional tests could be valuable:

| Area | Current | Gap | Priority |
|------|---------|-----|----------|
| `ToolRunner` help topic injection from master YAML | ✅ Tested | Could add more edge cases for auto-injection of masterYamlHelpTopics | Low |
| `{TOOL}` placeholder in help topics | Partially tested via help generator | End-to-end test with actual tool name | Low |
| Pipeline `stdin:` with `%{...}` placeholders | ✅ Tested in features | Integration test with real stdin pipe | Low |
| `--dump-definitions` output format | Tested in ToolRunner | Validate complete YAML structure | Low |
| ConfigLoader with nested `@{...}` in `@[...]` | ✅ Recursive test exists | Additional nesting depth scenarios | Low |

Overall coverage assessment: **Excellent — 718 tests covering all features.**
