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
