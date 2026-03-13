import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('RepositoryIdLookup metadata resolution', () {
    late Directory tempWorkspace;

    setUp(() {
      tempWorkspace =
          Directory.systemTemp.createTempSync('repo_lookup_workspace_');

      final repoOne = Directory(p.join(tempWorkspace.path, 'repo_one'));
      repoOne.createSync(recursive: true);
      File(p.join(repoOne.path, 'tom_repository.yaml')).writeAsStringSync('''
repository_id: R1
name: repo_one
''');

      final repoTwo = Directory(p.join(tempWorkspace.path, 'repo_two'));
      repoTwo.createSync(recursive: true);
      File(p.join(repoTwo.path, 'tom_repository.yaml')).writeAsStringSync('''
repository_id: R2
name: repo-two
''');

      RepositoryIdLookup.clearCache(executionRoot: tempWorkspace.path);
    });

    tearDown(() {
      RepositoryIdLookup.clearCache(executionRoot: tempWorkspace.path);
      if (tempWorkspace.existsSync()) {
        tempWorkspace.deleteSync(recursive: true);
      }
    });

    test('resolves repository IDs from tom_repository.yaml', () {
      expect(
        RepositoryIdLookup.resolveToName(
          'R1',
          executionRoot: tempWorkspace.path,
        ),
        equals('repo_one'),
      );
      expect(
        RepositoryIdLookup.resolveToName(
          'R2',
          executionRoot: tempWorkspace.path,
        ),
        equals('repo-two'),
      );
    });

    test('ID lookup is case-insensitive', () {
      expect(
        RepositoryIdLookup.resolveToName(
          'r1',
          executionRoot: tempWorkspace.path,
        ),
        equals('repo_one'),
      );
      expect(
        RepositoryIdLookup.isRepositoryId(
          'r2',
          executionRoot: tempWorkspace.path,
        ),
        isTrue,
      );
    });

    test('unknown values remain unchanged', () {
      expect(
        RepositoryIdLookup.resolveToName(
          'unknown',
          executionRoot: tempWorkspace.path,
        ),
        equals('unknown'),
      );
      expect(
        RepositoryIdLookup.isRepositoryId(
          'unknown',
          executionRoot: tempWorkspace.path,
        ),
        isFalse,
      );
    });

    test('falls back to folder name when name is missing', () {
      final fallbackRepo = Directory(p.join(tempWorkspace.path, 'repo_fallback'));
      fallbackRepo.createSync(recursive: true);
      File(p.join(fallbackRepo.path, 'tom_repository.yaml')).writeAsStringSync('''
repository_id: RF
''');

      RepositoryIdLookup.clearCache(executionRoot: tempWorkspace.path);

      expect(
        RepositoryIdLookup.resolveToName(
          'RF',
          executionRoot: tempWorkspace.path,
        ),
        equals('repo_fallback'),
      );
    });
  });
}
