/// Unit tests for builtin_commands.dart
///
/// Tests command argument parsing and shorthand resolution.
///
/// Test IDs: BIC_PAR01-PAR06, BIC_SHR01-SHR06, BIC_ISB01-ISB04
@TestOn('!browser')
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/tom_build_kit.dart';

void main() {
  group('parseCommandArgs', () {
    test('parses simple command with no arguments', () {
      // BIC_PAR01
      expect(parseCommandArgs('versioner'), equals(['versioner']));
    });

    test('parses command with unquoted arguments', () {
      // BIC_PAR02
      expect(
        parseCommandArgs('versioner --list --verbose'),
        equals(['versioner', '--list', '--verbose']),
      );
    });

    test('parses double-quoted strings as single argument', () {
      // BIC_PAR03
      expect(
        parseCommandArgs('dcli "print(\'Hello World\')"'),
        equals(['dcli', '"print(\'Hello World\')"']),
      );
    });

    test('parses single-quoted strings as single argument', () {
      // BIC_PAR04
      expect(
        parseCommandArgs("dcli 'print(\"Hello World\")'"),
        equals(['dcli', "'print(\"Hello World\")'"])
      );
    });

    test('parses mixed quoted and unquoted arguments', () {
      // BIC_PAR05
      expect(
        parseCommandArgs('dcli "1 + 2" --verbose'),
        equals(['dcli', '"1 + 2"', '--verbose']),
      );
    });

    test('handles multiple spaces between arguments', () {
      // BIC_PAR06
      expect(
        parseCommandArgs('versioner   --list    --verbose'),
        equals(['versioner', '--list', '--verbose']),
      );
    });

    test('handles empty string', () {
      // BIC_PAR07
      expect(parseCommandArgs(''), isEmpty);
    });

    test('handles string with only whitespace', () {
      // BIC_PAR08
      expect(parseCommandArgs('   '), isEmpty);
    });

    test('preserves backslash escapes in quoted strings', () {
      // BIC_PAR09
      expect(
        parseCommandArgs(r'dcli "Hello\nWorld"'),
        equals(['dcli', r'"Hello\nWorld"']),
      );
    });
  });

  group('resolveShorthand', () {
    test('returns exact match for full command name', () {
      // BIC_SHR01
      expect(BuiltinCommands.resolveShorthand('versioner'), equals('versioner'));
      expect(BuiltinCommands.resolveShorthand('bumpversion'), equals('bumpversion'));
      expect(BuiltinCommands.resolveShorthand('dcli'), equals('dcli'));
    });

    test('is case-insensitive', () {
      // BIC_SHR02
      expect(BuiltinCommands.resolveShorthand('VERSIONER'), equals('versioner'));
      expect(BuiltinCommands.resolveShorthand('Dcli'), equals('dcli'));
    });

    test('resolves unique prefix to full command', () {
      // BIC_SHR03
      expect(BuiltinCommands.resolveShorthand('v'), equals('versioner'));
      expect(BuiltinCommands.resolveShorthand('dc'), equals('dcli'));
      expect(BuiltinCommands.resolveShorthand('cle'), equals('cleanup'));
    });

    test('returns null for ambiguous prefix', () {
      // BIC_SHR04
      // 'c' matches 'cleanup', 'compiler'
      expect(BuiltinCommands.resolveShorthand('c'), isNull);
      // 'pu' matches 'pubget', 'pubgetall'
      expect(BuiltinCommands.resolveShorthand('pu'), isNull);
    });

    test('returns null for no match', () {
      // BIC_SHR05
      expect(BuiltinCommands.resolveShorthand('xyz'), isNull);
      expect(BuiltinCommands.resolveShorthand('unknown'), isNull);
    });

    test('resolves all full command names', () {
      // BIC_SHR06
      final commands = [
        'buildsorter',
        'versioner',
        'bumpversion',
        'compiler',
        'runner',
        'cleanup',
        'dependencies',
        'pubget',
        'pubgetall',
        'dcli',
      ];
      for (final cmd in commands) {
        expect(
          BuiltinCommands.resolveShorthand(cmd),
          equals(cmd),
          reason: 'Expected $cmd to resolve to itself',
        );
      }
    });
  });

  group('BuiltinCommands.isBuiltin', () {
    late BuiltinCommands commands;

    setUp(() {
      commands = BuiltinCommands(
        projectPath: '/test/project',
        rootPath: '/test/root',
        verbose: false,
        dryRun: true,
      );
    });

    test('returns true for full command names', () {
      // BIC_ISB01
      expect(commands.isBuiltin('versioner'), isTrue);
      expect(commands.isBuiltin('bumpversion'), isTrue);
      expect(commands.isBuiltin('dcli'), isTrue);
    });

    test('returns true for command with arguments', () {
      // BIC_ISB02
      expect(commands.isBuiltin('versioner --list'), isTrue);
      expect(commands.isBuiltin('dcli "1+2"'), isTrue);
    });

    test('returns true for unique shorthand', () {
      // BIC_ISB03
      expect(commands.isBuiltin('v'), isTrue);
      expect(commands.isBuiltin('dc'), isTrue);
    });

    test('returns false for ambiguous or unknown commands', () {
      // BIC_ISB04
      expect(commands.isBuiltin('c'), isFalse); // ambiguous
      expect(commands.isBuiltin('xyz'), isFalse); // unknown
    });
  });
}
