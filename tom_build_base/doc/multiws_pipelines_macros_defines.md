# Multi-Workspace Pipelines, Macros, and Defines

This document describes the pipeline execution model, runtime macro system, and persistent define system as implemented in `tom_build_base`. These features are available to all multi-command tools that define a `<tool>_master.yaml`.

## Related Documentation

- [Build Base User Guide](build_base_user_guide.md) — Comprehensive guide to implementing tools
- [Modes and Placeholders](modes_and_placeholders.md) — Mode system and placeholder resolution
- [CLI Tools Navigation](cli_tools_navigation.md) — Standard navigation options
- [Tool Inheritance and Nesting](tool_inheritance_and_nesting.md) — Tool composition and wiring

---

## Table of Contents

- [Feature Eligibility](#feature-eligibility)
- [Pipeline System](#pipeline-system)
  - [Pipeline Structure](#pipeline-structure)
  - [Pipeline Phases](#pipeline-phases)
  - [Command Prefixes](#command-prefixes)
  - [Pipeline Option Precedence](#pipeline-option-precedence)
  - [Multi-Workspace Traversal](#multi-workspace-traversal)
  - [Dry-Run and Verbose Behavior](#dry-run-and-verbose-behavior)
- [Runtime Macros](#runtime-macros)
  - [Defining Macros](#defining-macros)
  - [Invoking Macros](#invoking-macros)
  - [Argument Placeholders](#argument-placeholders)
  - [Managing Macros](#managing-macros)
  - [Shell Quoting](#shell-quoting)
- [Persistent Defines](#persistent-defines)
  - [Adding Defines](#adding-defines)
  - [Mode-Specific Defines](#mode-specific-defines)
  - [Resolution Order](#resolution-order)
  - [Referencing Defines in YAML](#referencing-defines-in-yaml)
  - [Managing Defines](#managing-defines)
  - [Project-Level Overrides](#project-level-overrides)
- [Configuration Authority](#configuration-authority)

---

## Feature Eligibility

All three features — pipelines, runtime macros, and persistent defines — are gated by the same two conditions:

1. The tool must be a **multi-command** tool (`ToolMode.multiCommand`)
2. A `<tool>_master.yaml` file must exist in the workspace root

When either condition is not met:
- Pipeline names are rejected with an error message
- `:macro`, `:macros`, `:unmacro` commands are not available
- `:define`, `:defines`, `:undefine` commands are not available
- These features do not appear in `--help` output

This ensures standalone tools (like `astgen`, `d4rtgen`) never expose multi-command features.

---

## Pipeline System

Pipelines are named, multi-step workflows defined in `<tool>_master.yaml`. Pipeline handling is owned by `tom_build_base` and is available uniformly across all eligible tools.

### Pipeline Structure

Pipelines are defined under the `pipelines:` key in the tool section of `<tool>_master.yaml`:

```yaml
buildkit:
  pipelines:
    build:
      executable: true
      runBefore: clean
      core:
        - commands:
            - versioner
            - runner
            - compiler

    clean:
      executable: true
      core:
        - commands:
            - cleanup
            - shell rm -rf build/

    deploy:
      executable: true
      runAfter: build
      precore:
        - commands:
            - print "Preparing deployment..."
      core:
        - commands:
            - shell rsync -av build/ server:/app/
```

**Pipeline properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `executable` | bool | `true` | Whether the pipeline can be invoked from the command line |
| `runBefore` | String/List | — | Pipeline(s) to run before this one |
| `runAfter` | String/List | — | Pipeline(s) to run after this one |
| `global-options` | String | — | Default options for all commands in the pipeline |
| `precore` | List\<Step> | — | Steps to run before main work |
| `core` | List\<Step> | — | Main pipeline steps |
| `postcore` | List\<Step> | — | Steps to run after main work |

Non-executable pipelines can still be called as dependencies via `runBefore`/`runAfter`.

### Pipeline Phases

Execution order for a pipeline:

```
runBefore pipelines → precore → core → postcore → runAfter pipelines
```

- `runBefore`/`runAfter` references are resolved recursively
- Circular dependencies are detected and reported as errors
- Already-executed pipelines are skipped (no duplicate execution)

Each phase contains a list of step groups:

```yaml
core:
  - commands:
      - versioner
      - compiler
    platforms:
      - darwin-arm64
      - linux-x64
```

| Field | Type | Description |
|-------|------|-------------|
| `commands` | List\<String> | Commands to execute in this step |
| `platforms` | List\<String> | Platform filter (empty/omitted = all platforms) |

### Command Prefixes

Each command string in a pipeline starts with a prefix that determines how it is executed:

| Prefix | Description | Execution Context |
|--------|-------------|-------------------|
| `<tool>` | Delegate to the tool's own command | Per the tool's traversal rules |
| `shell` | Execute a shell command once | Directory containing `<tool>_master.yaml` |
| `shell-scan` | Execute in each traversed directory | Same traversal as `<tool> :execute` |
| `stdin` | Pipe multi-line content to a command | Directory containing `<tool>_master.yaml` |

**Tool commands:**

```yaml
- commands:
    - "buildkit :versioner --no-git"
    - "buildkit :compiler --targets linux-x64"
```

**Shell commands:**

```yaml
- commands:
    - "shell dart pub get"
    - "print Building on %{current-platform}"
```

**Shell-scan commands** (run once per scanned project):

```yaml
- commands:
    - "shell-scan echo %{folder.name} at %{folder}"
    - "shell-scan dart analyze %{folder}"
```

**Stdin commands** (pipe multi-line content):

```yaml
- commands:
    - |
      stdin dcli --stdin
      print("Hello from DartScript!");
      print("Platform: ${Platform.operatingSystem}");
```

All pipeline command types resolve `%{...}` placeholders before execution. Run `<tool> help placeholders` for the complete reference.

**Prefix matching is strict** — no alias expansion (e.g., `bk` is NOT accepted as a prefix for `buildkit`).

### Pipeline Option Precedence

When options apply to pipeline commands, three sources are checked in priority order:

| Priority | Source | Description |
|----------|--------|-------------|
| 1 (highest) | **Command-level options** | Options embedded inside the command string |
| 2 | **Invocation options** | Options from the command line (e.g., `buildkit --verbose build`) |
| 3 (lowest) | **Pipeline global-options** | Defaults in `pipelines.<name>.global-options` |

Command-level options always win. Invocation options override pipeline-level options. No merging occurs at the command level — it's a complete override.

### Multi-Workspace Traversal

Multi-workspace traversal applies **only** to pipeline execution. Direct commands always run in the current workspace only.

When only pipelines are invoked, `tom_build_base` shells out to each sub-workspace that contains its own `<tool>_master.yaml` by default.

For mixed command+pipeline invocations, cross-workspace delegation requires `-w` / `--workspace-recursion`.

**Disqualifying options** prevent multi-workspace traversal:

- `--root <dir>` (explicit workspace root)
- `--filter <pattern>` / `--exclude <pattern>` (traversal filters)
- `--depth <n>` (recursion depth limiter)
- `--workspace <name|path>` (explicit workspace target)

When disqualifying options are present, sub-workspaces are skipped with:

```text
Skipped workspace: <directory>, global traversal option specified.
```

**Never disqualifying:** `--verbose` and `--dry-run` always propagate to sub-workspace invocations.

### Dry-Run and Verbose Behavior

- `--dry-run` displays resolved pipeline command lines and option sources without executing
- `--dry-run` performs multi-workspace traversal, calling `<tool> --dry-run <pipeline>` in sub-workspaces
- `--verbose` shows full command resolution details AND executes
- Both flags are always propagated to sub-workspace delegated invocations

### Pipeline Execution Policy

- **Fail-fast:** If a pipeline step fails, execution stops immediately
- **Serial execution:** No concurrent step execution
- **No backward compatibility:** Legacy pipeline implementations are replaced by the base engine

---

## Runtime Macros

Runtime macros are reusable command-line shortcuts. They are persisted in `<tool>_macros.yaml` in the workspace root and available across all subsequent invocations.

### Defining Macros

Use `:macro` to define a new macro:

```bash
buildkit :macro cv=:versioner :compiler
buildkit :macro cvc=:cleanup :versioner :compiler
buildkit :macro run=:runner --command $$
```

All tokens after `name=value` are captured as the macro value — they are NOT executed immediately. They expand only when the macro is invoked with `@name`.

### Invoking Macros

Use `@name` to invoke a macro on the command line:

```bash
buildkit @cv                 # Expands to: :versioner :compiler
buildkit @cvc                # Expands to: :cleanup :versioner :compiler
buildkit :cleanup @cv        # Mix with regular commands
```

### Argument Placeholders

Macro values support positional argument substitution:

| Placeholder | Description |
|-------------|-------------|
| `$1` through `$9` | Positional arguments after `@name` |
| `$$` | All remaining arguments (spread/rest) |

**Positional example:**

```bash
buildkit :macro bp=:build --project $1
buildkit @bp tom_core         →  :build --project tom_core
```

**Spread example:**

```bash
buildkit :macro all=:execute $$
buildkit @all --verbose "echo hello"
→  :execute --verbose "echo hello"
```

**Multiple positional:**

```bash
buildkit :macro pair=:copy $1 $2
buildkit @pair source.txt dest.txt    →  :copy source.txt dest.txt
```

Unused positional placeholders are replaced with empty strings. Extra arguments beyond the highest placeholder are appended.

### Managing Macros

```bash
<tool> :macros               # List all macros
<tool> :unmacro <name>       # Remove a macro
```

Macros are stored in `<tool>_macros.yaml`. The file is created when the first macro is added and deleted when the last macro is removed.

### Shell Quoting

When defining macros at an interactive shell prompt, `$` placeholders may be expanded by the shell. Escape them:

```bash
# Both are equivalent — pass literal $1 and $2 to the tool:
buildkit :macro vc=:versioner --project \$1 :compiler \$2
buildkit ':macro' 'vc=:versioner --project $1 :compiler $2'
```

---

## Persistent Defines

Persistent defines are key-value pairs stored in `<tool>_master.yaml` under the `defines:` section. They are resolved as `@[name]` placeholders at YAML load time, before any commands execute.

### Adding Defines

Use `:define` to add or update a define:

```bash
buildkit :define env=production
buildkit :define output_dir=build/release
```

Confirmation output: `Added define: <name>: <value>`

### Mode-Specific Defines

Defines can target a specific mode using `-m`:

```bash
buildkit :define -m DEV output_dir=build/debug
buildkit :define -m CI output_dir=/tmp/ci-output
```

This creates mode-prefixed sections in `<tool>_master.yaml`:

```yaml
buildkit:
  defines:
    output_dir: build/release
  DEV-defines:
    output_dir: build/debug
  CI-defines:
    output_dir: /tmp/ci-output
```

### Resolution Order

When modes are active (via `--modes` CLI option or `tom_workspace.yaml` defaults), defines are merged in order:

1. **Default defines** (`defines:` section)
2. **First mode defines** (e.g., `DEV-defines:` if `--modes DEV,CI`)
3. **Second mode defines** (e.g., `CI-defines:` if `--modes DEV,CI`)
4. **Project-level defines** (from `<tool>.yaml` per project)

Later sources override earlier ones for the same key. This means project-level defines can override workspace-level defines, and later modes override earlier modes.

### Referencing Defines in YAML

Use `@[name]` syntax anywhere in YAML configuration files:

```yaml
compiler:
  binaryPath: @[output_dir]/bin/@[arch]
```

Define resolution is recursive (max depth 10):

```yaml
defines:
  base: /opt/tools
  bin: @[base]/bin          # Resolves to /opt/tools/bin
```

Resolved values can themselves contain `${...}` command placeholders, which are resolved later during command execution.

### Managing Defines

```bash
<tool> :defines              # List all defines (default + mode-specific)
<tool> :undefine <name>      # Remove a default define
<tool> :undefine -m DEV <name>  # Remove a mode-specific define
```

Removal confirmation: `Removed define: <name> : <value>`

Defines are always written in **alphabetical key order**.

### Project-Level Overrides

Users can manually add defines to project-level `<tool>.yaml` files:

```yaml
# project/buildkit.yaml
buildkit:
  defines:
    output_dir: ./local-build    # Overrides workspace define
  DEV-defines:
    debug: true                  # Project-specific DEV define
```

Project defines are merged on top of workspace defines once per project during configuration loading.

---

## Configuration Authority

| Feature | Configuration File | Owner |
|---------|-------------------|-------|
| Pipelines | `<tool>_master.yaml` (`pipelines:`) | `tom_build_base` |
| Runtime macros | `<tool>_macros.yaml` | `tom_build_base` |
| Persistent defines | `<tool>_master.yaml` (`defines:`) | `tom_build_base` |
| Pipeline execution | `ToolPipelineExecutor` | `tom_build_base` |
| Macro expansion | `MacroExpander` | `tom_build_base` |
| Define resolution | `ConfigLoader` | `tom_build_base` |
| Feature gating | `ToolRunner` | `tom_build_base` |

All three features are implemented in `tom_build_base` and consumed by tools like `buildkit`, `issuekit`, and `testkit` without any tool-local implementation.
