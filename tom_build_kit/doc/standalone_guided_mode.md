# Standalone Guided Mode Design

This document describes guided mode (`-g` / `--guide`) for standalone tools beyond git commands.

## Overview

Guided mode provides a step-by-step, menu-driven interface for CLI tools. It follows the same principles as [git_guide_mode.md](git_guide_mode.md):

- **Main flow** leads to completion (execute → exit)
- **Sub-flows** return to parent step when done
- **Confirmation gate** shows preview before execution
- **Self-documenting** through on-screen descriptions

---

## Git Tools (Reference)

See [git_guide_mode.md](git_guide_mode.md) for complete git command flows.

| Command | Primary Use Case |
|---------|------------------|
| `gitstatus -g` | View status, offer quick actions |
| `gitcommit -g` | Stage, message, push workflow |
| `gitpull -g` | Pull with merge/rebase options |
| `gitsync -g` | Complete sync workflow |
| `gitbranch -g` | Create, switch, delete branches |
| `gittag -g` | Create, push, delete tags |
| `gitcheckout -g` | Switch to branch/tag/commit |
| `gitreset -g` | Reset with mode selection |
| `gitclean -g` | Clean untracked files safely |
| `gitprune -g` | Prune stale remote branches |
| `gitstash -g` | Stash changes with options |
| `gitunstash -g` | Restore stashes |
| `gitcompare -g` | Compare branches/commits |
| `gitmerge -g` | Merge with preview |
| `gitsquash -g` | Squash commits guided |
| `gitrebase -g` | Rebase with options |

---

## Docker Tools

### docker -g (Proposed)

**Use case:** Run Docker commands across workspace containers.

```
=== Docker - Guided Mode ===

What would you like to do?
  1. View container status
  2. Start containers
  3. Stop containers
  4. Build images
  5. View logs
  6. Execute in container
  7. Exit

Choose [1-7]:
```

### dockerbuild -g (Proposed)

**Use case:** Build Docker images with guided configuration.

```
=== Docker Build - Guided Mode ===

Step 1: Select project to build
  1. tom_uam_server (has Dockerfile)
  2. tom_sqm_server (has Dockerfile)
  3. tom_assistant_server (has Dockerfile)
  4. Cancel

Choose [1-4]: 1

Step 2: Build type
  1. Development (includes dev tools, debug)
  2. Production (optimized, minimal)
  3. Cancel

Choose [1-3]: 2

Step 3: Tag the image
  Default tag: tom_uam_server:latest
  Enter tag (or press Enter for default): v1.2.0

Step 4: Build options
  [ ] No cache (--no-cache)
  [x] Pull base images (--pull)
  [ ] Squash layers (--squash)

Preview:
  docker build -t tom_uam_server:v1.2.0 --pull -f Dockerfile.prod .

Proceed? [Y/n]:
```

### dockerrun -g (Proposed)

**Use case:** Run containers with guided port/volume mapping.

```
=== Docker Run - Guided Mode ===

Step 1: Select image
  Local images:
  1. tom_uam_server:v1.2.0
  2. tom_sqm_server:latest
  3. postgres:15
  4. Enter image name manually
  5. Cancel

Choose [1-5]: 1

Step 2: Port mappings
  Exposed ports: 8080, 9090
  
  8080 -> Host port [8080]:
  9090 -> Host port [9090]:

Step 3: Environment
  1. Use .env file
  2. Enter variables manually
  3. Skip

Choose [1-3]: 1
  Select .env file: .env.local

Step 4: Volume mounts
  1. Add mount
  2. Skip mounts
  
Choose [1-2]:

Step 5: Run mode
  1. Foreground (attached)
  2. Background (detached, -d)
  3. Cancel

Preview:
  docker run -d -p 8080:8080 -p 9090:9090 \
    --env-file .env.local \
    tom_uam_server:v1.2.0

Proceed? [Y/n]:
```

### dockerlogs -g (Proposed)

```
=== Docker Logs - Guided Mode ===

Running containers:
  1. tom_uam_server (up 2h)
  2. postgres-db (up 2h)
  3. redis-cache (up 2h)
  4. Cancel

Choose [1-4]: 1

Log options:
  1. Last 100 lines (default)
  2. Last N lines
  3. Follow (tail -f)
  4. Since timestamp
  5. Cancel

Choose [1-5]:
```

---

## Dart Tools

### dartanalyze -g (Proposed)

**Use case:** Run dart analyze with guided options.

```
=== Dart Analyze - Guided Mode ===

Step 1: Scope
  1. Current project only
  2. All workspace projects
  3. Select projects
  4. Cancel

Choose [1-4]: 3

Select projects (space to toggle):
  [x] tom_core_kernel
  [x] tom_core_flutter
  [ ] tom_uam_server
  [ ] tom_sqm_server
  
  Enter - Confirm selection

Step 2: Options
  [ ] Fatal infos (treat infos as fatal)
  [ ] Fatal warnings (treat warnings as fatal)
  [x] Show statistics

Preview:
  dart analyze tom_core_kernel tom_core_flutter

Proceed? [Y/n]:
```

### darttest -g (Proposed)

**Use case:** Run dart test with guided selection.

```
=== Dart Test - Guided Mode ===

Step 1: Scope
  1. All tests in project
  2. Specific test file
  3. Tests matching pattern
  4. Failed tests only (from last run)
  5. Cancel

Choose [1-5]: 2

Select test file:
  1. test/unit/parser_test.dart
  2. test/unit/validator_test.dart
  3. test/integration/api_test.dart
  4. Enter path manually

Choose [1-4]: 1

Step 2: Options
  [ ] Verbose output
  [x] Coverage collection
  [ ] Update golden files
  [ ] Chain test on save

Preview:
  dart test --coverage test/unit/parser_test.dart

Proceed? [Y/n]:
```

