// BK-OUT: the record beside each binary `:compiler` writes
// (`<binary>.buildkit.json`) and the output paths read from the compile
// commands. The end-to-end behaviour (a missing or replaced binary compiles
// the project again) is BK-INC-9 in incremental_steps_test.dart.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/incremental/output_records.dart';

void main() {
  test('BK-OUT-1: the outputs of `dart compile` commands: -o, --output=, '
      'quoted; other commands name none [2026-11-15]', () {
    expect(
      compileOutputPaths([
        'mkdir -p out',
        'dart compile exe bin/a.dart -o out/a',
        'dart compile kernel bin/b.dart --output=out/b.dill',
        'dart compile exe bin/c.dart -o "out dir/c"',
        'cp out/a out/a2 -o ignored',
        'echo dart compile exe x -o y',
      ]),
      ['out/a', 'out/b.dill', 'out dir/c'],
    );
  });

  test('BK-OUT-2: a written record describes the binary; the check names '
      'what does not match [2026-11-15]', () {
    final dir = Directory.systemTemp.createTempSync('bk_out_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final binary = p.join(dir.path, 'tool');
    File(binary).writeAsStringSync('program');

    writeOutputRecord(
      binary: binary,
      project: 'proj',
      buildkitVersion: '9.9.9',
      fingerprint: 'fp1',
    );
    final record =
        jsonDecode(File(outputRecordPath(binary)).readAsStringSync()) as Map;
    expect(record['format'], outputRecordFormat);
    expect(record['formatVersion'], outputRecordFormatVersion);
    expect(record['project'], 'proj');
    expect(record['buildkit'], '9.9.9');
    expect(record['fingerprint'], 'fp1');
    expect(record['size'], 7);
    expect(DateTime.tryParse(record['builtAt'] as String), isNotNull);

    expect(staleOutputReason(binary, 'fp1'), isNull);
    expect(staleOutputReason(binary, 'fp2'), contains('another build'));
    File(binary).writeAsStringSync('progrxm');
    expect(staleOutputReason(binary, 'fp1'), contains('replaced'));
    File(outputRecordPath(binary)).writeAsStringSync('{');
    expect(staleOutputReason(binary, 'fp1'), contains('cannot be read'));
    File(outputRecordPath(binary)).deleteSync();
    expect(staleOutputReason(binary, 'fp1'), contains('has no tool.buildkit'));
    File(binary).deleteSync();
    expect(staleOutputReason(binary, 'fp1'), 'tool is missing');
  });
}
