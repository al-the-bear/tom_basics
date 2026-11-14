import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `CommandDefinition.parallel` and `--jobs`: the projects of a command
/// whose projects are independent run at once, each project's output kept
/// together; every other command keeps running them one after another.
///
/// Test IDs: BB-JOBS-1..5.

const _tool = ToolDefinition(
  name: 'jobtool',
  description: 'Tool for the --jobs tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  commands: [
    CommandDefinition(
      name: 'fetch',
      description: 'Independent per project',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
      parallel: true,
    ),
    CommandDefinition(
      name: 'check',
      description: 'Also independent',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
      parallel: true,
    ),
    CommandDefinition(
      name: 'build',
      description: 'In build order',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
  ],
);

/// Sleeps per project and records how many ran at once; fails `gamma`.
class _Sleeper extends CommandExecutor {
  _Sleeper({this.failing});

  final String? failing;
  int running = 0;
  int maxRunning = 0;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    running++;
    if (running > maxRunning) maxRunning = running;
    print('start ${context.name}');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    print('end ${context.name}');
    running--;
    return context.name == failing
        ? ItemResult.failure(
            path: context.path,
            name: context.name,
            error: 'boom',
          )
        : ItemResult.success(path: context.path, name: context.name);
  }
}

void main() {
  late Directory root;
  late StringBuffer out;

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('bb_jobs_')
          .resolveSymbolicLinksSync(),
    );
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    for (final name in ['alpha', 'beta', 'gamma', 'delta']) {
      File(p.join(root.path, name, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: $name\n');
    }
    out = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ToolResult> run(
    Map<String, CommandExecutor> executors,
    List<String> args,
  ) => ToolRunner(
    tool: _tool,
    output: out,
    executors: executors,
  ).run(['-R', root.path, '-s', root.path, '-r', ...args]);

  test('BB-JOBS-1: a parallel command runs its projects at once, at most '
      '--jobs of them; --jobs 1 one after another [2026-11-14]', () async {
    final fetch = _Sleeper();
    final watch = Stopwatch()..start();
    var result = await run({'fetch': fetch}, [':fetch', '--jobs', '2']);
    final parallelTime = watch.elapsed;
    expect(result.success, isTrue);
    expect(fetch.maxRunning, 2);
    expect(parallelTime, lessThan(const Duration(milliseconds: 1100)));

    final sequential = _Sleeper();
    watch.reset();
    result = await run({'fetch': sequential}, ['--jobs', '1', ':fetch']);
    expect(sequential.maxRunning, 1);
    expect(
      watch.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 1200)),
    );
  });

  test('BB-JOBS-2: each project\'s output is kept together; the results '
      'keep the traversal order; a failure does not stop the others '
      '[2026-11-14]', () async {
    final result = await run(
      {'fetch': _Sleeper(failing: 'gamma')},
      [':fetch', '--jobs', '4'],
    );
    expect(result.success, isFalse);
    expect(
      result.itemResults.map((r) => r.name),
      ['alpha', 'beta', 'delta', 'gamma']..sort(),
    );
    final lines = out
        .toString()
        .split('\n')
        .where((l) => l.startsWith('start ') || l.startsWith('end '))
        .toList();
    expect(lines, hasLength(8));
    for (var i = 0; i < lines.length; i += 2) {
      final name = lines[i].substring('start '.length);
      expect(lines[i + 1], 'end $name', reason: out.toString());
    }
  });

  test('BB-JOBS-3: a command that is not parallel ignores --jobs and keeps '
      'its order [2026-11-14]', () async {
    final build = _Sleeper();
    await run({'build': build}, [':build', '--jobs', '4']);
    expect(build.maxRunning, 1);
  });

  test('BB-JOBS-4: several commands run folders at once only when every one '
      'is parallel [2026-11-14]', () async {
    final fetch = _Sleeper();
    final check = _Sleeper();
    await run(
      {'fetch': fetch, 'check': check},
      ['--jobs', '3', ':fetch', ':check'],
    );
    expect(fetch.maxRunning, greaterThan(1));
    expect(
      out.toString().split('\n').where((l) => l.startsWith('>>> ')).length,
      4,
    );

    final f2 = _Sleeper();
    final build = _Sleeper();
    await run(
      {'fetch': f2, 'build': build},
      ['--jobs', '3', ':fetch', ':build'],
    );
    expect(f2.maxRunning, 1);
    expect(build.maxRunning, 1);
  });

  test(
    'BB-JOBS-5: --list runs nothing and stays in order; the default is '
    'more than one job on a machine with several CPUs [2026-11-14]',
    () async {
      final fetch = _Sleeper();
      await run({'fetch': fetch}, ['--list', ':fetch']);
      expect(fetch.maxRunning, 0);

      final byDefault = _Sleeper();
      await run({'fetch': byDefault}, [':fetch']);
      expect(
        byDefault.maxRunning,
        Platform.numberOfProcessors > 1 ? greaterThan(1) : 1,
      );
    },
  );
}
