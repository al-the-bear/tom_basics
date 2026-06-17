# BuildKit Guided Mode - Workspace Build Flow

This document proposes `bk --guide` for comprehensive workspace build operations with git integration and project scope selection.

## Overview

`bk --guide` provides a top-level guided experience for complete workspace operations:
- Full build cycles across multiple projects
- Git synchronization before/after builds
- Deployment preparation
- Development mode setup

---

## Entry Point

```bash
bk -g
# or
bk --guide
```

```
=== BuildKit - Guided Mode ===

Welcome to BuildKit workspace management.

What would you like to do?
  1. Quick sync & build (development)
  2. Full release build
  3. Git operations
  4. Deployment preparation
  5. Workspace maintenance
  6. Exit

Choose [1-6]:
```

---

## Flow 1: Quick Sync & Build (Development)

**Use case:** Daily development - sync, build, run.

```
=== Quick Sync & Build ===

Step 1: Git synchronization
  Checking workspace status...
  
  Repositories:
    ✓ tom2 (main) - clean
    ⚠ tom_module_d4rt (main) - 2 uncommitted files
    ✓ tom_module_basics (main) - clean
  
  [1] Pull all repositories first
  [2] Skip git sync (use current state)
  [3] View uncommitted changes
  [4] Cancel

Choose [1-4]: 1
```

```
Step 2: Select scope
  [1] All projects (17 packages)
  [2] Modified projects only (3 packages)
  [3] Specific project group
  [4] Cancel

Choose [1-4]: 3

Project groups:
  [1] Core packages (tom_core_*)
  [2] Server packages (*_server)
  [3] Flutter apps (*_flutter)
  [4] Build tools (_build, tom_build_*)
  [5] Custom selection

Choose [1-5]: 1
```

```
Step 3: Build actions
  [x] Run pub get
  [x] Run build_runner
  [ ] Run dart analyze
  [ ] Run tests
  
  Space to toggle, Enter to confirm
```

```
Step 4: Development mode
  [1] Start watch mode (build_runner watch)
  [2] Build once and exit
  [3] Cancel

Choose [1-3]: 2
```

```
Preview:
  Scope: tom_core_kernel, tom_core_flutter, tom_core_server
  
  Actions:
    1. git pull (3 repositories)
    2. pub get (3 packages)
    3. build_runner build (3 packages)

Estimated time: ~2 minutes

Proceed? [Y/n]:
```

```
=== Executing ===

[1/3] Syncing git repositories...
  ✓ tom2 - up to date
  ✓ tom_module_d4rt - pulled 3 commits
  ✓ tom_module_basics - up to date

[2/3] Running pub get...
  ✓ tom_core_kernel
  ✓ tom_core_flutter  
  ✓ tom_core_server

[3/3] Running build_runner...
  ✓ tom_core_kernel (12 files generated)
  ✓ tom_core_flutter (8 files generated)
  ✓ tom_core_server (15 files generated)

=== Complete ===
Build finished in 1m 42s
```

---

## Flow 2: Full Release Build

**Use case:** Prepare for release - version bump, build all, tag.

```
=== Full Release Build ===

Step 1: Pre-flight checks
  Checking workspace state...
  
  ⚠ Issues found:
    - tom_core_kernel: uncommitted changes
    - tom_uam_server: 2 analyzer warnings
  
  [1] Fix issues first (recommended)
  [2] Continue anyway
  [3] Cancel

Choose [1-3]: 1
```

```
Step 2: Version management
  Current versions:
    tom_core_kernel: 1.2.3
    tom_core_flutter: 1.1.0
    tom_core_server: 2.0.1
  
  [1] Bump all (patch: 1.2.3 → 1.2.4)
  [2] Bump all (minor: 1.2.3 → 1.3.0)
  [3] Bump all (major: 1.2.3 → 2.0.0)
  [4] Individual version selection
  [5] Skip version bump

Choose [1-5]: 1
```

```
Step 3: Build configuration
  [x] Clean build (remove previous artifacts)
  [x] Run full test suite
  [x] Generate documentation
  [ ] Build executables (compile)
  
  Space to toggle, Enter to confirm
```

```
Step 4: Release actions
  [x] Create git tags
  [x] Push to remote
  [ ] Publish to pub.dev
  [ ] Create GitHub release
  
  Space to toggle, Enter to confirm
```

