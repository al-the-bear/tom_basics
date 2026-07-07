# CLI Shell Completion

Every Tom CLI tool built on `tom_build_base` (`buildkit`, `testkit`,
`issuekit`, and future tools) can emit a **shell completion script** for bash,
zsh, or fish, generated directly from the tool's own command and option
definitions. Because the scripts are generated from the live `ToolDefinition`,
completions stay in sync with the tool as commands and options evolve — there
is no separately-maintained completion file to drift.

## Related Documentation

- [CLI Tools and Workspace Navigation](cli_tools_navigation.md) — Shared navigation options
- [CLI Output Formats](cli_output_formats.md) — Shared output-format contract
- [CLI Error Handling and Exit Codes](cli_error_handling.md) — Shared error/exit-code contract
- [Build Base User Guide](build_base_user_guide.md) — Implementing tools with `tom_build_base`

## The `--completion` option

Every tool accepts a global `--completion <shell>` option:

```bash
<tool> --completion bash      # print a bash completion script to stdout
<tool> --completion zsh       # print a zsh completion script
<tool> --completion fish      # print a fish completion script
```

- `<shell>` must be one of `bash`, `zsh`, `fish`. Any other value prints an
  error to stdout and exits non-zero (see
  [CLI Error Handling](cli_error_handling.md)).
- The script is written to **stdout only** — nothing is installed. You redirect
  it to the location your shell expects (below).
- It is a single-shot option: like `--version` / `--help`, it is intercepted
  before any workspace traversal or command execution, so it is safe to run
  anywhere and never touches the repository.

The generated script completes:

- **Commands** — every `:command` and its aliases (e.g. `:compiler`, `:c`).
- **Global options** — the shared options (`--verbose`, `--dry-run`,
  `--scan`, `--project`, …) plus any tool-specific global options.
- **Per-command options** — options declared on each command, offered after the
  command name.

## Installation

The examples use `buildkit`; substitute `testkit` or `issuekit` as needed. Each
tool generates a script named for itself, so the three tools' completions
coexist without collision.

### bash

Requires the `bash-completion` package (provides `_init_completion`).

```bash
# System-wide (Linux):
buildkit --completion bash | sudo tee /etc/bash_completion.d/buildkit >/dev/null

# Per-user: write it somewhere and source it from ~/.bashrc:
buildkit --completion bash > ~/.local/share/bash-completion/completions/buildkit
```

Reload with `source ~/.bashrc` or open a new shell.

### zsh

Write the script to a directory on your `$fpath` with a `_<tool>` filename:

```bash
# e.g. a user completion dir already on fpath:
buildkit --completion zsh > ~/.zsh/completions/_buildkit
```

Ensure the directory is on `fpath` and `compinit` runs, in `~/.zshrc`:

```zsh
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

Open a new shell (or run `compinit`) to pick it up.

### fish

```bash
buildkit --completion fish > ~/.config/fish/completions/buildkit.fish
```

Fish loads it automatically in new shells; no sourcing required.

## Keeping completions current

The scripts reflect the tool's command/option definitions **at generation
time**. Regenerate after upgrading a tool (or whenever commands/options change)
by re-running the same `--completion` command and overwriting the installed
file. A simple refresh helper:

```bash
for t in buildkit testkit issuekit; do
  "$t" --completion bash | sudo tee "/etc/bash_completion.d/$t" >/dev/null
done
```

## Version compatibility

- The `--completion` option is provided by the shared framework, so **all tools
  on a `tom_build_base` version that includes it expose it identically**. It was
  introduced in `tom_build_base` **2.6.32**; a tool built against an older base
  will not recognise `--completion` (it would be treated as an unknown option).
  Check with `<tool> --help`, which lists `--completion` when supported.
- Generated scripts are plain shell and have no runtime dependency on the Dart
  toolchain — they only invoke the tool for nothing; completion candidates are
  embedded in the script itself, so they work offline and fast.

## For tool authors

The generation lives in `CompletionGenerator`
(`lib/src/v2/core/completion_generator.dart`) and the
`ToolDefinition.generateCompletion(ShellType)` extension. Tools get the
`--completion` option and its handling **for free** from `ToolRunner`; there is
nothing to wire per tool. Declaring accurate `CommandDefinition` /
`OptionDefinition` metadata (names, `abbr`, `aliases`, `description`) is all
that is required for good completions.
