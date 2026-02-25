# Modes and Placeholders

This document specifies the mode support system and placeholder resolution for Tom workspace tools. It applies to all tools that use the `tom_build_base` infrastructure: `buildkit`, `testkit`, `issuekit`, `linkkit`, and others.

---

## Terminology

| Term | Definition | Examples |
|------|------------|----------|
| **Tool** | Top-level CLI application | `buildkit`, `testkit`, `issuekit`, `linkkit` |
| **Command** | Subcommand within a tool | `:compiler`, `:versioner`, `:cleanup`, `:gitcommit` |
| **Configuration files** | Named after the tool | `buildkit.yaml` / `buildkit_master.yaml`, `testkit.yaml` / `testkit_master.yaml` |

---

## Placeholder Types

There are four distinct placeholder types, resolved at different times:

| Syntax | Name | Source | Resolution Time |
|--------|------|--------|-----------------|
| `@[...]` | **Define placeholders** | `{tool}_master.yaml` and `{tool}.yaml` `defines:` section | At YAML load time, before merge |
| `@{...}` | **Tool placeholders** | Tool-level values (project path, tool version, etc.) | After mode processing, before commands |
| `${...}` | **Command placeholders** | Command-specific (file, target, etc.) | During command execution |
| `$VAR` or `$[VAR]` | **Environment variables** | Shell environment | During command execution |

### Define Placeholders (`@[...]`)

Define placeholders reference values from the `defines:` section of configuration files. They are resolved during YAML loading, **before** the tool merges workspace and project configurations.

```yaml
# buildkit_master.yaml
buildkit:
  defines:
    binaryPath: $HOME/.tom/bin
    outputDir: @[binaryPath]/output  # Can reference other defines
  DEV-defines:
    binaryPath: $HOME/.tom/bin/dev

# project/buildkit.yaml
compiler:
  compiles:
    - commandline:
        - mkdir -p @[binaryPath]/${target-platform-vs}
        - dart compile exe ${file} -o @[binaryPath]/${target-platform-vs}/${file.name}
```

**Notes:**
- `@[...]` placeholders can contain `${...}` placeholders inside their resolved values
- Resolution is recursive (max depth: 10) — a define value can reference other defines

### Tool Placeholders (`@{...}`)

Tool placeholders are defined by the tool itself and resolved after mode processing, once per project (not per command). Tools register these placeholders with descriptions for help output.

```yaml
# project/buildkit.yaml
compiler:
  compiles:
    - commandline:
        - echo "Building in @{project-path}"
        - echo "Tool version: @{tool-version}"
```

**Example tool placeholders:**

| Placeholder | Description |
|-------------|-------------|
| `@{project-path}` | Absolute path to current project |
| `@{project-name}` | Name of current project |
| `@{tool-version}` | Version of the tool |
| `@{workspace-root}` | Root path of the workspace |

**Notes:**
- Tool placeholders are resolved once per project, before any commands execute
- Tools register their placeholders for help output generation
- The same placeholder resolution utility is used (recursive, max depth 10)

### Command Placeholders (`${...}`)

Command placeholders are resolved by specific commands during execution. Each command defines its own set of available placeholders.

**Example placeholders from the `:compiler` command:**

| Placeholder | Description |
|-------------|-------------|
| `${file}` | Source file path |
| `${file.name}` | File name without extension |
| `${file.basename}` | File name with extension |
| `${file.extension}` | File extension (e.g., `.dart`) |
| `${file.dir}` | File directory path |
| `${target-os}` | Target OS (macos, linux, windows) |
| `${target-arch}` | Target architecture (x64, arm64, arm) |
| `${target-platform}` | Dart target format (macos-arm64) |
| `${target-platform-vs}` | VS Code format (darwin-arm64) |
| `${current-os}` | Current OS |
| `${current-arch}` | Current architecture |
| `${current-platform}` | Current platform (Dart format) |
| `${current-platform-vs}` | Current platform (VS Code format) |

### Environment Variables (`$VAR` / `$[VAR]`)

