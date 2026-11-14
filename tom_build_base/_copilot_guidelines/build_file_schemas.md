# Build file schemas

The two files the build tools read have JSON schemas in the container's `.tom/json-schema/buildkit/`:

| File | Schema | What it holds |
|------|--------|---------------|
| `buildkit_master.yaml` (the workspace root marker) | `.tom/json-schema/buildkit/buildkit_master.schema.json` | `navigation`, `pipelines`, `macros`, `buildkit:` (defines, `<MODE>-defines`), `required-environment`, `nested_tools`, the workspace defaults of `versioner`, `build_runner` and `doccheck`, and issuekit's `issuekit:` section |
| `buildkit.yaml` (a project's file) | `.tom/json-schema/buildkit/buildkit.schema.json` | the identity (`project_id`, `name`, `description`, `license`), `build` / `test` / `clean`, defines, `release`, `navigation`, and one section per tool or buildkit command: `versioner`, `compiler`, `cleanup`, `build_runner`, `unreferenced`, `boundaries`, `doccheck`, `testkit`, `d4rtgen`, `astgen`, `tom_reflection_generator`, `tom_reflector`, `tom_analyzer`, `dart-editor-bundler` |

## How they are kept

- **Written by hand from the readers**, not from the files: every key in a schema has a reader in tom_build_base, tom_build_kit, tom_test_kit, tom_issue_kit, tom_package_scanner, a generator (d4rtgen, astgen, the reflection generator, the reflector / analyzer) or the dart editor bundler. A key nothing reads is not in the schema; the few kept as documentation say "Not read" in their description (`pipelines.<name>.description`, `required-environment.setup.setup-pipeline`, `required-environment.binaries[].name`, `required-environment.binaryPath`).
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

## Things the schema cannot see

- `buildkit :define` / `buildkit :macro` rewrite `buildkit_master.yaml` through their own serialiser, which drops comments, the schema line included; the check reports the missing line afterwards.
- A project's `recursive:` is read into `BuildkitFolder.recursive`, but no traversal acts on it yet. This and the other keys a doc or help text promises but no reader honours are build_tom `aft_bkcfg_akmt-build-file-readers-and-docs-disagree`.
