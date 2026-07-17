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
