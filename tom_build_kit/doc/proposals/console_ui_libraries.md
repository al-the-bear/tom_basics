# Console UI Libraries & REPL Design for BuildKit

This document covers library recommendations for improved console UI in guided mode, and proposes REPL use cases for BuildKit.

## Current Stack

The workspace already uses:
- **console_markdown** (^0.0.3) - Markdown-to-ANSI rendering
- **dart_console** (^4.1.2) - Basic console manipulation, cursor control (in tom_d4rt_dcli)

## Console UI Library Recommendations

### Tier 1: Recommended (Dart Native)

| Library | Purpose | pub.dev | Notes |
|---------|---------|---------|-------|
| **dart_console** | Cursor, colors, key input | [dart_console](https://pub.dev/packages/dart_console) | Already in use. Good for basic TUI |
| **console_markdown** | Markdown rendering | [console_markdown](https://pub.dev/packages/console_markdown) | Already in use |
| **interact** | Interactive prompts | [interact](https://pub.dev/packages/interact) | Inquirer-style prompts: select, confirm, input |
| **prompts** | Simple prompts | [prompts](https://pub.dev/packages/prompts) | Lighter alternative to interact |
| **chalkdart** | Styled text | [chalkdart](https://pub.dev/packages/chalkdart) | Chalk.js port, chainable styles |
| **cli_util** | CLI utilities | [cli_util](https://pub.dev/packages/cli_util) | Progress, spinners, logging |
| **mason_logger** | Beautiful CLI output | [mason_logger](https://pub.dev/packages/mason_logger) | Used by Mason/Dart CLI tools |

### Tier 2: Advanced TUI

| Library | Purpose | Notes |
|---------|---------|-------|
| **tui** | Full terminal UI | Widgets, layouts, scrolling (less maintained) |
| **terminal_ui** | Terminal widgets | Experimental, modeled after Rust's ratatui |
| **dart_ncurses** | ncurses bindings | FFI-based, platform-specific |

### Tier 3: Cross-Platform Considerations

| Library | Windows | macOS | Linux |
|---------|---------|-------|-------|
| dart_console | ✅ | ✅ | ✅ |
| interact | ✅ | ✅ | ✅ |
| chalkdart | ✅ | ✅ | ✅ |
| mason_logger | ✅ | ✅ | ✅ |

---

## Recommended Library for Guided Mode: `interact`

The `interact` package provides exactly what guided mode needs:

### Features

```dart
import 'package:interact/interact.dart';

// Single select (menu)
final selection = Select(
  prompt: 'What files to stage?',
  options: ['All files (git add -A)', 'Tracked only', 'Already staged', 'Pick files'],
  initialIndex: 0, // default selection
).interact();

// Multi-select (checkboxes)
final files = MultiSelect(
  prompt: 'Select files to stage',
  options: ['src/main.dart', 'src/utils.dart', 'lib/api.dart', 'test/main_test.dart'],
  defaults: [true, false, false, true], // pre-selected
).interact();

// Confirmation
final proceed = Confirm(
  prompt: 'Execute commands?',
  defaultValue: true, // Y/n vs y/N
).interact();

// Text input
final message = Input(
  prompt: 'Commit message',
  defaultValue: '',
  validator: (s) => s.length > 0 ? true : 'Message required',
).interact();

// Password input (hidden)
final token = Password(
  prompt: 'GitHub token',
).interact();

// Spinner for long operations
final spinner = Spinner(
  icon: SpinnerIcon.dots,
  rightPrompt: (done) => done ? 'Complete!' : 'Fetching...',
).interact();
await Future.delayed(Duration(seconds: 2));
spinner.stop();
```

### Why `interact`?

1. **Cross-platform** - Works on Windows, macOS, Linux
2. **Keyboard navigation** - Arrow keys, Enter, Space
3. **Styled output** - Colors, bold, dim
4. **Well-maintained** - Active development
5. **Pure Dart** - No FFI dependencies
6. **Familiar API** - Similar to Node.js Inquirer

### Alternative: `prompts`

Lighter weight with subset of features:

```dart
import 'package:prompts/prompts.dart';

// Simple choice
final choice = get('What files to stage?', [
  'All files',
  'Tracked only',
]);

// Confirmation
if (getBool('Proceed?', defaultsTo: true)) {
  // execute
}

// Text input
final msg = get('Commit message:', defaultsTo: 'Update');
```

---

## Implementation Architecture

### GuidedModeHelper Class

```dart
import 'package:interact/interact.dart';

/// Helper for guided mode interactions
class GuidedModeHelper {
  /// Show a menu and return selected index
  int menu(String prompt, List<String> options, {int defaultIndex = 0}) {
    return Select(
      prompt: prompt,
      options: options,
      initialIndex: defaultIndex,
    ).interact();
  }

  /// Multi-select with checkboxes
  List<int> multiSelect(String prompt, List<String> options, {List<bool>? defaults}) {
    return MultiSelect(
      prompt: prompt,
      options: options,
      defaults: defaults ?? List.filled(options.length, false),
    ).interact();
  }

  /// Confirm Y/n or y/N
  bool confirm(String prompt, {bool defaultYes = true}) {
    return Confirm(
      prompt: prompt,
      defaultValue: defaultYes,
    ).interact();
  }

  /// Text input with validation
  String input(String prompt, {String? defaultValue, String? hint}) {
    return Input(
      prompt: prompt,
      defaultValue: defaultValue ?? '',
    ).interact();
  }

  /// Show command preview
  void showCommandPreview(String command, {List<String>? repos}) {
    print('');
    print('┌─ Command Preview ───────────────────────');
    print('│ $command');
    if (repos != null && repos.isNotEmpty) {
      print('├─ Repositories ──────────────────────────');
      for (final repo in repos.take(5)) {
        print('│   $repo');
      }
      if (repos.length > 5) {
        print('│   ... and ${repos.length - 5} more');
      }
    }
    print('└──────────────────────────────────────────');
    print('');
  }

  /// File/folder tree selection (custom implementation needed)
  List<String> fileTreeSelect(String root, {bool foldersOnly = false}) {
    // Would need custom implementation or external tool
    throw UnimplementedError('Requires custom tree picker');
  }
}
```

### File Tree Picker

For the file/folder picking requirement, `interact` doesn't provide a tree picker. Options:

1. **Custom implementation** using dart_console for cursor positioning
2. **Flat list approach** - Show full paths, group by folder
3. **Two-step selection** - First pick folder, then pick files within

#### Recommended: Flat List with Folder Grouping

```dart
/// Show files grouped by folder with multi-select
List<String> pickFiles(List<String> allFiles) {
  // Group by folder
  final byFolder = <String, List<String>>{};
  for (final file in allFiles) {
    final folder = p.dirname(file);
    byFolder.putIfAbsent(folder, () => []).add(file);
  }

  // Build flat list with folder headers
  final options = <String>[];
  final isFolder = <bool>[];
  
  for (final folder in byFolder.keys.toList()..sort()) {
    options.add('📁 $folder/');  // Folder header
    isFolder.add(true);
    for (final file in byFolder[folder]!) {
      options.add('   ${p.basename(file)}');
      isFolder.add(false);
    }
  }

  final selected = MultiSelect(
    prompt: 'Select files (folder selects all within)',
    options: options,
  ).interact();

  // Expand folder selections to all files within
  final result = <String>[];
  for (final idx in selected) {
    if (isFolder[idx]) {
      // Selected a folder - include all files in that folder
      final folder = options[idx].substring(3).replaceAll('/', '');
      result.addAll(byFolder[folder]!);
    } else {
      // Selected a file - map back to full path
      final folder = _findParentFolder(options, idx);
      final fileName = options[idx].trim();
      result.add(p.join(folder, fileName));
    }
  }
  
  return result;
}
```

---

## REPL Proposal for BuildKit

### Use Cases for a BuildKit REPL

The existing D4rt REPL (`dcli`, `d4rt`) focuses on **Dart scripting and code execution**. A BuildKit REPL would focus on **workspace and build management**.

| D4rt REPL (dcli/d4rt) | BuildKit REPL |
|----------------------|---------------|
| Execute Dart code | Execute build commands |
| Script automation | Pipeline orchestration |
| Bridge exploration | Project exploration |
| Code evaluation | Status monitoring |

### Proposed: `bk repl` or `bkit`

```
╔════════════════════════════════════════════════════════════╗
║  BuildKit REPL v1.0.0                                       ║
║  Workspace: ~/Code/tom2 (12 projects, 9 git repos)         ║
╚════════════════════════════════════════════════════════════╝

bk> 
```

### REPL Commands

```
bk> help

BuildKit REPL Commands:

  Navigation & Status
    :status              Show workspace/git status overview
    :projects            List all projects with status
    :git                 Show git status across repos
    :cd <project>        Change focus to project
    :tree                Show workspace structure

  Build Operations
    :build               Run default pipeline
    :build <pipeline>    Run specific pipeline
    :test                Run tests in focused project
    :analyze             Run dart analyze

  Git Operations (guided by default)
    :commit              Start guided commit flow
    :pull                Pull with safety checks
    :sync                Full sync flow
    :branch              Branch management
    
  Pipeline Management
    :pipelines           List available pipelines
    :define <name>=<cmd> Create macro
    :undefine <name>     Remove macro
    :macros              List macros

  History
    :history             Show command history
    :!<n>                Re-run command from history

  Meta
    :help                Show this help
    :quit                Exit REPL
```

### Interactive Session Example

```
bk> :status

Workspace: ~/Code/tom2
  12 projects found
  9 git repositories
  
Git Status:
  ✓ tom2 (main) - clean
  ✓ tom_module_basics (main) - clean
  ⚠ tom_module_d4rt (main) - 3 modified files
  
bk> :cd tom_module_d4rt

Focus: tom_module_d4rt @ ~/Code/tom2/xternal/tom_module_d4rt

bk> :git

[tom_module_d4rt] main
  M lib/src/api/cli_controller.dart
  M lib/src/cli/repl_base.dart
  A lib/src/cli/new_feature.dart

bk> :commit

=== Git Commit - Guided Mode ===
...

bk> :test

Running tests in tom_module_d4rt...
  ✓ 45 passed
  ✓ 0 failed
  
bk> :sync

=== Git Sync - Guided Mode ===
...

bk> :quit
```

### Implementation Options

1. **Extend D4rtReplBase** - Leverage existing REPL infrastructure
2. **New standalone REPL** - Simpler, focused on build operations
3. **Hybrid** - Use D4rt for scripting, add BuildKit commands

#### Recommended: Option 1 - Extend D4rtReplBase

```dart
/// BuildKit REPL extending D4rt base
class BuildKitRepl extends D4rtReplBase {
  @override
  String get toolName => 'bkit';
  
  @override
  String get toolVersion => '1.0.0';
  
  @override
  bool handleAdditionalCommands(String line) {
    if (line.startsWith(':status')) {
      return _showStatus();
    }
    if (line.startsWith(':commit')) {
      return _runGuidedCommit();
    }
    // ... other commands
    return false; // Not handled, let D4rt process
  }
  
  @override
  void registerBridges(D4rt d4rt) {
    super.registerBridges(d4rt);
    // Register BuildKit-specific bridges
    d4rt.bridge(BuildKitBridge());
  }
}
```

#### Benefits of Extending D4rtReplBase

1. **Command history** - Already implemented
2. **Script execution** - Can run buildkit scripts
3. **Bridges available** - Git, file, console bridges
4. **Consistent UX** - Same key bindings, help format
5. **Replay files** - Record and playback sessions

### Alternative: Minimal Standalone REPL

If D4rt dependency is too heavy:

```dart
/// Minimal BuildKit REPL
class BuildKitMinimalRepl {
  final Console _console;
  final PersistentHistory _history;
  
  Future<void> run() async {
    print('BuildKit REPL v1.0.0');
    
    while (true) {
      stdout.write('bk> ');
      final line = stdin.readLineSync()?.trim();
      
      if (line == null || line == ':quit') break;
      
      await _handleCommand(line);
    }
  }
  
  Future<void> _handleCommand(String line) async {
    switch (line) {
      case ':status':
        await _showStatus();
      case ':commit':
        await _runGuidedCommit();
      // ...
      default:
        print('Unknown command. Type :help for help.');
    }
  }
}
```

---

## Decision Summary

### For Guided Mode

| Recommendation | Library |
|----------------|---------|
| **Primary** | `interact` - Interactive prompts |
| **Styling** | `chalkdart` - Colored output |
| **Already have** | `console_markdown`, `dart_console` |

### For BuildKit REPL

| Approach | Recommendation |
|----------|----------------|
| **Short term** | Add REPL commands to buildkit as `:repl` command |
| **Long term** | Extend D4rtReplBase for full scripting support |

### Next Steps

1. Add `interact` and `chalkdart` to tom_build_kit dependencies
2. Create `GuidedModeHelper` utility class
3. Refactor existing guided modes to use helper
4. Add guided mode to remaining git commands
5. Consider REPL implementation for future sprint