```
Preview:
  1. Clean all build artifacts
  2. Bump versions (patch)
  3. Run pub get
  4. Run build_runner
  5. Run dart analyze
  6. Run all tests
  7. Commit version changes
  8. Create tags (v1.2.4)
  9. Push to remote

Proceed? [Y/n]:
```

---

## Flow 3: Git Operations

**Use case:** Workspace-wide git management.

```
=== Git Operations ===

What would you like to do?
  [1] Status overview
  [2] Sync all (pull + push)
  [3] Commit changes
  [4] Branch operations
  [5] Tag operations
  [6] Back to main menu

Choose [1-6]:
```

Each option launches the corresponding tool's guided mode:
- `gitstatus -g`
- `gitsync -g`
- `gitcommit -g`
- `gitbranch -g`
- `gittag -g`

---

## Flow 4: Deployment Preparation

**Use case:** Prepare for cloud deployment.

```
=== Deployment Preparation ===

Step 1: Select deployment target
  [1] Docker images
  [2] Cloud Functions
  [3] Static web hosting
  [4] Kubernetes manifests
  [5] Cancel

Choose [1-5]: 1
```

```
Step 2: Select applications
  Server applications detected:
  [x] tom_uam_server
  [x] tom_sqm_server
  [ ] tom_assistant_server
  
  Space to toggle, Enter to confirm
```

```
Step 3: Build configuration
  Target environment:
  [1] Development
  [2] Staging
  [3] Production

Choose [1-3]: 3

Registry:
  [1] Docker Hub
  [2] GitHub Container Registry
  [3] AWS ECR
  [4] Custom registry

Choose [1-4]: 2
```

```
Step 4: Image options
  [x] Multi-stage build (smaller images)
  [x] Include healthcheck
  [ ] Run security scan
  
  Tag format:
  [1] Version tag (v1.2.4)
  [2] Git SHA (abc1234)
  [3] Date tag (2026-02-10)
  [4] Custom

Choose [1-4]: 1
```

```
Preview:
  Build images:
    ghcr.io/al-the-bear/tom_uam_server:v1.2.4
    ghcr.io/al-the-bear/tom_sqm_server:v1.2.4
  
  Commands:
    docker build -t ghcr.io/al-the-bear/tom_uam_server:v1.2.4 tom_uam_server/
    docker build -t ghcr.io/al-the-bear/tom_sqm_server:v1.2.4 tom_sqm_server/
    docker push ghcr.io/al-the-bear/tom_uam_server:v1.2.4
    docker push ghcr.io/al-the-bear/tom_sqm_server:v1.2.4

Proceed? [Y/n]:
```

---

## Flow 5: Workspace Maintenance

**Use case:** Clean up and maintain workspace health.

```
=== Workspace Maintenance ===

What would you like to do?
  [1] Clean build artifacts
  [2] Analyze code quality
  [3] Update dependencies
  [4] Fix formatting
  [5] Prune git branches
  [6] Back to main menu

Choose [1-6]:
```

### Clean Build Artifacts

```
=== Clean Build Artifacts ===

What to clean?
  [x] Build folders (build/, .dart_tool/)
  [x] Generated files (*.g.dart, *.freezed.dart)
  [ ] Dependencies (delete pubspec.lock)
  [ ] IDE caches (.idea/, .vscode/)
  
  Space to toggle, Enter to confirm

Scope:
  [1] All projects
  [2] Select projects

Choose [1-2]: 1

Preview:
  Will remove:
    - 23 build/ folders
    - 156 generated files
    
  Disk space recovered: ~450MB

Proceed? [Y/n]:
```

### Update Dependencies

```
=== Update Dependencies ===

Checking for updates...

Updates available:
  freezed: 2.3.2 → 2.4.0
  riverpod: 3.0.0 → 3.1.0
  json_serializable: 6.6.0 → 6.7.0

  [1] Update all
  [2] Update selected
  [3] Show changelogs
  [4] Cancel

Choose [1-4]: 1

Apply to:
  [1] All packages using these dependencies
  [2] Select packages

Choose [1-2]: 1
```

---

## Project Scope Selection

### Scope Types

| Type | Description | Example Filter |
|------|-------------|----------------|
| All | Every project in workspace | No filter |
| Modified | Projects with uncommitted changes | Git status check |
| Group | Predefined project groups | `tom_core_*` |
| Custom | Manual selection | Interactive picker |
| Single | One specific project | Path argument |

