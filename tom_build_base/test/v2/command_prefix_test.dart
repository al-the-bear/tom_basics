/// Tests for command prefix matching in ToolDefinition.
///
/// Verifies that commands can be matched by:
/// 1. Exact name match
/// 2. Exact alias match
/// 3. Unambiguous prefix of name
/// 4. Unambiguous prefix of alias
library;

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('Command Prefix Matching', () {
    // Test fixture: sample tool with multiple commands
    final tool = ToolDefinition(
      name: 'testtool',
      description: 'Test tool for prefix matching',
      commands: [
        const CommandDefinition(
          name: 'versioner',
          description: 'Version command',
          aliases: ['v', 'ver'],
        ),
        const CommandDefinition(
          name: 'compiler',
          description: 'Compile command',
          aliases: ['c', 'comp'],
        ),
        const CommandDefinition(
          name: 'cleanup',
          description: 'Cleanup command',
          aliases: ['clean'],
        ),
        const CommandDefinition(
          name: 'config',
          description: 'Config command',
          aliases: ['cfg'],
        ),
        const CommandDefinition(
          name: 'dependencies',
          description: 'Dependencies command',
          aliases: ['deps', 'd'],
        ),
      ],
    );

    group('BB-CPM-01: Exact name match', () {
      test('finds command by exact name', () {
        final cmd = tool.findCommand('versioner');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('versioner'));
      });

      test('finds command by exact name - compiler', () {
        final cmd = tool.findCommand('compiler');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('compiler'));
      });

      test('finds command by exact name - cleanup', () {
        final cmd = tool.findCommand('cleanup');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('cleanup'));
      });
    });

    group('BB-CPM-02: Exact alias match', () {
      test('finds command by single-char alias', () {
        final cmd = tool.findCommand('v');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('versioner'));
      });

      test('finds command by multi-char alias', () {
        final cmd = tool.findCommand('ver');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('versioner'));
      });

      test('finds command by alias - clean', () {
        final cmd = tool.findCommand('clean');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('cleanup'));
      });
    });

    group('BB-CPM-03: Unambiguous name prefix', () {
      test('vers matches versioner (unambiguous)', () {
        final cmd = tool.findCommand('vers');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('versioner'));
      });

      test('version matches versioner', () {
        final cmd = tool.findCommand('version');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('versioner'));
      });

      test('dep matches dependencies', () {
        final cmd = tool.findCommand('dep');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('dependencies'));
      });

      test('depen matches dependencies', () {
        final cmd = tool.findCommand('depen');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('dependencies'));
      });
    });

    group('BB-CPM-04: Ambiguous prefix returns null', () {
      test('co matches both compiler and config - returns null', () {
        final cmd = tool.findCommand('co');
        expect(cmd, isNull);
      });

      test('c matches both compiler and config - returns null', () {
        // Note: 'c' is an exact alias for compiler, so this should match!
        final cmd = tool.findCommand('c');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('compiler'));
      });

      test('cle matches just cleanup', () {
        final cmd = tool.findCommand('cle');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('cleanup'));
      });

      test('clea matches just cleanup', () {
        final cmd = tool.findCommand('clea');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('cleanup'));
      });
    });

    group('BB-CPM-05: findCommandsWithPrefix', () {
      test('returns all commands starting with prefix', () {
        final matches = tool.findCommandsWithPrefix('co');
        expect(
          matches.length,
          equals(2),
        ); // compiler, config (cleanup starts with 'cl')
        expect(
          matches.map((m) => m.name).toSet(),
          equals({'compiler', 'config'}),
        );
      });

      test('returns single command for unambiguous prefix', () {
        final matches = tool.findCommandsWithPrefix('vers');
        expect(matches.length, equals(1));
        expect(matches.first.name, equals('versioner'));
      });

      test('returns empty list for no matches', () {
        final matches = tool.findCommandsWithPrefix('xyz');
        expect(matches, isEmpty);
      });

      test('includes alias matches', () {
        final matches = tool.findCommandsWithPrefix('dep');
        expect(matches.length, equals(1));
        expect(matches.first.name, equals('dependencies'));
      });
    });

    group('BB-CPM-06: Unknown command returns null', () {
      test('xyz returns null', () {
        final cmd = tool.findCommand('xyz');
        expect(cmd, isNull);
      });

      test('empty string returns null', () {
        final cmd = tool.findCommand('');
        expect(cmd, isNull);
      });
    });

    group('BB-CPM-07: Exact match takes priority over prefix', () {
      // Add a command whose name is a prefix of another
      final toolWithPrefix = ToolDefinition(
        name: 'testtool',
        description: 'Test tool',
        commands: [
          const CommandDefinition(name: 'run', description: 'Run command'),
          const CommandDefinition(
            name: 'runner',
            description: 'Runner command',
          ),
        ],
      );

      test('run matches run exactly, not runner', () {
        final cmd = toolWithPrefix.findCommand('run');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('run'));
      });

      test('runn matches runner by prefix', () {
        final cmd = toolWithPrefix.findCommand('runn');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('runner'));
      });
    });

    group('BB-CPM-08: Alias prefix matching', () {
      test('com matches compiler via comp alias', () {
        final cmd = tool.findCommand('com');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('compiler'));
      });

      test('cf matches config via cfg alias', () {
        final cmd = tool.findCommand('cf');
        expect(cmd, isNotNull);
        expect(cmd!.name, equals('config'));
      });
    });
  });
}
