// Shared fixture-workspace builder for the projreport examples.
//
// A `tom_build_base` tool works against a real directory tree of Dart
// projects. To keep every example hermetic and deterministic — and to avoid
// committing nested pubspecs that `dart pub get` would try to resolve — each
// example builds a throwaway workspace in a temp directory, runs the tool
// against it, and deletes it afterwards. This file is that builder; it is
// support code, not a concept example (hence the lower-cased, number-less name).
import 'dart:io';

/// Creates a temp workspace with four mini Dart packages and returns its path:
///
///   <temp>/
///   ├── app/      (app_runner     v0.9.0, depends on service_layer)
///   ├── service/  (service_layer  v1.2.0, depends on data_layer)
///   ├── data/     (data_layer     v1.0.0, no dependencies)
///   └── draft/    (draft_pkg, *no version* — reported as a skip)
///
/// The packages are *created in dependency-reverse order on purpose* (app, then
/// service, then data) so that the default build-order traversal — which emits
/// a package only after its dependencies — visibly reorders them to
/// data_layer, service_layer, app_runner. That `app_runner` ends up last
/// despite sorting first alphabetically is the proof that the framework's
/// dependency ordering is doing real work. The version-less `draft` package
/// demonstrates the skipped path in the run summary.
///
/// The caller is responsible for deleting the returned directory (see
/// [disposeFixture]).
Future<Directory> createFixtureWorkspace() async {
  final root = await Directory.systemTemp.createTemp('projreport_fixture_');

  await _writePackage(root, 'app', '''
name: app_runner
version: 0.9.0
environment:
  sdk: ^3.10.0
dependencies:
  service_layer: ^1.2.0
''');

  await _writePackage(root, 'service', '''
name: service_layer
version: 1.2.0
environment:
  sdk: ^3.10.0
dependencies:
  data_layer: ^1.0.0
''');

  await _writePackage(root, 'data', '''
name: data_layer
version: 1.0.0
environment:
  sdk: ^3.10.0
''');

  // No `version:` — the executor reports this one as a (non-failing) skip.
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
