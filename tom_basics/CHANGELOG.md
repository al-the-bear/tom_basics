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
