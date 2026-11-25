# Tom Build Kit — Test Coverage Plan

This document lists all testable features across buildkit tools and tracks test implementation status.

## Status Legend

- ✅ Test implemented and passing
- ⬜ Test not yet implemented

---

## Overview

| # | Feature Area | Tests | Status | Test File | Details |
|---|-------------|-------|--------|-----------|---------|
| 1 | [ToolBase — Shared Infrastructure](#1-toolbase--shared-infrastructure) | 14 | 14✅ | `toolbase_test.dart` | [→](#1-toolbase--shared-infrastructure) |
| 2 | [Versioner — Version File Generation](#2-versioner--version-file-generation) | 13 | 13✅ | `versioner_test.dart`, `versioner_build_number_test.dart`, `versioner_dart_sdk_test.dart` | [→](#2-versioner--version-file-generation) |
| 3 | [Cleanup — File Deletion](#3-cleanup--file-deletion) | 9 | 9✅ | `cleanup_test.dart` | [→](#3-cleanup--file-deletion) |
| 4 | [Compiler — Cross-Platform Compilation](#4-compiler--cross-platform-compilation) | 6 | 6✅ | `compiler_test.dart` | [→](#4-compiler--cross-platform-compilation) |
| 5 | [Runner — Build Runner Wrapper](#5-runner--build-runner-wrapper) | 5 | 5✅ | `runner_test.dart` | [→](#5-runner--build-runner-wrapper) |
| 6 | [Dependencies — Dependency Tree](#6-dependencies--dependency-tree) | 7 | 7✅ | `dependencies_test.dart` | [→](#6-dependencies--dependency-tree) |
| 7 | [VersionBump — Version Bumping](#7-versionbump--version-bumping) | 6 | 6✅ | `versionbump_test.dart` | [→](#7-versionbump--version-bumping) |
| 8 | [BuildKit — Pipeline Orchestrator](#8-buildkit--pipeline-orchestrator) | 13 | 13✅ | `buildkit_test.dart` | [→](#8-buildkit--pipeline-orchestrator) |
| 9 | [Config Merge — Merge Precedence](#9-config-merge--merge-precedence) | 4 | 4✅ | `config_merge_test.dart` | [→](#9-config-merge--merge-precedence) |
| 10 | [Security — Path & Command Validation](#10-security--path--command-validation) | 4 | 4✅ | `security_test.dart` | [→](#10-security--path--command-validation) |
| 11 | [Exclusion — Cross-Tool Filtering](#11-exclusion--cross-tool-filtering) | 27 | 27✅ | `exclusion_test.dart` | [→](#11-exclusion--cross-tool-filtering) |
| 12 | [Execute Command — Placeholder Resolution](#12-execute-command--placeholder-resolution) | 14 | 14✅ | `execute_command_test.dart` | [→](#12-execute-command--placeholder-resolution) |
| 13 | [Script Utilities — Multi-Line & Stdin](#13-script-utilities--multi-line--stdin) | 12 | 12✅ | `script_utils_test.dart` | [→](#13-script-utilities--multi-line--stdin) |
| 14 | [Built-in Commands — Parsing & Resolution](#14-built-in-commands--parsing--resolution) | 19 | 19✅ | `builtin_commands_test.dart` | [→](#14-built-in-commands--parsing--resolution) |
| 15 | [Unreferenced — Export Audit](#15-unreferenced--export-audit) | 9 | 9✅ | `unreferenced_exports_test.dart` | [→](#15-unreferenced--export-audit) |
| 16 | [Build, Test, Clean — Per Nature](#16-build-test-clean--per-nature) | 7 | 7✅ | `project_action_test.dart` | [→](#16-build-test-clean--per-nature) |
| 17 | [Projects — The Project Listing](#17-projects--the-project-listing) | 6 | 6✅ | `projects_command_test.dart` | [→](#17-projects--the-project-listing) |
| 18 | [Versioner — Build Number](#2-versioner--version-file-generation) | 5 | 5✅ | `versioner_build_number_test.dart` | [→](#2-versioner--version-file-generation) |
| 19 | [Help Footer](#19-help-footer) | 1 | 1✅ | `help_footer_test.dart` | [→](#19-help-footer) |
| 20 | [Pub Get — Stale Git Refs](#20-pub-get--stale-git-refs) | 3 | 3✅ | `pubget_git_ref_test.dart` | [→](#20-pub-get--stale-git-refs) |
| 21 | [Status — Git Mode](#21-status--git-mode) | 1 | 1✅ | `status_git_mode_test.dart` | [→](#21-status--git-mode) |
| 21 | [wssetup — Tree Setup](#21-wssetup--tree-setup) | 11 | 11✅ | `wssetup_test.dart` | [→](#21-wssetup--tree-setup) |
| — | **Total** | **196** | **196✅** | | |

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
| VER_BLD01 | Build number increments on each run that writes | ✅ | Run versioner, then again with `--force` (unchanged, it would be skipped: BK-INC-5). Extract `buildNumber` from each. Verify second = first + 1. |
| VBN-1 | No versioner file: build 1 | ✅ | Run on a project without a stamp. Verify `buildNumber = 1`. |
| VBN-2 | Counts on from the versioner file | ✅ | Stamp with build 41 (older version). Run twice. Verify 42, then 43; the version is the pubspec's. |
| VBN-3 | A stamp without a build number is a named error | ✅ | Stamp without `buildNumber`. Verify the run fails, `VersionerFileException` names the file, the file is untouched. |
| VSDK-1 | No Dart SDK version: the project fails | ✅ | `test/versioner_dart_sdk_test.dart`: the executor with an SDK reader returning null, real and dry run. Verify failure naming `dart --version` and PATH, no file written. |
| VSDK-2 | An existing stamp stays | ✅ | Stamp with SDK `3.13.7`, run again without an SDK. Verify failure and the file unchanged. |
| VSDK-3 | buildkit with a PATH that has no `dart` | ✅ | Run `bin/buildkit.dart :versioner` with `PATH=/usr/bin:/bin`. Verify a non-zero exit, `dart --version failed (is dart on PATH?)`, no "version file generated", no file. |
| DSV-1..3 | `dart --version` on Windows | ✅ | `test/dart_sdk_version_test.dart`: with a fake process runner, the version is read in a shell on Windows (a `dart.bat` on the PATH) and without one elsewhere; from stdout, stderr or a bare number; a `dart` that cannot start gives no version. |
| VBN-4 | `tom_build_state.json` is neither read nor written | ✅ | A state file with 500 beside no stamp. Verify build 1 and the state file unchanged; without it, none is created. |
| VBN-5 | `nextBuildNumber` reads the configured output file | ✅ | Another path with build 9 gives 10; a missing path gives 1. |

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

**Target plan** — `test/compiler_target_plan_test.dart` (pure; nothing is compiled): which of a section's `targets:` a run
builds, and the named reason for every other one.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| CMP_PLAN01 | A plain run builds the host and names the rest | ✅ | `planTargets` on darwin-arm64 for `[darwin-arm64, linux-x64]`; linux-x64 is not built, with `--all-platforms` in the reason. |
| CMP_PLAN02 | `--all-platforms` builds every listed target | ✅ | Same list with `allPlatforms`; both built. |
| CMP_PLAN03 | A target the host cannot build is a named skip | ✅ | `win32-x64` listed, built from darwin-arm64: in `unbuildable` with the reason. |
| CMP_PLAN04 | `--targets` builds the matching targets only | ✅ | Filter `linux-x64`; darwin-arm64 is not built, reason names `--targets`. |
| CMP_PLAN05 | A host outside the list builds nothing by default | ✅ | win32-x64 host; nothing built, both targets named. |
| CMP_PLAN06 | `--targets` naming an unbuildable target skips it by name | ✅ | win32-x64 requested from linux-x64; in `unbuildable`. |
| CMP_PLAN07 | Cross-compilation reaches Linux only | ✅ | `PlatformUtils.canBuildOn` for host, Linux, Windows and macOS targets. |

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
| VBM_RST01 | A bump leaves the build number alone | ✅ | Run versionbump. Verify `version.versioner.dart` is unchanged and no `tom_build_state.json` is written. |
| VBM_DRY01 | `--dry-run` shows planned bumps without changing files | ✅ | Run with `--dry-run`. Verify pubspec.yaml unchanged and stdout shows planned bump. |

---

## 8. BuildKit — Pipeline Orchestrator

**Test file:** `test/buildkit_test.dart`

Uses workspace-level pipeline configuration from `buildkit_master.yaml`.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BKT_LST01 | `--list` shows available pipelines | ✅ | Run `buildkit --list`. Verify pipeline names from `buildkit_master.yaml` are listed. |
| BKT_HLP01 | `--help` shows usage | ✅ | Run `buildkit --help`. Verify usage text displayed. |
| BKT_HLP03 | `help <command>` | ✅ | `buildkit help compiler`, `help :compiler` and `help comp` print what `buildkit :compiler --help` prints; `help bump` the :bumpversion help; an unknown name fails with `Unknown help topic`. |
| BKT_CMD01 | Direct command execution (`:versioner`) | ✅ | Run `buildkit :versioner --project _build`. Verify versioner executes. |
| BKT_PIP01 | Pipeline execution (`build`, `clean`) | ✅ | Run `buildkit clean --project _build`. Verify pipeline steps execute in order. |
| BKT_DRY01 | `--dry-run` after the pipeline name | ✅ | `buildkit test-simple --project tom_ai/basics/tom_build_kit --dry-run`: an option after a pipeline name counts like one before it (bug #15 fixed); [DRY RUN] markers, no step executed. |
| BKT_DRY02 | `--dry-run` before the pipeline name | ✅ | The same run with the flags first: [PIPELINE:shell] markers, no step executed. |
| BKT_OPT01 | Per-step option suppression (`-s-`) is refused | ✅ | `buildkit --project tom_ai/basics/tom_build_kit --dry-run :versioner -s-` fails with an `Error:` naming `-s-` ("not supported") and does not scan `<root>/-`. |
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
| EXCL_BN05 | Runner excludes by basename | ✅ | `tom_core_kernel` is listed without the exclusion; with `--exclude-projects 'tom_core_kernel'` no `tom_core_kernel` basename. |
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
| EXCL_SF05 | Skip file excludes from runner | ✅ | Place a skip file in a project the runner lists. Verify absent. |
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

### Build Sorter

**Test file:** `test/buildsorter_test.dart`

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-SORT-1 | Dev dependencies do not order by default | ✅ | Two packages, one a dev dependency of the other; `:buildsorter --names` lists them alphabetically. |
| BK-SORT-2 | `--include-dev` after the command orders by dev dependencies | ✅ | Same fixture with `--include-dev`; the dev dependency comes first. |

### Boundaries

**Test file:** `test/boundaries_test.dart` (runs `bin/buildkit.dart` on fixture packages under `.dart_tool`, rooted there with `-R`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-BND-1 | A package that keeps its boundaries exits 0 | ✅ | `:boundaries` in the package; `clean`. |
| BK-BND-2 | A violation exits 1 and names file and line | ✅ | A billing library imports identity's internal library. |
| BK-BND-3 | `--json` | ✅ | One JSON line with the verdict and the violation (file, line, kind). |
| BK-BND-4 | A rotted rule exits 1 | ✅ | A `libraries:` glob that matches nothing. |
| BK-BND-5 | No rules, asked for: NOT MEASURED, exit 1 | ✅ | `:boundaries` inside a package without the section. |
| BK-BND-6 | No rules, met in a traversal: skipped by name | ✅ | A folder with a clean package and one without rules; exit 0. |

### Apidoc

**Test file:** `test/apidoc_test.dart` (BK-APIDOC-1..3 read dartdoc's output; 4..9 run `bin/buildkit.dart` on fixture packages under `.dart_tool`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-APIDOC-1 | Warnings, unresolved references, libraries, undocumented elements | ✅ | dartdoc output and an `index.json` with one element without `desc`. |
| BK-APIDOC-2 | Failures | ✅ | A non-zero exit, dartdoc errors, no public library. |
| BK-APIDOC-3 | Output folder | ✅ | Inside the package, never inside `doc/`, not absolute. |
| BK-APIDOC-4 | Success | ✅ | A package with one unresolved reference: `build/api/index.html` written, no `doc/`, the warning and the result line printed; exit 0. |
| BK-APIDOC-5 | A failing package | ✅ | A package whose `dartdoc_options.yaml` makes the unresolved reference an error: exit 1, its error line printed; the other package is still documented. |
| BK-APIDOC-6 | Refused before dartdoc | ✅ | A package without `package_config.json`; `--output doc/api`. |
| BK-APIDOC-7 | `--dry-run` | ✅ | The `dart doc` call is printed, nothing written. |
| BK-APIDOC-8 | Pipeline step | ✅ | A pipeline with `buildkit :apidoc`, run with this source's buildkit on `PATH`. |
| BK-APIDOC-9 | Relative `--scan`; no `lib/` | ✅ | `-s pkgs` from the fixture root: the docs land in each package's `build/api`; a package without `lib/` is skipped. |

### Apisummary

**Test file:** `test/apisummary_test.dart` (BK-APISUM-1..6 call the check on fixture packages; 7..8 run `bin/buildkit.dart` on them under `.dart_tool`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-APISUM-1 | A complete summary | ✅ | Class, enum, extension, function and constant documented: no finding. |
| BK-APISUM-2 | A missing class | ✅ | The `Base` section removed: `Base` reported (class, its file), its members not one by one. |
| BK-APISUM-3 | Removed member, function, class | ✅ | A `checkout` row, a `closeCart` row and a `### SavedCart` heading: each reported with the summary line. |
| BK-APISUM-4 | Missing member and constant; code span | ✅ | `total` and `maxItems` removed; `` `Cart.discount()` `` in prose names a member that does not exist. |
| BK-APISUM-5 | Supertype and extension sections; inherited members | ✅ | `save` (inherited) and `hashCode` in `Cart`'s table are no stale claims; `CartTools.clear` documented in `Cart`'s table. |
| BK-APISUM-6 | No summary | ✅ | Not measured; the index alone is no summary. |
| BK-APISUM-7 | The command, `--strict` | ✅ | Both directions printed; exit 0 without `--strict`, 1 with it. |
| BK-APISUM-8 | Up to date; not measured | ✅ | `--strict` passes an up-to-date package; a package without a summary is named NOT MEASURED. |

### Apireference

**Test file:** `test/apireference_test.dart` (BK-APIREF-1..3 and 10 collect and assemble; 4..7 and 9 run buildkit (compiled once) with a stand-in md2pdf; 8 with the real tom_md2pdf, compiled from the workspace when its source is there)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-APIREF-1 | Inputs of a documented package | ✅ | Index, summaries in order, guides in `doc/<m>/<m>.md` and `doc/<m>.md`, guide-less modules listed; no `doc/api/` is not documented. |
| BK-APIREF-2 | Missing inputs | ✅ | A summary the index links to is gone; no index and no module summary. |
| BK-APIREF-3 | The assembled document | ✅ | Title and date, parts in order, headlines dropped, headings deeper outside code, link columns removed, links as text, `\|` kept. |
| BK-APIREF-4 | Rendering | ✅ | The PDF and the Markdown in `build/api_reference/`, nothing in `doc/`; guide-less module named. |
| BK-APIREF-5 | A package with missing inputs | ✅ | Fails naming the input; an undocumented package skipped; the complete one rendered. |
| BK-APIREF-6 | md2pdf failing or absent | ✅ | Exit 3 from md2pdf, and an executable that is not there, fail the package. |
| BK-APIREF-7 | `--output` in `doc/`; `--dry-run` | ✅ | Refused; the dry run writes nothing. |
| BK-APIREF-8 | Real tom_md2pdf | ✅ | The output starts with `%PDF-`. |
| BK-APIREF-9 | `--timeout` | ✅ | A stand-in md2pdf that hangs is stopped after 3 s; the package fails, naming the limit; the run ends within 40 s of md2pdf's own start, its process is gone and it never woke up. |
| BK-APIREF-10 | Guides named by the index | ✅ | A guide the index links beside a module summary (Quick Navigation) is that module's guide, before `doc/<module>.md`; a linked guide that is not there is a missing input. |

### Doccheck

**Test file:** `test/doccheck_test.dart` (BK-DOCCHK-1..5 call the check on fixture packages; 6..8 run `bin/buildkit.dart` on them under `.dart_tool`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-DOCCHK-1 | A complete package | ✅ | README with attribution and the four sections, CHANGELOG, example, doc/, guidelines index: no gap. |
| BK-DOCCHK-2 | An incomplete package | ✅ | Every missing document and section named, in check order; no README at all. |
| BK-DOCCHK-3 | Matching | ✅ | Case and hyphens aside, a heading in fenced code and a blockquote after the first section not counted, no guidelines folder needs no index. |
| BK-DOCCHK-4 | Configuration | ✅ | The master's checks and sections, a package's own sections, an exclusion and a skip with their reasons. |
| BK-DOCCHK-5 | Configuration errors | ✅ | An unknown check, an exclusion and a skip without a reason. |
| BK-DOCCHK-6 | The command, `--strict` | ✅ | Gaps per package; exit 0 without `--strict`, 1 with it. |
| BK-DOCCHK-7 | Opted out | ✅ | A skipped package reported with its reason and no gaps; an excluded check named; `--strict` passes. |
| BK-DOCCHK-8 | A configuration error | ✅ | Fails the package without `--strict`. |

### Docsite

**Test file:** `test/docsite_test.dart` (BK-DOCSITE-1..3 read, render and build; 4..5 run `bin/buildkit.dart` on fixture packages under `.dart_tool`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-DOCSITE-1 | A package as the site shows it | ✅ | Name, version, description from the pubspec; API docs and README found or not. |
| BK-DOCSITE-2 | The index | ✅ | Every package with API docs linked to its API docs and README, sorted, HTML escaped; one without API docs named without a link. |
| BK-DOCSITE-3 | Building | ✅ | API docs copied, README rendered, an older site replaced whole. |
| BK-DOCSITE-4 | The command | ✅ | Two packages with API docs and one without: `build/doc_site/index.html` links both, names the third. |
| BK-DOCSITE-5 | `--output` in `doc/`; `--dry-run` | ✅ | Refused; the dry run writes nothing. |

### Changelog draft

**Test file:** `test/changelog_draft_test.dart` (each test builds a git repository under `.dart_tool`; 5..6 run `bin/buildkit.dart` there)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-CLOG-1 | With earlier versions | ✅ | Commits since the 1.1.0 release that touched the package, newest first; another folder's commit left out. |
| BK-CLOG-2 | Without an earlier version change | ✅ | Everything since the package was created; uncommitted changes detected. |
| BK-CLOG-3 | The draft section | ✅ | Version, origin comment, subjects, the uncommitted line; no git history named. |
| BK-CLOG-4 | Inserting | ✅ | Above the newest section, under a title; a section of the version (`## 1.1.1`, `## [1.1.1] - date`, `## 1.1.1 - date`) kept; `1.1.10` is not `1.1.1`; no CHANGELOG created. |
| BK-CLOG-5 | `:bumpversion --changelog` | ✅ | `--dry-run` prints the draft and writes nothing; the run inserts it and bumps the version. |
| BK-CLOG-6 | Existing section kept | ✅ | The hand-written 1.0.1 section unchanged, the version bumped; without `--changelog` nothing drafted. |

### Pub get at once

**Test file:** `test/pubget_parallel_test.dart` (runs `bin/buildkit.dart` on three fixture packages under `.dart_tool`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-PUBJ-1 | At once, output together, timing | ✅ | `:pubget --jobs 3`: every package resolved, each project's pub output and status inside its own block; the summary's Timing section names the step. |
| BK-PUBJ-2 | `--jobs 1` | ✅ | The same blocks one after another. |

### Skipping unchanged projects

**Test file:** `test/incremental_steps_test.dart` (runs `bin/buildkit.dart` on a fixture workspace under `.dart_tool`, a git repository of its own; its compile step appends one line per run to a log beside the projects)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-INC-1 | Unchanged projects skipped | ✅ | A second `:compiler` compiles nothing and reports both projects up to date; `.dart_tool/buildkit/steps.json` holds the step. |
| BK-INC-2 | A changed input runs again | ✅ | A changed source, a changed (gitignored) `pubspec.lock`, a changed path dependency and a new untracked file each make exactly the affected projects compile again. |
| BK-INC-3 | `--force`; failures | ✅ | `--force` compiles both again; a failed compile removes the project's entry, and the next run runs it again. |
| BK-INC-4 | Dry run | ✅ | A dry run records nothing; after a real run it reports the project up to date. |
| BK-INC-5 | `:versioner` | ✅ | A second run writes no new build; `--force` writes one. |
| BK-INC-8 | A later step rewrites an input | ✅ | `:compiler :versioner`: the second run compiles again (the version file changed) and skips the versioner; the third skips both. |
| BK-INC-6 | The project's files | ✅ | In git: tracked and untracked files, not ignored ones or `.dart_tool`; outside git: every file outside `.dart_tool`, `build` and hidden folders. |
| BK-INC-7 | Path dependencies | ✅ | The `source: path` packages of a lock, with absolute paths. |
| BK-INC-9 | Binaries outside the project | ✅ | A `dart compile kernel ... -o ../out/alpha.dill` step: the record `alpha.dill.buildkit.json` and the step's outputs in `steps.json`; up to date while the binary matches; a deleted binary, a replaced binary, a record with another fingerprint and a deleted record each compile `alpha` again (naming why), `beta` stays up to date. |
| BK-OUT-1 | Output paths of compile commands | ✅ | `test/output_records_test.dart`: `-o`, `--output=`, a quoted path; `mkdir`, `cp` and `echo` name none. |
| BK-OUT-2 | The record and the check | ✅ | A written record holds format, version, project, buildkit, fingerprint, time, size; the check names another fingerprint, a replaced binary, an unreadable or missing record and a missing binary. |

### Skipping what another host built

**Test file:** `test/binary_fingerprint_test.dart` (runs `bin/buildkit.dart` on a fixture workspace under `.dart_tool`, a git repository of its own whose `buildkit_master.yaml` names the binaries layer; a second clone of it stands for another host, and the binaries folder is moved before it builds; a fake `d4rtgen` first on the PATH stands for the generator)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-FP-1 | Another clone skips | ✅ | `:versioner :d4rtgen :compiler` in the first clone writes the shared records (`:compiler`'s per platform, with the binary relative to `TOM_BINARY_PATH`; the others for every platform); the second clone compiles nothing, runs no generator, keeps the version file and reports each step `up to date (fingerprint)`; its next run skips by its own `steps.json`. |
| BK-FP-2 | A changed input rebuilds | ✅ | A changed source in the second clone: a new build number, the generator and the compile run; the next run skips `:versioner` (recorded with the project as the run left it). |
| BK-FP-3 | `--force` | ✅ | Runs every step although the shared records match. |
| BK-FP-4 | Without `TOM_BINARY_PATH` | ✅ | Nothing is written to the binaries layer; the second clone runs, and its next run skips by its own record. |
| BK-FP-5 | Outputs relative to their folder | ✅ | An output under the root is kept relative and found there again; one outside stays absolute; a project's label from `-R`. |
| BK-FP-6 | Which workspaces share | ✅ | Only a workspace whose `buildkit_master.yaml` names `required-environment: binaryPath:`; never a project under `.dart_tool` or `ztmp`; a platform's step in `<platform>/.buildkit/steps`, another in `.buildkit/steps`. |

### Build cache

**Test file:** `test/compile_cache_test.dart` (unit tests on a temporary cache folder; BK-CACHE-6 runs `bin/buildkit.dart` on a fixture project under `.dart_tool` with `TOM_BUILDKIT_CACHE_DIR` set, compiling with `dart compile kernel`)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-CACHE-1 | What is cacheable; the key | ✅ | `mkdir` + `dart compile ... -o` is cacheable, any other command or a compile without output is not; the key ignores the output path and changes with inputs, SDK and target. |
| BK-CACHE-2 | Hit | ✅ | A stored compile is copied back, executable; an unknown key copies nothing. |
| BK-CACHE-3 | Miss | ✅ | Another Dart SDK or other inputs (a changed lock) miss. |
| BK-CACHE-4 | Eviction | ✅ | Past the size limit the entry used longest ago is deleted; a restored entry counts as used. |
| BK-CACHE-5 | Folder and limit | ✅ | `~/.tom/cache/buildkit` and 2048 MB by default; `TOM_BUILDKIT_CACHE_DIR`, `TOM_BUILDKIT_CACHE_MAX_MB`. |
| BK-CACHE-6 | `buildkit :compiler` | ✅ | A deleted binary comes back from the cache on `--force`; a changed lock compiles (a second entry); the lock switched back hits; `--force --no-cache` compiles. |
| BK-CACHE-7 | A relative project path | ✅ | A project selected with `-p` from the workspace root compiles with the cache on (the input hash runs before the compile changes into the project). |

### Bootstrap — Shell Setup

**Test file:** `test/bootstrap_binaries_test.dart` (sources `bootstrap_binaries.sh`'s functions in a temporary `HOME`; nothing is built)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-BOOT-1 | zsh users get `~/.zshenv`, bash users `~/.bashrc` | ✅ | `shell_env_files` with `SHELL=/bin/zsh` and `/bin/bash` in an empty `HOME`. |
| BK-BOOT-2 | The block goes above the interactive guard of `~/.bashrc` | ✅ | Write it into a distribution-style `~/.bashrc`; a non-interactive bash sourcing it gets `TOM_BINARY_PATH` and the platform folder first on `PATH`. |
| BK-BOOT-3 | A rerun replaces the block, never adds one | ✅ | Write it three times with two paths; one block, the latest path, the rest of the file intact. |
| BK-BOOT-4 | A non-interactive zsh gets the binaries from `~/.zshenv` | ✅ | `zsh -c` with that `HOME`/`ZDOTDIR` prints the exported values. |

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

## 16. Test Infrastructure — Workspace Clone and Clean Check

**Test files:** `test/workspace_isolation_test.dart`, `test/workspace_cleanliness_test.dart`

The integration suites run on the machine's workspace clone (tom_test_support `TomWorkspaceClone`, taken by `TestWorkspace.isolated()`); see `_agent_guidelines/testing.md`.

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-ISO-1 | The workspace is the clone, outside the live workspace | ✅ | Clone marker present; the root is not inside the live root; `liveRoot` is the live workspace. |
| BK-ISO-2 | Fixtures, skip files and reverts stay in the clone | ✅ | The live `buildkit_master.yaml` is unchanged and no skip file appears in the live tree. |
| BK-ISO-3 | buildkit is not run outside the clone | ✅ | `runTool` with a live `workingDirectory` throws. |
| BK-ISO-4 | A root that is not a clone is never changed | ✅ | Fixture, revert, provisioning, skip file, buildkit and dispose all throw; the file is untouched. |
| BK-ISO-5 | Every suite that holds the clone gives it back in `tearDownAll` | ✅ | Source scan of `test/`. |
| BK-CLEAN-1 | A clean repository has no uncommitted changes | ✅ | Scratch superproject with a submodule. |
| BK-CLEAN-2 | A submodule whose HEAD moved does not make it dirty | ✅ | Commit in the submodule only. |
| BK-CLEAN-3 | A modified tracked file does | ✅ | |
| BK-CLEAN-4 | An untracked file does | ✅ | |
| BK-CLEAN-5 | A modified file inside a submodule does | ✅ | Reported as the submodule's path. |
| BK-CLEAN-6 | An untracked file inside a submodule does | ✅ | |
| BK-CLEAN-7 | A submodule whose only change is that its own submodule moved is not dirty | ✅ | Nested submodule two levels down. |
| BK-CLEAN-8 | A modified file two levels down is | ✅ | Reported as the top submodule's path. |

---

## 16. Build, Test, Clean — Per Nature

**Test file:** `test/project_action_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BK-ACT-1 | Defaults | ✅ | Each language's default build / test / clean step. |
| BK-ACT-2 | buildkit.yaml | ✅ | A command, a list or `false` replaces the default; a map is refused. |
| BK-ACT-3 | Primary nature | ✅ | Dart before the other languages; no nature, no step. |
| BK-ACT-4 | Run / dry run | ✅ | `:test` runs the step in the project; `--dry-run` runs nothing. |
| BK-ACT-5 | Failure | ✅ | A failing command fails the run and is named. |
| BK-ACT-6 | Clean | ✅ | Default paths and globs deleted, sources kept. |
| BK-ACT-7 | Bump | ✅ | `:bumpversion` in package.json, pyproject.toml, Cargo.toml, pom.xml; Go skipped. |

---

## 17. Projects — The Project Listing

**Test file:** `test/projects_command_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BK-PRJ-1 | JSON | ✅ | One document: format version, root, count; each project with identity from `buildkit.yaml`, path, language, type, natures, version; skipped and nested projects left out. |
| BK-PRJ-2 | Selection | ✅ | `-r` lists nested fixtures; `-p` and `--exclude-projects` select as for every project command. |
| BK-PRJ-3 | Table | ✅ | Without `--json`: path, id, natures per line and the count. |
| BK-PRJ-4 | `-R` | ✅ | Run from another directory with `-R` and `-s`, the listing is of that root. |
| BK-PRJ-5 | `--all` | ✅ | The `navigation:` excludes of `buildkit_master.yaml` apply by default and not with `--all`. |
| BK-PRJ-6 | No environment needed | ✅ | A missing `required-environment` entry does not stop `:projects` / `:proj`; it still stops `:versioner`. |

---

## 19. Help Footer

**Test file:** `test/help_footer_test.dart`

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BK-HELPFOOT-1 | Where pipelines live | ✅ | The footer names the top-level `pipelines:` of `buildkit_master.yaml` and no project file. |

---

## 20. Pub Get — Stale Git Refs

**Test file:** `test/pubget_git_ref_test.dart` (local git repositories and a `PUB_CACHE` of its own under `.dart_tool`; runs `bin/buildkit.dart`)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BK-PUBGIT-1 | Retry for an untracked lock | ✅ | A lock pinning a moved git branch that no longer solves is upgraded once (`pub upgrade` of the lock's git packages); the output says so. |
| BK-PUBGIT-2 | Tracked lock left alone | ✅ | A lock git tracks is not upgraded; `:pubget` fails as `pub get` did. |
| BK-PUBGIT-3 | Git packages of a lock | ✅ | `gitPackagesInLock` names the `source: git` packages in the lock's order; none for a missing file. |

---

## 21. Status — Git Mode

**Test file:** `test/status_git_mode_test.dart` (repositories made with `git init` in a temporary folder; the buildkit runner in-process)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BK-STAT-1 | `:status -i` | ✅ | Accepted (git traversal declared); lists the repositories git mode walks, without `ztmp/` and a repository holding `buildkit_skip.yaml`; `--no-skip` lists the marked one. |

---

## 21. wssetup — Tree Setup

**Test file:** `test/wssetup_test.dart` (a fixture of bare local repositories under the system temp folder, `git@fixture:<name>.git` mapped onto them with `insteadOf`; no `.tom`, no `_ai`)

| ID | Feature | Status | Description |
|----|---------|--------|-------------|
| BK-WSS-1 | Whole tree | ✅ | From a root checkout: every entry for this host on its branch, an upstream at its pin, the AI entry and other hosts' / on-demand entries skipped, each parent's ignore block written. |
| BK-WSS-2 | Idempotent | ✅ | A second run clones nothing and writes nothing. |
| BK-WSS-3 | One workspace folder | ✅ | Run in a workspace folder (or `--folder`): only its repositories; the root's block is left alone. |
| BK-WSS-4 | `-n`, `--check` | ✅ | The dry run lists the plan and changes nothing; `--check` clones but reports the blocks. |
| BK-WSS-5 | `--only` | ✅ | An on-demand entry and another host's are cloned when named; an unknown path fails. |
| BK-WSS-6 | Compare, never change | ✅ | Wrong branch, wrong origin and an upstream off its pin are reported `differs`; nothing is changed. |
| BK-WSS-7 | Reduced mode | ✅ | With a root `.gitmodules` no ignore block is written. |
| BK-WSS-8 | Usage errors | ✅ | No `repos.yaml` is a usage error; an invalid one names each problem. |
| BK-WSS-9 | Block format | ✅ | `blockWritten` gives what `tom_repos --apply` writes (new, replaced, removed). |
| BK-WSS-10 | Both entry points | ✅ | `wssetup` and `buildkit :wssetup` run the same; a failing `required-environment` does not stop it. |
| BK-WSS-11 | `--manifest` | ✅ | Reaches wssetup in both tools, before or after the command, also where the git traversal options take it. |

### :ws-push

**Test file:** `test/ws_push_test.dart` (a tree of real repositories with bare remotes, a `repos.yaml` and a fixed host in a temporary folder; faked window heartbeats in a folder of the test; never the live workspace)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-WSP-1 | Clean tree | ✅ | Nothing to do, exit 0; the upstream and an unknown clone are no part of the run. |
| BK-WSP-2 | Commit and push | ✅ | `_ai` first, deeper first, the root last; the default message; after exit 0 nothing uncommitted and every `origin/<branch>` holds HEAD; the committed files listed. |
| BK-WSP-3 | Incoming merge, `-m` | ✅ | Incoming commits merged before the push; `-m` is the commit message. |
| BK-WSP-4 | `ws-conflict` | ✅ | Aborted, nothing pushed for it, the others pushed; options and repeat line; the text block. |
| BK-WSP-5 | `--merge-branch`, `ws-rescue-open` | ✅ | Commits on `ws-push/<host>/<stamp>`, the branch left; the next run warns. |
| BK-WSP-6 | `--ours`, `--theirs` | ✅ | Merged again with that side winning, pushed. |
| BK-WSP-7 | `--leave-conflict`, `--skip` | ✅ | The conflict left in the working tree; the repository left out; exit 1. |
| BK-WSP-8 | `ws-off-branch`, `--push-current` | ✅ | Reported with its options; the current branch pushed. |
| BK-WSP-9 | `--to-branch`, `--set-branch` | ✅ | Merged into the expected branch and pushed; the branch recorded in repos.yaml, the root commits it. |
| BK-WSP-10 | `ws-detached`, `--rescue-detached` | ✅ | A detached HEAD at its branch put back; commits on no branch reported, rescued and pushed. |
| BK-WSP-11 | `ws-secret` | ✅ | Refused before anything changes; `--skip-file` (exit 1), `--allow-file`. |
| BK-WSP-12 | `ws-large` | ✅ | A 51 MB file refused. |
| BK-WSP-13 | `ws-active` | ✅ | A fresh heartbeat sending refuses, listing the window; a stale one is ignored; `--ignore-active`. |
| BK-WSP-14 | `ws-unknown` | ✅ | Skipped and named first, exit 1; `--include-unknown` pushes it. |
| BK-WSP-15 | `ws-binaries` | ✅ | A warning, exit 0, not committed; `--commit-binaries`. |
| BK-WSP-16 | `ws-push-rejected` | ✅ | A remote that refuses the push (pre-receive hook): reported after one more merge, never forced. |
| BK-WSP-17 | `ws-driver` | ✅ | An unregistered driver in a `.gitattributes` refuses the run; no override. |
| BK-WSP-18 | `ws-in-progress` | ✅ | A repository mid-merge refuses the run; `--skip` leaves it out. |
| BK-WSP-19 | `ws-manifest`, usage | ✅ | No repos.yaml and an invalid one refuse; an unknown repository name is a usage error. |
| BK-WSP-20 | `ws-fetch-failed`, `ws-upstream-dirty` | ✅ | An unreachable remote; an upstream with a local change. |
| BK-WSP-21 | `-n` | ✅ | The plan (would commit, would merge, would push), nothing changed. |
| BK-WSP-22 | Help | ✅ | Every option, the steps, the exit codes, examples; a topic per message. |

### :ws-update

**Test file:** `test/ws_update_test.dart` (a tree of real repositories with bare remotes in a temporary folder; the entries' URLs `git@fixture:<name>.git` mapped onto the remotes by an `insteadOf` rule of the test's git configuration; never the live workspace)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-WSU-1 | Behind the remotes | ✅ | Root, `_ai`, code merged, the fork fast-forwarded; every repository at or ahead of `origin/<branch>`; an uncommitted file the merge does not touch stays; nothing pushed; an `insteadOf` rewrite is no changed origin; exit 0. |
| BK-WSU-2 | Root first, missing entries | ✅ | The root's merge brings new entries; repos.yaml read again; a code entry cloned on its branch, an upstream at its pin. |
| BK-WSU-3 | `ws-clone-failed` | ✅ | An entry whose remote does not exist; `--skip <name>` as the repeat line. |
| BK-WSU-4 | Moved entry, `ws-move-blocked` | ✅ | A dirty old checkout blocks the move; clean, it is moved. |
| BK-WSU-5 | Changed origin URL | ✅ | Re-pointed to the URL of repos.yaml. |
| BK-WSU-6 | `ws-held` | ✅ | A file the merge would overwrite holds the repository (files, incoming commits, options, repeat line); a dirty file the merge does not touch goes through. |
| BK-WSU-7 | `--commit-first`, `--stash-merge` | ✅ | Committed with `-m` and merged, not pushed; stashed, merged, the file back unstaged, no stash left. |
| BK-WSU-8 | `ws-conflict`, `--leave-conflict`, `--theirs` | ✅ | Aborted with its options; left in the working tree; merged with the incoming side. |
| BK-WSU-9 | `ws-fork-diverged`, `--merge-fork` | ✅ | A fork with a local commit is not merged; `--merge-fork` merges it. |
| BK-WSU-10 | Changed pin, `ws-upstream-dirty` | ✅ | An upstream put at its new pin; a dirty one left alone. |
| BK-WSU-11 | `tom_binaries` latest wins | ✅ | A conflicting local commit merged with `-X theirs`. |
| BK-WSU-12 | `ws-off-branch`, `--to-branch`, `ws-detached` | ✅ | Off its branch reported; `--to-branch` commits on it, switches back and merges it in, not pushed; commits on no branch reported. |
| BK-WSU-13 | Ignore blocks, `ws-unknown-seen` | ✅ | The root's ignore block written; an unknown clone reported. |
| BK-WSU-14 | Refusals | ✅ | `ws-driver`, `ws-in-progress`, `ws-manifest` refuse before anything changes; exit 2. |
| BK-WSU-15 | `ws-fetch-failed` | ✅ | A remote that cannot be reached. |
| BK-WSU-16 | `-n` | ✅ | The plan (would merge), nothing changed. |
| BK-WSU-17 | Help | ✅ | Every option, the steps, the exit codes, examples; one topic per message, shared ones once. |
| BK-WSU-18 | `--skip`, `--ours`, `--set-branch`, `--rescue-detached` | ✅ | A held repository left out (exit 1); a conflict merged with the local side; the branch recorded in repos.yaml; the detached commits pushed to the rescue branch, the branch itself not. |

### :ws-repo-cleanup

**Test file:** `test/ws_repo_cleanup_test.dart` (a tree of real repositories with bare remotes in a temporary folder, `git@fixture:<name>.git` mapped onto them with `insteadOf`; surplus clones removable, dirty, unpushed, with a stash, holding a clone, holding an entry, and one under `_ai`; never the live workspace)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-WSR-1 | Report only | ✅ | Every surplus clone named with origin, branch, uncommitted files, commits on no remote branch, branches without upstream, stashes, what is inside; options and repeat lines (`--apply`, `--delete`, `--force-remove`, `--skip`, the `:ws-push --include-unknown` alternative); a nest offers no `--force-remove`; nothing changed, nothing under `_ai` named; exit 1. |
| BK-WSR-2 | Only removable clones | ✅ | Warnings only, exit 0. |
| BK-WSR-3 | `--apply` | ✅ | Only the removable clones moved to `ztmp/<yymmdd>_ws_repo_cleanup/<path>`; the others, the entry inside a clone and `_ai` untouched; a second run does not look into `ztmp/` and moves a nest emptied by the first. |
| BK-WSR-4 | `--apply --delete`, `--delete` | ✅ | Only the removable clones deleted, nothing moved. |
| BK-WSR-5 | `--force-remove` | ✅ | A dirty and an unpushed clone moved with their work, also with `--delete`; a nest never. |
| BK-WSR-6 | `-n` | ✅ | The plan (would move), nothing changed. |
| BK-WSR-7 | Target taken | ✅ | A free name (`-2`). |
| BK-WSR-8 | `--skip`, usage, `ws-manifest` | ✅ | A clone left out (exit 1); an unknown name exit 2; no repos.yaml refused. |
| BK-WSR-9 | Help | ✅ | Every option, the steps, the exit codes; a topic per message; the text blocks. |

### :skill-reconcile-code, :skill-status, :skill-dirty-scan

**Test file:** `test/skill_commands_test.dart` (the fleet skills' own fixture, `.claude/skills/_lib/fixtures/make_fixture_repos.sh`, two hosts with shared bare remotes in a temporary folder; its URLs rewritten to `git@fixture:<name>.git` and mapped onto the remotes with `insteadOf`; compared with the skills' scripts on the same tree; skipped without the skills)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-SKS-1 | Status rows | ✅ | On a tree with a stale, a behind and an ahead clone, an upstream off its pin, a missing clone, run branches and an old tree, `--rows` equals `status_probe.sh`; the JSON carries what `test_fleet_status.sh` case 11 checks; messages for off pin, missing, the run branch, the old tree. |
| BK-SKS-2 | `nobranch` | ✅ | A branch origin lacks: the same row as the probe, `skill-no-branch`. |
| BK-SKS-3 | `-n` | ✅ | Nothing fetched. |
| BK-SKD-1 | Scan rows | ✅ | `--rows` equals `tom_dirty_work --scan` (ages aside): groups, fingerprints, a nested clone under its own path, an upstream, a run worktree, the root's own file, `_ai` and the binaries left out, the unknown repository, SCANNED; the JSON and messages. |
| BK-SKD-2 | Fingerprints | ✅ | A group's fingerprint moves with that group only. |
| BK-SKD-3 | `--baseline` | ✅ | The same lines as `tom_dirty_work --baseline`. |
| BK-SKR-1 | converge | ✅ | A local and a remote commit on origin and both hosts; only the changed repository reported. |
| BK-SKR-2 | ask | ✅ | Uncommitted work: exit 3, `skill-decision` with the groups and `--dirty=hold`, nothing changed. |
| BK-SKR-3 | hold | ✅ | The repository the merge would overwrite held, the file kept and not committed; another reconciled; exit 0. |
| BK-SKR-4 | staged | ✅ | A file another session staged stays staged and off origin; the local commit pushed. |
| BK-SKR-5 | `--own-since` | ✅ | The file written after the baseline committed and pushed; the one from before not. |
| BK-SKR-6 | fork | ✅ | Fast-forwarded when behind; diverged fails (exit 1), not merged. |
| BK-SKR-7 | upstream | ✅ | Off its pin: put back. |
| BK-SKR-8 | missing | ✅ | Cloned and reported. |
| BK-SKR-9 | unknown | ✅ | Stops the run (exit 1), nothing touched. |
| BK-SKR-10 | `-n` | ✅ | Nothing taken in or pushed; the plan. |
| BK-SKR-11 | quiet | ✅ | A level host: no change, exit 0. |
| BK-SKR-12 | merge drivers | ✅ | One unregistered: exit 1, named. |
| BK-SKR-13 | conflict, usage | ✅ | Aborted, fails (exit 1); a bad `--dirty` or a missing baseline exit 2. |
| BK-SKR-14 | Help | ✅ | Every option and the exit codes of the three; every message and `skill-json` a topic. |

### The release binaries: :skill-build-binaries, :skill-build-all-binaries, :skill-push-binaries

**Test file:** `test/binaries_test.dart` (a workspace and a tom_binaries clone with a bare remote in a temporary folder; the buildkit subprocess and the self-compile are fakes that write what the real ones write; never the live workspace)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-BIN-1 | The set from both declarations | ✅ | `release: true` flags and the master list summed; an entry in both is one, declared in both; `release: false` and test fixtures left out; projects by folder name or path; external, bundled, short names, platforms. |
| BK-BIN-2 | Problems | ✅ | A missing project and an entry that says nothing of how it is built: `--list` names them (exit 2), the build refuses (`bin-set`). |
| BK-BIN-3 | `--list` | ✅ | Every entry with where it is declared, text and JSON. |
| BK-BIN-4 | `:skill-build-binaries` | ✅ | The generators first, then only the release projects, into `tom/<platform>/`; a non-release binary the run wrote moved to `all/` with its stamp, files from before left alone; buildkit swapped in (`.old`); short names; tom_binaries' status shows only release files; `bin-not-built` names the externals and bundled ones. |
| BK-BIN-5 | `.old` deleted next time | ✅ | The next run deletes what the previous one set aside. |
| BK-BIN-6 | Self-swap of a running executable | ✅ | A running executable replaced twice; the running process goes on; deleted once it has exited. On Windows with a running AOT executable (checked on legiondary01). |
| BK-BIN-7 | `:skill-build-all-binaries` | ✅ | Every project; the non-release binaries only in the ignored `all/<platform>/`; tom_binaries' status without them. |
| BK-BIN-8 | Refusals | ✅ | No clone (`bin-no-clone`), `all/` not ignored (`bin-not-ignored`): nothing built. |
| BK-BIN-9 | Failures | ✅ | A failing step (`bin-build-failed`) and a release binary not written (`bin-missing`): exit 1, the rest in place. |
| BK-BIN-10 | Windows layout | ✅ | `.exe` binaries; a short name is a Git Bash script and a CRLF `.cmd`. |
| BK-BIN-11 | `:skill-push-binaries` | ✅ | Committed by platform, rebased onto another platform's push, this build wins a path both changed, a no-op when level, an unrelated history refused (nothing pushed). |
| BK-BIN-12 | `-n`, help | ✅ | The plan, nothing changed; every option and the exit codes; every message a topic. |

### Help of the workspace and skill commands

**Test file:** `test/ws_help_test.dart` (the help read through the tool as a user runs it)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-WSH-1 | `buildkit --help` | ✅ | Every new command listed with its one line. |
| BK-WSH-2 | Command pages | ✅ | Each `:ws-*` and `:skill-*` page has its steps, every option, the exit codes. |
| BK-WSH-3 | Topics | ✅ | `help ws`, `help ws-options`, `help skill-json` print their contents. |
| BK-WSH-4 | `ws-options` | ✅ | An option is credited only to the commands that accept it (`--merge-branch` not to `:ws-update`); every option a command's messages offer is on the page. |
| BK-WSH-5 | A topic per message | ✅ | Every code of every catalog a report can show has exactly one topic; `help <code>` prints its summary and options. |
| BK-WSH-6 | Footer and block | ✅ | A report's footer names `buildkit help <topic>`, its block the code that is the topic. |

### Git commands on the repository set

**Test file:** `test/git_commands_set_test.dart` (real repositories with bare remotes and a `repos.yaml` in a temporary folder; never the live workspace)

| ID | Feature | Status | How to Test |
|----|---------|--------|-------------|
| BK-GSET-1 | `:gitcommit` stages nothing by itself | ✅ | Without `--only` / `--all` nothing is committed; what is already staged is. |
| BK-GSET-2 | `--only` | ✅ | Exactly the named paths, an untracked one included, the rest left; a path of another repository is not this one's; absolute paths. |
| BK-GSET-3 | `--all` | ✅ | Every change staged first; `--only` with `--all` refused. |
| BK-GSET-4 | `:gitpush` | ✅ | Pushes the checked-out branch, says up to date, reports a rejected push without forcing (the remote unchanged), refuses a detached HEAD. |
| BK-GSET-5 | `:gitstatus --json` | ✅ | Every repository of the set with branch, expected branch and where it comes from, ahead / behind `origin/<expected>`; detached, off branch and off pin as messages; exit 0. |
| BK-GSET-6 | `:gitstatus` text; without repos.yaml | ✅ | One line per repository; without `repos.yaml` the branch checked out is the expected one. |
| BK-GSET-7 | Help | ✅ | `:gitpush` (`gp`), `:gitcommit`'s `--only` / `--all`, `:gitstatus --json`, one topic per `:gitstatus` message. |

