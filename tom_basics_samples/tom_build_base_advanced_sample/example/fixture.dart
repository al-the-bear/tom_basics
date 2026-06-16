// Shared fixture-workspace builder for the relkit examples.
//
// `relkit` works against a real tree of Dart projects, so each example builds a
// throwaway workspace in a temp directory, runs the tool against it, and
// deletes it afterwards. This keeps every example hermetic and deterministic,
// and avoids committing nested pubspecs that `dart pub get` would try to
// resolve. This file is that builder — support code, not a concept example
// (hence the lower-cased, number-less name).
import 'dart:io';

/// Creates a temp workspace whose packages are deliberately **nested** so the
/// recursive traversal has a real tree to walk, and returns its path:
///
///   <temp>/
///   ├── app/         app_runner    v0.9.0   long description, deps service_layer
///   │   └── tool/    app_tools     v0.1.0   short-but-valid description, no deps
///   ├── service/     service_layer v1.2.0   description, deps data_layer
///   ├── data/        data_layer    v1.0.0   5-char description ("Data."), no deps
///   └── draft/       draft_pkg     (no version, no description)
///
/// The shape is chosen so each command has something interesting to say:
///
///   * `app/tool/` is a package *inside* another package — only a recursive
///     (`-r`) walk finds it, which is what makes this a "tree".
///   * `draft_pkg` has neither a version nor a description, so `:audit` fails it
///     and `:bump` skips it while `:report` still lists it.
///   * `data_layer`'s description is just 5 characters, so it passes a default
///     `:audit` but fails `:audit --min-desc=20`.
///
/// The caller is responsible for deleting the returned directory (see
/// [disposeFixture]).
Future<Directory> createFixtureWorkspace() async {
  final root = await Directory.systemTemp.createTemp('relkit_fixture_');

  await _writePackage(root, 'app', '''
name: app_runner
version: 0.9.0
description: Runs the sample application by wiring the service layer together.
environment:
  sdk: ^3.10.0
dependencies:
  service_layer: ^1.2.0
''');

  await _writePackage(root, 'app/tool', '''
name: app_tools
version: 0.1.0
description: Helper tools for the app.
environment:
  sdk: ^3.10.0
''');

  await _writePackage(root, 'service', '''
name: service_layer
version: 1.2.0
description: Service layer for the sample workspace.
environment:
  sdk: ^3.10.0
dependencies:
  data_layer: ^1.0.0
''');

  await _writePackage(root, 'data', '''
name: data_layer
version: 1.0.0
description: Data.
environment:
  sdk: ^3.10.0
''');

  // No version and no description — :audit fails it, :bump skips it.
  await _writePackage(root, 'draft', '''
name: draft_pkg
environment:
  sdk: ^3.10.0
''');

  return root;
}

/// Deletes a fixture workspace created by [createFixtureWorkspace].
Future<void> disposeFixture(Directory root) async {
  if (root.existsSync()) {
    await root.delete(recursive: true);
  }
}

Future<void> _writePackage(
  Directory root,
  String folder,
  String pubspec,
) async {
  final dir = Directory('${root.path}/$folder');
  await dir.create(recursive: true);
  await File('${dir.path}/pubspec.yaml').writeAsString(pubspec);
}
