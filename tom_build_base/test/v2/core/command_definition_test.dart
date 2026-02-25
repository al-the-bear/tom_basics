import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('GitTraversalOrder', () {
    test('BB-CMD-1: GitTraversalOrder has two values [2026-02-12]', () {
      expect(GitTraversalOrder.values, hasLength(2));
      expect(GitTraversalOrder.values, contains(GitTraversalOrder.innerFirst));
      expect(GitTraversalOrder.values, contains(GitTraversalOrder.outerFirst));
    });
  });

  group('CommandDefinition', () {
    group('constructor', () {
      test('BB-CMD-2: Creates command with required fields [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'cleanup',
          description: 'Clean build artifacts',
        );

        expect(cmd.name, equals('cleanup'));
        expect(cmd.description, equals('Clean build artifacts'));
        expect(cmd.aliases, isEmpty);
        expect(cmd.options, isEmpty);
        expect(cmd.requiredNatures, isNull);
        expect(cmd.worksWithNatures, isEmpty);
        expect(cmd.supportsProjectTraversal, isTrue);
        expect(cmd.supportsGitTraversal, isFalse);
        expect(cmd.defaultGitOrder, isNull);
        expect(cmd.supportsPerCommandFilter, isFalse);
        expect(cmd.requiresTraversal, isTrue);
        expect(cmd.examples, isEmpty);
        expect(cmd.canRunStandalone, isFalse);
        expect(cmd.hidden, isFalse);
      });

      test('BB-CMD-3: Creates command with all fields [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'push',
          description: 'Push to remote',
          aliases: ['pu', 'p'],
          options: [
            OptionDefinition.flag(
              name: 'force',
              abbr: 'f',
              description: 'Force push',
            ),
          ],
          requiredNatures: {},
          worksWithNatures: {},
          supportsProjectTraversal: false,
          supportsGitTraversal: true,
          defaultGitOrder: GitTraversalOrder.outerFirst,
          supportsPerCommandFilter: true,
          requiresTraversal: true,
          examples: ['push --force', 'push -f'],
          canRunStandalone: true,
          hidden: true,
        );

        expect(cmd.name, equals('push'));
        expect(cmd.aliases, equals(['pu', 'p']));
        expect(cmd.options, hasLength(1));
        expect(cmd.supportsProjectTraversal, isFalse);
        expect(cmd.supportsGitTraversal, isTrue);
        expect(cmd.defaultGitOrder, equals(GitTraversalOrder.outerFirst));
        expect(cmd.supportsPerCommandFilter, isTrue);
        expect(cmd.examples, hasLength(2));
        expect(cmd.canRunStandalone, isTrue);
        expect(cmd.hidden, isTrue);
      });
    });

    group('allOptions', () {
      test('BB-CMD-4: Returns only command options when no traversal support [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'version',
          description: 'Show version',
          supportsProjectTraversal: false,
          supportsGitTraversal: false,
          options: [
            OptionDefinition.flag(name: 'json', description: 'JSON output'),
          ],
        );

        expect(cmd.allOptions, hasLength(1));
        expect(cmd.allOptions.first.name, equals('json'));
      });

      test('BB-CMD-5: Includes project traversal options when supported [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'compile',
          description: 'Compile project',
          supportsProjectTraversal: true,
          supportsGitTraversal: false,
        );

        final allOptions = cmd.allOptions;
        final names = allOptions.map((o) => o.name).toList();

        expect(names, contains('scan'));
        expect(names, contains('recursive'));
        expect(names, contains('project'));
      });

      test('BB-CMD-6: Includes git traversal options when supported [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'gitstatus',
          description: 'Git status',
          supportsProjectTraversal: false,
          supportsGitTraversal: true,
        );

        final allOptions = cmd.allOptions;
        final names = allOptions.map((o) => o.name).toList();

        expect(names, contains('modules'));
        expect(names, contains('inner-first-git'));
        expect(names, isNot(contains('scan')));
      });

      test('BB-CMD-7: Includes both traversal types when supported [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'status',
          description: 'Show status',
          supportsProjectTraversal: true,
          supportsGitTraversal: true,
        );

        final allOptions = cmd.allOptions;
        final names = allOptions.map((o) => o.name).toList();

        expect(names, contains('scan'));
        expect(names, contains('modules'));
      });

      test('BB-CMD-8: Command options come first [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'test',
          description: 'Run tests',
          supportsProjectTraversal: true,
          options: [
            OptionDefinition.flag(name: 'coverage', description: 'Enable coverage'),
          ],
        );

        final allOptions = cmd.allOptions;
        expect(allOptions.first.name, equals('coverage'));
      });
    });

    group('usage', () {
      test('BB-CMD-9: Generates usage without aliases [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'cleanup',
          description: 'Clean',
        );

        expect(cmd.usage, equals(':cleanup'));
      });

      test('BB-CMD-10: Generates usage with single alias [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'compile',
          description: 'Compile',
          aliases: ['c'],
        );

        expect(cmd.usage, equals(':compile, :c'));
      });

      test('BB-CMD-11: Generates usage with multiple aliases [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'crossreference',
          description: 'Cross reference',
          aliases: ['crossref', 'xref'],
        );

        expect(cmd.usage, equals(':crossreference, :crossref, :xref'));
      });
    });

    group('toString', () {
      test('BB-CMD-12: Returns descriptive string [2026-02-12]', () {
        const cmd = CommandDefinition(
          name: 'cleanup',
          description: 'Clean',
        );

        expect(cmd.toString(), equals('CommandDefinition(cleanup)'));
      });
    });
  });

  group('Command with nature requirements', () {
    test('BB-CMD-13: Can specify required natures [2026-02-12]', () {
      const cmd = CommandDefinition(
        name: 'analyze',
        description: 'Analyze Dart code',
        requiredNatures: {DartProjectFolder},
        worksWithNatures: {DartProjectFolder},
      );

      expect(cmd.requiredNatures, isNotNull);
      expect(cmd.requiredNatures, contains(DartProjectFolder));
    });

    test('BB-CMD-14: Null required natures means any folder [2026-02-12]', () {
      const cmd = CommandDefinition(
        name: 'status',
        description: 'Show status',
        requiredNatures: null,
      );

      expect(cmd.requiredNatures, isNull);
    });

    test('BB-CMD-15: Empty required natures is different from null [2026-02-12]', () {
      const cmd = CommandDefinition(
        name: 'status',
        description: 'Show status',
        requiredNatures: {},
      );

      expect(cmd.requiredNatures, isNotNull);
      expect(cmd.requiredNatures, isEmpty);
    });
  });
}
