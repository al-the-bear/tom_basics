import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// [CommandExecutor.afterTraversal]: called once per command after the
/// traversal, with that command's results, so an executor can sum up over
/// every project it visited (a report table). Its result joins the run's.
///
/// Test IDs: BB-AFT-1..5.

const _tool = ToolDefinition(
  name: 'aftertool',
  description: 'Tool for the afterTraversal tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  commands: [
    CommandDefinition(
      name: 'count',
      description: 'Counts the projects',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
    CommandDefinition(
      name: 'other',
      description: 'Another per-project command',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
  ],
);

class _Summing extends CommandExecutor {
  final visited = <String>[];
  final finished = <List<ItemResult>>[];
  ItemResult? answer;
  bool throwInFinish = false;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    visited.add(context.name);
    return ItemResult.success(path: context.path, name: context.name);
  }

  @override
  Future<ItemResult?> afterTraversal(
    List<ItemResult> results,
    CliArgs args,
  ) async {
    if (throwInFinish) throw StateError('cannot write the report');
    finished.add(List.of(results));
    return answer;
  }
}

void main() {
  late Directory root;
  late _Summing count, other;
  late StringBuffer out;

  ToolRunner runner() => ToolRunner(
    tool: _tool,
    output: out,
    executors: {'count': count, 'other': other},
  );

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('bb_after_')
          .resolveSymbolicLinksSync(),
    );
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    for (final name in ['alpha', 'beta']) {
      File(p.join(root.path, name, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: $name\n');
    }
    count = _Summing();
    other = _Summing();
    out = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  List<String> nav() => ['-R', root.path, '-s', root.path, '-r'];

  test('BB-AFT-1: called once after the traversal with every project\'s '
      'result [2026-11-13]', () async {
    final result = await runner().run([...nav(), ':count']);
    expect(result.success, isTrue);
    expect(count.finished, hasLength(1));
    expect(count.finished.single.map((r) => r.name).toSet(), {'alpha', 'beta'});
  });

  test('BB-AFT-2: with two commands each gets only its own results '
      '[2026-11-13]', () async {
    await runner().run([...nav(), ':count', ':other']);
    expect(count.finished, hasLength(1));
    expect(other.finished, hasLength(1));
    expect(
      count.finished.single.every((r) => r.commandName == 'count'),
      isTrue,
    );
    expect(count.finished.single, hasLength(2));
    expect(other.finished.single, hasLength(2));
  });

  test('BB-AFT-3: a failure it answers fails the run; an exception is '
      'reported as a failure [2026-11-13]', () async {
    count.answer = const ItemResult.failure(
      path: '',
      name: 'count',
      error: 'report not written',
    );
    var result = await runner().run([...nav(), ':count']);
    expect(result.success, isFalse);
    expect(result.itemResults.last.error, 'report not written');

    count = _Summing()..throwInFinish = true;
    result = await runner().run([...nav(), ':count']);
    expect(result.success, isFalse);
    expect(result.itemResults.last.error, contains('cannot write the report'));
  });

  test('BB-AFT-4: not called under --list [2026-11-13]', () async {
    await runner().run([...nav(), '--list', ':count']);
    expect(count.visited, isEmpty);
    expect(count.finished, isEmpty);
  });

  test('BB-AFT-5: the default answers nothing and changes no result '
      '[2026-11-13]', () async {
    final plain = _Plain();
    final result = await ToolRunner(
      tool: _tool,
      output: out,
      executors: {'count': plain, 'other': other},
    ).run([...nav(), ':count']);
    expect(result.success, isTrue);
    expect(result.itemResults, hasLength(2));
  });
}

class _Plain extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.success(path: context.path, name: context.name);
}
