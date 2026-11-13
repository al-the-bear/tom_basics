import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `--list` never runs anything: alone it lists the commands and pipelines;
/// with a command it lists the projects that command would visit; with a
/// pipeline it lists the pipeline's steps.
///
/// Test IDs: BB-LIST-1..7.

const _tool = ToolDefinition(
  name: 'listtool',
  description: 'Tool for the --list tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Writes into each project',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
    CommandDefinition(
      name: 'stamp',
      description: 'Stamps each project',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
    CommandDefinition(
      name: 'once',
      description: 'Runs once, without traversal',
      requiresTraversal: false,
    ),
  ],
);

class _RecordingExecutor extends CommandExecutor {
  final calls = <String>[];

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    calls.add(context.path);
    return ItemResult.success(path: context.path, name: context.name);
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    calls.add('<once>');
    return const ToolResult.success();
  }
}

void main() {
  late Directory root;
  late _RecordingExecutor write, stamp, once;
  late StringBuffer out;

  ToolRunner runner() => ToolRunner(
    tool: _tool,
    output: out,
    executors: {'write': write, 'stamp': stamp, 'once': once},
  );

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('bb_list_')
          .resolveSymbolicLinksSync(),
    );
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    for (final name in ['alpha', 'beta']) {
      File(p.join(root.path, name, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: $name\n');
    }
    write = _RecordingExecutor();
    stamp = _RecordingExecutor();
    once = _RecordingExecutor();
    out = StringBuffer();
  });
  tearDown(() => root.deleteSync(recursive: true));

  List<String> nav() => ['-R', root.path, '-s', root.path, '-r'];

  test('BB-LIST-1: --list with a command lists the projects it would visit '
      'and runs nothing [2026-11-13]', () async {
    final result = await runner().run([...nav(), '--list', ':write']);

    expect(write.calls, isEmpty, reason: 'no executor may run with --list');
    expect(result.success, isTrue);
    final text = out.toString();
    expect(text, contains('alpha'));
    expect(text, contains('beta'));
    expect(text, contains('not run (--list)'));
  });

  test('BB-LIST-2: --list with several commands, -l, and a command placed '
      'after the flag run nothing [2026-11-13]', () async {
    await runner().run([...nav(), '--list', ':write', ':stamp']);
    await runner().run([...nav(), ':stamp', '-l']);
    expect(write.calls, isEmpty);
    expect(stamp.calls, isEmpty);
    expect(out.toString(), contains(':stamp'));
  });

  test('BB-LIST-3: a command that runs without traversal is named, not run '
      '[2026-11-13]', () async {
    final result = await runner().run([...nav(), '--list', ':once']);
    expect(once.calls, isEmpty);
    expect(result.success, isTrue);
    expect(out.toString(), contains(':once'));
  });

  test('BB-LIST-4: --list alone lists the commands [2026-11-13]', () async {
    final result = await runner().run([...nav(), '--list']);
    expect(result.success, isTrue);
    final text = out.toString();
    expect(text, contains(':write'));
    expect(text, contains(':once'));
    expect(text, isNot(contains('No command specified')));
  });

  test('BB-LIST-7: an executor with its own list mode is called with '
      'listOnly set; the others are not called [2026-11-13]', () async {
    final listed = <bool>[];
    final r = ToolRunner(
      tool: _tool,
      output: out,
      executors: {'write': _ListModeSpy(listed), 'stamp': stamp, 'once': once},
    );

    await r.run([...nav(), '--list', ':write', ':stamp']);

    expect(listed, [true, true], reason: 'write lists itself, per project');
    expect(stamp.calls, isEmpty);
    expect(out.toString(), contains(':stamp  not run (--list)'));
  });

  group('in the workspace directory', () {
    late String previousCwd;
    setUp(() {
      previousCwd = Directory.current.path;
      Directory.current = root.path;
    });
    tearDown(() => Directory.current = previousCwd);

    test('BB-LIST-5: --list :define writes nothing [2026-11-13]', () async {
      final master = File(p.join(root.path, 'listtool_master.yaml'))
        ..writeAsStringSync('listtool:\n  defines: {}\n');
      final before = master.readAsStringSync();

      final result = await runner().run(['--list', ':define', 'x=1']);

      expect(master.readAsStringSync(), before);
      expect(result.success, isTrue);
      expect(out.toString(), contains('not run (--list)'));
    });

    test('BB-LIST-6: --list with a pipeline lists its steps and runs none '
        '[2026-11-13]', () async {
      final marker = p.join(root.path, 'ran.txt');
      File(p.join(root.path, 'listtool_master.yaml')).writeAsStringSync('''
pipelines:
  ci:
    core:
      - commands:
          - shell touch "$marker"
''');

      final result = await runner().run(['--list', 'ci']);

      expect(File(marker).existsSync(), isFalse);
      expect(result.success, isTrue);
      expect(out.toString(), contains('shell touch'));
    });
  });
}

/// An executor with its own list mode: records the listOnly flag it sees.
class _ListModeSpy extends CommandExecutor {
  final List<bool> listed;
  _ListModeSpy(this.listed);

  @override
  bool get handlesListMode => true;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    listed.add(args.listOnly);
    return ItemResult.success(path: context.path, name: context.name);
  }
}
