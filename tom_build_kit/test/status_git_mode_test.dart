/// `:status -i` lists the repositories git mode walks: it skips what project
/// mode skips (`ztmp`, `_ai`, folders with a skip marker) and `--no-skip`
/// lists the marked ones.
///
/// Test IDs: BK-STAT-1.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';

void main() {
  late Directory ws;

  void gitInit(String rel) {
    final dir = Directory(p.join(ws.path, rel))..createSync(recursive: true);
    final r = Process.runSync('git', ['init', '-q', dir.path]);
    if (r.exitCode != 0) throw StateError('git init $rel: ${r.stderr}');
  }

  setUp(() {
    ws = Directory(
      Directory.systemTemp
          .createTempSync('bk_status_')
          .resolveSymbolicLinksSync(),
    );
    File(p.join(ws.path, 'buildkit_master.yaml')).writeAsStringSync('');
    gitInit('.');
    gitInit('tom_ai/basics');
    gitInit('tom_ai/xternal/fork');
    File(
      p.join(ws.path, 'tom_ai/xternal/fork/buildkit_skip.yaml'),
    ).writeAsStringSync('');
    gitInit('ztmp/scratch_copy');
  });
  tearDown(() => ws.deleteSync(recursive: true));

  Future<Set<String>> statusRepos(List<String> extra) async {
    final out = StringBuffer();
    final previous = Directory.current;
    Directory.current = ws;
    try {
      final result = await runZoned(
        () => ToolRunner(
          tool: buildkitTool,
          executors: createBuildkitExecutors(),
          output: StringBuffer(),
        ).run([':status', '--json', '--skip-binaries', '-i', ...extra]),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => out.writeln(line),
        ),
      );
      expect(result.success, isTrue, reason: result.errorMessage);
    } finally {
      Directory.current = previous;
    }
    final doc = jsonDecode(out.toString()) as Map<String, dynamic>;
    return {
      for (final r in (doc['repos'] as List).cast<Map<String, dynamic>>())
        p.relative(r['path'] as String, from: ws.path),
    };
  }

  test('BK-STAT-1: :status -i skips ztmp and marked repositories; --no-skip '
      'lists the marked ones [2026-11-17]', () async {
    expect(await statusRepos([]), {'.', 'tom_ai/basics'});
    expect(await statusRepos(['--no-skip']), {
      '.',
      'tom_ai/basics',
      'tom_ai/xternal/fork',
    });
  });
}
