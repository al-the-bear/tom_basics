/// The roots are found by landmark from any depth, and a landmark that is not
/// there is reported as absent rather than guessed at.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/roots.dart';

void main() {
  group('TSUP-ROOT the roots', () {
    test(
      'TSUP-ROOT-1: the repository root holds the marker and this package',
      () {
        final root = tomFindRepositoryRoot();
        expect(
          File(p.join(root.path, tomRepositoryMarker)).existsSync(),
          isTrue,
        );
        expect(
          p.isWithin(root.path, Directory.current.absolute.path),
          isTrue,
          reason: 'the nearest marker above the package is its repository',
        );
      },
    );

    test('TSUP-ROOT-2: the same root is found from a deeper directory', () {
      final from = Directory(p.join(Directory.current.path, 'lib'));
      expect(
        tomFindRepositoryRoot(from: from).path,
        tomFindRepositoryRoot().path,
      );
    });

    test('TSUP-ROOT-3: the workspace root, when there is one, holds its marker '
        'and contains the repository, or is it', () {
      final workspace = tomFindWorkspaceRoot();
      if (workspace == null) {
        markTestSkipped('this checkout has no workspace above it');
        return;
      }
      expect(
        File(p.join(workspace.path, tomWorkspaceMarker)).existsSync(),
        isTrue,
      );
      final repository = tomFindRepositoryRoot().path;
      expect(
        p.equals(workspace.path, repository) ||
            p.isWithin(workspace.path, repository),
        isTrue,
        reason: 'a repository may itself be a workspace root',
      );
      expect(tomWorkspaceZtmp().path, p.join(workspace.path, 'ztmp'));
    });

    test('TSUP-ROOT-4: negative control — no landmark up to the filesystem '
        'root is null for the walk and a named failure for the repository', () {
      final top = Directory.current.absolute.uri.resolve('/');
      final root = Directory.fromUri(top);
      expect(tomFindUp(root, (_) => false), isNull);
      expect(
        () => tomFindRepositoryRoot(from: root),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains(tomRepositoryMarker),
          ),
        ),
      );
    });

    test('TSUP-ROOT-6: the retired markers (.tom_metadata/, '
        'tom_workspace.yaml, tom.code-workspace) below the root mark nothing; '
        'the root is the directory with buildkit_master.yaml [2026-11-13]', () {
      final scratch = Directory(
        p.join(Directory.current.path, '.dart_tool', 'roots_test_stray'),
      );
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      addTearDown(() {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      });
      final workspace = Directory(p.join(scratch.path, 'ws'))
        ..createSync(recursive: true);
      File(p.join(workspace.path, tomWorkspaceMarker)).writeAsStringSync('');
      final stray = Directory(p.join(workspace.path, 'tom_ai'));
      Directory(p.join(stray.path, '.tom_metadata'))
          .createSync(recursive: true);
      File(p.join(stray.path, 'tom_workspace.yaml')).writeAsStringSync('');
      File(p.join(stray.path, 'tom.code-workspace')).writeAsStringSync('');
      final start = Directory(p.join(stray.path, 'basics', 'pkg'))
        ..createSync(recursive: true);

      expect(
        tomFindWorkspaceRoot(from: start)!.path,
        workspace.absolute.path,
      );
      expect(
        tomWorkspaceZtmp(from: start).path,
        p.join(workspace.absolute.path, 'ztmp'),
      );
    });

    test('TSUP-ROOT-7: the retired markers alone are no workspace '
        '[2026-11-13]', () {
      final scratch = Directory(
        p.join(Directory.current.path, '.dart_tool', 'roots_test_retired'),
      );
      if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      addTearDown(() {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      });
      Directory(p.join(scratch.path, '.tom_metadata'))
          .createSync(recursive: true);
      File(p.join(scratch.path, 'tom_workspace.yaml')).writeAsStringSync('');
      final start = Directory(p.join(scratch.path, 'pkg'))..createSync();
      final found = tomFindWorkspaceRoot(from: start);
      // Above the scratch folder is the real workspace (or nothing, in a
      // standalone checkout); never the scratch folder itself.
      expect(found?.path, isNot(scratch.absolute.path));
    });

    test('TSUP-ROOT-5: the walk stops at the nearest landmark, not the '
        'outermost', () {
      final start = Directory(p.join(Directory.current.path, 'lib'));
      final seen = <String>[];
      final found = tomFindUp(start, (dir) {
        seen.add(dir.path);
        return seen.length == 2;
      });
      expect(found!.path, seen.last);
      expect(seen, hasLength(2));
    });
  });
}
