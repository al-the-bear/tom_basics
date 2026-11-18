/// Console markdown styling (`**bold**`, backticks, `<cyan>`) becomes ANSI
/// escape codes only on a terminal: piped or redirected output, and any
/// output under NO_COLOR, carries the text with the markers removed and no
/// escape code. FORCE_COLOR forces the styling through a pipe.
///
/// The fixture tool is compiled once (`dart compile exe`) and run as the
/// binaries are.
///
/// Test IDs: BB-STYLE-1..6.
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

import '../../fixtures/compiled_tool.dart';

late CompiledTool _tool;
const _esc = '\x1B[';

Future<ProcessResult> _run(
  List<String> args, {
  Map<String, String> environment = const {},
}) => Process.run(
  _tool.path,
  args,
  environment: {
    // A test runner may itself run with these set; each test says what it needs.
    'NO_COLOR': '',
    'FORCE_COLOR': '',
    ...environment,
  },
);

void main() {
  setUpAll(
    () async => _tool = await CompiledTool.compile(
      p.join('test', 'fixtures', 'console_styling', 'styled_tool.dart'),
    ),
  );
  tearDownAll(() => _tool.delete());

  group('piped output', () {
    test('BB-STYLE-1: --help and an Error: line through a pipe carry no '
        'escape code, the markers removed [2026-11-15]', () async {
      final help = await _run(['--help']);
      expect(help.stdout, isNot(contains(_esc)), reason: help.stdout);
      expect(help.stdout, contains('styletool'));
      expect(help.stdout, isNot(contains('**')));

      final error = await _run([':first', '-s-']);
      final out = '${error.stdout}${error.stderr}';
      expect(out, contains('Error: -s-:'), reason: out);
      expect(out, isNot(contains(_esc)));
      expect(out, contains('done: false ok'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('BB-STYLE-2: NO_COLOR keeps the escape codes out, also when '
        'FORCE_COLOR is set [2026-11-15]', () async {
      for (final env in [
        {'NO_COLOR': '1'},
        {'NO_COLOR': '1', 'FORCE_COLOR': '1'},
      ]) {
        final r = await _run(['--help'], environment: env);
        expect(r.stdout, isNot(contains(_esc)), reason: '$env');
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('BB-STYLE-3: FORCE_COLOR styles a pipe [2026-11-15]', () async {
      final r = await _run(['--help'], environment: {'FORCE_COLOR': '1'});
      expect(r.stdout, contains(_esc));
      final off = await _run(['--help'], environment: {'FORCE_COLOR': '0'});
      expect(off.stdout, isNot(contains(_esc)));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  test(
    'BB-STYLE-4: a terminal still gets the styling [2026-11-15]',
    () async {
      // `script` gives the tool a pseudo-terminal for stdout. Its stdin stays
      // open until the tool exits: an end of input ends the session early.
      final command = '"${_tool.path}" --help';
      final process = await Process.start(
        'script',
        Platform.isMacOS
            ? ['-q', '/dev/null', 'bash', '-c', command]
            : ['-qc', command, '/dev/null'],
        environment: {'NO_COLOR': '', 'FORCE_COLOR': ''},
      );
      final out = StringBuffer();
      final done = process.stdout
          .transform(systemEncoding.decoder)
          .forEach(out.write);
      await process.exitCode;
      await done;
      await process.stdin.close();
      expect(out.toString(), contains(_esc), reason: out.toString());
      expect(out.toString(), contains('styletool'));
    },
    skip: Platform.isWindows ? 'needs script(1)' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  group('the decision', () {
    test('BB-STYLE-5: styling on a terminal, off without one, off under '
        'NO_COLOR, forced by FORCE_COLOR (not 0) [2026-11-15]', () {
      bool on(bool terminal, Map<String, String> env) =>
          consoleStylingEnabled(hasTerminal: terminal, environment: env);
      expect(on(true, {}), isTrue);
      expect(on(false, {}), isFalse);
      expect(on(true, {'NO_COLOR': '1'}), isFalse);
      expect(on(true, {'NO_COLOR': ''}), isTrue, reason: 'empty: not set');
      expect(on(false, {'FORCE_COLOR': '1'}), isTrue);
      expect(on(false, {'FORCE_COLOR': 'true'}), isTrue);
      expect(on(false, {'FORCE_COLOR': '0'}), isFalse);
      expect(on(false, {'FORCE_COLOR': 'false'}), isFalse);
      expect(on(true, {'NO_COLOR': '1', 'FORCE_COLOR': '1'}), isFalse);
    });

    test('BB-STYLE-6: rendering keeps the text and removes the markers; '
        'only styled output has escape codes [2026-11-15]', () {
      const text = 'The **bold** `code` <cyan>cyan</cyan> word';
      final styled = renderConsoleMarkdown(text, styled: true);
      final plain = renderConsoleMarkdown(text, styled: false);
      expect(styled, contains(_esc));
      expect(plain, 'The bold code cyan word');
      expect(
        renderConsoleMarkdown(
          'from a tool: \x1B[32mgreen\x1B[0m',
          styled: false,
        ),
        'from a tool: green',
      );
      final buffer = StringBuffer();
      ConsoleMarkdownSink(buffer, styled: false).writeln('**x**');
      expect(buffer.toString(), 'x\n');
    });
  });
}
