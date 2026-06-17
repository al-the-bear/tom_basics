# Tom BuildKit REPL Integration Assessment

This document assesses the relationship between Tom CLI, BuildKit, and REPL tools, with a proposal for integration.

## Current Architecture

### Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **Tom CLI** | `devops/tom_build_cli` | Master CLI with command dispatch |
| **BuildKit** | `xternal/tom_module_basics/tom_build_kit` | Workspace build tools (bk, git commands) |
| **D4rt REPL** | `xternal/tom_module_d4rt/tom_d4rt_dcli` | DartScript REPL framework |
| **TomD4rt** | `devops/tom_build_cli` | Extended D4rt with Tom bridges |

### Current Relationships

```
┌─────────────────────────────────────────────────────────────────┐
│                          tom CLI                                 │
│  Entry point: tom                                               │
│  Modes: tom command | tom d4rt (script execution)               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   tom <command>            tom <script.dart>                    │
│        │                         │                               │
│        ▼                         ▼                               │
│   ┌─────────┐              ┌──────────┐                         │
│   │ TomCli  │              │ TomD4rt  │                         │
│   │ Commands│              │   REPL   │                         │
│   └─────────┘              └──────────┘                         │
│                                  │                               │
│                                  ▼                               │
│                           ┌──────────────┐                      │
│                           │ D4rtReplBase │                      │
│                           └──────────────┘                      │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        BuildKit (bk)                            │
│  Entry point: bk                                                │
│  Standalone tool, not integrated with tom CLI                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   bk :<tool> [options]     Standalone: gitcommit, cleanup, etc.│
│        │                                                        │
│        ▼                                                        │
│   ┌─────────────────┐                                          │
│   │ BuildtoolBase   │                                          │
│   │ WorkspaceNav    │                                          │
│   └─────────────────┘                                          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Integration Proposals

### Option 1: BuildKit as Tom CLI Subcommands

Integrate BuildKit tools as `tom build:*` subcommands.

```bash
# Current
bk :gitcommit -m "message"
gitcommit -m "message"

# Proposed
tom build:gitcommit -m "message"
tom build:cleanup
tom build:compile
```

**Pros:**
- Unified command namespace
- Single entry point for workspace management
- Shared configuration loading

**Cons:**
- Longer commands for frequent operations
- Requires tom CLI dependency in scripts
- Breaking change for existing usage

**Recommendation:** Keep standalone binaries, add optional integration.

---

### Option 2: BuildKit REPL (bk-repl)

Create a BuildKit REPL extending D4rtReplBase for interactive workflow.

```bash
bk --repl
# or
bk-repl
```

```
=== BuildKit REPL ===
Type .help for commands, Ctrl+C to exit

bk> status
  tom2: clean, up to date
  tom_module_d4rt: 2 modified files

bk> commit -m "Fix parser"
  Committing in tom_module_d4rt...
  ✓ Committed: Fix parser

bk> sync
  Pulling...
  Pushing...
  ✓ All repositories synced

bk> .scripts
  Available scripts:
  - daily_build.bk
  - release.bk
  
bk> .run daily_build.bk
  Running daily_build.bk...
```

**Features:**
- Interactive command execution
- Script loading (.bk files)
- Command history
- Tab completion
- Variable persistence between commands

**Implementation:**

```dart
class BuildKitRepl extends D4rtReplBase {
  @override
  String get toolName => 'bk';
  
  @override
  String get toolVersion => '1.0.0';
  
  @override
  void registerBridges(D4rt d4rt) {
    // Register BuildKit bridges
    d4rt.registerBridge(GitBridge());
    d4rt.registerBridge(WorkspaceBridge());
    d4rt.registerBridge(BuildBridge());
  }
  