Environment variables from the shell environment. Two syntaxes are supported:

| Syntax | Use case |
|--------|----------|
| `$VAR` | When followed by non-word characters (e.g., `$HOME/.tom`) |
| `$[VAR]` | When more characters follow the variable name (e.g., `$[HOME]path`) |

```yaml
compiler:
  compiles:
    - commandline:
        - mkdir -p $HOME/.tom/bin      # $HOME followed by /
        - echo $[USER]_backup          # $[USER] allows _backup suffix
```

---

## Mode System

### Concept

Modes represent **workspace-wide configuration dimensions** that can be changed independently. They allow switching all configurations across all projects between different environments.

| Dimension | Values | Purpose |
|-----------|--------|---------|
| Environment | `DEV`, `TEST`, `PROD` | Development vs production settings |
| Deployment | `LOCAL`, `DOCKER`, `CLOUD` | Where the code runs |
| CI | `CI` | Continuous integration specific overrides |

Multiple modes can be active simultaneously, allowing orthogonal configuration:

- `DEV + LOCAL` = Local development
- `DEV + DOCKER` = Development in Docker
- `PROD + CLOUD` = Production deployment

### Mode Sources (Priority)

1. **CLI option** — `--modes DEV,DOCKER` (highest priority)
2. **tom_workspace.yaml** — Default modes for the workspace

```yaml
# tom_workspace.yaml
build:
  modes: DEV, LOCAL  # default modes for all tools
```

### No Mode / Implicit "None" State

Modes are **opt-in feature switches**. The base (unprefixed) configuration represents the default behavior when no modes are active.

**Single mode as feature flag:**

A mode like `CI` acts as a feature switch. When `CI` is active, `CI-` prefixed keys override their base keys. When `CI` is not active, only the base keys are used.

```yaml
versioner:
  enabled: true              # Default: versioner runs
  CI-enabled: false          # In CI mode: skip versioner
```

**Dimension modes with implicit "none":**

For dimensions with multiple modes (like `DEV`, `TEST`, `PROD`), there's always an implicit fourth state: **none of them active**. This means the base configuration is used — which typically represents production/default behavior.

| Active Mode | Configuration Used |
|-------------|-------------------|
| (none) | Base keys only (production defaults) |
| `DEV` | Base + `DEV-` overrides |
| `TEST` | Base + `TEST-` overrides |
| `PROD` | Base + `PROD-` overrides |

**Example:**
```yaml
compiler:
  target-restriction: [darwin-arm64, linux-x64, linux-arm64]  # Default: all platforms
  DEV-target-restriction: darwin-arm64                         # DEV: current platform only
  CI-target-restriction: [linux-x64, linux-arm64]              # CI: server platforms only
```

- No modes active → all 3 platforms
- `DEV` active → darwin-arm64 only
- `CI` active → linux-x64 and linux-arm64
- `DEV, CI` active → `CI-` overrides `DEV-` (mode order matters)

### Mode-Prefixed Keys

Any configuration key can have mode-prefixed variants. **Mode prefixes are UPPERCASE** to make them visually distinct:

```yaml
# buildkit_master.yaml
buildkit:
  defines:
    binaryPath: $HOME/.tom/bin
  DEV-defines:
    binaryPath: $HOME/.tom/bin/dev
  DOCKER-defines:
    binaryPath: /app/bin

compiler:
  target-restriction: [darwin-arm64, linux-x64, linux-arm64]
  DEV-target-restriction: darwin-arm64
  CI-target-restriction: [linux-x64, linux-arm64]
```

### Mode Prefix Syntax

- **UPPERCASE letters and numbers only**: `DEV`, `PROD`, `TEST1`, `CI`
- **Followed by hyphen**: `DEV-`, `CI-`
- **Applied to any key**: `DEV-target-restriction`, `DEV-defines`, `CI-enabled`

