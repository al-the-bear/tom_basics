import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('scanForDartProjects always-skip directories', () {
    late Directory tempWorkspace;

    setUp(() {
      tempWorkspace = Directory.systemTemp.createTempSync('scan_skip_ws_');

      // A real, top-level project that must always be discovered.
      _writeProject(tempWorkspace.path, 'real_project');

      // Scratch / artifact directories that must never be descended into.
      // `ztmp` is the workspace's canonical gitignored scratch dir — full
      // project copies routinely accumulate there and must not be built.
      _writeProject(p.join(tempWorkspace.path, 'ztmp'), 'scratch_copy');
      _writeProject(p.join(tempWorkspace.path, 'build'), 'build_copy');
      _writeProject(p.join(tempWorkspace.path, '__pycache__'), 'cache_copy');
    });

    tearDown(() {
      if (tempWorkspace.existsSync()) {
        tempWorkspace.deleteSync(recursive: true);
      }
    });

    test('recursive scan skips ztmp and other always-skip dirs', () {
      final found = scanForDartProjects(tempWorkspace.path, recursive: true);
      final names = found.map(p.basename).toList();

      expect(names, contains('real_project'));
      expect(
        names,
        isNot(contains('scratch_copy')),
        reason: 'projects under ztmp/ must never be scanned',
      );
      expect(names, isNot(contains('build_copy')));
      expect(names, isNot(contains('cache_copy')));
    });

    test('ztmp is registered as an always-skip directory', () {
      expect(kAlwaysSkipDirectories, contains('ztmp'));
    });
  });
}

/// Create a directory [name] under [parent] containing a minimal pubspec so it
/// is recognised as a Dart project.
void _writeProject(String parent, String name) {
  final dir = Directory(p.join(parent, name));
  dir.createSync(recursive: true);
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
}
