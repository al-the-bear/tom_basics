import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('OptionType', () {
    test('BB-OPT-1: OptionType has three values [2026-02-12]', () {
      expect(OptionType.values, hasLength(3));
      expect(OptionType.values, contains(OptionType.flag));
      expect(OptionType.values, contains(OptionType.option));
      expect(OptionType.values, contains(OptionType.multiOption));
    });
  });

  group('OptionDefinition', () {
    group('constructor', () {
      test('BB-OPT-2: Creates option with required fields [2026-02-12]', () {
        const opt = OptionDefinition(
          name: 'verbose',
          description: 'Enable verbose output',
        );

        expect(opt.name, equals('verbose'));
        expect(opt.description, equals('Enable verbose output'));
        expect(opt.abbr, isNull);
        expect(opt.type, equals(OptionType.flag));
        expect(opt.defaultValue, isNull);
        expect(opt.allowedValues, isNull);
        expect(opt.mandatory, isFalse);
        expect(opt.negatable, isFalse);
        expect(opt.valueName, isNull);
        expect(opt.hidden, isFalse);
      });

      test('BB-OPT-3: Creates option with all fields [2026-02-12]', () {
        const opt = OptionDefinition(
          name: 'format',
          abbr: 'f',
          description: 'Output format',
          type: OptionType.option,
          defaultValue: 'json',
          allowedValues: ['json', 'yaml', 'text'],
          mandatory: true,
          negatable: true,
          valueName: 'format',
          hidden: true,
        );

        expect(opt.name, equals('format'));
        expect(opt.abbr, equals('f'));
        expect(opt.description, equals('Output format'));
        expect(opt.type, equals(OptionType.option));
        expect(opt.defaultValue, equals('json'));
        expect(opt.allowedValues, equals(['json', 'yaml', 'text']));
        expect(opt.mandatory, isTrue);
        expect(opt.negatable, isTrue);
        expect(opt.valueName, equals('format'));
        expect(opt.hidden, isTrue);
      });
    });

    group('flag factory', () {
      test('BB-OPT-4: Creates flag with minimal fields [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'verbose',
          description: 'Enable verbose output',
        );

        expect(opt.name, equals('verbose'));
        expect(opt.description, equals('Enable verbose output'));
        expect(opt.type, equals(OptionType.flag));
        expect(opt.abbr, isNull);
        expect(opt.defaultValue, isNull);
        expect(opt.allowedValues, isNull);
        expect(opt.mandatory, isFalse);
        expect(opt.negatable, isFalse);
        expect(opt.valueName, isNull);
        expect(opt.hidden, isFalse);
      });

      test('BB-OPT-5: Creates negatable flag [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'color',
          abbr: 'c',
          description: 'Enable colored output',
          negatable: true,
        );

        expect(opt.name, equals('color'));
        expect(opt.abbr, equals('c'));
        expect(opt.type, equals(OptionType.flag));
        expect(opt.negatable, isTrue);
      });

      test('BB-OPT-6: Creates flag with default value [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'color',
          description: 'Enable colored output',
          defaultValue: 'true',
        );

        expect(opt.defaultValue, equals('true'));
      });

      test('BB-OPT-7: Creates hidden flag [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'debug',
          description: 'Debug mode',
          hidden: true,
        );

        expect(opt.hidden, isTrue);
      });
    });

    group('option factory', () {
      test('BB-OPT-8: Creates single-value option [2026-02-12]', () {
        const opt = OptionDefinition.option(
          name: 'config',
          description: 'Config file path',
        );

        expect(opt.name, equals('config'));
        expect(opt.type, equals(OptionType.option));
        expect(opt.negatable, isFalse);
      });

      test('BB-OPT-9: Creates option with all fields [2026-02-12]', () {
        const opt = OptionDefinition.option(
          name: 'format',
          abbr: 'f',
          description: 'Output format',
          defaultValue: 'json',
          allowedValues: ['json', 'yaml'],
          mandatory: true,
          valueName: 'fmt',
          hidden: true,
        );

        expect(opt.name, equals('format'));
        expect(opt.abbr, equals('f'));
        expect(opt.type, equals(OptionType.option));
        expect(opt.defaultValue, equals('json'));
        expect(opt.allowedValues, equals(['json', 'yaml']));
        expect(opt.mandatory, isTrue);
        expect(opt.valueName, equals('fmt'));
        expect(opt.hidden, isTrue);
      });
    });

    group('multi factory', () {
      test('BB-OPT-10: Creates multi-value option [2026-02-12]', () {
        const opt = OptionDefinition.multi(
          name: 'exclude',
          description: 'Patterns to exclude',
        );

        expect(opt.name, equals('exclude'));
        expect(opt.type, equals(OptionType.multiOption));
        expect(opt.defaultValue, isNull);
        expect(opt.negatable, isFalse);
      });

      test(
        'BB-OPT-11: Creates multi-value option with all fields [2026-02-12]',
        () {
          const opt = OptionDefinition.multi(
            name: 'tag',
            abbr: 't',
            description: 'Tags to include',
            allowedValues: ['unit', 'integration', 'e2e'],
            mandatory: true,
            valueName: 'tag',
            hidden: true,
          );

          expect(opt.name, equals('tag'));
          expect(opt.abbr, equals('t'));
          expect(opt.type, equals(OptionType.multiOption));
          expect(opt.allowedValues, equals(['unit', 'integration', 'e2e']));
          expect(opt.mandatory, isTrue);
          expect(opt.valueName, equals('tag'));
          expect(opt.hidden, isTrue);
        },
      );
    });

    group('usage', () {
      test('BB-OPT-12: Generates usage for flag without abbr [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'verbose',
          description: 'Verbose',
        );

        expect(opt.usage, equals('    --verbose'));
      });

      test('BB-OPT-13: Generates usage for flag with abbr [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'verbose',
          abbr: 'v',
          description: 'Verbose',
        );

        expect(opt.usage, equals('-v, --verbose'));
      });

      test(
        'BB-OPT-14: Generates usage for option with value name [2026-02-12]',
        () {
          const opt = OptionDefinition.option(
            name: 'config',
            abbr: 'c',
            description: 'Config',
            valueName: 'path',
          );

          expect(opt.usage, equals('-c, --config=<path>'));
        },
      );

      test(
        'BB-OPT-15: Generates usage for option without abbr [2026-02-12]',
        () {
          const opt = OptionDefinition.option(
            name: 'config',
            description: 'Config',
            valueName: 'path',
          );

          expect(opt.usage, equals('    --config=<path>'));
        },
      );

      test('BB-OPT-16: Generates usage for multi option [2026-02-12]', () {
        const opt = OptionDefinition.multi(
          name: 'exclude',
          abbr: 'x',
          description: 'Exclude',
          valueName: 'pattern',
        );

        expect(opt.usage, equals('-x, --exclude=<pattern>'));
      });
    });

    group('toString', () {
      test('BB-OPT-17: Returns descriptive string [2026-02-12]', () {
        const opt = OptionDefinition.flag(
          name: 'verbose',
          description: 'Verbose',
        );

        expect(opt.toString(), equals('OptionDefinition(verbose)'));
      });
    });
  });

  group('Standard option definitions', () {
    test(
      'BB-OPT-18: projectTraversalOptions contains expected options [2026-02-12]',
      () {
        final names = projectTraversalOptions.map((o) => o.name).toList();

        expect(names, contains('scan'));
        expect(names, contains('recursive'));
        expect(names, contains('not-recursive'));
        expect(names, contains('recursion-exclude'));
        expect(names, contains('project'));
        expect(names, contains('exclude-projects'));
        expect(names, contains('build-order'));
        expect(names, contains('no-skip'));
      },
    );

    test('BB-OPT-19: Scan option has correct attributes [2026-02-12]', () {
      final scan = projectTraversalOptions.firstWhere((o) => o.name == 'scan');

      expect(scan.abbr, equals('s'));
      expect(scan.type, equals(OptionType.option));
      expect(scan.valueName, equals('path'));
    });

    test('BB-OPT-20: Recursive option is a flag [2026-02-12]', () {
      final recursive = projectTraversalOptions.firstWhere(
        (o) => o.name == 'recursive',
      );

      expect(recursive.abbr, equals('r'));
      expect(recursive.type, equals(OptionType.flag));
    });

    test('BB-OPT-21: Project option is multi-value [2026-02-12]', () {
      final project = projectTraversalOptions.firstWhere(
        (o) => o.name == 'project',
      );

      expect(project.abbr, equals('p'));
      expect(project.type, equals(OptionType.multiOption));
    });

    test(
      'BB-OPT-22: gitTraversalOptions contains expected options [2026-02-12]',
      () {
        final names = gitTraversalOptions.map((o) => o.name).toList();

        expect(names, contains('modules'));
        expect(names, contains('skip-modules'));
        expect(names, contains('inner-first-git'));
        expect(names, contains('outer-first-git'));
      },
    );

    test('BB-OPT-23: Modules option has correct attributes [2026-02-12]', () {
      final modules = gitTraversalOptions.firstWhere(
        (o) => o.name == 'modules',
      );

      expect(modules.abbr, equals('m'));
      expect(modules.type, equals(OptionType.multiOption));
    });

    test('BB-OPT-24: Inner-first-git option is a flag [2026-02-12]', () {
      final innerFirst = gitTraversalOptions.firstWhere(
        (o) => o.name == 'inner-first-git',
      );

      expect(innerFirst.abbr, equals('i'));
      expect(innerFirst.type, equals(OptionType.flag));
    });

    test('BB-OPT-25: commonOptions contains exclude option [2026-02-12]', () {
      final names = commonOptions.map((o) => o.name).toList();

      expect(names, contains('exclude'));
      expect(names, contains('test'));
      expect(names, contains('test-only'));
    });

    test('BB-OPT-26: Exclude option is multi-value [2026-02-12]', () {
      final exclude = commonOptions.firstWhere((o) => o.name == 'exclude');

      expect(exclude.abbr, equals('x'));
      expect(exclude.type, equals(OptionType.multiOption));
    });
  });
}
