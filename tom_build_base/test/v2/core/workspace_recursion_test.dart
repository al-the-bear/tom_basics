import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `-w` / `--workspace-recursion` with a direct command: the tool also runs,
/// with the same arguments, in every nested workspace (a folder with its own
/// `buildkit_master.yaml`) the traversal passed over; without it they are
/// skipped with a message.
///
/// Test IDs: BB-WSR-1..9.

const _tool = ToolDefinition(
  name: 'wstool',
  description: 'Tool for the -w tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  // As buildkit declares it.
  globalOptions: [
    OptionDefinition.flag(
      name: 'workspace-recursion',
      abbr: 'w',
      description: 'Also run in nested workspaces',
    ),
  ],
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Writes into each project',
      requiresTraversal: true,
      supportsProjectTraversal: true,
      worksWithNatures: {DartProjectFolder},
    ),
  ],
);

class _RecordingExecutor extends CommandExecutor {
  final List<String> calls;
  _RecordingExecutor(this.calls);

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    calls.add(p.basename(context.path));
    return ItemResult.success(path: context.path, name: context.name);
  }
}

void main() {
  late Directory root;
  late Directory previousCwd;
  late List<String> visited;
  late List<({List<String> args, String dir})> delegated;
  late StringBuffer out;
  var exitCodeIn = <String, int>{};
  late ToolRunner Function(StringSink) runnerWith;

  /// Runs the tool in [dir], as the binary would: from that folder, with a
  /// runner of its own that shells out the same way.
  Future<ProcessResult> runIn(
    String binary,
    List<String> args,
    String dir,
  ) async {
    delegated.add((args: args, dir: p.basename(dir)));
    final code = exitCodeIn[p.basename(dir)];
    if (code != null) return ProcessResult(0, code, '', 'failed there');
    final outer = Directory.current;
    Directory.current = dir;
    try {
      final own = StringBuffer();
      final result = await runnerWith(own).run(args);
      return ProcessResult(0, result.success ? 0 : 1, own.toString(), '');
    } finally {
      Directory.current = outer;
    }
  }

  runnerWith = (sink) => ToolRunner(
    tool: _tool,
    output: sink,
    executors: {'write': _RecordingExecutor(visited)},
    workspaceRunner: runIn,
  );

  void project(String rel) => File(p.join(root.path, rel, 'pubspec.yaml'))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('name: ${p.basename(rel)}\n');

  void workspace(String rel) =>
      File(p.join(root.path, rel, 'buildkit_master.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('');

  setUp(() {
    root = Directory(
      Directory.systemTemp.createTempSync('bb_wsr_').resolveSymbolicLinksSync(),
    );
    workspace('.');
    project('alpha');
    // A nested workspace below a plain folder, with a nested one of its own.
    workspace('apps/sub');
    project('apps/sub/gamma');
    workspace('apps/sub/deeper');
    project('apps/sub/deeper/delta');
    visited = [];
    delegated = [];
    exitCodeIn = {};
    out = StringBuffer();
    previousCwd = Directory.current;
    Directory.current = root;
  });
  tearDown(() {
    Directory.current = previousCwd;
    root.deleteSync(recursive: true);
  });

  /// Runs [args] in the root, collecting what the tool writes to stderr.
  Future<(ToolResult, String)> run(List<String> args) async {
    final err = StringBuffer();
    final result = await IOOverrides.runZoned(
      () => runnerWith(out).run(args),
      stderr: () => _BufferStdout(err),
    );
    return (result, err.toString());
  }

  test('BB-WSR-1: without -w a nested workspace is skipped with the '
      'message, its projects not run [2026-11-19]', () async {
    final (result, err) = await run([':write']);
    expect(result.success, isTrue);
    expect(visited, ['alpha']);
    expect(err, contains('Skipping subworkspace: sub'));
    expect(delegated, isEmpty);
  });

  test('BB-WSR-2: with -w the tool runs in the nested workspace, which runs '
      'its own nested workspace: every project is run [2026-11-19]', () async {
    final (result, _) = await run(['-w', ':write']);
    expect(result.success, isTrue);
    expect(visited.toSet(), {'alpha', 'gamma', 'delta'});
    expect(delegated.map((d) => d.dir), ['sub', 'deeper']);
    expect(delegated.first.args, ['-w', ':write']);
    expect(out.toString(), contains('>>> workspace sub: wstool -w :write'));
  });

  test('BB-WSR-3: the nested run gets the run\'s options without the scan '
      'roots [2026-11-19]', () async {
    expect(
      argsForNestedWorkspace([
        '-w',
        '-l',
        '-s',
        'apps',
        '--scan=x',
        '--verbose',
        ':write',
      ]),
      ['-w', '-l', '--verbose', ':write'],
    );
    await run(['-w', '-s', 'apps', ':write']);
    expect(visited.toSet(), {'gamma', 'delta'});
    expect(delegated.first.args, ['-w', ':write']);
  });

  test('BB-WSR-4: an option that pins the traversal keeps the nested '
      'workspaces out, with a message [2026-11-19]', () async {
    final (result, _) = await run(['-w', '--exclude', 'beta', ':write']);
    expect(result.success, isTrue);
    expect(visited, ['alpha']);
    expect(delegated, isEmpty);
    expect(
      out.toString(),
      contains('Skipped workspace: sub, global traversal option specified.'),
    );
  });

  test('BB-WSR-5: a failing run in a nested workspace fails the run '
      '[2026-11-19]', () async {
    exitCodeIn = {'sub': 2};
    final (result, _) = await run(['-w', ':write']);
    expect(result.success, isFalse);
    expect(visited, ['alpha']);
  });

  test('BB-WSR-6: -w -l lists the projects of the nested workspaces too, '
      'running nothing [2026-11-19]', () async {
    final (result, _) = await run(['-w', '-l', ':write']);
    expect(result.success, isTrue);
    expect(visited, isEmpty);
    expect(delegated.first.args, ['-w', '-l', ':write']);
    final listed = out.toString();
    expect(listed, contains('alpha'));
    expect(listed, contains('gamma'));
    expect(listed, contains('delta'));
  });

  test('BB-WSR-7: a nested workspace with a skip file (a clone a tool '
      'owns) is left out, also with -w [2026-11-20]', () async {
    File(
      p.join(root.path, 'apps', 'sub', 'tom_skip.yaml'),
    ).writeAsStringSync('');
    final (result, err) = await run(['-w', ':write']);
    expect(result.success, isTrue);
    expect(visited, ['alpha']);
    expect(delegated, isEmpty);
    expect(err, contains('Skipping - tom_skip.yaml found: sub'));
  });

  test('BB-WSR-8: selfInvocation: a compiled binary runs itself; under the '
      'Dart VM, the VM with its flags and the script [2026-11-20]', () {
    final binary = selfInvocation(
      resolvedExecutable: '/opt/tom/darwin-arm64/buildkit',
      script: Uri.file('/opt/tom/darwin-arm64/buildkit'),
    )!;
    expect(binary.executable, '/opt/tom/darwin-arm64/buildkit');
    expect(binary.leading, isEmpty);
    final vm = selfInvocation(
      resolvedExecutable: '/sdk/bin/dart',
      script: Uri.file('/ws/tom_build_kit/bin/buildkit.dart'),
      executableArguments: ['--packages=/ws/.dart_tool/package_config.json'],
    )!;
    expect(vm.executable, '/sdk/bin/dart');
    expect(vm.leading, [
      '--packages=/ws/.dart_tool/package_config.json',
      '/ws/tom_build_kit/bin/buildkit.dart',
    ]);
    final windows = selfInvocation(
      resolvedExecutable: r'C:\sdk\bin\dart.exe',
      script: Uri.file(r'C:\ws\bin\buildkit.dart', windows: true),
      executableArguments: const [],
    )!;
    expect(windows.leading, hasLength(1));
    expect(
      selfInvocation(
        resolvedExecutable: '/sdk/bin/dartaotruntime',
        script: Uri.parse('data:application/dart;base64,AA=='),
      ),
      isNull,
    );
  });

  test('BB-WSR-9: -w starts the nested runs with the running program itself: '
      'nothing is looked up on the PATH [2026-11-20]', () async {
    final package = previousCwd.path;
    final result = await Process.run(
      Platform.resolvedExecutable,
      [
        '--packages=${p.join(package, '.dart_tool', 'package_config.json')}',
        p.join(package, 'test', 'v2', 'core', 'fixtures', 'self_tool.dart'),
        '-w',
        ':write',
      ],
      workingDirectory: root.path,
      environment: {'PATH': ''},
    );
    final out = '${result.stdout}${result.stderr}';
    expect(result.exitCode, 0, reason: out);
    expect(out, contains('visited alpha'));
    expect(out, contains('visited gamma'));
    expect(out, contains('visited delta'));
    expect(out, isNot(contains('could not start')));
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// A [Stdout] stand-in that collects what is written.
class _BufferStdout implements Stdout {
  _BufferStdout(this.buffer);
  final StringBuffer buffer;

  @override
  void write(Object? object) => buffer.write(object);

  @override
  void writeln([Object? object = '']) => buffer.writeln(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      buffer.writeAll(objects, separator);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
