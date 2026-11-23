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
/// A run whose working directory no longer exists has no workspace to check.
///
/// A command that declares `needsEnvironment: false` (a listing that runs no
/// tool) is not checked when the run holds only such commands.
///
/// A required folder that is a link whose target cannot be followed is
/// reported as such, with the target and how to recreate the link, not as
/// missing: on Windows a junction whose reparse data Windows cannot follow
/// (an MSYS-made one with forward slashes or without the `\??\` prefix in
/// its substitute name, found on legiondary01) reads as not there, while
/// .NET's `Directory.Exists`, which does not follow it, says it is.
///
/// Test IDs: BB-ENV-1..9.

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
    CommandDefinition(
      name: 'look',
      description: 'Reads the tree only',
      aliases: ['lk'],
      requiresTraversal: false,
      needsEnvironment: false,
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

  test('BB-ENV-7: the checks of a run whose working directory is gone find '
      'no workspace and do not throw [2026-11-16]', () async {
    master(failing);
    final gone = Directory(p.join(workspace.path, 'gone'))..createSync();
    Directory.current = gone.path;
    gone.deleteSync();
    final ToolResult result;
    try {
      result = await run(['doctor']);
    } finally {
      Directory.current = workspace.path;
    }
    expect(result.success, isTrue, reason: out.toString());
    expect(out.toString(), contains('Doctor check passed.'));
  });

  test('BB-ENV-8: a command that needs no environment (a listing) runs '
      'despite an error; next to one that does, the run is checked '
      '[2026-11-17]', () async {
    master(failing);
    final look = _Recorder();
    Future<ToolResult> runWith(List<String> args) => ToolRunner(
      tool: _tool,
      output: out,
      executors: {'work': work, 'look': look},
    ).run(args);

    expect((await runWith([':look'])).success, isTrue, reason: '$out');
    expect((await runWith([':lk'])).success, isTrue, reason: '$out');
    expect(look.runs, 2);
    expect('$out', isNot(contains('Installation requirements not met')));

    expect((await runWith([':look', ':work'])).success, isFalse);
    expect(work.runs, 0);
    expect('$out', contains('Installation requirements not met'));
  });

  test('BB-ENV-9: a required folder that is a link whose target cannot be '
      'followed is named as such, with its target and how to recreate it '
      '[2026-11-23]', () async {
    final target = p.join(workspace.path, 'gone');
    final link = p.join(workspace.path, 'tac');
    Link(link).createSync(target);
    master('''
required-environment:
  folders:
    - name: Workspace root
      path: $link
      error: Workspace root symlink doesn't exist
''');
    final result = await run([':work']);
    expect(result.success, isFalse);
    final text = out.toString();
    expect(text, contains("Workspace root symlink doesn't exist"));
    expect(text, contains('$link is a link to $target'));
    expect(text, contains('cannot be followed'));
    expect(
      text,
      contains(
        Platform.isWindows
            ? 'mklink /J "$link" "$target"'
            : 'ln -sfn "$target" "$link"',
      ),
    );

    // Once the target is there, the link passes.
    Directory(target).createSync();
    out.clear();
    expect((await run([':work'])).success, isTrue, reason: out.toString());
  });

  test('BB-ENV-10: requiredFolderLinkNote names only a link: nothing for a '
      'folder or a path that is not there, the target for a link; on Windows '
      'with backslashes [2026-11-23]', () {
    final folder = Directory(p.join(workspace.path, 'real'))..createSync();
    expect(requiredFolderLinkNote(folder.path), isNull);
    expect(requiredFolderLinkNote(p.join(workspace.path, 'nothing')), isNull);
    final link = p.join(workspace.path, 'dangling');
    Link(link).createSync(p.join(workspace.path, 'nowhere'));
    expect(requiredFolderLinkNote(link), contains('nowhere'));
    expect(
      requiredFolderLinkNote(link, windows: true, readTarget: (_) => 'C:/x/y'),
      allOf(
        contains(r'is a link to C:\x\y'),
        contains(r'mklink /J "' + link + r'" "C:\x\y"'),
      ),
    );
    expect(
      requiredFolderLinkNote(
        link,
        windows: true,
        readTarget: (_) => r'\??\C:\x\y',
      ),
      contains(r'mklink /J "' + link + r'" "C:\x\y"'),
    );
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
