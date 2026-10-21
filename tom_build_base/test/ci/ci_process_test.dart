/// A child's output is streamed whole into its log, and read back for counts.
///
/// Spawns Dart children that print and exit at once; the bound is for a child that hangs.
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/ci.dart';

import 'support_scratch.dart';

void main() {
  group('CI-STEP the process runner', () {
    test(
      'CI-STEP-1: every line goes to the log, commands run in order',
      () async {
        final dir = scratchDir('step');
        writeFile(dir, 'hello.dart', '''
import 'dart:io';
void main(List<String> a) {
  for (var i = 0; i < 300; i++) { stdout.writeln('line \$i \${a.first}'); }
  stderr.writeln('to stderr');
}
''');
        final runner = CiProcessRunner(lock: CiLock(p.join(dir.path, 'l')));
        final log = p.join(dir.path, 'logs', 'out.log');
        final result = await runner.run([
          CiCommand(Platform.resolvedExecutable, [
            'hello.dart',
            'one',
          ], workingDirectory: dir.path),
          CiCommand(
            Platform.resolvedExecutable,
            ['hello.dart', 'two'],
            workingDirectory: dir.path,
            environment: {'X': '1'},
          ),
        ], logPath: log);
        expect(result.ok, isTrue);
        final text = File(log).readAsStringSync();
        expect(
          'line'.allMatches(text).length,
          600,
          reason: 'nothing is dropped',
        );
        expect(text, contains('to stderr'));
        expect(
          text.indexOf('line 299 one'),
          lessThan(text.indexOf('line 0 two')),
        );
        expect(text, contains('[exit 0]'));
        expect(result.tail.length, lessThanOrEqualTo(40));
      },
    );

    test('CI-STEP-2: the first failing command stops the step', () async {
      final dir = scratchDir('step_fail');
      writeFile(
        dir,
        'boom.dart',
        "import 'dart:io';\nvoid main() { exitCode = 3; }\n",
      );
      writeFile(dir, 'never.dart', "void main() { print('ran'); }\n");
      final runner = CiProcessRunner(lock: CiLock(p.join(dir.path, 'l')));
      final log = p.join(dir.path, 'x.log');
      final result = await runner.run([
        CiCommand(Platform.resolvedExecutable, [
          'boom.dart',
        ], workingDirectory: dir.path),
        CiCommand(Platform.resolvedExecutable, [
          'never.dart',
        ], workingDirectory: dir.path),
      ], logPath: log);
      expect(result.exitCode, 3);
      expect(File(log).readAsStringSync(), isNot(contains('ran')));
    });

    test(
      'CI-STEP-3: a command that cannot start is a red, not a crash',
      () async {
        final dir = scratchDir('step_missing');
        final runner = CiProcessRunner(lock: CiLock(p.join(dir.path, 'l')));
        final result = await runner.run([
          CiCommand(
            'no-such-executable-ci-step',
            const [],
            workingDirectory: dir.path,
          ),
        ], logPath: p.join(dir.path, 'm.log'));
        expect(result.ok, isFalse);
      },
    );

    test('CI-STEP-4: test counts come from the last progress line', () {
      expect(
        parseCiTestCounts([
          '00:01 +3: a',
          '\x1B[32m00:09 +157 ~9: All tests passed!\x1B[0m',
        ]).toString(),
        '+157 ~9',
      );
      expect(parseCiTestCounts(['00:02 +4 -1: Some tests failed.'])!.failed, 1);
      expect(
        parseCiTestCounts(['01:02 +2 ~1 -3: x\r01:03 +5 ~1 -3: y'])!.passed,
        5,
      );
      expect(parseCiTestCounts(['Compilation failed']), isNull);
    });
  });
}
