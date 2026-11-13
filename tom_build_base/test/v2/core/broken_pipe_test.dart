/// A tool whose stdout reader goes away (`tool | head -1`) exits quietly
/// instead of dying with an uncaught broken-pipe error.
///
/// Test IDs: BB-PIPE-1..3.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

void main() {
  test('BB-PIPE-1: output piped into `head -1`: one line, nothing on stderr, '
      'exit 0', () async {
    final script = p.join('test', 'fixtures', 'broken_pipe', 'many_lines.dart');
    // pipefail: the pipeline's exit code is the tool's, not head's.
    final result = await Process.run('bash', [
      '-c',
      'set -o pipefail; dart run $script | head -1',
    ]);
    expect(result.stdout, startsWith('line 0'));
    expect((result.stdout as String).trim().split('\n'), hasLength(1));
    expect(result.stderr, isNot(contains('Uncaught error')));
    expect(result.stderr, isNot(contains('Broken pipe')));
    expect(result.exitCode, 0);
  }, skip: Platform.isWindows ? 'needs bash and head' : false,
      timeout: const Timeout(Duration(minutes: 2)));

  test('BB-PIPE-2: isBrokenPipe knows EPIPE (and the Windows codes), nothing '
      'else', () {
    FileSystemException fse(int code) => FileSystemException(
      'writeFrom failed', '', OSError('Broken pipe', code));
    expect(isBrokenPipe(fse(32)), isTrue);
    expect(isBrokenPipe(SocketException('x', osError: const OSError('', 32))),
        isTrue);
    expect(isBrokenPipe(fse(109)), Platform.isWindows);
    expect(isBrokenPipe(fse(232)), Platform.isWindows);
    expect(isBrokenPipe(fse(28)), isFalse, reason: 'no space left');
    expect(isBrokenPipe(const FileSystemException('x')), isFalse);
    expect(isBrokenPipe(StateError('x')), isFalse);
  });

  test('BB-PIPE-3: a ToolRunner tool (`--help`, through ConsoleMarkdownSink) '
      'piped into `head -1`: one line, nothing on stderr, exit 0', () async {
    final script = p.join('test', 'fixtures', 'broken_pipe', 'tool_help.dart');
    final result = await Process.run('bash', [
      '-c',
      'set -o pipefail; dart run $script --help | head -1',
    ]);
    expect((result.stdout as String).trim().split('\n'), hasLength(1));
    expect(result.stderr, isNot(contains('Uncaught error')));
    expect(result.stderr, isNot(contains('Broken pipe')));
    expect(result.exitCode, 0);
  }, skip: Platform.isWindows ? 'needs bash and head' : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
