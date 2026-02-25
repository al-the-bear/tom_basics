# Tom Build Base - Dependent Projects

This document lists all projects in the workspace that depend on `tom_build_base` and are part of the buildkit family of tools.

## Dependent Projects

| Project | Path | Description |
|---------|------|-------------|
| tom_build_kit | `xternal/tom_module_basics/tom_build_kit/` | Build tools collection (versioner, cleanup, compiler, runner, etc.) |
| tom_analyzer | `xternal/tom_module_basics/tom_analyzer/` | Code analysis and workspace scanning tool |
| tom_d4rt_astgen | `xternal/tom_module_basics/tom_d4rt_astgen/` | D4rt AST generator for bridge code |
| tom_d4rt_generator | `xternal/tom_module_d4rt/tom_d4rt_generator/` | D4rt bridge code generator |

## What They Inherit

All dependent projects inherit from tom_build_base:

- **Workspace navigation options** — `-s`, `-r`, `-R`, `-p`, `-x`, etc.
- **Project discovery** — Scanning for pubspec.yaml, tom_project.yaml
- **Configuration loading** — TomBuildConfig, TomProjectConfig
- **CLI standardization** — `--help`, `--version`, usage patterns

## Adding a New Dependent

When adding a new project that depends on tom_build_base:

1. Add `tom_build_base:` to pubspec.yaml dependencies
2. Create `_copilot_guidelines/implementation_hints.md` for the project
3. Update this list in both:
   - `tom_build_base/_copilot_guidelines/build_base_projects.md`
   - `tom_build_kit/_copilot_guidelines/build_base_projects.md`
