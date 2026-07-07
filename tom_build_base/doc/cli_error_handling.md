# CLI Error Handling and Exit Codes

This document defines the **shared error-handling and exit-code contract** for
every Tom CLI tool built on `tom_build_base` (`buildkit`, `testkit`,
`issuekit`, and future tools). It exists so equivalent failure scenarios map to
the same result handling, error messages read consistently, and automation can
rely on stable exit-code semantics.

## Related Documentation

- [CLI Tools and Workspace Navigation](cli_tools_navigation.md) — Shared navigation options
- [CLI Output Formats](cli_output_formats.md) — Shared output-format contract
- [Build Base User Guide](build_base_user_guide.md) — Implementing tools with `tom_build_base`

## Result model

All command execution flows through the shared v2 framework and produces a
`ToolResult` (`lib/src/v2/core/tool_runner.dart`):

- **`ToolResult.success`** — the single source of truth for whether the run
  succeeded. A run is successful when no processed item failed.
- **`ItemResult`** — per-item (per-project/folder) outcome, carrying `success`,
  `skipped`, `message`, and `error`. Deliberately skipped items stay
  `success: true` so they never affect the exit code.
- **`ToolResult.renderRunSummary()`** — the shared end-of-run block every tool
  prints. It lists deliberately **Skipped** items, then either an **Errors**
  section naming each failed item with an `N error(s) in M project(s).` tally,
  or the single line `Done. No errors.`. It returns an empty string for
  single-shot commands that traverse nothing (`--version`, `--help`), so callers
  print it unconditionally.

There are **no legacy (pre-v2) execution paths** in the core tools; every tool
constructs a `ToolRunner`, calls `run()`, and consumes the returned
`ToolResult`. Error taxonomy and per-item reporting are therefore uniform by
construction.

## Exit-code semantics

| Code | Meaning |
| ---- | ------- |
| `0` | Success — `ToolResult.success == true` (including runs whose only non-processed items were deliberately skipped). |
| `1` | Failure — any processed item failed, or a pre-flight/validation error prevented execution (e.g. argument/traversal/execution/partial failures, missing configuration). |
| `255` | Uncaught exception escaped `main` (Dart's default). Tools do not mask these; a stack trace on stderr indicates a defect, not an expected failure mode. |

Automation should treat **`0` as success and any non-zero as failure**, and may
distinguish an expected failure (`1`) from a crash (`255`).

## Entrypoint contract

Every tool's `main` / CLI flow MUST:

1. Run the flow inside `runWithConsoleMarkdown()` so help/version/output render
   consistently (the TUI is the deliberate exception — it renders its own frames
   and runs outside the zone).
2. After `runner.run(args)`, print `result.renderRunSummary()` when non-empty.
3. **Set `exitCode = 1` on failure and return — never call `exit(1)`.**
   A bare `exit()` terminates the VM immediately and can drop buffered stdout
   (including the run summary just written), and diverges from the other tools.
   Setting `exitCode` lets `main` return and the VM drain its output first.

Tool-specific pre-flight errors (e.g. issuekit's missing-GitHub-token check)
are written to **stderr** with an actionable `Error: <what> … <how to fix>`
message, then `exitCode = 1; return` — before any network/config work that would
otherwise fail less clearly.

## Rationale

Prior to this contract, `buildkit` hard-exited with `exit(1)` while `testkit`
and `issuekit` set `exitCode`. Both produced exit code 1, but the hard exit was
(a) inconsistent and (b) able to truncate the final summary line under the
output-buffering zone. Aligning all three on `exitCode = 1; return` makes
failure semantics identical and flush-safe.

A future base-first refactor may fold the "run → print summary → set exitCode"
tail into a single shared `ToolRunner` helper so entrypoints cannot drift again
— tracked as quest todo **AF1** in
`_ai/quests/cli_tools/todos.cli_tools.todo.yaml`.
