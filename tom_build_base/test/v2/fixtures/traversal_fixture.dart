import 'dart:io';
import 'package:path/path.dart' as p;

/// Creates a temporary workspace fixture for traversal testing.
///
/// The fixture resembles a real Tom workspace with nested projects,
/// git repos at different depths, skip files, and various project types.
///
/// Structure:
/// ```
/// zom_traversal_ws/           (workspace root, has buildkit_master.yaml + .git)
///   ├── proj_alpha/            (Dart console, has pubspec.yaml + bin/)
///   ├── proj_beta/             (Dart package, has pubspec.yaml + lib/)
///   ├── proj_gamma/            (Dart package depending on alpha & beta)
///   ├── skipped_project/       (has buildkit_skip.yaml → should be skipped)
///   │   └── nested_in_skip/    (Dart project inside skipped → also skipped)
///   ├── tom_skipped/           (has tom_skip.yaml → globally skipped)
///   ├── nested_workspace/      (has buildkit_master.yaml → workspace boundary)
///   │   └── inner_project/     (should NOT be found due to boundary)
///   ├── sub_dart/              (non-project subdir)
///   │   └── proj_delta/        (nested Dart package)
///   ├── xternal/
///   │   ├── module_one/        (.git submodule, Dart package)
///   │   │   └── pkg_one_a/     (nested Dart package in submodule)
///   │   └── module_two/        (.git submodule, Dart package)
///   │       └── pkg_two_a/     (nested Dart package in submodule)
///   └── ts_project/            (TypeScript project, has package.json)
/// ```
class TraversalFixture {
  /// Root path of the temporary workspace.
  late final String rootPath;
  late final Directory _tempDir;

  /// Create the fixture in a new temp directory.
  Future<void> setUp() async {
    _tempDir = await Directory.systemTemp.createTemp('zom_traversal_ws_');
    rootPath = _tempDir.path;

    // Workspace root markers
    _writeFile('buildkit_master.yaml', 'name: zom_traversal_ws\n');
    _createDir('.git'); // fake git root

    // ---- proj_alpha: Dart console app ----
    _writePubspec('proj_alpha', '''
name: proj_alpha
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _createDir('proj_alpha/bin');
    _writeFile('proj_alpha/bin/main.dart', 'void main() {}\n');
    _writeFile('proj_alpha/lib/alpha.dart', 'int alpha = 1;\n');

    // ---- proj_beta: Dart package (needs lib/src/ for DartPackageFolder) ----
    _writePubspec('proj_beta', '''
name: proj_beta
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _createDir('proj_beta/lib/src');
    _writeFile('proj_beta/lib/src/beta.dart', 'int beta = 2;\n');

    // ---- proj_gamma: Dart package depending on alpha and beta ----
    _writePubspec('proj_gamma', '''
name: proj_gamma
version: 0.1.0
environment:
  sdk: ^3.0.0
dependencies:
  proj_alpha:
    path: ../proj_alpha
  proj_beta:
    path: ../proj_beta
''');
    _createDir('proj_gamma/lib/src');
    _writeFile('proj_gamma/lib/src/gamma.dart', 'int gamma = 3;\n');

    // ---- skipped_project: has buildkit_skip.yaml ----
    _writePubspec('skipped_project', '''
name: skipped_project
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _writeFile('skipped_project/buildkit_skip.yaml', 'skip: true\n');
    _writeFile('skipped_project/lib/skipped.dart', '');

    // ---- nested_in_skip: inside skipped ----
    _writePubspec('skipped_project/nested_in_skip', '''
name: nested_in_skip
version: 0.1.0
environment:
  sdk: ^3.0.0
''');

    // ---- tom_skipped: has tom_skip.yaml (global skip) ----
    _writePubspec('tom_skipped', '''
name: tom_skipped
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _writeFile('tom_skipped/tom_skip.yaml', 'skip: true\n');

    // ---- nested_workspace: workspace boundary ----
    _writeFile('nested_workspace/buildkit_master.yaml', 'name: nested_ws\n');
    _writePubspec('nested_workspace/inner_project', '''
name: inner_project
version: 0.1.0
environment:
  sdk: ^3.0.0
''');

    // ---- sub_dart/proj_delta: nested Dart package ----
    _writePubspec('sub_dart/proj_delta', '''
name: proj_delta
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _writeFile('sub_dart/proj_delta/lib/delta.dart', 'int delta = 4;\n');

    // ---- xternal/module_one: git submodule with nested project ----
    _createDir('xternal/module_one/.git'); // submodule
    _writePubspec('xternal/module_one', '''
name: module_one
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _writeFile('xternal/module_one/lib/module_one.dart', '');

    _writePubspec('xternal/module_one/pkg_one_a', '''
name: pkg_one_a
version: 0.1.0
environment:
  sdk: ^3.0.0
dependencies:
  module_one:
    path: ..
''');

    // ---- xternal/module_two: git submodule with nested project ----
    _createDir('xternal/module_two/.git'); // submodule
    _writePubspec('xternal/module_two', '''
name: module_two
version: 0.1.0
environment:
  sdk: ^3.0.0
''');
    _writeFile('xternal/module_two/lib/module_two.dart', '');

    _writePubspec('xternal/module_two/pkg_two_a', '''
name: pkg_two_a
version: 0.1.0
environment:
  sdk: ^3.0.0
''');

    // ---- ts_project: TypeScript project ----
    _writeFile('ts_project/package.json', '''
{
  "name": "ts_project",
  "version": "1.0.0"
}
''');
    _writeFile('ts_project/tsconfig.json', '{}');
  }

  /// Remove the fixture directory.
  Future<void> tearDown() async {
    if (_tempDir.existsSync()) {
      await _tempDir.delete(recursive: true);
    }
  }

  /// Project names that should be found in a recursive scan.
  List<String> get expectedProjectNames => [
        'proj_alpha',
        'proj_beta',
        'proj_gamma',
        'proj_delta',
        'module_one',
        'pkg_one_a',
        'module_two',
        'pkg_two_a',
        'ts_project',
      ];

  /// Project names that should be skipped.
  List<String> get expectedSkippedNames => [
        'skipped_project',
        'nested_in_skip',
        'tom_skipped',
        'inner_project', // behind workspace boundary
      ];

  /// Git repo paths relative to root.
  List<String> get gitRepoPaths => [
        '.', // root
        'xternal/module_one',
        'xternal/module_two',
      ];

  // Helpers

  void _writeFile(String relativePath, String content) {
    final file = File(p.join(rootPath, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void _writePubspec(String projectDir, String content) {
    _writeFile('$projectDir/pubspec.yaml', content);
    _createDir('$projectDir/lib');
  }

  void _createDir(String relativePath) {
    Directory(p.join(rootPath, relativePath)).createSync(recursive: true);
  }
}
