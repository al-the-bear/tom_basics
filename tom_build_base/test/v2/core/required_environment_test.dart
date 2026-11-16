import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `required-environment:` in `<tool>_master.yaml` is checked on every run,
/// not only by `doctor`: a missing environment variable, folder or binary at
/// error level stops the run before any command, and the output says how to
/// fix it — the setup instructions and the setup pipeline to run. Warnings
/// show with `--verbose` and in `doctor`. Help, version, `--nested` runs and
/// the setup pipeline itself are not checked (the pipeline is the fix).
/// A binary counts as present when it is in `binaryPath` (or its
/// `<platform>/` folder) or on PATH; a missing binary's `error` / `warning`
/// get `%{version-constraint}` substituted.
///
/// Test IDs: BB-ENV-1..6.

const _tool = ToolDefinition(
  name: 'envtool',
  description: 'Tool for the required-environment tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.minimal,
  commands: [
    CommandDefinition(
      name: 'work',
      description: 'Runs once',
      requiresTraversal: false,
    ),
  ],
);

class _Recorder extends CommandExecutor {
  int runs = 0;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.success(path: context.path, name: context.name);

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    runs++;
    return const ToolResult.success();
  }
}

/// `linux-x64`, `darwin-arm64`, `win32-x64`: the binaries layer's folder of
/// this platform.
String _platformFolder() {
  final abi = Abi.current().toString(); // e.g. macos_arm64
  final parts = abi.split('_');
  final os = switch (parts.first) {
    'macos' => 'darwin',
    'windows' => 'win32',
    final other => other,
  };
  return '$os-${parts.last}';
}

void main() {
  late Directory workspace;
  late String previousCwd;
  late StringBuffer out;
  late _Recorder work;

  setUp(() {
    previousCwd = Directory.current.path;
    workspace = Directory(
      Directory.systemTemp.createTempSync('bb_env_').resolveSymbolicLinksSync(),
    );
    File(p.join(workspace.path, 'buildkit_master.yaml')).writeAsStringSync('');
    Directory.current = workspace.path;
    out = StringBuffer();
    work = _Recorder();
  });
  tearDown(() {
    Directory.current = previousCwd;
    workspace.deleteSync(recursive: true);
  });

  void master(String yaml) => File(
    p.join(workspace.path, 'envtool_master.yaml'),
  ).writeAsStringSync(yaml);

  Future<ToolResult> run(List<String> args) =>
      ToolRunner(tool: _tool, output: out, executors: {'work': work}).run(args);

  const failing = '''
required-environment:
  setup:
    instructions: Please run bootstrap.sh first.
    setup-pipeline: setup
  env-variables:
    - name: BB_ENV_SURELY_NOT_SET_1
      error: BB_ENV_SURELY_NOT_SET_1 is not set.
pipelines:
  setup:
    core:
      - commands:
          - shell true
''';

  test('BB-ENV-1: an error stops a run before any command and says how to '
      'fix it, naming the setup pipeline [2026-11-16]', () async {
    master(failing);
    final result = await run([':work']);
    expect(result.success, isFalse);
    expect(work.runs, 0, reason: 'no command may run');
    final text = out.toString();
    expect(text, contains('Installation requirements not met'));
    expect(text, contains('BB_ENV_SURELY_NOT_SET_1 is not set.'));
    expect(text, contains('How to fix:'));
    expect(text, contains('Please run bootstrap.sh first.'));
    expect(text, contains('envtool setup'));
  });

  test('BB-ENV-2: help, version, --nested and the setup pipeline itself run '
      'despite the error [2026-11-16]', () async {
    master(failing);
    expect((await run(['--help'])).success, isTrue);
    expect((await run(['--version'])).success, isTrue);
    expect((await run(['--nested', ':work'])).success, isTrue);
    expect(work.runs, 1);
    final setup = await run(['setup']);
    expect(setup.success, isTrue, reason: out.toString());
  });

  test('BB-ENV-3: warnings do not stop a run; they show with --verbose '
      '[2026-11-16]', () async {
    master('''
required-environment:
  env-variables:
    - name: BB_ENV_SURELY_NOT_SET_2
      warning: BB_ENV_SURELY_NOT_SET_2 would be nice.
''');
    expect((await run([':work'])).success, isTrue);
    expect(work.runs, 1);
    expect(out.toString(), isNot(contains('would be nice')));
    expect((await run(['-v', ':work'])).success, isTrue);
    expect(out.toString(), contains('BB_ENV_SURELY_NOT_SET_2 would be nice.'));
  });

  test('BB-ENV-4: a binary in binaryPath, or in its platform folder, counts '
      'as present [2026-11-16]', () async {
    final bin = Directory(p.join(workspace.path, 'bin'))..createSync();
    final exe = Platform.isWindows ? '.exe' : '';
    File(p.join(bin.path, 'bbenvflat$exe')).writeAsStringSync('');
    Directory(p.join(bin.path, _platformFolder())).createSync();
    File(
      p.join(bin.path, _platformFolder(), 'bbenvplatform$exe'),
    ).writeAsStringSync('');
    master('''
required-environment:
  binaryPath: ${bin.path}
  binaries:
    - binary: bbenvflat
      error: bbenvflat missing
    - binary: bbenvplatform
      error: bbenvplatform missing
''');
    final result = await run([':work']);
    expect(result.success, isTrue, reason: out.toString());
    expect(work.runs, 1);
  });

  test('BB-ENV-5: a missing binary\'s error gets %{version-constraint} '
      'substituted [2026-11-16]', () async {
    master('''
required-environment:
  binaries:
    - binary: bb-env-no-such-binary
      version-constraint: ^9.9
      error: Please install it, version %{version-constraint}.
''');
    final result = await run([':work']);
    expect(result.success, isFalse);
    expect(out.toString(), contains('Please install it, version ^9.9.'));
    expect(out.toString(), isNot(contains('%{version-constraint}')));
  });

  test('BB-ENV-6: doctor reports errors and warnings and how to fix them '
      '[2026-11-16]', () async {
    master(failing);
    final result = await run(['doctor']);
    expect(result.success, isFalse);
    expect(out.toString(), contains('BB_ENV_SURELY_NOT_SET_1 is not set.'));
    expect(out.toString(), contains('envtool setup'));
    expect(work.runs, 0);
  });
}