### dartformat -g (Proposed)

```
=== Dart Format - Guided Mode ===

Step 1: Scope
  1. Current project
  2. All workspace projects
  3. Select files
  4. Cancel

Choose [1-4]: 1

Step 2: Options
  1. Format in place (--fix)
  2. Preview changes only (--set-exit-if-changed)
  3. Cancel

Choose [1-3]: 2

Checking files...

Files that would change:
  lib/src/api.dart
  lib/src/models/user.dart

Apply formatting? [Y/n]:
```

### pubget -g (Proposed)

```
=== Pub Get - Guided Mode ===

Step 1: Scope
  1. Current project only
  2. All workspace projects
  3. Select projects
  4. Cancel

Choose [1-4]: 2

Step 2: Options
  [ ] Offline mode
  [x] Upgrade dependencies (pub upgrade)
  [ ] Dry run

Preview:
  Running pub get in 12 projects...

Proceed? [Y/n]:
```

---

## Flutter Tools

### flutterbuild -g (Proposed)

**Use case:** Build Flutter apps with platform selection.

```
=== Flutter Build - Guided Mode ===

Step 1: Select project
  Flutter projects found:
  1. tom_assistant_flutter
  2. tom_uam_flutter
  3. tom_pass_flutter
  4. Cancel

Choose [1-4]: 1

Step 2: Platform
  1. Android APK
  2. Android App Bundle (AAB)
  3. iOS
  4. macOS
  5. Linux
  6. Windows
  7. Web
  8. Cancel

Choose [1-8]: 7

Step 3: Build mode
  1. Debug
  2. Profile
  3. Release [default]
  4. Cancel

Choose [1-4]: 3

Step 4: Options
  [ ] Tree shake icons
  [x] Split debug info
  [ ] Obfuscate

Step 5: Flavor (if applicable)
  1. Development
  2. Staging
  3. Production
  4. No flavor

Choose [1-4]: 3

Preview:
  flutter build web --release --flavor production \
    --split-debug-info=build/debug-info

Proceed? [Y/n]:
```

### flutterrun -g (Proposed)

```
=== Flutter Run - Guided Mode ===

Step 1: Select device
  Available devices:
  1. iPhone 15 Pro (simulator)
  2. Pixel 7 (emulator)
  3. Chrome (web)
  4. macOS (desktop)
  5. Cancel

Choose [1-5]: 3

Step 2: Build mode
  1. Debug (hot reload enabled) [default]
  2. Profile
  3. Release
  4. Cancel

Choose [1-4]: 1

Step 3: Flavor
  1. Development [default]
  2. Staging
  3. Production
  4. No flavor

Choose [1-4]: 1

Preview:
  flutter run -d chrome --flavor development

Proceed? [Y/n]:
```

### fluttertest -g (Proposed)

```
=== Flutter Test - Guided Mode ===

Step 1: Test type
  1. Unit tests
  2. Widget tests
  3. Integration tests
  4. All tests
  5. Golden tests only
  6. Cancel

Choose [1-6]: 5

Step 2: Golden test action
  1. Run and compare
  2. Update goldens [default]
  3. Cancel

Choose [1-3]: 2

Preview:
  flutter test --update-goldens test/golden/

Proceed? [Y/n]:
```

---

## Design Principles

### Menu Structure

```dart
enum MenuResult {
  selected,   // User chose an option
  cancelled,  // User pressed Escape or chose Cancel
  back,       // User wants to go back (sub-flow)
}

Future<(MenuResult, T?)> showMenu<T>({
  required String title,
  required List<MenuOption<T>> options,
  bool allowBack = false,
  T? defaultValue,
});
```

### Confirmation Pattern

All flows end with a confirmation gate:

```
Preview:
  [command to be executed]

Proceed? [Y/n]:
```

- `Y` or `Enter` - Execute and exit
- `n` - Cancel and exit
- No loop back to menu (use case is complete or cancelled)

### Error Handling

```
Error: No Docker daemon running

Options:
  1. Start Docker Desktop
  2. Retry
  3. Exit

Choose [1-3]:
```

### Progress Display

For long operations:
```
Building tom_uam_server:v1.2.0...

Step 1/5: Downloading base image...
Step 2/5: Installing dependencies...
Step 3/5: Copying source files...
Step 4/5: Building application...
Step 5/5: Finalizing image...

✓ Build complete: tom_uam_server:v1.2.0 (245MB)
```

---

## Implementation Notes

### Library Dependencies

See [console_ui_libraries.md](console_ui_libraries.md) for recommended packages:
- `interact` - Menus, spinners, confirmations
- `chalkdart` - Terminal styling
- `mason_logger` - Progress indicators

### Shared Utilities

Create `lib/src/guided/` folder:
- `guided_menu.dart` - Menu display and input
- `guided_confirm.dart` - Confirmation prompts
- `guided_progress.dart` - Progress indicators
- `guided_file_picker.dart` - File/directory selection

### Integration with BuildKit

All guided commands should:
1. Check for `--guide` / `-g` flag in `run()`
2. Call `_runGuided()` method if flag is set
3. Use standard argument parsing for non-guided mode
4. Support same options in both modes

```dart
@override
Future<bool> run(List<String> args) async {
  final results = parseArgs(args);
  
  if (results['guide'] as bool) {
    return await _runGuided(results);
  }
  
  // Normal execution
  return await _runCommand(results);
}
```
