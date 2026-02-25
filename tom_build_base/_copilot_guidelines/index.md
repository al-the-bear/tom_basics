# Tom Build Base Project Guidelines

**Project:** `tom_build_base`  
**Type:** Dart Package

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

## Publishing

This package is published to pub.dev. See [Project Republishing](/_copilot_guidelines/dart/project_republishing.md) for the complete publishing workflow.

## Project-Specific Guidelines

| File | Description |
|------|-------------|
| [build_base_projects.md](build_base_projects.md) | List of all projects depending on tom_build_base |
| [cli_v2_design.md](cli_v2_design.md) | V2 CLI framework architecture and design specification |
| [implementation_guidelines.md](implementation_guidelines.md) | Development workflow, test-first approach, naming conventions |

## Quick Reference

**Purpose:** Shared CLI infrastructure for Tom build tools

**Key Components:**
- **Workspace navigation** — `-s`, `-r`, `-R`, `-p`, `-x` options for directory targeting
- **Project discovery** — Scanning for pubspec.yaml, tom_project.yaml files
- **Configuration loading** — TomBuildConfig, TomProjectConfig classes
- **CLI helpers** — `isHelpCommand()`, `isVersionCommand()`, help text generation

## Terminology

### Traversal Modes

| Term | Description |
|------|-------------|
| **git-traversal** | Traversal mode that discovers and processes git repositories. Uses `-i` (inner-first) or `-o` (outer-first) flags. Inner-first processes submodules before parent repos; outer-first does the reverse. Required for git commands (`:gitstatus`, `:gitcommit`). |
| **project-traversal** | Traversal mode that discovers and processes projects by markers (pubspec.yaml, tom_project.yaml, etc.). Uses `-s`/`--scan` and `-r`/`--recursive` flags. Default mode when no git flags specified. |

### Execution Modes

| Term | Description |
|------|-------------|
| **kit-mode** | Running a tool as a buildkit command (e.g., `buildkit :versioner`). Options parsed by buildkit orchestrator, tool receives pre-processed args. Supports pipelines and multi-command execution. |
| **standalone-mode** | Running a tool directly as a binary (e.g., `versioner --scan .`). Tool parses its own args using ToolBase infrastructure. No buildkit orchestration. |

### Navigation Flags

| Flag | Mode | Description |
|------|------|-------------|
| `-i`, `--inner-first-git` | git-traversal | Process deepest repos first (submodules before parents) |
| `-o`, `--outer-first-git` | git-traversal | Process shallowest repos first (parents before submodules) |
| `-T`, `--top-repo` | git-traversal | Find topmost git repo by walking up from cwd |
| `-s`, `--scan` | project-traversal | Starting directory for project scan |
| `-r`, `--recursive` | project-traversal | Recurse into subdirectories during scan |
| `-R`, `--root` | both | Set/detect workspace root |
| `-p`, `--project` | project-traversal | Filter projects by glob pattern |

**Documentation:**
- [Build Base User Guide](../doc/build_base_user_guide.md) — Full API documentation
- [CLI Tools Navigation](../doc/cli_tools_navigation.md) — Navigation options reference
- [Modes and Placeholders](../doc/modes_and_placeholders.md) — Mode system and placeholder resolution
- [README](../README.md) — Quick start guide

## Dependent Projects

See [build_base_projects.md](build_base_projects.md) for the full list of projects that depend on this package.