```yaml
# Valid mode prefixes
DEV-target-restriction: darwin-arm64
CI-skip-versioner: true
TEST1-output-path: ./test-build/

# Invalid (not recognized as mode prefixes)
dev-target-restriction: ...     # lowercase
Dev-target-restriction: ...     # mixed case
DEV_target_restriction: ...     # underscore instead of hyphen
```

### Mode Merging Behavior

For YAML map nodes (like `defines:`), mode-prefixed versions are **merged** with the base, not replaced. Merging happens in mode order, with later modes overriding earlier values for the same keys.

**Convention:** The unprefixed (base) node represents **production/default settings**. Mode-prefixed nodes provide overrides for specific environments.

#### Example: Multiple modes with merging

```yaml
buildkit:
  modes: DEV, CLOUD
  defines:
    binaryPath: $HOME/.tom/bin
    cloudProvider: AWS
  DEV-defines:
    binaryPath: $HOME/.tom/bin/dev
  CLOUD-defines:
    cloudProvider: GCP
```

**Resolution with `modes: DEV, CLOUD`:**

1. Start with base `defines:` → `{ binaryPath: $HOME/.tom/bin, cloudProvider: AWS }`
2. Merge `DEV-defines:` → `{ binaryPath: $HOME/.tom/bin/dev, cloudProvider: AWS }`
3. Merge `CLOUD-defines:` → `{ binaryPath: $HOME/.tom/bin/dev, cloudProvider: GCP }`

**Final result:**
```yaml
defines:
  binaryPath: $HOME/.tom/bin/dev   # from DEV-defines
  cloudProvider: GCP               # from CLOUD-defines (overrides AWS)
```

---

## Resolution Flow

Modes are **global** for all tools — YAML files are processed once per project, not per command.

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Determine active modes                                       │
│    - CLI --modes option OR                                      │
│    - tom_workspace.yaml build.modes default                     │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Load {tool}_master.yaml                                      │
│    a) Process mode prefixes:                                    │
│       - For each active mode, merge MODE-key: into key:         │
│       - Discard all MODE- prefixed keys (for inactive modes)    │
│    b) Resolve @[...] placeholders using merged defines:         │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Load project {tool}.yaml                                     │
│    a) Process mode prefixes (same as above)                     │
│    b) Resolve @[...] placeholders using:                        │
│       - Local defines (project)                                 │
│       - Master defines (workspace)                              │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. Resolve @{...} tool placeholders (once per project)          │
│    - Tool provides values: project-path, tool-version, etc.     │
│    - Applied to both workspace and project YAMLs                │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Pass clean workspace and project YAMLs to tool/commands      │
│    - Both YAMLs have NO @[...] or @{...} placeholders           │
│    - Both YAMLs have NO MODE- prefixed keys                     │
│    - Tool performs merge using tool-specific merge rules        │
└─────────────────────────────────────────────────────────────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Command execution                                            │
│    a) Command resolves ${...} placeholders (file, target, etc.) │
│    b) Shell/tool resolves $VAR / $[VAR] environment variables   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Configuration Example

```yaml
# tom_workspace.yaml
build:
  modes: DEV, LOCAL

# buildkit_master.yaml
buildkit:
  defines:
    binaryPath: $HOME/.tom/bin
    buildOutputPath: $HOME/.tom/build
  DEV-defines:
    binaryPath: $HOME/.tom/bin/dev
    buildOutputPath: ./build
  DOCKER-defines:
    binaryPath: /app/bin
    buildOutputPath: /app/build

compiler:
  DEV-target-restriction: darwin-arm64

# project/buildkit.yaml
compiler:
  compiles:
    - commandline:
        - mkdir -p @[binaryPath]/${target-platform-vs}
        - dart compile exe ${file} -o @[binaryPath]/${target-platform-vs}/${file.name}
      files:
        - bin/my_tool.dart
      platforms: [darwin-arm64, linux-x64, linux-arm64]
```

**With modes `DEV, LOCAL`:**
- `@[binaryPath]` → `$HOME/.tom/bin/dev`
- `target-restriction` → `darwin-arm64`
- Only `darwin-arm64` compiled

