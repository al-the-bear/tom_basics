import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// `ToolRunner(wiredExecutorWrapper:)`: a tool puts its own behaviour around
/// the executors nested-tool wiring adds; a command's help still comes from
/// the nested tool.
///
/// Test IDs: BB-WEW-1..2.

class _Wrapper extends CommandExecutor {
  _Wrapper(this.inner, this.log);
  final CommandExecutor inner;
  final List<String> log;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    log.add('before ${p.basename(context.path)}');
    final result = await inner.execute(context, args);
    log.add('after ${p.basename(context.path)} ${result.success}');
    return result;
  }
}

void main() {
  late Directory root;
  late String fakegen;

  setUp(() {
    root = Directory(
      Directory.systemTemp.createTempSync('bb_wew_').resolveSymbolicLinksSync(),
    );
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    File(p.join(root.path, 'alpha', 'pubspec.yaml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('name: alpha\n');
    // A nested multi-command tool: answers --dump-definitions, otherwise
    // notes the folder it ran in.
    fakegen = p.join(root.path, 'bin', 'fakegen');
    File(fakegen)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''#!/bin/sh
if [ "\$1" = "--dump-definitions" ]; then
cat <<'YAML'
name: fakegen
version: 1.0.0
description: A fake generator
mode: multi_command
features:
  project_traversal: true
  dry_run: false
commands:
  gen:
    description: Generates
    works_with_natures: [DartProjectFolder]
YAML
exit 0
fi
echo "\$PWD" >> "${root.path}/ran.log"
''');
    Process.runSync('chmod', ['+x', fakegen]);
  });
  tearDown(() => root.deleteSync(recursive: true));

  ToolDefinition tool() => ToolDefinition(
    name: 'host',
    description: 'A host tool',
    version: '1.0.0',
    mode: ToolMode.multiCommand,
    features: NavigationFeatures.all,
    defaultIncludes: [
      ToolWiringEntry(
        binary: fakegen,
        mode: WiringMode.multiCommand,
        commands: {'fakegen': 'gen'},
      ),
    ],
  );

  test('BB-WEW-1: the wrapper is put around each wired executor and runs '
      'it [2026-11-23]', () async {
    final log = <String>[];
    final names = <String>[];
    final result = await ToolRunner(
      tool: tool(),
      output: StringBuffer(),
      wiredExecutorWrapper: (name, executor) {
        names.add(name);
        return _Wrapper(executor, log);
      },
    ).run(['-R', root.path, '-s', root.path, '-r', ':fakegen']);
    expect(result.success, isTrue);
    expect(names, ['fakegen']);
    expect(log, ['before alpha', 'after alpha true']);
    expect(
      File(p.join(root.path, 'ran.log')).readAsStringSync(),
      contains('alpha'),
    );
  }, testOn: '!windows');

  test('BB-WEW-2: without a wrapper the wired executor runs as wired '
      '[2026-11-23]', () async {
    final result = await ToolRunner(
      tool: tool(),
      output: StringBuffer(),
    ).run(['-R', root.path, '-s', root.path, '-r', ':fakegen']);
    expect(result.success, isTrue);
    expect(File(p.join(root.path, 'ran.log')).existsSync(), isTrue);
  }, testOn: '!windows');
}