  @override
  Future<bool> handleAdditionalCommands(
    D4rt d4rt,
    ReplState state,
    String line, {
    bool silent = false,
  }) async {
    // Handle bk-specific commands
    if (line.startsWith('status')) {
      return await _handleStatus(line);
    }
    if (line.startsWith('commit')) {
      return await _handleCommit(line);
    }
    return false;
  }
}
```

---

### Option 3: Tom CLI REPL Mode

Add REPL mode to existing Tom CLI.

```bash
tom --repl
# or
tom repl
```

```
=== Tom CLI REPL ===

tom> bk status
tom> build tom_core_kernel
tom> deploy uam staging
tom> git sync
```

**This already partially exists** via TomD4rt mode. Enhancement would add:
- BuildKit command shortcuts
- Workspace-aware auto-completion
- Project context switching

---

### Option 4: Guided Mode as REPL Alternative

Keep guided mode (`-g`) as the interactive experience, no REPL needed.

```bash
bk -g           # Top-level guided mode
gitcommit -g    # Tool-specific guided mode
```

**Rationale:**
- Guided mode covers interactive use cases
- REPL adds complexity without clear benefit
- Most build operations are single commands
- Scripts handle automation needs

---

## Recommended Approach

### Hybrid Solution

1. **Keep BuildKit standalone** - Fast access for frequent operations
2. **Add guided mode** - Already implemented (`-g` flag) ✓
3. **Optional Tom CLI integration** - For unified scripting
4. **Defer REPL** - Low priority, guided mode suffices

### Integration Points

```yaml
# tom_workspace.yaml
cli_integration:
  buildkit:
    # Make bk commands available in tom scripts
    expose_as: "bk"
    # Enable in tom REPL
    repl_shortcuts: true
```

### Tom Script Integration

Allow calling BuildKit from Tom scripts:

```dart
// In a .tom.dart script
import 'package:tom_build_kit/tom_build_kit.dart';

void main() async {
  final bk = BuildKit();
  
  // Use BuildKit programmatically
  await bk.gitSync(all: true);
  await bk.cleanup();
  await bk.compile(projects: ['tom_core_kernel']);
}
```

---

## REPL Design (If Implemented)

### Command Categories

```
=== BuildKit REPL Commands ===

Git Operations:
  status              Show git status across workspace
  commit <msg>        Commit with message
  sync                Pull and push all repos
  branch <args>       Branch operations
  
Build Operations:
  build [project]     Run build_runner
  compile [project]   Compile executables
  clean [project]     Clean build artifacts
  test [project]      Run tests
  
Workspace:
  projects            List all projects
  cd <project>        Change current project context
  deps [project]      Show dependencies
  
REPL Commands:
  .help               Show help
  .history            Show command history
  .scripts            List available scripts
  .run <script>       Run a .bk script
  .guide              Enter guided mode
  .exit               Exit REPL
```

### Script Format (.bk files)

```bash
# daily_build.bk
# Daily development build script

sync --quiet           # Pull latest
clean --generated      # Clean generated files
pub_get --all          # Update dependencies
build --all            # Run build_runner
analyze                # Check for issues
```

### State Management

```dart
class BuildKitReplState extends ReplState {
  /// Current project context (for scoped commands)
  String? currentProject;
  
  /// Last executed results (for chaining)
  BuildResult? lastResult;
  
  /// Accumulated errors
  List<String> sessionErrors = [];
}
```

---

## Priority Assessment

| Feature | Priority | Effort | Value |
|---------|----------|--------|-------|
| Guided mode (`-g`) | High | Completed | High |
| Tom script API | Medium | Medium | High |
| Tom CLI integration | Low | Low | Medium |
| BuildKit REPL | Low | High | Low |

### Reasoning

1. **Guided mode** handles interactive use case well
2. **Scripting API** enables automation without REPL complexity
3. **Tom CLI integration** is nice-to-have, not essential
4. **REPL** adds maintenance burden with limited benefit over guided mode

---

## Next Steps

1. ✅ Complete guided mode for all BuildKit commands
2. Document BuildKit API for programmatic use
3. Consider Tom CLI shortcut registration (future)
4. Evaluate REPL need after guided mode field testing
