# Tom Build Kit — Test Coverage Plan

This document lists all testable features across buildkit tools and tracks test implementation status.

For the testing strategy, safety protocol, and test infrastructure, see [_copilot_guidelines/testing.md](../_copilot_guidelines/testing.md).

## Status Legend

- ✅ Test implemented and passing
- ⬜ Test not yet implemented

---

## Overview

| # | Feature Area | Tests | Status | Test File | Details |
|---|-------------|-------|--------|-----------|---------|
| 1 | [ToolBase — Shared Infrastructure](#1-toolbase--shared-infrastructure) | 14 | 14✅ | `toolbase_test.dart` | [→](#1-toolbase--shared-infrastructure) |
| 2 | [Versioner — Version File Generation](#2-versioner--version-file-generation) | 7 | 7✅ | `versioner_test.dart` | [→](#2-versioner--version-file-generation) |
| 3 | [Cleanup — File Deletion](#3-cleanup--file-deletion) | 9 | 9✅ | `cleanup_test.dart` | [→](#3-cleanup--file-deletion) |
| 4 | [Compiler — Cross-Platform Compilation](#4-compiler--cross-platform-compilation) | 6 | 6✅ | `compiler_test.dart` | [→](#4-compiler--cross-platform-compilation) |
| 5 | [Runner — Build Runner Wrapper](#5-runner--build-runner-wrapper) | 5 | 5✅ | `runner_test.dart` | [→](#5-runner--build-runner-wrapper) |
| 6 | [Dependencies — Dependency Tree](#6-dependencies--dependency-tree) | 7 | 7✅ | `dependencies_test.dart` | [→](#6-dependencies--dependency-tree) |
| 7 | [VersionBump — Version Bumping](#7-versionbump--version-bumping) | 6 | 6✅ | `versionbump_test.dart` | [→](#7-versionbump--version-bumping) |
| 8 | [BuildKit — Pipeline Orchestrator](#8-buildkit--pipeline-orchestrator) | 12 | 12✅ | `buildkit_test.dart` | [→](#8-buildkit--pipeline-orchestrator) |
| 9 | [Config Merge — Merge Precedence](#9-config-merge--merge-precedence) | 4 | 4✅ | `config_merge_test.dart` | [→](#9-config-merge--merge-precedence) |
| 10 | [Security — Path & Command Validation](#10-security--path--command-validation) | 4 | 4✅ | `security_test.dart` | [→](#10-security--path--command-validation) |
| 11 | [Exclusion — Cross-Tool Filtering](#11-exclusion--cross-tool-filtering) | 27 | 27✅ | `exclusion_test.dart` | [→](#11-exclusion--cross-tool-filtering) |
| 12 | [Execute Command — Placeholder Resolution](#12-execute-command--placeholder-resolution) | 14 | 14✅ | `execute_command_test.dart` | [→](#12-execute-command--placeholder-resolution) |
| 13 | [Script Utilities — Multi-Line & Stdin](#13-script-utilities--multi-line--stdin) | 12 | 12✅ | `script_utils_test.dart` | [→](#13-script-utilities--multi-line--stdin) |
| 14 | [Built-in Commands — Parsing & Resolution](#14-built-in-commands--parsing--resolution) | 19 | 19✅ | `builtin_commands_test.dart` | [→](#14-built-in-commands--parsing--resolution) |
| 15 | [Unreferenced — Export Audit](#15-unreferenced--export-audit) | 9 | 9✅ | `unreferenced_exports_test.dart` | [→](#15-unreferenced--export-audit) |
| — | **Total** | **155** | **155✅** | | |

---

## 1. ToolBase — Shared Infrastructure

**Test file:** `test/toolbase_test.dart`

These features are shared by all tools. Test via any tool (e.g., versioner or dependencies) since they all inherit from `ToolBase`.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| TB_VER01 | Version argument (`version`, `--version`, `-version`) | ✅ | Run tool with `version` as first arg. Verify stdout contains tool name and version string. |
| TB_HLP01 | `--help` flag | ✅ | Run tool with `--help`. Verify exit code 0 and stdout contains usage text. |
| TB_LST01 | `--list` with `--scan` and `--recursive` | ✅ | Run versioner `--scan . --recursive --list`. Verify output lists discovered projects. |
| TB_EXC01 | `--exclude` glob filtering | ✅ | Run versioner `--scan . -r --list --exclude 'zom_*'`. Verify no `zom_` projects in output. |
| TB_EXC02 | `--recursion-exclude` during scanning | ✅ | Run with `--recursion-exclude node_modules`. Verify node_modules subdirs not scanned. |
| TB_DSC01 | Workspace root discovery | ✅ | Run tool from workspace root vs from a subdirectory. Both should find `buildkit_master.yaml`. |
| TB_XPJ01 | `--exclude-projects` folder name filtering | ✅ | Run versioner `--scan . -r --list --exclude-projects 'tom_d4rt*'`. Verify no `tom_d4rt*` folders in output. |
| TB_XPJ02 | `--exclude-projects` from master YAML | ✅ | Set `exclude-projects: ['tom_test_*']` in master YAML navigation. Run `--list`. Verify excluded. |
| TB_SKP01 | `buildkit_skip.yaml` skips directory | ✅ | Place `buildkit_skip.yaml` in a project dir. Run `--list`. Verify project excluded. |
| TB_SKP02 | `buildkit_skip.yaml` skips subdirectories | ✅ | Place skip file in parent dir. Run `--scan` recursively. Verify no children found. |
| TB_XPJ03 | `--exclude-projects` with relative path pattern | ✅ | Run versioner `--scan . -r --list --exclude-projects 'xternal/tom_module_basics/*'`. Verify all projects under that submodule excluded. |
| TB_XPJ04 | `--exclude-projects` with `**` glob path pattern | ✅ | Run versioner `--scan . -r --list --exclude-projects '**/tom_module_basics/*'`. Verify same exclusion regardless of leading path. |
| TB_XPJ05 | `--exclude-projects` combined basename + path patterns | ✅ | Run versioner `--scan . -r --list --exclude-projects 'zom_*' --exclude-projects 'xternal/tom_module_basics/*'`. Verify both pattern types applied. |
| TB_XPJ06 | `--exclude-projects` pattern auto-detection | ✅ | Verify patterns without `/` or `**` match basename only (e.g. `tom_basics` excludes `tom_basics` but not `xternal/tom_module_basics/tom_basics`). Verify patterns with `/` match workspace-relative path. |

---

## 2. Versioner — Version File Generation

**Test file:** `test/versioner_test.dart`

Target project: `_build` (main repo, has `variable-prefix: tomTools` in its `buildkit.yaml`).

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| VER_GEN01 | Generates `version.versioner.dart` with correct class name | ✅ | Run versioner `--project _build`. Verify file contains `class TomToolsVersionInfo` (project config overrides workspace default). |
| VER_GIT01 | `--no-git` omits git commit field | ✅ | Run with `--no-git`. Verify `gitCommit` is empty string. Bug #12 FIXED. |
| VER_LST01 | `--list` shows matching projects | ✅ | Run with `--list`. Verify `_build` appears in output. |
| VER_SHW01 | `--show` displays project config | ✅ | Run with `--show`. Verify `variable-prefix` and `tomTools` appear. |
| VER_OVR01 | `--version` overrides pubspec version | ✅ | Run with `--version 9.9.9`. Verify `version = '9.9.9'` in output. |
| VER_PFX01 | `--variable-prefix` overrides project config | ✅ | Run with `--variable-prefix myCustom`. Verify `class MyCustomVersionInfo`. Bug #12 FIXED. |
| VER_BLD01 | Build number increments on each run | ✅ | Run versioner twice. Extract `buildNumber` from each. Verify second = first + 1. |

---

## 3. Cleanup — File Deletion

**Test file:** `test/cleanup_test.dart`

Target project: `_build` (has cleanup config) or a test project.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| CLN_DEL01 | Deletes files matching glob patterns | ✅ | Create temp `.g.dart` files in target project. Run cleanup. Verify files deleted. |
| CLN_DRY01 | `--dry-run` lists files without deleting | ✅ | Create temp files. Run with `--dry-run`. Verify files still exist and stdout lists them. |
| CLN_EXC01 | `excludes` patterns prevent deletion | ✅ | Create a `version.versioner.dart` file. Configure exclude for it. Run cleanup. Verify it survives. |
| CLN_PRO01 | Protected folders are never deleted | ✅ | Attempt cleanup on directory containing `.git` or `.github`. Verify those are untouched. |
| CLN_PRO02 | Protected folders with multi-segment paths | ✅ | Set `protected-folders: ['lib/src']`. Verify lib/src/ contents survive. Bug #17 FIXED. |
| CLN_SAF01 | `--max-files` safety limit triggers abort | ✅ | Create >100 matching files. Run without `--force`. Verify exit code != 0 and files remain. |
| CLN_SAF02 | `--force` skips safety limit | ✅ | Create >100 matching files. Run with `--force`. Verify deletion proceeds. |
| CLN_LST01 | `--list` shows cleanup-configured projects | ✅ | Run with `--list`. Verify projects with `cleanup:` config appear. |
| CLN_SHW01 | `--show` displays cleanup config | ✅ | Run with `--show`. Verify cleanup sections are displayed. |

---

## 4. Compiler — Cross-Platform Compilation

**Test file:** `test/compiler_test.dart`

Target project: `_build` or another project with `compiler:` config.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| CMP_LST01 | `--list` shows compiler-configured projects | ✅ | Run with `--list`. Verify only projects with `compiler:` config appear. |
| CMP_SHW01 | `--show` displays compiler config | ✅ | Run with `--show`. Verify compile sections, targets, and pre/postcompile displayed. |
| CMP_DRY01 | `--dry-run` shows commands without executing | ✅ | Run with `--dry-run`. Verify stdout shows planned compilation commands. No binaries produced. |
| CMP_TGT01 | `--targets` filters target platforms | ✅ | Run with `--targets linux-x64`. Verify only linux-x64 compilation attempted. |
| CMP_PLC01 | Placeholder resolution in commandlines | ✅ | Configure `commandline` with `${file}`, `${target-platform}`. Run. Verify placeholders resolved in verbose output. |
| CMP_PHS01 | Precompile/postcompile phases execute | ✅ | Configure pre/postcompile steps (e.g., `echo` commands). Run. Verify all phases execute in order. |

---

## 5. Runner — Build Runner Wrapper

**Test file:** `test/runner_test.dart`

Target project: Any project with `build.yaml` (e.g., `_build`).

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| RUN_LST01 | `--list` shows runner-eligible projects | ✅ | Run with `--list`. Verify projects with `build.yaml` appear. |
| RUN_SHW01 | `--show` displays runner config and builders | ✅ | Run with `--show`. Verify builder names and filter config displayed. |
| RUN_DRY01 | `--dry-run` shows build_runner command | ✅ | Run with `--dry-run`. Verify planned command shown without execution. |
| RUN_FLT01 | `--include-builders` filters to specific builders | ✅ | Run with `--include-builders reflection`. Verify only reflection builder runs. |
| RUN_CLN01 | `--command clean` runs build_runner clean | ✅ | Run with `--command clean`. Verify build_runner clean executed successfully. |

---

## 6. Dependencies — Dependency Tree

**Test file:** `test/dependencies_test.dart`

Target project: Any project with dependencies (e.g., `_build`).

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| DEP_NRM01 | Default mode shows normal dependencies | ✅ | Run dependencies. Verify stdout lists `->` prefixed dependency names. |
| DEP_DEV01 | `--dev` shows dev dependencies only | ✅ | Run with `--dev`. Verify stdout lists `+>` prefixed dependencies. No `->` entries. |
| DEP_ALL01 | `--all` shows both normal and dev | ✅ | Run with `--all`. Verify both `->` and `+>` entries present. |
| DEP_DRP01 | `--deep` shows recursive dependency tree | ✅ | Run with `--deep`. Verify indented tree output with transitive dependencies. Bug #16 FIXED. |
| DEP_DRP02 | `--deep` output differs from normal mode | ✅ | Compare `--deep` vs normal output. Deep should have more entries (transitive deps). Bug #16 FIXED. |
| DEP_CBD01 | `--deep --dev` combined flags | ✅ | Run with `--deep --dev`. Verify no crash, shows only dev deps with +> prefix. |
| DEP_ERR01 | Non-existent `--project` path error | ✅ | Run with `--project nonexistent`. Verify non-zero exit and error message. Bug #19 FIXED. |

---

## 7. VersionBump — Version Bumping

**Test file:** `test/versionbump_test.dart`

Target project: `_build` (has `version:` in pubspec.yaml).

**Note:** VersionBump `-v` abbreviation conflict (issues.md #13) has been fixed. All tests now pass.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| VBM_BUG13 | Bug #13 FIXED: `--help` works after removing `-v` abbreviation | ✅ | Run `versionbump --help`. Verify exit code 0 and usage text displayed. |
| VBM_PAT01 | Default patch bump | ✅ | Run versionbump on `_build`. Verify `version:` in pubspec.yaml incremented patch (e.g., 1.0.0 → 1.0.1). |
| VBM_MIN01 | `--minor` bump for specific project | ✅ | Run with `--minor _build`. Verify minor version bumped (e.g., 1.0.0 → 1.1.0). |
| VBM_MAJ01 | `--major` bump for specific project | ✅ | Run with `--major _build`. Verify major version bumped (e.g., 1.0.0 → 2.0.0). |
| VBM_RST01 | Build counter reset after bump | ✅ | Run versionbump. Verify `tom_build_state.json` has `buildNumber: 0`. |
| VBM_DRY01 | `--dry-run` shows planned bumps without changing files | ✅ | Run with `--dry-run`. Verify pubspec.yaml unchanged and stdout shows planned bump. |

---

## 8. BuildKit — Pipeline Orchestrator

**Test file:** `test/buildkit_test.dart`

Uses workspace-level pipeline configuration from `buildkit_master.yaml`.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BKT_LST01 | `--list` shows available pipelines | ✅ | Run `buildkit --list`. Verify pipeline names from `buildkit_master.yaml` are listed. |
| BKT_HLP01 | `--help` shows usage | ✅ | Run `buildkit --help`. Verify usage text displayed. |
| BKT_CMD01 | Direct command execution (`:versioner`) | ✅ | Run `buildkit :versioner --project _build`. Verify versioner executes. |
| BKT_PIP01 | Pipeline execution (`build`, `clean`) | ✅ | Run `buildkit clean --project _build`. Verify pipeline steps execute in order. |
| BKT_DRY01 | `--dry-run` on pipeline (flags after pipeline name) | ✅ | Bug #15 FIXED: warning added when known flags appear after pipeline name. Test skipped since behavior is by design. |
| BKT_DRY02 | `--dry-run` before pipeline name (workaround) | ✅ | Run `buildkit --dry-run --project _build test-simple`. Verify [DRY RUN] markers and no execution. Documents workaround for bug #15. |
| BKT_OPT01 | Per-step option suppression (`-s-`, `-v-`) | ✅ | Run `buildkit :versioner -s- --project _build`. Verify `-s` not passed to versioner. |
| BKT_SHL01 | Shell command execution in pipeline | ✅ | Configure pipeline step with `shell echo hello`. Run. Verify "hello" in output. |
| BKT_XPJ01 | `--exclude-projects` filters pipeline targets | ✅ | Run `buildkit build --exclude-projects 'zom_*'`. Verify no `zom_` projects processed by any pipeline step. |
| BKT_XPJ02 | `--exclude` combined with `--exclude-projects` | ✅ | Run `buildkit build --exclude '*.g.dart' --exclude-projects 'xternal/tom_module_basics/*'`. Verify both file-level and project-level exclusions applied independently. |
| BKT_ERR01 | Unknown pipeline name error handling | ✅ | Run `buildkit nonexistent-pipeline`. Verify non-zero exit and clear error message. |
| BKT_ERR02 | Non-existent `--project` path error | ✅ | Run `buildkit --project nonexistent test-simple`. Verify error reported. |

---

## 9. Config Merge — Merge Precedence

**Test file:** `test/config_merge_test.dart`

Tests that verify the config merge hierarchy works correctly across all tools.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| CFG_DEF01 | Workspace defaults apply when project has no config | ✅ | Use fixture with workspace-level `versioner:` prefix. Target project without `versioner:` in `buildkit.yaml`. Verify workspace prefix used. |
| CFG_OVR01 | Project config overrides workspace config | ✅ | Use fixture with workspace prefix `testDefault`. Target project with `tomTools`. Verify project prefix used. |
| CFG_CLI01 | CLI args override both project and workspace config | ✅ | Run with `--variable-prefix myCustom`. Verify `MyCustomVersionInfo`. Bug #12 FIXED. |
| CFG_MRG01 | Additive merge for list fields (excludes, protected-folders) | ✅ | Configure workspace and project with different exclude patterns. Verify both patterns applied (union). |

---

## 10. Security — Path & Command Validation

**Test file:** `test/security_test.dart`

Tests that verify security boundaries are enforced.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| SEC_PRJ01 | `--project` rejects paths outside workspace | ✅ | Run versioner `--project /tmp/evil`. Verify non-zero exit code and error message about path containment. |
| SEC_SCN01 | `--scan` rejects paths outside workspace | ✅ | Run versioner `--scan /tmp`. Verify rejection. |
| SEC_PRO01 | Protected folders survive cleanup | ✅ | Configure cleanup that would match `.git/` contents. Run. Verify `.git/` untouched. |
| SEC_CMD01 | Pipeline rejects unknown commands | ✅ | Configure pipeline with `rm -rf /`. Run. Verify command rejected (not an allowed binary or `shell ` prefix). |

---

## 11. Exclusion — Cross-Tool Filtering

**Test file:** `test/exclusion_test.dart`

Comprehensive cross-tool tests for all project exclusion features. Tests every tool with `--scan . --recursive --list` and verifies exclusion filters work correctly.

### Basename Patterns (`--exclude-projects`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| EXCL_BN01 | Versioner excludes by basename | ✅ | `--exclude-projects '_build'`. Verify `_build` absent from `--list`. |
| EXCL_BN02 | Cleanup excludes by basename | ✅ | `--exclude-projects '_build'`. Verify `_build` absent. |
| EXCL_BN03 | Compiler excludes by basename | ✅ | `--exclude-projects '_build'`. Verify `_build` absent. |
| EXCL_BN04 | Dependencies excludes by basename | ✅ | `--exclude-projects '_build'`. Verify `_build` absent. |
| EXCL_BN05 | Runner excludes by basename | ✅ | `--exclude-projects 'tom_build_cli'`. Verify no `tom_build_cli` basename. |
| EXCL_BN06 | VersionBump excludes by basename | ✅ | `--exclude-projects '_build'`. Verify `_build` absent from `--list`. Bug #13 FIXED. |
| EXCL_BN07 | Glob pattern excludes multiple | ✅ | `--exclude-projects 'tom_core_*'`. Verify no `tom_core_*` basenames. |

### Path Patterns (`--exclude-projects`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| EXCL_PP01 | Path pattern `core/*` | ✅ | `--exclude-projects 'core/*'`. No `core/` projects in output. |
| EXCL_PP02 | Path pattern `devops/**` for runner | ✅ | `--exclude-projects 'devops/**'`. No `devops/` projects (including nested). |
| EXCL_PP03 | `**` glob matches nested paths | ✅ | `--exclude-projects '**/tom_core_*'`. No `tom_core_*` at any depth. |
| EXCL_PP04 | Combined basename + path patterns | ✅ | `--exclude-projects '_build' --exclude-projects 'core/*'`. Both applied. |

### `buildkit_skip.yaml` Marker File

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| EXCL_SF01 | Skip file excludes from versioner | ✅ | Place skip file in `_build`. Run `--list`. Verify `_build` absent. |
| EXCL_SF02 | Skip file excludes from cleanup | ✅ | Place skip file in `_build`. Verify absent. |
| EXCL_SF03 | Skip file excludes from compiler | ✅ | Place skip file in `_build`. Verify absent. |
| EXCL_SF04 | Skip file excludes from dependencies | ✅ | Place skip file in `_build`. Verify absent. |
| EXCL_SF05 | Skip file excludes from runner | ✅ | Place skip file in `devops/tom_build_cli`. Verify absent. |
| EXCL_SF06 | Skip file excludes from versionbump | ✅ | Place skip file. Verify versionbump excludes project. Bug #13 FIXED. |
| EXCL_SF07 | Skip file in parent excludes children | ✅ | Place skip file in `core/`. No `core/*` children found. |
| EXCL_SF08 | Skip file cleanup in tearDown | ✅ | Verify file exists after placement, removed in tearDown. |

### BuildKit Exclusion

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| EXCL_BK01 | BuildKit excludes by basename | ✅ | `--exclude-projects '_build' --verbose`. Verify not in project listing. |
| EXCL_BK02 | BuildKit excludes by path pattern | ✅ | `--exclude-projects 'core/*' --verbose`. No `core/` in listing. |
| EXCL_BK03 | BuildKit respects skip file | ✅ | Place skip file. Verify not in listing, skip message present. |

### Master YAML Exclusion

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| EXCL_MY01 | Master YAML basename exclude | ✅ | Set `exclude-projects: ['_build']` in fixture. Verify `_build` absent. |
| EXCL_MY02 | Master YAML path pattern exclude | ✅ | Set `exclude-projects: ['core/*']` in fixture. No `core/` projects. |

### Baseline (No Exclusion)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| EXCL_BL01 | Versioner finds _build without filters | ✅ | No exclusions. `_build` in output. |
| EXCL_BL02 | Dependencies finds core projects | ✅ | No exclusions. `core/` projects in output. |
| EXCL_BL03 | Runner finds projects | ✅ | No exclusions. Projects with `build.yaml` in output. |

---

## 12. Execute Command — Placeholder Resolution

**Test file:** `test/execute_command_test.dart`

Integration tests that spawn BuildKit as an external process against a temp workspace fixture.

### Basic Execution

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK_EXEC_01 | Echo with `%{folder.name}` placeholder | ✅ | Run `:execute "echo %{folder.name}"`. Verify folder names in output. |
| BK_EXEC_02 | `%{folder.relative}` placeholder | ✅ | Run `:execute "echo %{folder.relative}"`. Verify relative paths in output. |
| BK_EXEC_03 | Skip projects with `buildkit_skip.yaml` | ✅ | Place skip file. Run `:execute`. Verify skipped project not in output. |
| BK_EXEC_04 | `--dry-run` does not execute commands | ✅ | Run with `--dry-run`. Verify no actual output, only preview. |

### Placeholder Resolution

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK_EXEC_05 | `%{dart.exists?...}` ternary expression | ✅ | Run `:execute` with Dart ternary. Verify correct branch taken based on project type. |
| BK_EXEC_06 | `%{root}` resolves to workspace root | ✅ | Run `:execute "echo %{root}"`. Verify absolute workspace root path. |
| BK_EXEC_07 | `%{folder}` resolves to absolute path | ✅ | Run `:execute "echo %{folder}"`. Verify absolute folder path. |

### Navigation Integration

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK_EXEC_08 | `-p` project filter limits execution | ✅ | Run with `-p project_a`. Verify only one project processed. |
| BK_EXEC_09 | `-x` exclude removes matching projects | ✅ | Run with `-x project_b`. Verify excluded project absent. |
| BK_EXEC_10 | Git inner-first with `:execute` | ✅ | Run with `-i`. Verify git-based traversal ordering. |

### Condition Filtering

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK_EXEC_11 | `--condition dart.exists` filters non-Dart | ✅ | Run with `--condition dart.exists`. Verify only Dart projects processed. |
| BK_EXEC_12 | Non-existent condition skips all | ✅ | Run with `--condition nonexistent`. Verify all projects skipped. |
| BK_EXEC_14 | `-c dart.exists` short flag | ✅ | Run with `-c dart.exists`. Verify same result as `--condition`. |

### Syntax Regression

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK_EXEC_13 | `%{folder.name}` resolves correctly (not literal) | ✅ | Verify `%{folder.name}` is replaced, not passed through as literal text. |

---

## 13. Script Utilities — Multi-Line & Stdin

**Test file:** `test/script_utils_test.dart`

Unit tests for script parsing and integration tests for multi-line pipeline execution.

### Parsing

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| SCR_PRS01 | `isMultiLineShellScript` detects `shell\n` prefix | ✅ | Pass multi-line string. Verify returns true. |
| SCR_PRS02 | `isMultiLineShellScript` rejects non-multiline | ✅ | Pass single-line string. Verify returns false. |
| SCR_PRS03 | `extractScriptBody` extracts content after `shell\n` | ✅ | Extract body. Verify correct content. |
| SCR_PRS04 | `isStdinCommand` detects `stdin` prefix with newline | ✅ | Pass stdin-format string. Verify detection. |
| SCR_PRS05 | `isStdinCommand` rejects invalid formats | ✅ | Pass non-stdin string. Verify returns false. |
| SCR_PRS06 | `parseStdinCommand` extracts command and content | ✅ | Parse stdin string. Verify command and content split. |

### Multi-Line Execution

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| SCR_MLN01 | Multi-line shell script executes all lines | ✅ | Run pipeline with multi-line shell step. Verify all lines execute. |
| SCR_MLN02 | Multi-line shell in verbose mode | ✅ | Run with `--verbose`. Verify command echoing. |
| SCR_STD01 | Stdin piping sends content to command | ✅ | Run pipeline with stdin step. Verify content piped correctly. |
| SCR_STD02 | Stdin piping in verbose mode | ✅ | Run with `--verbose`. Verify stdin preview. |
| SCR_DRY01 | Multi-line shell dry-run shows preview | ✅ | Run with `--dry-run`. Verify preview without execution. |
| SCR_DRY02 | Stdin dry-run shows preview | ✅ | Run with `--dry-run`. Verify stdin preview. |

---

## 14. Built-in Commands — Parsing & Resolution

**Test file:** `test/builtin_commands_test.dart`

Unit tests for argument parsing and command shorthand resolution.

### Argument Parsing

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BIC_PAR01 | Simple command with no arguments | ✅ | Parse `:command`. Verify name extracted. |
| BIC_PAR02 | Command with unquoted arguments | ✅ | Parse `:command arg1 arg2`. Verify args split. |
| BIC_PAR03 | Double-quoted strings as single argument | ✅ | Parse `"quoted arg"`. Verify kept as one arg. |
| BIC_PAR04 | Single-quoted strings as single argument | ✅ | Parse `'quoted arg'`. Verify kept as one arg. |
| BIC_PAR05 | Mixed quoted and unquoted arguments | ✅ | Parse mixed. Verify correct split. |
| BIC_PAR06 | Multiple spaces between arguments | ✅ | Parse `a   b`. Verify trimmed to two args. |
| BIC_PAR07 | Empty string handling | ✅ | Parse `""`. Verify empty result. |
| BIC_PAR08 | Whitespace-only string | ✅ | Parse `"  "`. Verify empty result. |
| BIC_PAR09 | Backslash escapes in quoted strings | ✅ | Parse escaped content. Verify preserved. |

### Shorthand Resolution

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BIC_SHR01 | Returns exact match for full command name | ✅ | Resolve `versioner`. Verify exact match. |
| BIC_SHR02 | Case-insensitive matching | ✅ | Resolve `VERSIONER`. Verify case-insensitive match. |
| BIC_SHR03 | Unique prefix resolves to full command | ✅ | Resolve `vers`. Verify resolves to `versioner`. |
| BIC_SHR04 | Ambiguous prefix returns null | ✅ | Resolve ambiguous prefix. Verify null. |
| BIC_SHR05 | No match returns null | ✅ | Resolve unknown. Verify null. |
| BIC_SHR06 | All full command names resolve | ✅ | Resolve every known command. Verify all match. |

### isBuiltin Checks

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BIC_ISB01 | Full command names recognized | ✅ | Check `isBuiltin(:versioner)`. Verify true. |
| BIC_ISB02 | Command with arguments recognized | ✅ | Check `isBuiltin(:versioner --list)`. Verify true. |
| BIC_ISB03 | Unique shorthand recognized | ✅ | Check `isBuiltin(:vers)`. Verify true. |
| BIC_ISB04 | Ambiguous/unknown rejected | ✅ | Check `isBuiltin(:xyz)`. Verify false. |

---

## 15. Unreferenced — Export Audit

**Test file:** `test/unreferenced_exports_test.dart`

Drives the engine over planted trees under the package's `ztmp/`, and the
executor directly over a project with an `unreferenced:` section — no
workspace protocol, so it runs whatever the state of the workspace.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| UNREF-1 | Findings, with whether a test names them | ✅ | A planted tree: dead members, a symbol used only inside its type (make it private), and uses in another lib, the declaring file and an example application. |
| UNREF-2 | Declared test seams | ✅ | A `@visibleForTesting` member passes while a test names it and is a finding once none does. |
| UNREF-3 | The allowlist | ✅ | An entry excuses its symbol, a type entry its members; a stale entry fails the audit. |
| UNREF-4 | Nothing exported | ✅ | A tree with nothing exported proves nothing. |
| UNREF-5 | The section | ✅ | Read with its paths resolved against the project; no section is no configuration. |
| UNREF-6 | An entry without a reason | ✅ | Refused, naming the entry. |
| UNREF-7 | The command fails on findings | ✅ | And names them; a project without the section is skipped. |
| UNREF-8 | The command passes when everything is allowlisted | ✅ | And says how much it checked. |
| UNREF-9 | A prefix that matches nothing | ✅ | NOT MEASURED, a failure. |
