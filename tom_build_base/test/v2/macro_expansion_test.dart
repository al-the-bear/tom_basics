/// Tests for macro expansion with placeholder support.
///
/// Macros support positional placeholders ($1-$9) and rest placeholder ($$).
///
/// Test IDs: BB-MAC-01 through BB-MAC-12
@TestOn('!browser')
library;

import 'package:test/test.dart';
import 'package:tom_build_base/src/v2/core/macro_expansion.dart';

void main() {
  group('MacroExpander', () {
    group('BB-MAC-01: simple macro without placeholders', () {
      test('expands @name to stored value', () {
        final macros = {'ver': ':versioner'};
        final args = ['@ver'];
        final result = expandMacros(args, macros);
        expect(result, equals([':versioner']));
      });

      test('preserves surrounding args', () {
        final macros = {'ver': ':versioner'};
        final args = ['--verbose', '@ver', '--list'];
        final result = expandMacros(args, macros);
        expect(result, equals(['--verbose', ':versioner', '--list']));
      });
    });

    group('BB-MAC-02: macro with single placeholder \$1', () {
      test('substitutes \$1 with next argument', () {
        final macros = {'vp': ':versioner --project \$1'};
        final args = ['@vp', 'tom_build_base'];
        final result = expandMacros(args, macros);
        expect(result, equals([':versioner', '--project', 'tom_build_base']));
      });

      test('consumes only the needed argument', () {
        final macros = {'vp': ':versioner --project \$1'};
        final args = ['@vp', 'tom_build_base', '--list'];
        final result = expandMacros(args, macros);
        expect(
          result,
          equals([':versioner', '--project', 'tom_build_base', '--list']),
        );
      });
    });

    group('BB-MAC-03: macro with multiple placeholders \$1 \$2', () {
      test('substitutes both placeholders', () {
        final macros = {'gs': ':gitstatus --project \$1 --modules \$2'};
        final args = ['@gs', 'tom_core', 'inner'];
        final result = expandMacros(args, macros);
        expect(
          result,
          equals([':gitstatus', '--project', 'tom_core', '--modules', 'inner']),
        );
      });

      test('handles non-sequential placeholders', () {
        final macros = {'swap': 'echo \$2 \$1'};
        final args = ['@swap', 'first', 'second'];
        final result = expandMacros(args, macros);
        expect(result, equals(['echo', 'second', 'first']));
      });
    });

    group('BB-MAC-04: macro with rest placeholder \$\$', () {
      test('substitutes \$\$ with all remaining arguments', () {
        final macros = {'all': ':versioner \$\$'};
        final args = ['@all', '--project', 'tom_build_base', '--list'];
        final result = expandMacros(args, macros);
        expect(
          result,
          equals([':versioner', '--project', 'tom_build_base', '--list']),
        );
      });

      test('\$\$ with no remaining args expands to empty', () {
        final macros = {'all': ':versioner \$\$'};
        final args = ['@all'];
        final result = expandMacros(args, macros);
        expect(result, equals([':versioner']));
      });
    });

    group('BB-MAC-05: combined \$n and \$\$', () {
      test('\$1 followed by \$\$ consumes first arg then rest', () {
        final macros = {'cmd': ':compiler --project \$1 \$\$'};
        final args = ['@cmd', 'myproj', '--targets', 'linux-x64'];
        final result = expandMacros(args, macros);
        expect(
          result,
          equals([
            ':compiler',
            '--project',
            'myproj',
            '--targets',
            'linux-x64',
          ]),
        );
      });
    });

    group('BB-MAC-06: nested macro expansion', () {
      test('expands nested macros', () {
        final macros = {
          'proj': 'tom_build_base',
          'vp': ':versioner --project @proj',
        };
        final args = ['@vp'];
        final result = expandMacros(args, macros);
        expect(result, equals([':versioner', '--project', 'tom_build_base']));
      });
    });

    group('BB-MAC-07: missing arguments for placeholders', () {
      test('missing \$1 argument throws error', () {
        final macros = {'vp': ':versioner --project \$1'};
        final args = ['@vp']; // Missing argument for $1
        expect(
          () => expandMacros(args, macros),
          throwsA(isA<MacroExpansionException>()),
        );
      });

      test('missing \$2 argument throws error', () {
        final macros = {'gs': ':gitstatus --project \$1 --modules \$2'};
        final args = ['@gs', 'tom_core']; // Missing argument for $2
        expect(
          () => expandMacros(args, macros),
          throwsA(isA<MacroExpansionException>()),
        );
      });
    });

    group('BB-MAC-08: undefined macro', () {
      test('undefined macro is left as-is', () {
        final macros = <String, String>{};
        final args = ['@undefined'];
        final result = expandMacros(args, macros);
        expect(result, equals(['@undefined']));
      });
    });

    group('BB-MAC-09: multiple macros in args', () {
      test('expands multiple macros in sequence', () {
        final macros = {'opt1': '--verbose', 'opt2': '--list'};
        final args = ['@opt1', ':versioner', '@opt2'];
        final result = expandMacros(args, macros);
        expect(result, equals(['--verbose', ':versioner', '--list']));
      });
    });

    group('BB-MAC-10: @ in middle of token is literal', () {
      test('email-like string is not treated as macro', () {
        final macros = {'user': 'admin'};
        final args = ['user@example.com'];
        final result = expandMacros(args, macros);
        expect(result, equals(['user@example.com']));
      });
    });

    group('BB-MAC-11: quoted arguments with spaces', () {
      test('argument with spaces is passed as single \$1', () {
        final macros = {'e': 'echo \$1'};
        final args = ['@e', 'hello world'];
        final result = expandMacros(args, macros);
        expect(result, equals(['echo', 'hello world']));
      });

      test('\$\$ preserves argument boundaries', () {
        final macros = {'e': 'echo \$\$'};
        final args = ['@e', 'hello world', 'another arg'];
        final result = expandMacros(args, macros);
        expect(result, equals(['echo', 'hello world', 'another arg']));
      });
    });

    group('BB-MAC-12: escaping', () {
      test('\\\$1 is literal \$1', () {
        final macros = {'lit': 'echo \\\$1'};
        final args = ['@lit', 'ignored'];
        final result = expandMacros(args, macros);
        // The $1 should be literal, not substituted
        expect(result, equals(['echo', '\$1', 'ignored']));
      });
    });
  });

  group('getRequiredArgCount', () {
    test('returns 0 for no placeholders', () {
      expect(getRequiredArgCount(':versioner --list'), equals(0));
    });

    test('returns 1 for single \$1', () {
      expect(getRequiredArgCount(':versioner --project \$1'), equals(1));
    });

    test('returns highest placeholder number', () {
      expect(getRequiredArgCount('echo \$1 \$2 \$3'), equals(3));
    });

    test('handles gaps in placeholder numbers', () {
      expect(getRequiredArgCount('echo \$1 \$5'), equals(5));
    });

    test('returns -1 for \$\$', () {
      // -1 indicates variable args (rest)
      expect(getRequiredArgCount(':versioner \$\$'), equals(-1));
    });
  });
}
