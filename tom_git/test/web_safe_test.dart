/// The default entry point links for the browser: dart2js compiles a program
/// that uses it, and its import closure reaches no `dart:io`.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/tom_test_support.dart';

void main() {
  test('GIT-WEB-1: dart2js compiles the default entry point', () async {
    final dart = requireTomDartCli('compile the default entry point to JS');
    final out = Directory.systemTemp.createTempSync('tom_git_web_');
    addTearDown(() => out.deleteSync(recursive: true));
    final r = await Process.run(dart, [
      'compile',
      'js',
      '-o',
      p.join(out.path, 'entry.js'),
      'test/web/entry.dart',
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  test('GIT-WEB-2: no library of the default entry point imports dart:io', () {
    final seen = <String>{};
    final pending = ['lib/tom_git.dart'];
    while (pending.isNotEmpty) {
      final file = pending.removeLast();
      if (!seen.add(file)) continue;
      for (final line in File(file).readAsLinesSync()) {
        final m = RegExp(r"^(?:import|export) '([^']+)'").firstMatch(line);
        if (m == null) continue;
        final uri = m.group(1)!;
        expect(uri, isNot('dart:io'), reason: file);
        if (!uri.contains(':')) {
          pending.add(p.normalize(p.join(p.dirname(file), uri)));
        }
      }
    }
    expect(seen.length, greaterThan(5), reason: 'the walk found the library');
  });
}
