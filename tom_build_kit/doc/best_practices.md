# buildkit and testkit: best practices

How the workspace works with buildkit and testkit day to day: where a change goes, how it is released and reaches the
packages that use it, how builds and test runs are started. The [buildkit user guide](buildkit_user_guide.md), the
[tools user guide](tools_user_guide.md) and testkit's [test tracking guide](../../../devops/tom_test_kit/doc/test_tracking.md)
describe every command and option; this document says which of them to use when. Known failures and their fixes are
in [troubleshooting](troubleshooting.md). Each practice names the command it
uses. Paths such as `_bin/...` are relative to the workspace root (the folder with `buildkit_master.yaml`).

Builds, tests and checks are started by a person, from the cloned repository. Nothing schedules them.

## Contents

- [Shared CLI behaviour goes into tom_build_base first](#shared-cli-behaviour-goes-into-tom_build_base-first)
- [Publish from a staged copy](#publish-from-a-staged-copy)
- [Move the consumer locks after a release](#move-the-consumer-locks-after-a-release)
- [Bump the version, write the version file, refresh the application locks](#bump-the-version-write-the-version-file-refresh-the-application-locks)
- [Pipelines for sequences, direct commands for one step](#pipelines-for-sequences-direct-commands-for-one-step)
- [Project mode in a package, workspace mode for the tree](#project-mode-in-a-package-workspace-mode-for-the-tree)
- [Let buildkit skip what did not change](#let-buildkit-skip-what-did-not-change)
- [A baseline before the change, a tracked run after it](#a-baseline-before-the-change-a-tracked-run-after-it)
- [Build-tool tests run on the workspace clone](#build-tool-tests-run-on-the-workspace-clone)
- [Before calling a change done](#before-calling-a-change-done)

## Shared CLI behaviour goes into tom_build_base first

buildkit, testkit and issuekit are built on tom_build_base: argument parsing, help, project traversal, nature
detection, the run summary, the tool runner. Behaviour every tool shares is implemented and tested there, released,
and only then used by the tools. A tool never carries a temporary copy of it, and a missing API is never bridged with a
`path:` dependency or a `pubspec_overrides.yaml`: the tools take tom_build_base from pub.dev.

1. Change and test it in tom_build_base: `testkit :test` in `tom_ai/basics/tom_build_base`.
2. Release it: [publish from a staged copy](#publish-from-a-staged-copy).
3. Raise the constraint in each tool (`tom_build_base: ^<new version>` in its `pubspec.yaml`), `dart pub get`, and
   [move the consumer locks](#move-the-consumer-locks-after-a-release).
4. Run each tool's suite: `testkit :test` in `tom_ai/basics/tom_build_kit`, `tom_ai/devops/tom_test_kit`,
   `tom_ai/devops/tom_issue_kit`.

Behaviour only buildkit has (its steps, the incremental state, the build cache) stays in tom_build_kit.

## Publish from a staged copy

The workspace takes its own packages by relative path; a package reaches pub.dev from a staged copy in which every
path dependency is written as a version.

```bash
_bin/publishing/publish_staged.sh tom_ai/basics/tom_build_base tom_ai/basics/tom_build_kit
```

- **Commit first.** The copy is staged from `HEAD`; uncommitted changes are not published.
- **Dependency order.** Name the packages so each one's dependencies come before it, and every package it takes by
  path must be on pub.dev at the version its pubspec names.
- **0 warnings.** The script dry-runs each copy and stops at the first warning; a version already on pub.dev is
  skipped.
- **Rate limit.** pub.dev takes at most twelve versions of one package per rolling 24 hours. The script waits it
  out; `python3 _bin/publishing/rate_limit_wait.py <package>` says how long the next version has to wait. Bundle
  changes into fewer releases on a busy day.

`_bin/publishing/README.md` describes the staged copy in full.

## Move the consumer locks after a release

`dart pub get` keeps a lock, so a release reaches the packages that use it only when their locks move:

```bash
python3 _bin/upgrade_consumer_locks.py tom_build_base          # every lock in the workspace
python3 _bin/upgrade_consumer_locks.py tom_build_base --test   # and testkit :test in each moved package
```

- It runs `dart pub upgrade --unlock-transitive <package>` (or `flutter pub upgrade`) where a lock resolves an older
  hosted version, and reports each package as `upgraded`, `held` (a constraint keeps it lower — that package's owner
  raises it) or `failed`.
- If pub.dev does not list the new version yet, it reports the old one as the target: wait a few minutes and run it
  again.
- Commit per repository only the locks whose change moves that package (and what it had to take with it). A lock
  that also moves an unrelated package belongs to whoever changed that package.
- `python3 _bin/check_frozen_locks.py` lists locks still behind a version in the pub cache; tom_build_kit's own suite
  fails on such locks among its neighbours (`test/frozen_lock_guard_test.dart`, FL-2).

## Bump the version, write the version file, refresh the application locks

```bash
buildkit -p tom_build_kit :bumpversion --minor tom_build_kit --changelog   # 1.29.0 -> 1.30.0, CHANGELOG draft
buildkit -p tom_build_kit :versioner                                       # lib/src/version.versioner.dart
```

- `:bumpversion` bumps the patch version of every selected project; `--minor` / `--major` name the projects that bump
  more. `--changelog` drafts the new `## <version>` section from the commits since the last version change — rewrite
  it for the reader before publishing. `--versioner` runs `:versioner` after the bump.
- `:versioner` writes `version.versioner.dart` (version, build number, git commit, Dart SDK); the build number only
  grows. Commit the file with the bump.
- An application package (one with a tracked `bin/*.dart`, or a Flutter app) tracks its `pubspec.lock`, and the lock
  records its path dependencies' versions. After committing a version bump, refresh them and commit the locks it
  names:

```bash
al_the_bear/.claude/skills/tom_app_locks/tom_app_locks.sh --refresh
```

## Pipelines for sequences, direct commands for one step

A **pipeline** is a named sequence of steps in `buildkit_master.yaml`, run by its name without a colon:

```bash
buildkit build          # :pubget :runner :d4rtgen :v :comp over the workspace
buildkit buildupdate    # the same with :pubupdate
```

A **direct command** runs one step (or a few) with a colon:

```bash
buildkit :compiler
buildkit :pubget :versioner
```

- Use a pipeline for a sequence that is run again and again the same way, so everyone runs the same steps in the same
  order. Add a step to the pipeline in `buildkit_master.yaml`, not to a shell alias.
- Use a direct command for the one step a change needs: `:versioner` after a bump, `:compiler` after a change to a
  tool, `:pubget` after a dependency change.
- Preview either with `--dry-run` (`-n`) or `--list` (`-l`, the projects it would visit) before a run that writes.
- A pipeline prints each step's time and the run summary its Timing section, so a slow step is visible.

## Project mode in a package, workspace mode for the tree

- **Project mode** (no traversal option): run in a package folder, buildkit works on that folder and the projects
  below it, in build order — `cd tom_ai/basics/tom_build_kit && buildkit :versioner`.
- **Workspace mode** (`-R`, `-s <path>`, `-i`, `-o`): you choose what is scanned — `buildkit -R :pubgetall` for the
  whole workspace, `buildkit -s tom_ai/devops -r :versioner` for one folder.
- Select projects by name or group rather than by folder when you can: `buildkit -p tom_build_kit :compiler`,
  `buildkit --group basics :pubget` (a group is a git repository, named by its folder, or a folder with a
  `buildkit_group.yaml`). A selector that matches nothing fails the run unless `--allow-empty`.
- `buildkit :projects` lists the projects the tools work on (`--json`, `--all`); folders under a `buildkit_skip.yaml`
  or `tom_skip.yaml` are left out.
- testkit takes the same traversal options: `testkit -s tom_ai/basics -r :test` runs the suites of a folder,
  `testkit -R :report` reports every project's latest results.

## Let buildkit skip what did not change

- `:pubget`, `:pubgetall`, `:pubupdate` and `:pubupdateall` run their projects at once (`--jobs <n>`, default the CPU
  count up to 8). `--jobs 1` when you need the output in order.
- `:compiler`, `:versioner` and `:runner` skip a project whose inputs did not change since the step last succeeded
  there ("up to date"). `--force` runs them anyway — after deleting a binary, or to write a new build number on purpose.
- `:compiler` copies a binary from its build cache (`~/.tom/cache/buildkit/`) when the same inputs were compiled for
  the same target before. `--no-cache` compiles.
- The full `build` pipeline is dominated by build_runner's code generation; the second and later runs skip the
  projects that did not change.

The buildkit user guide's "Run time", "Skipping unchanged projects" and "Build cache" sections describe the details.

## A baseline before the change, a tracked run after it

Run Dart and Flutter tests with testkit, from the package folder, not with `dart test`: testkit records every run in
`testlog/` and compares it with the baseline.

```bash
testkit :baseline                         # before the change, when there is none or the last one is stale
# ... change the code, write the tests ...
testkit :test                             # adds a column to the latest baseline
testkit :basediff                         # what changed since the baseline
testkit :lastdiff                         # what changed since the previous run
testkit :test --failed                    # re-run only what failed
testkit :test --test-args="-N BK-INC"     # arguments for dart test
```

- A test that fails in the full suite and passes alone is not a pass: run it alone to tell load from a real failure
  (`testkit :test --test-args="-N <id>"`), then file it. `testkit :flaky` lists tests whose results change between
  runs.
- A new baseline (`testkit :baseline`) only before a change, never to make a regression disappear.
- Flutter packages run `flutter test` under testkit with the same commands.
- `testkit -R :report` shows the latest state of every project; a project without `testlog/` is reported as not
  measured.

## Build-tool tests run on the workspace clone

Tests of build tools that need a workspace (buildkit, testkit, the generators) never run on the live tree, where other
work is in progress. They take the machine's workspace clone from tom_test_support (`TomWorkspaceClone`, see its
[README](../../tom_test_support/README.md)): `acquire()` locks it and brings every repository to the commit its live
repository has checked out, `release()` resets it.

- A test that needs only a few packages builds them under the package's own `.dart_tool/` and runs the tool rooted
  there (`buildkit -R <fixture> -s <fixture> ...`), so the workspace is not read at all.
- `python3 _bin/check_build_tool_test_roots.py` reports a build-tool test that takes the live root.

## Before calling a change done

```bash
dart analyze                                         # no issue in the changed packages
testkit :test                                        # the suites of the changed packages
python3 _bin/check_doc_links_workspace.py --quiet    # the links of the changed documents resolve
python3 _bin/check_build_cleanup_references.py       # no retired build tool named
```

Then commit the change, [publish](#publish-from-a-staged-copy) when it is to reach other packages, [move the
locks](#move-the-consumer-locks-after-a-release), and rebuild the binaries with `buildkit :compiler` in the tool's
package when it is a command-line tool.
