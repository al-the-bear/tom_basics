# Tom Build Project Guidelines

**Project:** `_build` (tom_ai_build)  
**Type:** Dart Package

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
| [build.md](build.md) | Build and publishing guidelines |

## Quick Reference

**Purpose:** Workspace build configuration and automation

**Key Components:**
- Build configuration loading
- Workspace-level build orchestration
- Integration with buildkit tools

**Documentation:**
- [README](../README.md) — Quick start guide

## Related Packages

- [tom_build_kit](../../tom/xternal/tom_module_basics/tom_build_kit/) — Build tools (versioner, cleanup, compiler, etc.)
- [tom_build_cli](../../tom/devops/tom_build_cli/) — Command-line interface for build operations
