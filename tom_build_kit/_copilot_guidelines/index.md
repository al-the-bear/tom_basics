# Tom Build Kit Project Guidelines

**Project:** `tom_build_kit`  
**Type:** CLI Tool

## Essential: DCli for File/Directory Operations

> **IMPORTANT:** Use DCli for ALL file and directory manipulation. Do not use `dart:io` directly.

DCli provides Dart equivalents for Unix commands: `cp`, `mv`, `rm`, `mkdir`, `cat`, `find`, `head`, `tail`, `which`, `chmod`, `touch`, `ln -s`, and more.

| Document | Purpose |
|----------|----------|
| [DCli Overview](/_copilot_guidelines/d4rt/dcli_overview.md) | Introduction, command equivalents table, examples |
| [DCli Scripting Guide](/_copilot_guidelines/d4rt/dcli_scripting_guide.md) | Complete API reference |
| [dcli_usage.md](dcli_usage.md) | Project-specific DCli patterns |

**Quick Start:**
```dart
import 'package:dcli/dcli.dart';

// File operations: copy, move, delete, cat, read, head, tail, touch, replace
copy('src.txt', 'dst.txt');
cat('file.txt');
final lines = read('file.txt').toList();

// Directory operations: createDir, deleteDir, find, exists, isDirectory
createDir('path/to/dir', recursive: true);
find('*.dart', recursive: true).forEach((f) => print(f.path));

// Command execution
'dart --version'.run;
final output = 'ls -la'.toList();
```

## Global Guidelines

| Document | Purpose |
|----------|---------|
| [Documentation Guidelines](/_copilot_guidelines/documentation_guidelines.md) | Where to place user docs vs development docs |

## Dart Guidelines

| Document | Purpose |
|----------|---------|
| [Coding Guidelines](/_copilot_guidelines/dart/coding_guidelines.md) | Naming conventions, error handling, patterns |
| [Unit Tests](/_copilot_guidelines/dart/unit_tests.md) | Test structure, matchers, mocking patterns |
| [Examples](/_copilot_guidelines/dart/examples.md) | Example file creation guidelines |

## Project-Specific Guidelines

| File | Description |
|------|-------------|
| [build_base_projects.md](build_base_projects.md) | List of all projects depending on tom_build_base |
| [implementation_hints.md](implementation_hints.md) | tom_build_base integration, CLI infrastructure, and strict base-first ownership workflow |
| [testing.md](testing.md) | Testing guidelines |

## Quick Reference

**Purpose:** Build tools for the Tom workspace

**Key Components:**
- **versioner** — Generate version.versioner.dart files with build metadata
- **bumpversion** — Bump pubspec.yaml versions across projects
- **cleanup** — Remove generated and temporary files
- **compiler** — Cross-platform Dart compilation
- **runner** — build_runner wrapper with builder filtering
- **dependencies** — Dependency tree visualization
- **buildsorter** — Build order sorting
- **buildkit** — Pipeline orchestrator

**Documentation:**
- [Tools User Guide](../doc/tools_user_guide.md) — Individual tool reference
- [BuildKit User Guide](../doc/buildkit_user_guide.md) — Pipeline orchestrator
- [Git Guide Mode](../doc/git_guide_mode.md) — Guided mode flows for git commands
- [Standalone Guided Mode](../doc/standalone_guided_mode.md) — Guided mode for Docker, Dart, Flutter tools
- [BuildKit Guided](../doc/buildkit_guided.md) — `bk -g` workspace build flow proposal
- [Flutter Commands](../doc/flutter_buildkit_commands.md) — Proposed Flutter-specific BuildKit commands
- [REPL Integration](../doc/tom_buildkit_repls.md) — Tom CLI / BuildKit REPL assessment
- [Console UI Libraries](../doc/console_ui_libraries.md) — Library recommendations for interactive CLI
- [README](../README.md) — Quick start guide

## Related Packages

- [tom_build_base](../../tom_build_base/) — Shared CLI infrastructure (navigation, project discovery)
- [tom_d4rt_astgen](../../tom_d4rt_astgen/) — AST generator tool
- [tom_analyzer](../../tom_analyzer/) — Code analysis tool

## Dependencies

This package depends on **tom_build_base** for:
- Workspace navigation options (`-s`, `-r`, `-R`, `-p`, `-x`, etc.)
- Project discovery and scanning
- Configuration loading (TomBuildConfig)
- CLI standardization (help/version commands)

See [implementation_hints.md](implementation_hints.md) for details.
