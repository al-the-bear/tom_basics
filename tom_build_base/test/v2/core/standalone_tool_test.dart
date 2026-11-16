import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// A single-command tool that visits no projects (a daemon or a server:
/// neither project nor git traversal) runs once, and its own global options
/// keep their short forms even where a navigation option has the same letter.
///
/// An executor that has no run of its own without traversal (it implements
/// only `execute`, as a project tool like dart-editor-bundler does) works on
/// the current directory as its project instead.
///
/// Test IDs: BB-STA-1..6.

const _server = ToolDefinition(
  name: 'standalone',
  description: 'A server that visits no projects',
  version: '1.2.3',
  versionString: 'Standalone 1.2.3+7',
  mode: ToolMode.singleCommand,
  features: NavigationFeatures.minimal,
  globalOptions: [
    OptionDefinition.option(name: 'port', abbr: 'p', description: 'Port'),
    OptionDefinition.option(name: 'directory', abbr: 'd', description: 'Dir'),
    OptionDefinition.flag(name: 'foreground', abbr: 'f', description: 'Fg'),
    OptionDefinition.flag(name: 'status', description: 'Status'),
    OptionDefinition.option(name: 'instance', description: 'Id', hidden: true),
  ],
);

class _Recorder extends CommandExecutor {
  final runs = <CliArgs>[];
  int traversed = 0;
  bool fail = false;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    traversed++;
    return ItemResult.success(path: context.path, name: context.name);
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    runs.add(args);
    return fail
        ? const ToolResult.failure('not running')
        : const ToolResult.success();
  }
}

/// A project tool that visits no projects: it works on the Dart package it
/// is run in (shaped like dart-editor-bundler).
const _projectTool = ToolDefinition(
  name: 'projecttool',
  description: 'Works on the package it runs in',
  version: '1.0.0',
  mode: ToolMode.singleCommand,
  worksWithNatures: {DartProjectFolder},
  features: NavigationFeatures.minimal,
);

/// Implements only [execute]: a tool that works on the directory it runs in.
class _ProjectOnly extends CommandExecutor {
  final paths = <String>[];

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    paths.add(Directory(context.path).resolveSymbolicLinksSync());
    return ItemResult.success(path: context.path, name: context.name);
  }
}

void main() {
  late _Recorder recorder;
  late StringBuffer out;

  Future<ToolResult> run(List<String> args) => ToolRunner(
    tool: _server,
    output: out,
    executors: {'default': recorder},
  ).run(args);

  setUp(() {
    recorder = _Recorder();
    out = StringBuffer();
  });

  test('BB-STA-1: a single-command tool without traversal runs once, '
      'visiting no project [2026-11-13]', () async {
    final result = await run(['--status']);
    expect(result.success, isTrue);
    expect(recorder.runs, hasLength(1));
    expect(recorder.traversed, 0);
    expect(recorder.runs.single.extraOptions['status'], isTrue);

    recorder.fail = true;
    expect((await run(['--status'])).success, isFalse);
  });

  test('BB-STA-2: the tool\'s own global options win over the navigation '
      'letters: -p is --port, -f is --foreground [2026-11-13]', () async {
    await run(['-p', '8080', '-f', '-d', '/srv/x']);
    final o = recorder.runs.single.extraOptions;
    expect(o['port'], '8080');
    expect(o['foreground'], isTrue);
    expect(o['directory'], '/srv/x');
    expect(recorder.runs.single.projectPatterns, isEmpty);
    expect(recorder.runs.single.force, isFalse);
  });

  test('BB-STA-3: values in both forms, the hidden option, and a stray '
      'positional argument [2026-11-13]', () async {
    await run([
      '/path/to/binary',
      '--foreground',
      '--instance',
      'watcher',
      '--directory',
      '/a',
    ]);
    await run(['--instance=watcher', '--directory=/b', '--port=1']);
    final first = recorder.runs[0].extraOptions;
    final second = recorder.runs[1].extraOptions;
    expect(
      (first['instance'], first['directory'], first['foreground']),
      ('watcher', '/a', true),
    );
    expect(
      (second['instance'], second['directory'], second['port']),
      ('watcher', '/b', '1'),
    );
  });

  test('BB-STA-4: --version prints the versionString; nothing runs '
      '[2026-11-13]', () async {
    final result = await run(['--version']);
    expect(result.success, isTrue);
    expect(out.toString().split('\n').first, 'Standalone 1.2.3+7');
    expect(recorder.runs, isEmpty);
  });

  test('BB-STA-5: --help shows the tool\'s options and the shared ones, not '
      'hidden options and not the traversal options it cannot use '
      '[2026-11-13]', () async {
    final result = await run(['--help']);
    expect(result.success, isTrue);
    final text = out.toString();
    for (final shown in [
      '--port',
      '--directory',
      '--foreground',
      '--help',
      '--version',
      '--verbose',
    ]) {
      expect(text, contains(shown));
    }
    for (final hidden in [
      '--instance',
      '--exclude',
      '--test-only',
      '--execution-root',
      '--modes',
      '--nested',
    ]) {
      expect(text, isNot(contains(hidden)), reason: hidden);
    }
    expect(recorder.runs, isEmpty);
  });

  test('BB-STA-6: an executor with only execute() runs on the current '
      'directory, once [2026-11-16]', () async {
    final dir = Directory(
      Directory.systemTemp
          .createTempSync('bb_sta6_')
          .resolveSymbolicLinksSync(),
    );
    File('${dir.path}/pubspec.yaml').writeAsStringSync('name: sta6\n');
    final previous = Directory.current.path;
    Directory.current = dir.path;
    final projectOnly = _ProjectOnly();
    try {
      final result = await ToolRunner(
        tool: _projectTool,
        output: out,
        executors: {'default': projectOnly},
      ).run([]);
      expect(result.success, isTrue, reason: out.toString());
    } finally {
      Directory.current = previous;
      dir.deleteSync(recursive: true);
    }
    expect(projectOnly.paths, [dir.path]);
  });
}