**With modes `DOCKER`:**
- `@[binaryPath]` → `/app/bin`
- No target restriction
- All 3 platforms compiled

---

## Shared Infrastructure in tom_build_base

### Components

| Component | Purpose |
|-----------|---------|
| **Mode processor** | Merges mode-prefixed sections based on active modes |
| **Define resolver** | Resolves `@[...]` placeholders from defines |
| **Tool placeholder resolver** | Resolves `@{...}` placeholders from tool-provided values |
| **String replacement utility** | Recursive placeholder/environment variable replacement |
| **Placeholder registry** | Tools and commands register `{name: description}` for help generation |

### String Replacement Utility

The shared replacement utility provides recursive placeholder resolution:

```dart
/// Resolves placeholders in a template string.
/// 
/// Parameters:
/// - [template]: String containing placeholders
/// - [values]: Map of placeholder names to values
/// - [resolveEnvVars]: Whether to also resolve $VAR and $[VAR] environment variables
/// - [maxDepth]: Maximum recursion depth (default: 10)
/// 
/// Returns the resolved string. Unresolved placeholders remain unchanged.
String resolvePlaceholders(
  String template,
  Map<String, String> values, {
  bool resolveEnvVars = false,
  int maxDepth = 10,
});
```

**Behavior:**
- Recursively resolves placeholders (a resolved value may contain new placeholders)
- Maximum recursion depth of 10 to prevent infinite loops
- Optional environment variable resolution via `resolveEnvVars` parameter
- Unresolved placeholders remain unchanged (no error, enables later resolution)

**Example:**
```dart
final values = {
  'binaryPath': '\$HOME/.tom/bin',
  'outputDir': '@[binaryPath]/output',
};

// Without env var resolution
resolvePlaceholders('@[outputDir]/${file}', values);
// → '$HOME/.tom/bin/output/${file}'

// With env var resolution  
resolvePlaceholders('@[outputDir]/${file}', values, resolveEnvVars: true);
// → '/Users/alex/.tom/bin/output/${file}'
```

### Placeholder Registration

Both tools and commands register their placeholders with descriptions for help generation:

```dart
// Tool-level registration (in buildkit tool)
toolRegistry.register('project-path', 'Absolute path to current project');
toolRegistry.register('workspace-root', 'Root path of the workspace');

// Command-level registration (in compiler command)
commandRegistry.register('file', 'Source file path');
commandRegistry.register('file.name', 'File name without extension');
commandRegistry.register('target-platform-vs', 'Target platform (VS Code format)');
```

Used for:
- Help output generation (`<tool> help parameters`, `<tool> help :compiler parameters`)
- Documentation generation
- Could validate configs (unresolved placeholders = warning), but not required initially
- Invalid/unknown placeholders simply remain unresolved

---

## Command Line Mode Override

Modes are **global** for all tools and apply to all commands within a tool invocation. The `--modes` option is a global tool option (not command-specific).

```bash
# Use default mode from tom_workspace.yaml
buildkit :compiler :versioner

# Override to no mode (uses only base/unprefixed keys)
buildkit --modes= :compiler :versioner

# Override to specific mode (applies to ALL commands)
buildkit --modes=CI :compiler :versioner :gitcommit

# Use multiple modes (in priority order)
buildkit --modes=CI,RELEASE :compiler :versioner
```

### Standalone Command Executables

When a command is also available as a standalone executable, modes only apply to that single command:

```bash
# Standalone compiler executable — modes apply only to this command
compiler --modes=CI
```

### Standalone Tool Configuration Inheritance

A command can be exposed both as a subcommand of the parent tool (e.g., `buildkit :deploy`) and as a standalone executable (e.g., `deployer`). **Standalone tools inherit configuration from the parent tool's config file**, not their own separate config file.

**Key principle:** The standalone tool knows it's logically part of the parent tool, so it reads from:
- `{parent-basename}_master.yaml` — for workspace configuration
- `{parent-basename}.yaml` — for project configuration

**Example:**

