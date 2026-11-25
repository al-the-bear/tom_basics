/// The help of the `:ws-*` and `:skill-*` commands (buildkit_ws_commands.md
/// § 1.11): `buildkit --help` lists them, `buildkit help ws`, `ws-options`
/// and `skill-json` exist, and every message code a report can show has its
/// topic, which `buildkit help <code>` prints (the footer of every report
/// points there). Read through the tool as a user runs it.
///
/// Test IDs: BK-WSH-1..6.
@TestOn('vm')
library;

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/binaries/binaries_messages.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';
import 'package:tom_build_kit/src/v2/executors/git_executors.dart'
    show gitstatusMessages;
import 'package:tom_build_kit/src/v2/skill/skill_messages.dart';
import 'package:tom_build_kit/src/v2/ws/ws_messages.dart';

Future<String> run(List<String> args) async {
  final out = StringBuffer();
  final result = await ToolRunner(
    tool: buildkitTool,
    executors: createBuildkitExecutors(),
    output: out,
  ).run(args);
  expect(result.exitCode, 0, reason: '$args: $out');
  return '$out';
}

/// Every catalog a report of the new commands draws its messages from.
final catalogs = {
  ':ws-push': wsPushMessages,
  ':ws-update': wsUpdateMessages,
  ':ws-repo-cleanup': wsRepoCleanupMessages,
  ':skill-reconcile-code': skillReconcileMessages,
  ':skill-status': skillStatusMessages,
  ':skill-dirty-scan': skillDirtyScanMessages,
  ':skill-build-binaries': binBuildMessages,
  ':skill-push-binaries': binPushMessages,
  ':gitstatus': gitstatusMessages,
};

const newCommands = [
  'ws-push',
  'ws-update',
  'ws-repo-cleanup',
  'skill-reconcile-code',
  'skill-status',
  'skill-dirty-scan',
  'skill-build-binaries',
  'skill-build-all-binaries',
  'skill-push-binaries',
];

void main() {
  test('BK-WSH-1: buildkit --help lists every new command with its line '
      '[2026-11-25]', () async {
    final help = await run(['--help']);
    for (final c in newCommands) {
      final def = buildkitTool.commands.firstWhere((x) => x.name == c);
      expect(help, contains(':$c'), reason: c);
      expect(help, contains(def.description), reason: '$c: one line');
    }
  });

  test('BK-WSH-2: every new command has its page with steps, options and '
      'exit codes [2026-11-25]', () async {
    for (final c in newCommands) {
      final page = await run([':$c', '--help']);
      final def = buildkitTool.commands.firstWhere((x) => x.name == c);
      expect(page, contains('Exit Codes'), reason: c);
      for (final o in def.options) {
        expect(page, contains('--${o.name}'), reason: '$c --${o.name}');
      }
      expect(def.details, isNotNull, reason: '$c: its steps');
    }
  });

  test(
    'BK-WSH-3: buildkit help ws, ws-options and skill-json [2026-11-25]',
    () async {
      final ws = await run(['help', 'ws']);
      for (final x in [
        ':ws-push',
        ':ws-update',
        ':ws-repo-cleanup',
        'unmanaged',
        'machine by machine',
        'buildkit help ws-options',
      ]) {
        expect(ws, contains(x), reason: x);
      }
      final options = await run(['help', 'ws-options']);
      for (final x in [
        '--merge-branch <repos>',
        '--commit-first <repos>',
        '--skip-file <glob>',
        '--ignore-active',
        '--apply',
        '--force-remove <repos>',
      ]) {
        expect(options, contains(x), reason: x);
      }
      final json = await run(['help', 'skill-json']);
      for (final x in ['"status"', '"scan"', '"reconcile"', '--rows']) {
        expect(json, contains(x), reason: x);
      }
    },
  );

  test('BK-WSH-4: ws-options credits an option only to the commands that '
      'take it [2026-11-25]', () async {
    final options = await run(['help', 'ws-options']);
    final mergeBranch = options.substring(options.indexOf('--merge-branch'));
    final credit = mergeBranch.split('\n')[2];
    expect(credit, contains(':ws-push'));
    expect(
      credit,
      isNot(contains(':ws-update')),
      reason: ':ws-update has no --merge-branch',
    );
    for (final cmd in ['ws-push', 'ws-update', 'ws-repo-cleanup']) {
      final def = buildkitTool.commands.firstWhere((x) => x.name == cmd);
      final offered = {
        for (final d in catalogs[':$cmd']!.definitions)
          for (final o in d.options) o.name,
      };
      for (final o in def.options) {
        if (offered.contains(o.name)) {
          expect(options, contains('--${o.name}'), reason: '$cmd --${o.name}');
        }
      }
    }
  });

  test('BK-WSH-5: every message code a report can show has exactly one topic, '
      'and buildkit help <code> prints it [2026-11-25]', () async {
    final topics = buildkitTool.helpTopics.map((t) => t.name).toList();
    final codes = <String>{
      for (final c in catalogs.values)
        for (final d in c.definitions) d.code,
    };
    expect(
      codes.length,
      greaterThan(40),
      reason: "a read of the catalogs, not of nothing",
    );
    for (final code in codes) {
      expect(topics.where((t) => t == code), hasLength(1), reason: code);
    }
    for (final c in catalogs.values) {
      for (final d in c.definitions) {
        final page = await run(['help', d.code]);
        expect(page, contains(d.summary), reason: d.code);
        for (final o in d.options) {
          expect(
            page,
            contains('--${o.name}'),
            reason: '${d.code} --${o.name}',
          );
        }
      }
    }
  });

  test('BK-WSH-6: the footer of a report names `buildkit help <topic>`, and '
      'its block the code that is the topic [2026-11-25]', () {
    final report =
        RunReport(
          tool: 'buildkit',
          command: ':ws-push',
          root: '/r',
          host: 'h',
          started: DateTime(2026, 11, 25),
          names: RepoNames(['', 'core']),
        )..add(
          wsConflict.raise(
            repository: 'core',
            branch: 'main',
            finding: 'conflicts',
          ),
        );
    final text = report.renderText();
    expect(text, contains('`buildkit help <topic>` explains each message'));
    expect(text, contains('[ws-conflict]'));
    expect(buildkitTool.helpTopics.map((t) => t.name), contains('ws-conflict'));
  });
}
