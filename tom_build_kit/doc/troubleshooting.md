# buildkit and testkit: troubleshooting

The failures people run into with buildkit and testkit, one entry per symptom: **what you see**, **why**, and the
**command** that checks or fixes it. For how the tools are meant to be used, see the
[best practices](best_practices.md); every option is in the [buildkit user guide](buildkit_user_guide.md), the
[tools user guide](tools_user_guide.md) and testkit's [test tracking guide](../../../devops/tom_test_kit/doc/test_tracking.md).
Paths such as `_bin/...` are relative to the workspace root (the folder with `buildkit_master.yaml`).

## Contents

Resolving and publishing:

- [`Undefined name` for a symbol the dependency has](#undefined-name-for-a-symbol-the-dependency-has)
- [pub does not see a version you just published](#pub-does-not-see-a-version-you-just-published)
- [A lock stays behind a published version](#a-lock-stays-behind-a-published-version)
- [`publish_staged.sh` waits for hours](#publish_stagedsh-waits-for-hours)

Running buildkit:

- [`Installation requirements not met` for a folder that is a link](#installation-requirements-not-met-for-a-folder-that-is-a-link)
- [`binary <tool> not found` for a nested command](#binary-tool-not-found-for-a-nested-command)
- [`selector matched no project`](#selector-matched-no-project)
- [A step says `up to date` and does nothing](#a-step-says-up-to-date-and-does-nothing)
- [`compile skipped as configured in buildkit.yaml`](#compile-skipped-as-configured-in-buildkityaml)
- [`Unknown help topic: <command>`](#unknown-help-topic-command)

Tests and checks:

- [`NOT MEASURED`, or a project reported as not measured](#not-measured-or-a-project-reported-as-not-measured)
- [testkit records `--` for a test that passes](#testkit-records----for-a-test-that-passes)
- [A test times out or fails in the full suite and passes alone](#a-test-times-out-or-fails-in-the-full-suite-and-passes-alone)
- [`testkit :test` refuses to run](#testkit-test-refuses-to-run)

---

## `Undefined name` for a symbol the dependency has

**What you see:** `Error: Undefined name '<Symbol>'` at every use of a symbol you can find in the dependency's source;
when compiling, `AOT compilation failed` or `Bad state: Generating AOT kernel dill failed!`. `dart pub get` reports
success.

**Why:** the pub cache lost the package's files. Either its directory is gone, or it is there but empty or without
`pubspec.yaml` — pub counts an existing directory as installed, so `dart pub get` walks past it. Nothing in the error
mentions the cache; it reads like an API renamed upstream. (A stale `.dart_tool/package_config.json` pointing at an
older resolution gives the same message; `dart pub get` fixes that one.)

**Check:**

```bash
_bin/check_pub_cache.sh                # damaged package directories in the cache
python3 _bin/check_package_configs.py  # projects whose package config names a directory that is gone
```

`testkit :test` / `:baseline` and `buildkit :compiler` check the project's lock against the cache before they start
and name the package they cannot find.

**Fix:** delete the damaged directory, then resolve again:

```bash
rm -rf ~/.pub-cache/hosted/pub.dev/<package>-<version>
dart pub get
```

`dart pub cache repair --all` does the same for every package, much slower.

## pub does not see a version you just published

**What you see:** right after a publish, `dart pub get` with the new constraint fails with `Consider downgrading your
constraint on <package>`, or `python3 _bin/upgrade_consumer_locks.py <package>` moves locks to the previous version.

**Why:** pub keeps the version list of each package for a while (`~/.pub-cache/hosted/pub.dev/.cache/<package>-versions.json`),
and pub.dev's listing can lag the upload by a few minutes.

**Check:** what pub.dev lists now:

```bash
curl -s https://pub.dev/api/packages/<package> | python3 -c "import json,sys; print(json.load(sys.stdin)['latest']['version'])"
```

**Fix:** when pub.dev lists the version, drop the cached list and resolve again:

```bash
rm -f ~/.pub-cache/hosted/pub.dev/.cache/<package>-versions.json
dart pub get
python3 _bin/upgrade_consumer_locks.py <package>
```

## A lock stays behind a published version

**What you see:** a package still resolves an older version of a workspace package after its release; a frozen-lock
test (tom_build_kit's `test/frozen_lock_guard_test.dart`, FL-2) fails with `<pkg> locks <dep> <old> while <new> is
already in the pub cache`.

**Why:** `dart pub get` keeps a lock. A release reaches the packages that use it only when their locks are upgraded.

**Check:**

```bash
python3 _bin/check_frozen_locks.py     # locks behind a version that is already in the pub cache
```

**Fix:** move every lock that resolves the package, and commit the moved locks:

```bash
python3 _bin/upgrade_consumer_locks.py <package>         # add --test to run each moved package's suite
```

A package it reports as `held` has a constraint that keeps it lower: raise the constraint in that package, or leave
it to that package's owner.

## `publish_staged.sh` waits for hours

**What you see:** `_bin/publishing/publish_staged.sh <pkg-dir>` stops after the dry run and sleeps.

**Why:** pub.dev takes at most twelve versions of one package in a rolling 24 hours. The script waits until the oldest
of the last twelve is a day old, then publishes.

**Check:**

```bash
python3 _bin/publishing/rate_limit_wait.py <package>     # seconds until the next version can go out
```

**Fix:** let it wait (it publishes on its own), or stop it and bundle the next changes into one release.

## `Installation requirements not met` for a folder that is a link

**What you see:** every command stops with `Installation requirements not met`, naming a required folder (the
`folders:` of `required-environment` in `buildkit_master.yaml`, e.g. `Workspace root symlink doesn't exist` for
`$HOME/tac`), followed by `(<path> is a link to <target>, ... cannot be followed ...)`.

**Why:** the folder is a link, and the link cannot be followed: its target is gone, or (on Windows) the link itself is
one Windows cannot read. A junction made by Git Bash (MSYS) can hold its target with forward slashes or without the
`\??\` prefix; Windows, `cmd` and Dart do not follow it, while PowerShell's `Test-Path` and .NET's
`Directory.Exists`, which look only at the link, say it is there.

**Fix:** recreate the link with the command the message names:

```text
rmdir "C:\Users\<you>\tac" && mklink /J "C:\Users\<you>\tac" "C:\Code\...\tom_agent_container"   (Windows, cmd)
ln -sfn <target> ~/tac                                                                 (macOS, Linux)
```

On Windows make links with `mklink /J`, `New-Item -ItemType SymbolicLink`, or in Git Bash with
`MSYS=winsymlinks:nativestrict ln -s ...`; never with a plain Git Bash `ln -s`.

## `binary <tool> not found` for a nested command

**What you see:** `Warning: :d4rtgen — binary d4rtgen not found` at the start of a run, or a nested command shown as
`[binary astgen not found]` in the help; the command fails when it is run.

**Why:** some buildkit commands are other tools (`nested_tools:` in `buildkit_master.yaml`: d4rtgen, astgen,
testkit, issuekit, reflectiongenerator, reflector, ...). buildkit looks for them on `PATH`; the binaries live in
`$TOM_BINARY_PATH/<platform>/` (e.g. `darwin-arm64`), which the shell setup puts on `PATH`.

**Check:**

```bash
command -v d4rtgen
echo "$TOM_BINARY_PATH"; ls "$TOM_BINARY_PATH/darwin-arm64"
```

**Fix:** put the platform folder on `PATH` with `tom_ai/basics/tom_build_kit/bootstrap_binaries.sh --setup-shell`
(`bootstrap_binaries.ps1` on Windows) and open a new shell; if the binary is missing from the folder, build it in its
package (`buildkit -p tom_d4rt_generator :compiler`).

## `selector matched no project`

**What you see:** `Error: --group selector matched no project: '<name>' (scanned <path>; groups are git repositories
and buildkit_group.yaml directories)`, or the same for `--project`; the run exits 1.

**Why:** the selector names nothing in the scanned tree: a project name that is not a pubspec `name` or `project_id`,
a group that is not a git repository's folder name or a `buildkit_group.yaml` directory, a scan root that does not
contain it, or a folder under `buildkit_skip.yaml` / `tom_skip.yaml`.

**Check:** what the selection would visit, and the projects there are:

```bash
buildkit --group basics --list :pubget
buildkit :projects --all
```

**Fix:** correct the name (the group of `tom_ai/basics` is `basics`), widen the scan (`-R` for the whole workspace),
or pass `--allow-empty` when matching nothing is expected (a script over optional projects).

## A step says `up to date` and does nothing

**What you see:** `<project>: :compiler up to date (inputs unchanged; --force runs it)`; the summary counts the project
as skipped.

**Why:** `:compiler`, `:versioner`, `:runner` and the generators (`:d4rtgen`, `:reflectiongenerator`, `:reflector`)
skip a project whose files, lock, path dependencies and step configuration did not change since the step last
succeeded there (recorded in `.dart_tool/buildkit/steps.json`). `up to date (fingerprint)` says the step succeeded
with these inputs on another host or in another clone: its record is in the binaries layer,
`$TOM_BINARY_PATH/.buildkit/steps/` (`:compiler`: `$TOM_BINARY_PATH/<platform>/.buildkit/steps/`;
buildkit_user_guide.md, "Skipping what another host built").

**Fix:**

```bash
buildkit :compiler --force              # run it anyway (a binary may come from the build cache)
buildkit :compiler --force --no-cache   # and compile instead of copying from the cache
```

## `compile skipped as configured in buildkit.yaml`

**What you see:** `:compiler` reports the project as skipped, for example tom_build_kit itself.

**Why:** the project sets `compiler: skip-compile-with-buildkit: true`, because a running buildkit cannot overwrite its
own binary on Windows; such a tool is built by its bootstrap script.

**Fix:** build it with the bootstrap script, or compile it directly from its package:

```bash
tom_ai/basics/tom_build_kit/bootstrap_binaries.sh
dart compile exe bin/buildkit.dart -o "$TOM_BINARY_PATH/darwin-arm64/buildkit"
```

## `Unknown help topic: <command>`

**What you see:** `buildkit help compiler` or `testkit help report` prints `Unknown help topic: compiler`.

**Why:** `help <name>` looks up help topics (and wired nested tools), not the tool's own commands.

**Fix:** ask the command itself:

```bash
buildkit :compiler --help
testkit :report --help
```

## `NOT MEASURED`, or a project reported as not measured

**What you see:** a workspace check ends with `NOT MEASURED` and exit code 2; `testkit :report` lists a project as not
measured; `testkit :mutations` says `NOT MEASURED: no mutation ran`.

**Why:** the tool could not look, which is never the same as clean: its input is missing (no `testlog/` in the
project, no version of the package on pub.dev or in the cache), or it read fewer files than it must (run from the wrong
folder, submodules not checked out).

**Check / fix:** read the line after `NOT MEASURED`, which names what was missing, then supply it:

```bash
testkit :baseline                           # a project without testlog/: record its first run
git submodule update --init --recursive     # a check that read too few files
python3 _bin/check_doc_links_workspace.py   # run checks from the workspace root
```

## testkit records `--` for a test that passes

**What you see:** in the tracking file (`testlog/baseline_*.csv`) or in `testkit :lastdiff`, a test shows `--` (not
present in this run) although it runs and passes.

**Why:** `--` means testkit read no result for that row in that run:

- the run covered only some tests (`--test-args="-N ..."`, `:test --failed`, `--mismatched`), so the others are `--`;
- the test was renamed: its new description is a new row, the old row shows `--` from then on;
- before testkit 1.9.2, a test that printed text without a trailing newline hid the next test's result, and before
  1.9.0 two tests with the same name shared one row.

**Check:**

```bash
testkit --version                  # 1.9.2 or later
testkit :history "<test name>"     # every result of the test across runs
```

**Fix:** run the whole suite (`testkit :test` without filters); for a renamed test, start a new baseline before the
next change (`testkit :baseline`).

## A test times out or fails in the full suite and passes alone

**What you see:** `TimeoutException`, or a duration bound such as `Expected: a value less than <0:00:50>`, fails in a
full `testkit :test` and passes when the test runs alone.

**Why:** the full suite runs test files in parallel, and many tests start processes (`dart run bin/buildkit.dart`,
external tools); on a loaded machine they take several times longer than alone. A test whose bound includes that start
time fails under load without a defect in the code.

**Check:** the machine's load, then the test alone:

```bash
uptime
testkit :test --test-args="-N '<test id>'"
```

**Fix:** if it passes alone, the failure is load: record it for the test's package (the test should bound what it is
about, not the process start) and re-run when the machine is quieter. A test that also fails alone is a real failure.

## `testkit :test` refuses to run

**What you see:** `[<project>] No tracking file found. Run :baseline first, or use --baseline to create one.`

**Why:** `:test` adds a column to the latest baseline in `testlog/`; a project without one has nothing to add to.

**Fix:**

```bash
testkit :baseline                  # or: testkit :test --baseline (creates one when missing)
```
