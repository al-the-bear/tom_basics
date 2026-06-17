# Flutter BuildKit Commands Proposal

This document proposes Flutter-specific commands for BuildKit.

## Overview

BuildKit currently focuses on Dart packages and git operations. This proposal adds Flutter-specific tooling for workspace-wide Flutter operations.

---

## Proposed Commands

### Core Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `bk :flutter` | `flutter` | Run Flutter commands across projects |
| `bk :flutterbuild` | `flutterbuild` | Build Flutter apps (APK, AAB, iOS, web, desktop) |
| `bk :flutterrun` | `flutterrun` | Run Flutter apps with device selection |
| `bk :fluttertest` | `fluttertest` | Run Flutter tests (unit, widget, integration) |
| `bk :flutterdoctor` | `flutterdoctor` | Run flutter doctor across workspace |
| `bk :flutterclean` | `flutterclean` | Clean Flutter build artifacts |
| `bk :flutterupgrade` | `flutterupgrade` | Upgrade Flutter dependencies |

### Specialized Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `bk :fluttergolden` | `fluttergolden` | Update golden test files |
| `bk :flutterflavor` | `flutterflavor` | Build/run with flavor configuration |
| `bk :flutterlocalize` | `flutterlocalize` | Generate localization files |
| `bk :flutterassets` | `flutterassets` | Generate asset classes (flutter_gen) |
| `bk :fluttericons` | `fluttericons` | Generate app icons |
| `bk :fluttersplash` | `fluttersplash` | Generate splash screens |

---

## Command Details

### flutterbuild

**Purpose:** Build Flutter apps across the workspace.

```bash
# Usage
flutterbuild [options] [project-filter]

# Options
--platform, -p    Target platform (android, ios, web, macos, linux, windows)
--mode            Build mode (debug, profile, release) [default: release]
--flavor          Build flavor
--target, -t      Entry point file
--split-debug     Split debug info for smaller builds
--obfuscate       Obfuscate Dart code
--tree-shake      Remove unused icons
--output, -o      Output directory

# Examples
flutterbuild -p android --mode release
flutterbuild -p web --flavor production
flutterbuild -p ios --split-debug --obfuscate
```

**Workspace traversal:**
- Uses `--inner-first` by default (builds dependencies first)
- Detects Flutter projects via `pubspec.yaml` (contains `flutter:` section)

**Guided mode:**
```bash
flutterbuild -g
```
See [standalone_guided_mode.md](standalone_guided_mode.md#flutterbuild--g-proposed) for flow.

---

### flutterrun

**Purpose:** Run Flutter apps with device/emulator selection.

```bash
# Usage
flutterrun [options] [project]

# Options
--device, -d      Target device ID
--mode            Run mode (debug, profile, release) [default: debug]
--flavor          Run with flavor
--hot-restart     Start with hot restart capability
--trace-startup   Trace startup performance
--web-port        Web server port [default: 8080]

# Examples
flutterrun -d chrome
flutterrun --device "iPhone 15 Pro"
flutterrun --flavor development --mode debug
```

**Device discovery:**
- Runs `flutter devices` to list available devices
- Supports emulator/simulator launch if none running

---

### fluttertest

**Purpose:** Run Flutter tests workspace-wide.

```bash
# Usage
fluttertest [options] [project-filter]

# Options
--type            Test type (unit, widget, integration, all) [default: all]
--coverage        Collect coverage data
--update-goldens  Update golden test files
--reporter        Output format (compact, expanded, json)
--concurrency     Number of parallel test suites
--tags            Run tests with specific tags
--exclude-tags    Exclude tests with specific tags

# Examples
fluttertest --type widget --coverage
fluttertest --update-goldens
fluttertest --tags "slow" --concurrency 1
```

**Integration tests:**
- Detects `integration_test/` folder
- Requires device selection for integration tests

---

### flutterclean

**Purpose:** Clean Flutter build artifacts.

```bash
# Usage
flutterclean [options] [project-filter]

# Options
--all             Clean all projects in workspace
--build           Clean only build/ folder
--cache           Clean Flutter cache (~/.pub-cache)
--generated       Remove generated files (*.g.dart, *.freezed.dart)

# Examples
flutterclean --all
flutterclean --build --generated
```

---

### fluttergolden

**Purpose:** Manage golden test files.

```bash
# Usage
fluttergolden [options] [project-filter]

# Options
--update          Update all golden files
--compare         Compare against existing goldens
--device          Device profile for goldens (pixel_5, iphone_14, etc.)
--path            Path to golden test files

# Examples
fluttergolden --update
fluttergolden --compare --device pixel_5
```

---

### flutterflavor

**Purpose:** Manage flavor-based builds and runs.

```bash
# Usage
flutterflavor [options] [project]

# Options
--list            List available flavors
--create          Create new flavor configuration
--build           Build specific flavor
--run             Run specific flavor

# Examples
flutterflavor --list
flutterflavor --build production -p android
flutterflavor --run development -d chrome
```

---

### flutterlocalize

**Purpose:** Generate and manage localizations.

```bash
# Usage
flutterlocalize [options] [project]

# Options
--generate        Generate from .arb files
--add-locale      Add new locale
--extract         Extract strings to .arb
--verify          Verify all locales are complete

# Examples
flutterlocalize --generate
flutterlocalize --add-locale es
flutterlocalize --verify
```

---

### flutterassets

**Purpose:** Generate type-safe asset references.

```bash
# Usage
flutterassets [options] [project]

# Options
--generate        Generate asset classes
--watch           Watch for asset changes
--output          Output file path

# Examples
flutterassets --generate
flutterassets --watch
```

Uses `flutter_gen` or similar codegen under the hood.

---

## Implementation Considerations

### Project Detection

Flutter projects are identified by:
1. `pubspec.yaml` exists
2. Contains `flutter:` section
3. Has `lib/main.dart` or specified entry point

```dart
bool isFlutterProject(String dirPath) {
  final pubspec = File(p.join(dirPath, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  
  final content = pubspec.readAsStringSync();
  return content.contains('flutter:');
}
```

### Platform Detection

Detect available platforms from project structure:
- `android/` → Android support
- `ios/` → iOS support
- `web/` → Web support
- `macos/` → macOS support
- `linux/` → Linux support
- `windows/` → Windows support

### Workspace Traversal

Use existing `WorkspaceNavigationArgs` with Flutter-specific detection:

```dart
class FlutterToolBase extends BuildtoolBase {
  @override
  bool isToolProject(String dirPath) {
    return isFlutterProject(dirPath);
  }
}
```

### Error Handling

Common Flutter errors to handle:
- Flutter SDK not found
- No devices available
- Platform not enabled
- Build failures with actionable hints

---

## Priority

### Phase 1 (Essential)

1. `flutterclean` - Most frequently needed
2. `flutterbuild` - Core build functionality
3. `fluttertest` - Testing support
4. `flutterrun` - Development workflow

### Phase 2 (Productivity)

5. `fluttergolden` - Golden test management
6. `flutterflavor` - Flavor configurations
7. `flutter` - Generic command wrapper

### Phase 3 (Specialized)

8. `flutterlocalize` - L10n support
9. `flutterassets` - Asset generation
10. `fluttericons` / `fluttersplash` - App customization

---

## Integration with Existing Commands

### cleanup

Add Flutter-specific cleanup:
```bash
cleanup --flutter   # Removes Flutter build artifacts
```

### runner

Support Flutter app execution:
```bash
runner --flutter -d chrome
```

### dependencies

Show Flutter dependencies:
```bash
dependencies --flutter   # Shows flutter: and dev_dependencies with flutter
```
