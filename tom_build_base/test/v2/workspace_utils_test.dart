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

  group('validateProjectPathsWithinRoot', () {
    final root = p.normalize(p.absolute(p.join('home', 'user', 'workspace')));

    test('returns null when there are no project patterns', () {
      expect(validateProjectPathsWithinRoot([], root), isNull);
    });

    test('accepts project ids / names / globs (non-absolute patterns)', () {
      // These are filters resolved against the scanned tree; they can only
      // match inside the workspace, so they are never rejected.
      expect(
        validateProjectPathsWithinRoot(
          ['tom_build_kit', 'my_project', 'tom_*', 'sub/project'],
          root,
        ),
        isNull,
      );
    });

    test('accepts an absolute path equal to the execution root', () {
      expect(validateProjectPathsWithinRoot([root], root), isNull);
    });

    test('accepts an absolute path within the execution root', () {
      final inside = p.join(root, 'packages', 'inner');
      expect(validateProjectPathsWithinRoot([inside], root), isNull);
    });

    test('rejects an absolute path outside the execution root', () {
      final outside = p.normalize(p.absolute(p.join('tmp', 'evil_project')));
      final error = validateProjectPathsWithinRoot([outside], root);
      expect(error, isNotNull);
      // The message must let callers/tests recognise the rejection.
      final lower = error!.toLowerCase();
      expect(lower, contains('outside'));
      expect(lower, contains('path'));
      expect(lower, contains('within'));
      expect(error, contains(outside));
    });

    test('rejects on the first offending absolute path among many patterns', () {
      final inside = p.join(root, 'ok_project');
      final outside = p.normalize(p.absolute(p.join('elsewhere', 'bad')));
      final error = validateProjectPathsWithinRoot(
        ['some_id', inside, outside],
        root,
      );
      expect(error, isNotNull);
      expect(error, contains(outside));
    });
  });

  group('validateScanPathWithinRoot', () {
    final root = p.normalize(p.absolute(p.join('home', 'user', 'workspace')));

    test('accepts an absolute scan equal to the execution root', () {
      expect(validateScanPathWithinRoot(root, root), isNull);
    });

    test('accepts an absolute scan within the execution root', () {
      final inside = p.join(root, 'packages', 'inner');
      expect(validateScanPathWithinRoot(inside, root), isNull);
    });

    test('rejects an absolute scan outside the execution root', () {
      final outside = p.normalize(p.absolute(p.join('tmp')));
      final error = validateScanPathWithinRoot(outside, root);
      expect(error, isNotNull);
      final lower = error!.toLowerCase();
      expect(lower, contains('outside'));
      expect(lower, contains('path'));
      expect(lower, contains('within'));
      expect(error, contains(outside));
    });

    test('accepts a relative scan that resolves inside the root (cwd)', () {
      // The scanner resolves a relative scan against the current directory,
      // so use the real cwd as the root and `.` as the scan.
      final cwd = Directory.current.path;
      expect(validateScanPathWithinRoot('.', cwd), isNull);
    });

    test('rejects a relative scan that escapes the root via ..', () {
      // cwd is the root; `../..` walks above it and must be rejected.
      final cwd = Directory.current.path;
      final error = validateScanPathWithinRoot(p.join('..', '..'), cwd);
      expect(error, isNotNull);
      expect(error!.toLowerCase(), contains('outside'));
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
