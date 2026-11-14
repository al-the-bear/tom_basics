// BK-PUBJ: `buildkit :pubget` runs its projects at once (tom_build_base's
// `parallel` commands and `--jobs`), each project's output kept together,
// and the summary shows the time per step. Fixture packages live under
// .dart_tool and the run is rooted there (-R), so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('pubget_parallel_test_');
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    for (final name in ['alpha', 'beta', 'gamma']) {
      File(p.join(root.path, name, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: $name\nenvironment:\n  sdk: ^3.0.0\n');
    }
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> buildkit(List<String> args) => Process.run('dart', [
    'run',
    _buildkit,
    '-R',
    root.path,
    '-s',
    root.path,
    ...args,
  ], workingDirectory: root.path);

  /// The lines of each project's block, from its `>>> ` header to the next.
  Map<String, List<String>> blocks(String output) {
    final result = <String, List<String>>{};
    List<String>? current;
    for (final line in output.split('\n')) {
      if (line.startsWith('>>> ')) {
        current = result[p.basename(line.substring(4).trim())] = [];
      } else if (line.startsWith('=== ')) {
        current = null;
      } else {
        current?.add(line);
      }
    }
    return result;
  }

  test('BK-PUBJ-1: pub get in every project at once, each project\'s output '
      'and status together; the summary shows the time of the step '
      '[2026-11-14]', () async {
    final r = await buildkit([':pubget', '--jobs', '3']);
    final out = '${r.stdout}${r.stderr}';
    expect(r.exitCode, 0, reason: out);
    final byProject = blocks('${r.stdout}');
    expect(byProject.keys.toSet(), {'alpha', 'beta', 'gamma'}, reason: out);
    for (final entry in byProject.entries) {
      final text = entry.value.join('\n');
      expect(text, contains('Got dependencies'), reason: entry.key);
      expect(text, contains('-> :pubget pub get OK'), reason: entry.key);
    }
    for (final name in ['alpha', 'beta', 'gamma']) {
      expect(
        File(
          p.join(root.path, name, '.dart_tool', 'package_config.json'),
        ).existsSync(),
        isTrue,
      );
    }
    expect(out, contains('=== Timing ==='));
    expect(out, contains('  :pubget  3 project(s)  '));
  });

  test('BK-PUBJ-2: --jobs 1 runs them one after another, with the same '
      'output [2026-11-14]', () async {
    final r = await buildkit([':pubget', '--jobs', '1']);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(blocks('${r.stdout}').keys.toSet(), {'alpha', 'beta', 'gamma'});
  });
}