### Predefined Groups

```yaml
# In tom_workspace.yaml
build_groups:
  core:
    pattern: "tom_core_*"
    description: "Core framework packages"
  
  servers:
    pattern: "*_server"
    description: "Server applications"
  
  flutter:
    pattern: "*_flutter"
    description: "Flutter applications"
  
  build_tools:
    paths:
      - "_build"
      - "tom_build_kit"
    description: "Build and tooling"
```

### Custom Selection UI

```
Select projects (space to toggle, / to filter):

  Workspace: tom2
  [ ] _build
  [ ] _scripts
  [x] core/
      [x] tom_core_kernel
      [x] tom_core_flutter
      [x] tom_core_server
  [ ] uam/
      [ ] tom_uam_server
      [ ] tom_uam_client

Filter: core_
Matched: 3 projects

Shortcuts:
  a - Select all
  n - Deselect all
  g - Select by group
  / - Filter by name
  Enter - Confirm
```

---

## Development Mode Integration

### Watch Mode

```
=== Watch Mode ===

Starting development watch...

Watching:
  - tom_core_kernel (build_runner)
  - tom_core_flutter (build_runner)
  - tom_assistant_flutter (flutter)

Press Ctrl+C to stop, 'r' to force rebuild

[10:23:45] Watching 3 projects...
[10:24:01] tom_core_kernel: Detected change in lib/src/models/
[10:24:02] tom_core_kernel: Regenerating... ✓
[10:24:15] tom_core_flutter: Detected change in lib/src/widgets/
[10:24:16] tom_core_flutter: Regenerating... ✓
```

### Development Server

```
=== Development Server ===

Starting development environment...

Services:
  ✓ PostgreSQL (localhost:5432)
  ✓ Redis (localhost:6379)
  ✓ tom_uam_server (localhost:8080)
  ✓ tom_sqm_server (localhost:8081)

Press Ctrl+C to stop all services

Logs:
  [uam] 10:25:01 Request: GET /api/users
  [sqm] 10:25:03 Request: POST /api/subscriptions
```

---

## Configuration

### Workspace Presets

Save commonly used configurations:

```yaml
# tom_workspace.yaml
guided_presets:
  daily_dev:
    name: "Daily Development"
    actions:
      - git_pull
      - pub_get
      - build_runner_watch
    scope: modified
    
  release:
    name: "Release Build"
    actions:
      - git_pull
      - clean
      - pub_get
      - build_runner
      - analyze
      - test
      - version_bump
      - git_commit
      - git_tag
      - git_push
    scope: all
```

### Quick Launch

```bash
# Use saved preset
bk -g daily_dev

# Skip to specific flow
bk -g --flow release
bk -g --flow git
bk -g --flow deploy
```

---

## Error Recovery

### Build Failure

```
=== Build Failed ===

tom_core_server failed:
  Error: Missing dependency 'freezed_annotation'

Options:
  [1] Run pub get and retry
  [2] Skip this package
  [3] Open in editor
  [4] Abort build

Choose [1-4]:
```

### Test Failure

```
=== Tests Failed ===

2 failures in tom_core_kernel:
  - test/unit/parser_test.dart: Expected 42, got 41
  - test/integration/api_test.dart: Timeout

Options:
  [1] Continue (mark as warning)
  [2] Retry failed tests
  [3] Open test file
  [4] Abort

Choose [1-4]:
```

---

## Implementation Notes

### State Machine

```dart
enum BuildKitState {
  mainMenu,
  quickBuild,
  fullRelease,
  gitOperations,
  deployment,
  maintenance,
  executing,
  complete,
  error,
}

class GuidedBuildKit {
  BuildKitState _state = BuildKitState.mainMenu;
  
  Future<void> run() async {
    while (_state != BuildKitState.complete) {
      switch (_state) {
        case BuildKitState.mainMenu:
          _state = await _showMainMenu();
        case BuildKitState.quickBuild:
          _state = await _runQuickBuild();
        // ...
      }
    }
  }
}
```

### Progress Tracking

```dart
class BuildProgress {
  final int totalSteps;
  int currentStep = 0;
  String currentAction = '';
  
  void update(String action) {
    currentStep++;
    currentAction = action;
    _render();
  }
  
  void _render() {
    final percent = (currentStep / totalSteps * 100).round();
    print('[$percent%] $currentAction');
  }
}
```