The `deployer` standalone executable is also available as `buildkit :deploy`. Both read configuration from `buildkit_master.yaml` and project `buildkit.yaml`:

```yaml
# buildkit_master.yaml
deploy:
  target: production
  region: us-east-1
  DEV-target: staging
  DEV-region: us-west-2
```

```bash
# These are equivalent — both read from buildkit config
buildkit :deploy --modes=DEV
deployer --modes=DEV
```

**Implementation pattern:**

```dart
class DeployerStandalone {
  final String basename = 'buildkit';  // Parent tool basename
  final String commandName = 'deploy'; // Command section in config
  
  Future<void> run() async {
    final loader = ConfigLoader(basename: basename);
    final loaded = await loader.load(...);
    
    // Extract command-specific configuration
    final deployConfig = loaded.masterConfig[commandName];
    // ...
  }
}
```

This pattern ensures:
- Consistent configuration between tool and standalone modes
- Modes work the same way in both execution contexts
- Skip files apply based on the parent tool's basename


---

## Target Restrictions (Buildkit-Specific)

Target restrictions limit which platforms are compiled. This is particularly useful for:

- **Development:** Only compile for current platform — cross-platform binaries are useless locally
- **CI pipelines:** Restrict to specific target platforms per build agent

```yaml
# buildkit_master.yaml
compiler:
  DEV-target-restriction: darwin-arm64
```

| Project requests | DEV restriction | Actual targets (DEV) | Actual targets (no mode) |
|------------------|-----------------|----------------------|--------------------------|
| `[darwin-arm64, linux-x64, linux-arm64]` | `darwin-arm64` | `[darwin-arm64]` | `[darwin-arm64, linux-x64, linux-arm64]` |
| `[darwin-arm64, linux-x64]` | `linux-x64` | `[linux-x64]` | `[darwin-arm64, linux-x64]` |
| `[win32-x64]` | `darwin-arm64` | `[]` (none) | `[win32-x64]` |

---

## Tool Configuration

### Config File Basename

Each tool specifies a **basename** that determines its configuration file names:

| Basename | Master file | Project file | Skip file |
|----------|-------------|--------------|-----------|
| `buildkit` | `buildkit_master.yaml` | `buildkit.yaml` | `buildkit_skip.yaml` |
| `testkit` | `testkit_master.yaml` | `testkit.yaml` | `testkit_skip.yaml` |
| `issuekit` | `issuekit_master.yaml` | `issuekit.yaml` | `issuekit_skip.yaml` |
| `linkkit` | `linkkit_master.yaml` | `linkkit.yaml` | `linkkit_skip.yaml` |

Tools specify their basename when registering with `tom_build_base`:

```dart
final tool = ToolConfig(
  basename: 'buildkit',  // → buildkit_master.yaml, buildkit.yaml, buildkit_skip.yaml
  // ...
);
```

### Configuration File Locations

| File | Location | Purpose |
|------|----------|---------|
| `{basename}_master.yaml` | Workspace root | Workspace-wide settings, defines, pipelines |
| `{basename}.yaml` | Project root | Project-specific configuration |
| `{basename}_skip.yaml` | Any directory | Skip this directory for this tool |
| `tom_skip.yaml` | Any directory | Skip this directory for ALL tools |

---

## V2 Integration API

### Transparent Mode and Placeholder Resolution

The `tom_build_base` v2 implementation makes mode and placeholder resolution **transparent** to tools and commands. The framework handles all resolution before passing configuration to commands.

### ToolConfig Registration

```dart
/// Tool configuration with mode and placeholder support.
class ToolConfig {
  /// Config file basename (e.g., 'buildkit' → buildkit.yaml, buildkit_master.yaml)
  final String basename;
  
  /// Tool name for display
  final String name;
  
  /// Tool placeholders (resolved once per project)
  final Map<String, PlaceholderDefinition> toolPlaceholders;
  
  /// Commands with their placeholder definitions
  final List<CommandDefinition> commands;
}

/// Placeholder definition for registration and help output.
class PlaceholderDefinition {
  final String name;
  final String description;
  final String Function(CommandContext ctx)? resolver;
}
```

