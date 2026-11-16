# Build file schemas

The two files the build tools read have JSON schemas in the container's `.tom/json-schema/buildkit/`:

| File | Schema | What it holds |
|------|--------|---------------|
| `buildkit_master.yaml` (the workspace root marker) | `.tom/json-schema/buildkit/buildkit_master.schema.json` | `navigation`, `pipelines`, `macros`, `buildkit:` (defines, `<MODE>-defines`), `required-environment`, `nested_tools`, the workspace defaults of `versioner`, `build_runner` and `doccheck`, and issuekit's `issuekit:` section |
| `buildkit.yaml` (a project's file) | `.tom/json-schema/buildkit/buildkit.schema.json` | the identity (`project_id`, `name`, `description`, `license`), `build` / `test` / `clean`, defines, `release`, `navigation`, and one section per tool or buildkit command: `versioner`, `compiler`, `cleanup`, `build_runner`, `unreferenced`, `boundaries`, `doccheck`, `testkit`, `d4rtgen`, `astgen`, `tom_reflection_generator`, `tom_reflector`, `tom_analyzer`, `dart-editor-bundler` |

## How they are kept

- **Written by hand from the readers**, not from the files: every key in a schema has a reader in tom_build_base, tom_build_kit, tom_test_kit, tom_issue_kit, tom_package_scanner, a generator (d4rtgen, astgen, the reflection generator, the reflector / analyzer) or the dart editor bundler. A key nothing reads is not in the schema; the few kept as documentation say "Not read" in their description (`pipelines.<name>.description`, `required-environment.binaries[].name`).
- **Change a reader, change its schema in the same commit**: a new key, a renamed one, a new tool section, a new enum value. Both schemas set `additionalProperties: false`, so an unknown key, a typo and a section in the wrong file (`pipelines:` in a project file) are errors.
- **Every tracked build file names its schema** on its first line, so editors with the YAML language server validate while you type:

  ```yaml
  # yaml-language-server: $schema=../../../.tom/json-schema/buildkit/buildkit.schema.json
  ```

  The path is relative to the file. A new `buildkit.yaml` gets the line with the right number of `../`.
- **The check** validates every tracked `buildkit_master.yaml` / `buildkit.yaml` against its schema and checks the first line; run it by hand from the container root after changing a schema, a reader or build files:

  ```bash
  python3 _bin/check_buildkit_schemas.py
  ```

  A file that tests invalid input on purpose goes into the script's `EXCEPTIONS` with its reason (there is none today).

## How the readers treat the keys

- `buildkit :define` / `:undefine` / `:macro` / `:unmacro` edit `buildkit_master.yaml` in place (yaml_edit): only the entry they change is written; comments and the schema line stay.
- A project's `recursive: false` keeps every tool's walk out of the project's subfolders, also with `-r` (FolderScanner).
- `required-environment` is checked before every run of the tool (not for help, version, `--nested`, the setup pipeline, a run of commands that declare `needsEnvironment: false` only, such as `buildkit :projects`, or with `TOM_BOOTSTRAP_ALLOW_MISSING_SETUP` set): an error stops the run and the output says how to fix it, from `setup.instructions` and `setup.setup-pipeline`; binaries are looked up in `binaryPath`, its `<os>-<arch>/` folder, then on PATH; `error` / `warning` / `version-error` get `%{version-constraint}` substituted. Version tests run in `doctor` only.
- Pipelines are read from `buildkit_master.yaml` only (its top-level `pipelines:`); a project's `buildkit.yaml` holds none.
- `defines:` and `<MODE>-defines:` inside a tool's section are ToolRunner's: a tool reads its section through `TomBuildConfig.readToolSection` / `withoutDefines` / `TomBuildConfig.toolOptions`, which leave them out, so a tool that refuses unknown keys and a section of only defines both work.
