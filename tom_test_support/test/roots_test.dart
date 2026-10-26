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
        Directory(p.join(workspace.path, tomWorkspaceMarker)).existsSync(),
        isTrue,
      );
      final repository = tomFindRepositoryRoot().path;
      expect(
        p.equals(workspace.path, repository) ||
            p.isWithin(workspace.path, repository),
        isTrue,
        reason: 'a repository may itself be a workspace root (tom_ai is one)',
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