### ConfigLoader API

The `ConfigLoader` handles mode processing, placeholder resolution, and returns clean YAML:

```dart
/// Loads and processes configuration files with mode and placeholder resolution.
class ConfigLoader {
  /// Load configuration for a project.
  /// 
  /// Steps performed automatically:
  /// 1. Load {basename}_master.yaml from workspace root
  /// 2. Load {basename}.yaml from project root
  /// 3. Apply mode processing (merge MODE-keys, discard inactive)
  /// 4. Resolve @[...] define placeholders
  /// 5. Resolve @{...} tool placeholders
  /// 6. Return clean configs ready for tool-specific merge
  Future<LoadedConfig> load({
    required String basename,
    required String workspaceRoot,
    required String projectPath,
    required List<String> activeModes,
    required Map<String, String> toolPlaceholders,
  });
}

/// Result of configuration loading — all placeholders and modes resolved.
class LoadedConfig {
  /// Processed master config (no @[...], @{...}, or MODE- keys)
  final Map<String, dynamic> masterConfig;
  
  /// Processed project config (no @[...], @{...}, or MODE- keys)
  final Map<String, dynamic> projectConfig;
  
  /// Active modes that were applied
  final List<String> appliedModes;
}
```

### Command Execution Context

Commands receive fully resolved configuration:

```dart
/// Context passed to command execution — all pre-processing done.
class CommandContext {
  /// Project path
  final String projectPath;
  
  /// Workspace root
  final String workspaceRoot;
  
  /// Merged configuration (tool performed its merge)
  final Map<String, dynamic> config;
  
  /// Placeholder resolver for ${...} command placeholders
  final PlaceholderResolver resolver;
  
  /// Active modes (for informational purposes)
  final List<String> activeModes;
}
```

### What Tools/Commands Need to Do

**For existing tools:** No changes required — mode processing and placeholder resolution happen automatically.

**To use new features:**

1. **Register tool placeholders** (optional):
   ```dart
   toolPlaceholders: {
     'project-path': PlaceholderDefinition(
       name: 'project-path',
       description: 'Absolute path to current project',
       resolver: (ctx) => ctx.projectPath,
     ),
   }
   ```

2. **Register command placeholders** (optional, for help output):
   ```dart
   commandPlaceholders: {
     'file': PlaceholderDefinition(
       name: 'file',
       description: 'Source file path',
     ),
   }
   ```

---

## Migration Path

Existing configurations continue to work unchanged. To adopt mode support:

1. Add `build.modes:` to `tom_workspace.yaml` with default modes (e.g., `DEV`)
2. Add `defines:` under `{tool}:` in `{tool}_master.yaml` with common paths
3. Add `DEV-defines:` for development-specific overrides
4. Update project config files to use `@[placeholder]` for define references
5. Add mode-prefixed overrides as needed (e.g., `DEV-target-restriction:`)

---

## Implementation Notes

### Parser Requirements

1. When parsing any YAML key, check if it starts with `[A-Z][A-Z0-9]+-`
2. If yes, extract the prefix and the actual key name
3. Build a lookup table of: `{ key: { mode: value, ... } }`
4. At resolution time, iterate through active modes and look up prefixed keys

### Placeholder Resolution Order

1. Resolve mode-specific values (merge MODE-key into key, discard inactive mode keys)
2. Resolve `@[...]` define placeholders (recursive, max depth 10)
3. Resolve `@{...}` tool placeholders (once per project)
4. Pass clean YAML to tool for tool-specific merge
5. Command resolves `${...}` placeholders during execution
6. Resolve `$VAR` / `$[VAR]` environment variables (when appropriate)

### Error Handling

- Unknown mode prefixes: warn but don't fail
- Missing defines: error with clear message showing which placeholder failed
- Circular define references: error after hitting recursion limit
- Unresolved command placeholders: remain unchanged (may be resolved later or warn at execution)
