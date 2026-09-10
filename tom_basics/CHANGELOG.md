## 3.1.1

- **Fixed: `TomLogOutput.output` declared `origin` as a required positional
  while calling it optional.** The parameter documentation says "Optional
  caller information" and the class's own dartdoc example shows
  `[String? origin,]`, but the abstract declaration required it — so the word
  was true of the value and false of the signature.

  It compiled both ways, which is why it went unnoticed: an override may widen
  a required positional to optional, so implementations across the workspace
  split between the two spellings with nothing in the base class to say which
  was intended. Eleven files used the required form and roughly twice as many
  the optional one.

  `origin` is now optional in the declaration, matching the documentation.
  **An implementation that declared it as a required positional no longer
  compiles** — a required positional cannot override an optional one — and must
  add the brackets. The workspace's ten such implementations were updated with
  this change.

## 3.1.0

- **Added: `TomBaseException.renderStackTrace(stack, depth)`** — the seam that
  lets one renderer serve a whole framework. The constructor now fills
  `stackTrace` through it instead of through a private static, so a subclass
  can supply the rendering.

  It exists because a framework built on this class had two stack-trace
  formatters and no way to reduce them to one. `tom_core_kernel` is the case:
  `TomException.stackTrace` was produced here — core frames folded, each
  remaining frame rendered with `Frame.toString()` — while
  `TomException.printStackTrace()` formatted the same trace with the kernel's
  own function, which folds a wider set and renders a different line. One
  exception, two descriptions of its stack, differing in both which frames
  appeared and how each was written. tom_basics cannot depend on the framework
  above it, so the fix has to be a seam here rather than a shared function
  somewhere; the kernel now overrides `renderStackTrace` with
  `tomGetStackTrace` and the two agree by construction.

  The default is unchanged in what it folds and how it renders. It is
  deliberately narrow: this package sits at the bottom and has no view of what
  counts as noise in the layers above it.

  `renderStackTrace` is called from the constructor body, so an override must
  not read state its own class has not initialised yet. It needs none — the
  stack and the depth are both arguments.

- **Fixed: `printStackTrace(depth)` ignored `depth`.** The parameter was
  documented as limiting how many frames are printed and did nothing at all:
  the method printed the whole stored `stackTrace` whatever it was given.

  It now prints the first `depth` frames, counting from the throw site, so a
  bounded trace keeps the frames nearest the failure. The bound is applied to
  the string already captured at construction rather than by formatting the
  trace again — re-formatting would have to decide what to do about a null
  `stack`, and falling back to `StackTrace.current` there reports the call path
  of the *report*, naming none of the code that failed. A wrong trace is worse
  than no trace, because it looks right.

- **Fixed: a `depth` of 0 meant "every frame".** The renderer's guard read
  `depth > 0 && depth < frames.length`, so zero fell through to the unbounded
  branch — the opposite of what it asks for, and a caller driving the limit
  from configuration had to special-case it. The guard is now `depth >= 0`: a
  non-negative depth is a bound, and *every* negative value is the absence of
  one, so a computed -2 is unbounded like -1. This matches the rule
  `tom_core_kernel` already documents for its own formatter.

## 3.0.0

- **Removed: `TomLogOutput.globalSettingRemoteLogEndpoint`** and the private
  `_defaultRemoteLogEndpoint` behind it. Nothing read either one. A
  workspace-wide search over hand-written Dart found exactly two references: the
  declaration, and a test asserting the default was `/remotelog` — a test of a
  value no code consumed.

  It was vestigial rather than merely unused. Remote logging is configured
  through `TomRemoteLogOutput.remoteEndpoint`, a `TomServerEndpoint` carrying
  the whole URI, so an endpoint *path* setting had nothing left to influence.
  The harm was that it read as configuration: a settable global named
  `globalSettingRemoteLogEndpoint` invites a caller to set it and expect remote
  logging to change destination, which it never did, and nothing reported that.

  Breaking only in the semver sense — the field was reachable, so removing it is
  a major change; but no caller can have depended on its *effect*, because it
  had none. A consumer that set it should delete the line and set
  `TomRemoteLogOutput.remoteEndpoint` instead.

## 2.0.1

