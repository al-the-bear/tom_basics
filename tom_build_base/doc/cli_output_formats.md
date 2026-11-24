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

## Run reports and their messages

A command that ends with one report (buildkit's `:ws-*` and `:skill-*`) builds it with `RunReport`
(`lib/src/v2/report/run_report.dart`). It defines each of its messages once, as a `MessageDefinition`, and gets
from it the text, the JSON, the command line to repeat and the help topic:

```dart
const conflict = MessageDefinition(
  code: 'ws-conflict',              // the help topic: `buildkit help ws-conflict`
  level: MessageLevel.error,        // refusal (exit 2), error (exit 1), warning, note
  label: 'CONFLICT',
  summary: 'The merge of origin/<branch> conflicts.',
  description: 'Why it matters and what to do, at length.',
  options: [
    MessageOption('merge-branch', 'Push your commits to ws-push/<host>/<stamp>.\nMerge the branch later.'),
    MessageOption('skip', 'Leave the repository out of this run (exit 1).'),
    // run options and value options:
    // MessageOption('ignore-active', '...', repoList: false),
    // MessageOption('skip-file', '...', repoList: false, valueName: 'glob'),
  ],
);
final catalog = MessageCatalog([conflict, ...]);   // catalog.helpTopics -> ToolDefinition(helpTopics:)
```

A run raises messages and records what changed:

```dart
final report = RunReport(tool: 'buildkit', command: ':ws-push', root: root, host: host,
    started: DateTime.now(), given: args, names: RepoNames(paths))
  ..lookedAt.addAll(paths)
  ..add(conflict.raise(repository: 'tom_ai/core', branch: 'main',
      finding: 'Your 2 local commits and 3 incoming commits change the same lines:',
      evidence: [ReportEvidence('files', ['lib/src/config.dart  both changed'])],
      state: 'Nothing was pushed for this repository.'))
  ..changed(ReportDone('_ai', ['committed 2 files', 'pushed'], files: [...]));
print(json ? report.renderJson() : report.renderText(verbose: verbose));
exitCode = report.exitCode;
```

- **The text** (`renderText`): the header (command, root, host, start time, options given), the summary line with
  the exit code, then *Refused*, *Needs you*, *Warnings* and *Notes*, one block per message, *Done* (one line per
  changed repository with its first 20 files; the others counted; `verbose` lists them and every file), and the
  footer explaining the exit code and naming `<tool> help <topic>`. A block: the label, the repository and branch,
  the code on the right; the finding, the evidence (indented, or after a label such as `Local:`), the state, every
  option with its one or two explanation lines (a raised message may replace an option's explanation, to name the
  branch or the stamp, or offer only some options), and `Repeat with:` the command line of the first option.
- **The JSON** (`toJson` / `renderJson`): `command`, `root`, `host`, `started`, `options`, `exitCode`, `summary`
  (`repositories`, `changed`, `needsYou`, `warnings`, `refused`), `messages` (each `code`, `level`, `repository`
  `{name, path}`, `branch`, `finding`, `evidence` by kind, `state`, `options` `[{option, explanation,
  commandLine}]`), `done`, `unchanged`.
- **The command line to repeat** (`RepeatCommand`): the run's arguments as typed plus the chosen option; a
  repository-list option already given takes the repository added to its list (`--skip a` + `b` gives
  `--skip a,b`); arguments are shell-quoted where needed.
- **Repository names** (`RepoNames`): the last path segment when it is unique in the set, else the path from the
  root (`.` for the root). `resolve('core,basics')` throws `RepoNameException` for an unknown name (naming the
  repositories whose path contains it) or an ambiguous one (naming each repository it could mean): a usage error,
  exit 2. `RepoSelections.parse(args, options, names)` gives the repositories each option names; an option acts
  only on those (`applies(option, path)`).
- **Exit codes** (`ReportExitCode`): 0 nothing needs you, 1 something needs you, 2 refused before anything changed
  (and usage errors), 3 a decision about uncommitted work is open (`MessageDefinition(exitCode: 3)`). A report ends
  with the highest of its messages'.
- **Help topics** (`MessageCatalog.helpTopics`): one per code, built from the definition (label, summary,
  description, where it is listed and its exit code, every option with its syntax and explanation), so the text,
  the options and the topic come from one place.
