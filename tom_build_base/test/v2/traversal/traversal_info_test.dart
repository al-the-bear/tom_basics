import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('GitTraversalMode', () {
    test('BB-TRV-1: Has two values [2026-02-12]', () {
      expect(GitTraversalMode.values, hasLength(2));
      expect(GitTraversalMode.values, contains(GitTraversalMode.innerFirst));
      expect(GitTraversalMode.values, contains(GitTraversalMode.outerFirst));
    });
  });

  group('ProjectTraversalInfo', () {
    group('constructor', () {
      test('BB-TRV-2: Creates info with required fields [2026-02-12]', () {
        const info = ProjectTraversalInfo(executionRoot: '/workspace');

        expect(info.executionRoot, equals('/workspace'));
        expect(info.scan, equals('.'));
        expect(info.recursive, isFalse);
        expect(info.recursionExclude, isEmpty);
        expect(info.projectPatterns, isEmpty);
        expect(info.excludeProjects, isEmpty);
        expect(info.buildOrder, isTrue);
        expect(info.excludePatterns, isEmpty);
        expect(info.includeTestProjects, isFalse);
        expect(info.testProjectsOnly, isFalse);
      });

      test('BB-TRV-3: Creates info with all fields [2026-02-12]', () {
        const info = ProjectTraversalInfo(
          executionRoot: '/workspace',
          scan: './src',
          recursive: true,
          recursionExclude: ['node_modules', '.dart_tool'],
          projectPatterns: ['tom_*'],
          excludeProjects: ['tom_test_*'],
          buildOrder: true,
          excludePatterns: ['*.bak'],
          includeTestProjects: true,
          testProjectsOnly: false,
        );

        expect(info.executionRoot, equals('/workspace'));
        expect(info.scan, equals('./src'));
        expect(info.recursive, isTrue);
        expect(info.recursionExclude, equals(['node_modules', '.dart_tool']));
        expect(info.projectPatterns, equals(['tom_*']));
        expect(info.excludeProjects, equals(['tom_test_*']));
        expect(info.buildOrder, isTrue);
        expect(info.excludePatterns, equals(['*.bak']));
        expect(info.includeTestProjects, isTrue);
        expect(info.testProjectsOnly, isFalse);
      });
    });

    group('copyWith', () {
      test('BB-TRV-4: Copies with no changes [2026-02-12]', () {
        const original = ProjectTraversalInfo(
          executionRoot: '/workspace',
          scan: './src',
          recursive: true,
        );

        final copy = original.copyWith();

        expect(copy.executionRoot, equals('/workspace'));
        expect(copy.scan, equals('./src'));
        expect(copy.recursive, isTrue);
      });

      test('BB-TRV-5: Copies with changed executionRoot [2026-02-12]', () {
        const original = ProjectTraversalInfo(executionRoot: '/workspace');

        final copy = original.copyWith(executionRoot: '/other');

        expect(copy.executionRoot, equals('/other'));
        expect(copy.scan, equals('.'));
      });

      test('BB-TRV-6: Copies with changed scan [2026-02-12]', () {
        const original = ProjectTraversalInfo(
          executionRoot: '/workspace',
          scan: './src',
        );

        final copy = original.copyWith(scan: './lib');

        expect(copy.scan, equals('./lib'));
      });

      test('BB-TRV-7: Copies with changed recursive [2026-02-12]', () {
        const original = ProjectTraversalInfo(
          executionRoot: '/workspace',
          recursive: false,
        );

        final copy = original.copyWith(recursive: true);

        expect(copy.recursive, isTrue);
      });

      test('BB-TRV-8: Copies with changed projectPatterns [2026-02-12]', () {
        const original = ProjectTraversalInfo(
          executionRoot: '/workspace',
          projectPatterns: ['tom_*'],
        );

        final copy = original.copyWith(projectPatterns: ['d4rt_*']);

        expect(copy.projectPatterns, equals(['d4rt_*']));
      });

      test('BB-TRV-9: Copies with changed buildOrder [2026-02-12]', () {
        const original = ProjectTraversalInfo(
          executionRoot: '/workspace',
          buildOrder: false,
        );

        final copy = original.copyWith(buildOrder: true);

        expect(copy.buildOrder, isTrue);
      });

      test(
        'BB-TRV-10: Copies with changed test project flags [2026-02-12]',
        () {
          const original = ProjectTraversalInfo(
            executionRoot: '/workspace',
            includeTestProjects: false,
            testProjectsOnly: false,
          );

          var copy = original.copyWith(includeTestProjects: true);
          expect(copy.includeTestProjects, isTrue);
          expect(copy.testProjectsOnly, isFalse);

          copy = original.copyWith(testProjectsOnly: true);
          expect(copy.testProjectsOnly, isTrue);
        },
      );
    });
  });

  group('GitTraversalInfo', () {
    group('constructor', () {
      test('BB-TRV-11: Creates info with required fields [2026-02-12]', () {
        const info = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.innerFirst,
        );

        expect(info.executionRoot, equals('/workspace'));
        expect(info.gitMode, equals(GitTraversalMode.innerFirst));
        expect(info.modules, isEmpty);
        expect(info.skipModules, isEmpty);
        expect(info.excludePatterns, isEmpty);
        expect(info.includeTestProjects, isFalse);
        expect(info.testProjectsOnly, isFalse);
      });

      test('BB-TRV-12: Creates info with all fields [2026-02-12]', () {
        const info = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.outerFirst,
          modules: ['basics', 'd4rt'],
          skipModules: ['crypto'],
          excludePatterns: ['xternal/*'],
          includeTestProjects: true,
          testProjectsOnly: false,
        );

        expect(info.executionRoot, equals('/workspace'));
        expect(info.gitMode, equals(GitTraversalMode.outerFirst));
        expect(info.modules, equals(['basics', 'd4rt']));
        expect(info.skipModules, equals(['crypto']));
        expect(info.excludePatterns, equals(['xternal/*']));
        expect(info.includeTestProjects, isTrue);
      });
    });

    group('copyWith', () {
      test('BB-TRV-13: Copies with no changes [2026-02-12]', () {
        const original = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.innerFirst,
        );

        final copy = original.copyWith();

        expect(copy.executionRoot, equals('/workspace'));
        expect(copy.gitMode, equals(GitTraversalMode.innerFirst));
        expect(copy.modules, isEmpty);
      });

      test('BB-TRV-14: Copies with changed gitMode [2026-02-12]', () {
        const original = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.innerFirst,
        );

        final copy = original.copyWith(gitMode: GitTraversalMode.outerFirst);

        expect(copy.gitMode, equals(GitTraversalMode.outerFirst));
      });

      test('BB-TRV-15: Copies with changed modules [2026-02-12]', () {
        const original = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.innerFirst,
          modules: ['basics'],
        );

        final copy = original.copyWith(modules: ['basics', 'd4rt']);

        expect(copy.modules, equals(['basics', 'd4rt']));
      });

      test('BB-TRV-16: Copies with changed skipModules [2026-02-12]', () {
        const original = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.innerFirst,
        );

        final copy = original.copyWith(skipModules: ['crypto']);

        expect(copy.skipModules, equals(['crypto']));
      });
    });
  });

  group('TraversalInfo comparisons', () {
    test(
      'BB-TRV-17: ProjectTraversalInfo and GitTraversalInfo are distinct types [2026-02-12]',
      () {
        const project = ProjectTraversalInfo(executionRoot: '/workspace');
        const git = GitTraversalInfo(
          executionRoot: '/workspace',
          gitMode: GitTraversalMode.innerFirst,
        );

        expect(project, isA<ProjectTraversalInfo>());
        expect(project, isA<BaseTraversalInfo>());
        expect(git, isA<GitTraversalInfo>());
        expect(git, isA<BaseTraversalInfo>());
        expect(project, isNot(isA<GitTraversalInfo>()));
        expect(git, isNot(isA<ProjectTraversalInfo>()));
      },
    );

    test('BB-TRV-18: Base properties are shared [2026-02-12]', () {
      const project = ProjectTraversalInfo(
        executionRoot: '/workspace',
        excludePatterns: ['*.bak'],
        includeTestProjects: true,
      );
      const git = GitTraversalInfo(
        executionRoot: '/workspace',
        gitMode: GitTraversalMode.innerFirst,
        excludePatterns: ['*.bak'],
        includeTestProjects: true,
      );

      // Both have same base properties
      expect(project.executionRoot, equals(git.executionRoot));
      expect(project.excludePatterns, equals(git.excludePatterns));
      expect(project.includeTestProjects, equals(git.includeTestProjects));
    });
  });

  group('Realistic traversal configurations', () {
    test('BB-TRV-19: Buildkit recursive project traversal [2026-02-12]', () {
      // buildkit -s . -r --project=tom_* --exclude-projects=tom_test_*
      const info = ProjectTraversalInfo(
        executionRoot: '/workspace',
        scan: '.',
        recursive: true,
        projectPatterns: ['tom_*'],
        excludeProjects: ['tom_test_*'],
        buildOrder: false,
      );

      expect(info.scan, equals('.'));
      expect(info.recursive, isTrue);
      expect(info.projectPatterns, contains('tom_*'));
      expect(info.excludeProjects, contains('tom_test_*'));
    });

    test('BB-TRV-20: Buildkit git traversal with submodules [2026-02-12]', () {
      // buildkit -s . -r --inner-first-git --modules=basics,d4rt :commit
      const info = GitTraversalInfo(
        executionRoot: '/workspace',
        gitMode: GitTraversalMode.innerFirst,
        modules: ['basics', 'd4rt'],
      );

      expect(info.gitMode, equals(GitTraversalMode.innerFirst));
      expect(info.modules, equals(['basics', 'd4rt']));
    });

    test('BB-TRV-21: Testkit test-only project traversal [2026-02-12]', () {
      // testkit --test-only :test
      const info = ProjectTraversalInfo(
        executionRoot: '/workspace',
        scan: '.',
        recursive: false,
        testProjectsOnly: true,
      );

      expect(info.testProjectsOnly, isTrue);
      expect(info.includeTestProjects, isFalse);
    });

    test('BB-TRV-22: Build order with exclusions [2026-02-12]', () {
      // buildkit -s . -r -b --exclude=xternal/* :compile
      const info = ProjectTraversalInfo(
        executionRoot: '/workspace',
        scan: '.',
        recursive: true,
        buildOrder: true,
        excludePatterns: ['xternal/*'],
      );

      expect(info.buildOrder, isTrue);
      expect(info.excludePatterns, contains('xternal/*'));
    });
  });
}