- **Every exception key this package shows follows the framework convention.**
  The keys were `UPPER_SNAKE` — `USER_NOT_FOUND`, `VALIDATION_ERROR`, `BOOM` —
  while `tom_core_kernel`, which derives `TomException` from the class declared
  here, uses dotted lowercase `<area>.<operation>.<condition>` and lists
  `USER_NOT_FOUND` explicitly as a form to avoid. So the base class taught one
  convention and the derived class taught the opposite, and a reader met
  whichever came first.

  Documentation only: this package raises no exception of its own, so all 18
  literals were dartdoc examples, README samples, tests or sample apps. Nothing
  a consumer switches on has changed.

  `TomBaseException.key`'s own dartdoc now states the shape — the field is
  declared here, so the contract for its values belongs here — and names
  `tom_core_kernel` as where the convention is set out in full rather than
  restating the reasoning. The README says the same where it introduces the
  key.

## 2.0.0

- **Breaking: `TomBaseException.stack` is `StackTrace?`, not `Object?`.** The
  field promised a width the very next line refused: the constructor hands it
  straight to `_getStackTrace`, which opened `s as StackTrace?` — an unchecked
  downcast throwing `TypeError` for any non-null value that was not a trace. So
  a value the field's type invited could only ever fail, and fail *while
  reporting some other failure*, which is the one path where a thrown error
  costs the most: the report dies and the original error goes unrecorded.

  `_getStackTrace`'s parameter narrows with it and the cast is gone. Rejecting a
  wrong argument at compile time costs a caller nothing; the cast cost them the
  failure they were trying to report.

  **Major rather than minor**, though nothing in the Tom framework can observe
  the difference. Every exception in `tom_core_kernel` and `tom_core_server`
  reaches this class by forwarding `super.stack` from a constructor that already
  declared `StackTrace?`, so the wide field was unreachable through any of them
  and the cast never fired. The break is real only for code that constructs
  `TomBaseException` directly with a non-trace, assigns one to `.stack` after
  construction, or overrides the field — and a caller pinned to `^1.0.3` is not
  moved onto this release, which is what the major bump is for.

## 1.0.3

- **Fixed `TomRuntime.setCurrentEnvironment` to apply its fallback
  unconditionally (RCL1).** The fallback branches were guarded by
  `_currentEnvironment == null`, so once a current environment was set, calling
  the setter with an unregistered name silently kept the *old* environment
  instead of switching to the fallback — a setter that refuses to set. The
  fallback (`defaultRoot`, a named environment, or the root) now applies
  whether or not a current environment is already active, and the named-fallback
  branch returns instead of falling through to the root. No back-compat shim.

## 1.0.2

- **Added `TomRuntime.reset()` to clear the process-global environment/platform
  registries (RCL1).** The environment and platform registries are static
  process-global state. A real application registers each environment once at
  startup, but independent units of work that each build their own runtime —
  most visibly tests and runnable samples executed in one process — would
  otherwise inherit registrations from a previously executed unit. A second
  `addEnvironment('dev', ...)` then leaves two `dev` entries and
  `setCurrentEnvironment('dev')` resolves the *earlier* one, running the wrong
  initializer. `reset()` clears the environment and platform lists, drops the
  active environment/platform selections, and restores the root environment to
  `defaultTomEnvironment`. It mirrors `TomBean.resetBeanContext` for the bean
  registry; call it between independent units to isolate them.

## 1.0.1

- **Fixed `TomLogger` push/pop log-level stack to proper LIFO semantics (RCE6).**
  `popLogLevel()` previously removed the *front* of the level stack
  (`removeAt(0)`) rather than the most recently pushed level, so it could not
  restore the pre-push level; and the current level was tracked in a separate
  `_logLevel` field that could diverge from the stack. The stack top is now the
  single source of truth: `logLevel` is a getter returning `_levelStack.last`,
  `setLogLevel` replaces the top in place, `pushLogLevel` appends, and
  `popLogLevel` uses `removeLast()` (guarded so the base level is never popped).
  `setLogLevelByName('info'); pushLogLevel(trace); popLogLevel()` now correctly
  restores `info`, and nested push/pop unwinds in LIFO order. No back-compat
  shim — the buggy front-removal behaviour is gone.

## 1.0.0

- Initial version.
