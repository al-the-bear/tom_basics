# CLI Output Formats

This document defines the **canonical output-format contract** shared by all
Tom CLI tools (`buildkit`, `testkit`, `issuekit`, and future tools built on
`tom_build_base`). It specifies the supported formats, the `<format>:<file>`
redirection syntax, the shared defaults, and the **intentional** per-tool
surface differences.

## Related Documentation

- [CLI Tools and Workspace Navigation](cli_tools_navigation.md) — Shared navigation options
- [Build Base User Guide](build_base_user_guide.md) — Implementing tools with `tom_build_base`

## Supported formats

| Name | Aliases | Meaning |
| ---- | ------- | ------- |
| `plain` | `text` | Human-readable text (aligned columns / summaries). **Default.** |
| `csv` | — | Comma-separated values (RFC-4180 quoting). |
| `json` | — | Pretty-printed JSON (2-space indent). |
| `md` | `markdown` | GitHub-flavoured Markdown table. |

Format names are **case-insensitive** (`JSON`, `Md`, `Text` all parse). Any
other value is rejected (the parser returns `null`, and the tool reports an
argument error). Every tool that accepts a `--output` / `--format` option MUST
honour these names and aliases so scripts can pass the same value to any tool.

## Redirection syntax: `<format>:<file>`

The output option accepts either a bare format or a `format:file` pair:

- `plain` — plain text to **stdout** (the default).
- `csv:results.csv` — CSV written to `results.csv`.
- `json` — JSON to stdout.
- `md:report.md` — Markdown written to `report.md`.

**Colon rule (Windows-safe):** the format is everything **before the first
colon**; the file path is everything **after** it. This keeps drive-qualified
Windows paths intact — `json:C:\out\report.json` parses as format `json`, file
`C:\out\report.json`. A trailing empty path (`csv:`) means "format only,
stdout". Implementations MUST split on the first colon only.

## Shared defaults

- **Default format is `plain`.** A tool invoked without an output option emits
  human-readable text to stdout.
- **Default destination is stdout.** A file is written only when a `:file`
  suffix is supplied.
- **Structured output is stable.** `csv`/`json`/`md` are intended for
  automation: column/field names and ordering are part of the contract for a
  given command and should not change gratuitously between releases.

## Intentional per-tool differences

The tools deliberately expose the contract through different option surfaces;
these differences are **intentional**, not accidental drift:

| Tool | Option surface | Notes |
| ---- | -------------- | ----- |
| `buildkit` | `--json` (boolean flag) | Shorthand for `json` on commands whose primary machine-readable form is JSON. Equivalent to `--output=json` on tools that offer the full option. |
| `testkit` | `--output` / `--format` (`<format>[:<file>]`) | Diff/history/table commands support the full format set. |
| `issuekit` | `--output` (`<format>[:<file>]`) | List/summary/export commands support the full format set; `:export` requires a non-plain format. |

`buildkit`'s boolean `--json` is a convenience shorthand: buildkit's commands
are pipeline/traversal oriented and expose a single "machine-readable vs human"
switch rather than the four-way format selector. Tools that render tabular
results (`testkit`, `issuekit`) expose the full `--output` selector because
CSV/Markdown are meaningful there.

## Implementation status

The format enum and the `<format>:<file>` parser are currently **implemented
independently** in `testkit` and `issuekit`
(`lib/src/util/output_formatter.dart` in each). They are behaviourally aligned
to this contract (including the `text`/`markdown` aliases and the first-colon
split rule). Consolidating them into a single shared
`OutputFormat` / `OutputSpec` in `tom_build_base` (base-first, published, then
consumed) is tracked as quest todo **AE1** — see
`_ai/quests/cli_tools/todos.cli_tools.todo.yaml`. Until then, this document is
the authoritative contract that both implementations conform to.
