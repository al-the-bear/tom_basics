/// `buildkit :ws-push` on a tree of real repositories with bare remotes,
/// made by each test in a temporary folder (never the live workspace): the
/// root, `_ai`, two code entries, a fork, `tom_binaries`, an upstream, and
/// an unknown clone (BK-WSP-14). Each message code of `:ws-push` (§ 1.10) is produced
/// with its options and the command line to repeat.
///
/// Test IDs: BK-WSP-1..22.
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';
import 'package:tom_build_kit/src/v2/ws/ws_messages.dart';
import 'package:tom_build_kit/src/v2/ws/ws_push.dart';

late Directory base;
late String root;
late String beats;
final _now = DateTime(2026, 11, 24, 16, 2);

ProcessResult git(String dir, List<String> args, {bool check = true}) {
  final r = Process.runSync('git', [
    '-c',
    'user.email=t@t',
    '-c',
    'user.name=t',
    '-c',
    'init.defaultBranch=main',
    ...args,
  ], workingDirectory: dir);
  if (check && r.exitCode != 0) {
    throw StateError('git $args in $dir: ${r.stderr}');
  }
  return r;
}

String out(String dir, List<String> args) => '${git(dir, args).stdout}'.trim();

void write(String path, String text) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(text);

String remoteOf(String name) => p.join(base.path, 'remotes', '$name.git');

/// A bare remote with one commit on [branch] and its clone at [path].
void repo(String name, String path, {String branch = 'main'}) {
  final seed = p.join(base.path, 'seed', name);
  Directory(seed).createSync(recursive: true);
  git(seed, ['init', '-q', '-b', branch]);
  write(p.join(seed, 'README.md'), '$name\n');
  write(p.join(seed, 'shared.txt'), 'line 1\nline 2\nline 3\n');
  git(seed, ['add', '-A']);
  git(seed, ['commit', '-qm', 'init $name']);
  Directory(p.dirname(remoteOf(name))).createSync(recursive: true);
  git(base.path, ['clone', '-q', '--bare', seed, remoteOf(name)]);
  final target = path.isEmpty ? root : p.join(root, path);
  git(base.path, ['clone', '-q', '-b', branch, remoteOf(name), target]);
  git(target, ['config', 'user.email', 't@t']);
  git(target, ['config', 'user.name', 't']);
}

/// [name]'s remote gets [file] from another clone.
void incoming(String name, String file, String text, {String branch = 'main'}) {
  final other = p.join(base.path, 'other', name);
  if (!Directory(other).existsSync()) {
    git(base.path, ['clone', '-q', '-b', branch, remoteOf(name), other]);
  } else {
    git(other, ['pull', '-q']);
  }
  write(p.join(other, file), text);
  git(other, ['add', '-A']);
  git(other, ['commit', '-qm', 'elsewhere $file']);
  git(other, ['push', '-q', 'origin', branch]);
}

String remoteHead(String name, [String branch = 'main']) =>
    out(base.path, ['--git-dir', remoteOf(name), 'rev-parse', branch]);

String at(String rel) => rel.isEmpty ? root : p.join(root, rel);

String head(String rel) => out(at(rel), ['rev-parse', 'HEAD']);

String status(String rel) => out(at(rel), ['status', '--porcelain', '-uall']);

/// Runs `:ws-push` [args] through buildkit; the exit code and the report.
Future<({int exit, String text, Map<String, dynamic>? json})> wsPush(
  List<String> args, {
  bool json = true,
}) async {
  final buffer = StringBuffer();
  final previous = Directory.current;
  Directory.current = root;
  try {
    final result = await ToolRunner(
      tool: buildkitTool,
      executors: {
        ...createBuildkitExecutors(),
        'ws-push': WsPushExecutor(out: buffer, now: _now, heartbeatDir: beats),
      },
      output: StringBuffer(),
    ).run(['-R', root, ':ws-push', if (json) '--json', ...args]);
    final text = '$buffer';
    Map<String, dynamic>? doc;
    if (json) {
      final start = text.indexOf('{');
      doc = start < 0
          ? null
          : jsonDecode(text.substring(start)) as Map<String, dynamic>;
    }
    return (exit: result.exitCode, text: text, json: doc);
  } finally {
    Directory.current = previous;
  }
}

List<Map<String, dynamic>> messages(Map<String, dynamic>? json, String code) =>
    [
      for (final m in (json!['messages'] as List).cast<Map<String, dynamic>>())
        if (m['code'] == code) m,
    ];

/// The message [code] about [repo]: its options are offered and each has a
/// command line to repeat that names the option.
Map<String, dynamic> expectMessage(
  Map<String, dynamic>? json,
  String code, {
  String? repo,
  List<String> options = const [],
}) {
  final found = messages(
    json,
    code,
  ).where((m) => repo == null || (m['repository'] as Map?)?['path'] == repo);
  expect(
    found,
    isNotEmpty,
    reason: '$code ${repo ?? ''} in ${jsonEncode(json!['messages'])}',
  );
  final m = found.first;
  final offered = [
    for (final o in m['options'] as List) (o as Map)['option'] as String,
  ];
  for (final o in options) {
    expect(
      offered.any((x) => x.startsWith('--$o')),
      isTrue,
      reason: '$code offers --$o: $offered',
    );
  }
  for (final o in (m['options'] as List).cast<Map>()) {
    expect(o['commandLine'], startsWith('buildkit :ws-push'));
    expect(
      o['commandLine'],
      contains((o['option'] as String).split(' ').first),
    );
    expect(o['explanation'], isNotEmpty);
  }
  return m;
}

void main() {
  setUp(() {
    base = Directory(
      Directory.systemTemp.createTempSync('bk_wsp_').resolveSymbolicLinksSync(),
    );
    root = p.join(base.path, 'tree');
    beats = p.join(base.path, 'beats');
    repo('root', '');
    repo('ai', '_ai');
    repo('core', 'tom_ai/core');
    repo('basics', 'tom_ai/basics');
    repo('fork', 'tom_ai/xternal/fork', branch: 'tom/1.0-fixes');
    repo('bin', 'tom_binaries');
    repo('up', 'c/up');
    final pin = out(at('c/up'), ['rev-parse', 'HEAD']);
    write(p.join(root, 'repos.yaml'), '''
version: 1
root: {url: git@fixture:root.git, branch: main}
repos:
  - {path: tom_ai/core, url: git@fixture:core.git, kind: code, branch: main}
  - {path: tom_ai/basics, url: git@fixture:basics.git, kind: code, branch: main}
  - {path: tom_ai/xternal/fork, url: git@fixture:fork.git, kind: fork, branch: tom/1.0-fixes}
  - {path: _ai, url: git@fixture:ai.git, kind: ai, branch: main}
  - {path: tom_binaries, url: git@fixture:bin.git, kind: binaries, branch: main}
  - {path: c/up, url: git@fixture:up.git, kind: upstream, pin: $pin}
''');
    write(p.join(root, '.tom', 'machine_id'), 'testhost\n');
    write(
      p.join(root, '.gitignore'),
      '/_ai/\n/tom_ai/\n/tom_binaries/\n/c/\n/stray/\n/.tom/\n',
    );
    git(root, ['add', '-A']);
    git(root, ['commit', '-qm', 'manifest']);
    git(root, ['push', '-q', 'origin', 'main']);
  });
  tearDown(() => base.deleteSync(recursive: true));

  test('BK-WSP-1: a clean tree: one fetch per repository, nothing to do, '
      'exit 0 [2026-11-24]', () async {
    final r = await wsPush([]);
    expect(r.exit, 0, reason: r.text);
    expect(r.json!['messages'], isEmpty);
    expect(r.json!['done'], isEmpty);
    expect((r.json!['unchanged'] as List).toSet(), {
      '.',
      '_ai',
      'tom_ai/core',
      'tom_ai/basics',
      'tom_ai/xternal/fork',
      'tom_binaries',
    }, reason: 'the upstream and the unknown clone are no part of the run');
  });

  test('BK-WSP-2: everything committed with one message and pushed, _ai and '
      'the leaves first, the root last; after exit 0 nothing is uncommitted '
      'and every origin/<branch> holds HEAD [2026-11-24]', () async {
    write(p.join(at('_ai'), 'quests/q.md'), 'q\n');
    write(p.join(at('tom_ai/core'), 'lib/a.dart'), 'a\n');
    write(p.join(at('tom_ai/xternal/fork'), 'f.txt'), 'f\n');
    write(p.join(root, 'notes.md'), 'n\n');
    final r = await wsPush([]);
    expect(r.exit, 0, reason: r.text);
    final done = [
      for (final d in r.json!['done'] as List) (d as Map)['repository'],
    ];
    expect(done.first, '_ai');
    expect(done.last, '.');
    expect(
      done.indexOf('tom_ai/xternal/fork'),
      lessThan(done.indexOf('tom_ai/core')),
      reason: 'deeper first',
    );
    for (final (rel, name, branch) in [
      ('', 'root', 'main'),
      ('_ai', 'ai', 'main'),
      ('tom_ai/core', 'core', 'main'),
      ('tom_ai/basics', 'basics', 'main'),
      ('tom_ai/xternal/fork', 'fork', 'tom/1.0-fixes'),
    ]) {
      expect(status(rel), isEmpty, reason: rel);
      expect(remoteHead(name, branch), head(rel), reason: rel);
    }
    expect(
      out(at('tom_ai/core'), ['log', '-1', '--format=%s']),
      'ws-push on testhost at 2026-11-24T16:02',
    );
    final core = (r.json!['done'] as List).cast<Map>().firstWhere(
      (d) => d['repository'] == 'tom_ai/core',
    );
    expect(core['files'], ['lib/a.dart']);
    expect(core['actions'], ['committed 1 file(s)', 'pushed main']);
  });

  test('BK-WSP-3: -m gives every commit its message; incoming commits are '
      'merged before the push [2026-11-24]', () async {
    incoming('core', 'remote.txt', 'r\n');
    write(p.join(at('tom_ai/core'), 'local.txt'), 'l\n');
    final r = await wsPush(['-m', 'Evening state']);
    expect(r.exit, 0, reason: r.text);
    expect(
      out(at('tom_ai/core'), ['log', '-1', '--format=%s', 'HEAD^2']),
      'elsewhere remote.txt',
    );
    expect(remoteHead('core'), head('tom_ai/core'));
    expect(File(p.join(at('tom_ai/core'), 'remote.txt')).existsSync(), isTrue);
    final core = (r.json!['done'] as List).cast<Map>().firstWhere(
      (d) => d['repository'] == 'tom_ai/core',
    );
    expect(core['actions'], contains('merged 1 incoming commit(s)'));
    expect(
      out(at('tom_ai/core'), ['log', '-1', '--format=%s', 'HEAD^1']),
      'Evening state',
    );
  });

  void conflict() {
    incoming('core', 'shared.txt', 'line 1\nTHEIRS\nline 3\n');
    write(p.join(at('tom_ai/core'), 'shared.txt'), 'line 1\nOURS\nline 3\n');
  }

  test('BK-WSP-4: a conflict is aborted, nothing pushed for the repository, '
      'ws-conflict with its options and repeat line; the others are pushed; '
      'exit 1 [2026-11-24]', () async {
    conflict();
    write(p.join(at('tom_ai/basics'), 'b.txt'), 'b\n');
    final before = remoteHead('core');
    final r = await wsPush(['-m', 'x']);
    expect(r.exit, 1, reason: r.text);
    final m = expectMessage(
      r.json,
      'ws-conflict',
      repo: 'tom_ai/core',
      options: ['merge-branch', 'ours', 'theirs', 'leave-conflict', 'skip'],
    );
    expect(m['evidence']['files'], ['shared.txt  both changed']);
    expect(m['state'], contains('Nothing was pushed'));
    expect(
      (m['options'] as List).cast<Map>().first['commandLine'],
      'buildkit :ws-push -m x --merge-branch core',
    );
    expect(remoteHead('core'), before);
    expect(
      File(p.join(at('tom_ai/core'), '.git', 'MERGE_HEAD')).existsSync(),
      isFalse,
    );
    expect(remoteHead('basics'), head('tom_ai/basics'));
    final text = await wsPush(['-m', 'x'], json: false);
    expect(text.text, contains('CONFLICT  tom_ai/core  (main)'));
    expect(
      text.text,
      contains('Repeat with:  buildkit :ws-push -m x --merge-branch core'),
    );
  });

  test(
    'BK-WSP-5: --merge-branch pushes the commits to ws-push/<host>/<stamp> '
    'and leaves the branch; the next run warns ws-rescue-open [2026-11-24]',
    () async {
      conflict();
      final before = remoteHead('core');
      final r = await wsPush(['--merge-branch', 'core']);
      expect(r.exit, 1, reason: 'origin/main does not hold HEAD yet');
      expect(remoteHead('core'), before);
      expect(
        remoteHead('core', 'ws-push/testhost/261124-1602'),
        head('tom_ai/core'),
      );
      final again = await wsPush([]);
      expectMessage(again.json, 'ws-rescue-open', repo: 'tom_ai/core');
      expect(
        messages(
          again.json,
          'ws-rescue-open',
        ).first['evidence']['branches'].first,
        startsWith('origin/ws-push/testhost/261124-1602'),
      );
    },
  );

  test('BK-WSP-6: --ours and --theirs merge again with that side winning, '
      'then push; exit 0 [2026-11-24]', () async {
    conflict();
    var r = await wsPush(['--ours', 'core']);
    expect(r.exit, 0, reason: r.text);
    expect(
      File(p.join(at('tom_ai/core'), 'shared.txt')).readAsStringSync(),
      contains('OURS'),
    );
    expect(remoteHead('core'), head('tom_ai/core'));

    incoming('core', 'shared.txt', 'line 1\nTHEIRS AGAIN\nline 3\n');
    write(
      p.join(at('tom_ai/core'), 'shared.txt'),
      'line 1\nOURS AGAIN\nline 3\n',
    );
    r = await wsPush(['--theirs', 'core']);
    expect(r.exit, 0, reason: r.text);
    expect(
      File(p.join(at('tom_ai/core'), 'shared.txt')).readAsStringSync(),
      contains('THEIRS AGAIN'),
    );
    expect(remoteHead('core'), head('tom_ai/core'));
  });

  test('BK-WSP-7: --leave-conflict leaves the conflict in the working tree; '
      '--skip leaves the repository out; both exit 1 [2026-11-24]', () async {
    conflict();
    var r = await wsPush(['--skip', 'core']);
    expect(r.exit, 1);
    expect(
      status('tom_ai/core'),
      contains('shared.txt'),
      reason: 'not even committed',
    );
    r = await wsPush(['--leave-conflict', 'core']);
    expect(r.exit, 1);
    expect(
      File(p.join(at('tom_ai/core'), '.git', 'MERGE_HEAD')).existsSync(),
      isTrue,
    );
    final m = expectMessage(r.json, 'ws-conflict', repo: 'tom_ai/core');
    expect(m['state'], contains('Resolve the files'));
  });

  test('BK-WSP-8: off its branch: ws-off-branch; --push-current pushes the '
      'branch it is on [2026-11-24]', () async {
    final fork = at('tom_ai/xternal/fork');
    git(fork, ['checkout', '-q', '-b', 'feature']);
    write(p.join(fork, 'x.txt'), 'x\n');
    var r = await wsPush([]);
    expect(r.exit, 1);
    final m = expectMessage(
      r.json,
      'ws-off-branch',
      repo: 'tom_ai/xternal/fork',
      options: ['push-current', 'to-branch', 'set-branch', 'skip'],
    );
    expect(
      m['finding'],
      contains('On feature; repos.yaml expects tom/1.0-fixes'),
    );
    expect(
      (m['options'] as List).cast<Map>().first['commandLine'],
      'buildkit :ws-push --push-current fork',
    );
    expect(
      status('tom_ai/xternal/fork'),
      isNotEmpty,
      reason: 'nothing committed',
    );
    r = await wsPush(['--push-current', 'fork']);
    expect(r.exit, 0, reason: r.text);
    expect(remoteHead('fork', 'feature'), head('tom_ai/xternal/fork'));
  });

  test('BK-WSP-9: --to-branch merges the current branch into the expected '
      'one and pushes it; --set-branch records the branch in repos.yaml and '
      'the root commits it [2026-11-24]', () async {
    final fork = at('tom_ai/xternal/fork');
    git(fork, ['checkout', '-q', '-b', 'feature']);
    write(p.join(fork, 'x.txt'), 'x\n');
    var r = await wsPush(['--to-branch', 'fork']);
    expect(r.exit, 0, reason: r.text);
    expect(out(fork, ['symbolic-ref', '--short', 'HEAD']), 'tom/1.0-fixes');
    expect(remoteHead('fork', 'tom/1.0-fixes'), head('tom_ai/xternal/fork'));
    expect(File(p.join(fork, 'x.txt')).existsSync(), isTrue);

    git(fork, ['checkout', '-q', '-b', 'next']);
    r = await wsPush(['--set-branch', 'fork']);
    expect(r.exit, 0, reason: r.text);
    expect(
      File(p.join(root, 'repos.yaml')).readAsStringSync(),
      contains(
        'path: tom_ai/xternal/fork, url: git@fixture:fork.git, kind: fork, branch: next}',
      ),
    );
    expect(status(''), isEmpty);
    expect(remoteHead('root'), head(''));
    expect(remoteHead('fork', 'next'), head('tom_ai/xternal/fork'));
  });

  test('BK-WSP-10: a detached HEAD at its branch is put back; one with commits '
      'on no branch is ws-detached; --rescue-detached pushes them and returns '
      '[2026-11-24]', () async {
    final core = at('tom_ai/core');
    git(core, ['checkout', '-q', '--detach']);
    var r = await wsPush([]);
    expect(r.exit, 0, reason: r.text);
    expect(out(core, ['symbolic-ref', '--short', 'HEAD']), 'main');

    git(core, ['checkout', '-q', '--detach']);
    write(p.join(core, 'lost.txt'), 'l\n');
    git(core, ['add', '-A']);
    git(core, ['commit', '-qm', 'on no branch']);
    final lost = head('tom_ai/core');
    r = await wsPush([]);
    expect(r.exit, 1);
    final m = expectMessage(
      r.json,
      'ws-detached',
      repo: 'tom_ai/core',
      options: ['rescue-detached', 'skip'],
    );
    expect(m['evidence']['commits'].first, contains('on no branch'));
    expect(
      (m['options'] as List).cast<Map>().first['commandLine'],
      'buildkit :ws-push --rescue-detached core',
    );
    r = await wsPush(['--rescue-detached', 'core']);
    expect(r.exit, 0, reason: r.text);
    expect(out(core, ['symbolic-ref', '--short', 'HEAD']), 'main');
    expect(remoteHead('core', 'ws-push/testhost/261124-1602'), lost);
  });

  test('BK-WSP-11: a secret refuses the run before anything changes; '
      '--skip-file leaves it uncommitted (exit 1), --allow-file commits it '
      '[2026-11-24]', () async {
    final core = at('tom_ai/core');
    write(p.join(core, 'config/.env'), 'TOKEN=x\n');
    write(p.join(at('tom_ai/basics'), 'b.txt'), 'b\n');
    var r = await wsPush([]);
    expect(r.exit, 2);
    final m = expectMessage(
      r.json,
      'ws-secret',
      repo: 'tom_ai/core',
      options: ['skip-file', 'allow-file'],
    );
    expect(m['evidence']['files'].first, startsWith('config/.env'));
    expect(
      (m['options'] as List).cast<Map>().first['commandLine'],
      'buildkit :ws-push --skip-file config/.env',
    );
    expect(
      status('tom_ai/basics'),
      isNotEmpty,
      reason: 'refused: nothing changed',
    );
    r = await wsPush(['--skip-file', 'config/.env']);
    expect(r.exit, 1);
    expect(status('tom_ai/core'), '?? config/.env');
    expect(status('tom_ai/basics'), isEmpty);
    r = await wsPush(['--allow-file', 'config/.env']);
    expect(r.exit, 0, reason: r.text);
    expect(status('tom_ai/core'), isEmpty);
  });

  test(
    'BK-WSP-12: a file over 50 MB refuses the run (ws-large) [2026-11-24]',
    () async {
      final big = File(p.join(at('tom_ai/basics'), 'big.bin'))..createSync();
      big.openSync(mode: FileMode.write)
        ..setPositionSync(51 * 1024 * 1024)
        ..writeByteSync(1)
        ..closeSync();
      final r = await wsPush([]);
      expect(r.exit, 2);
      final m = expectMessage(
        r.json,
        'ws-large',
        repo: 'tom_ai/basics',
        options: ['skip-file', 'allow-file'],
      );
      expect(m['evidence']['sizes'].first, 'big.bin  (51 MB)');
      expect(status('tom_ai/basics'), '?? big.bin');
    },
  );

  test('BK-WSP-13: an active Tom AI window refuses the run, listing it; '
      '--ignore-active runs anyway; a stale heartbeat is no window '
      '[2026-11-24]', () async {
    write(p.join(at('tom_ai/core'), 'a.txt'), 'a\n');
    write(
      p.join(beats, 'w1.window-state.json'),
      jsonEncode({
        'workspace': 'tom_agent_container',
        'activeQuest': 'build_tom',
        'heartbeat': _now
            .subtract(const Duration(seconds: 20))
            .toIso8601String(),
        'queue': {
          'run': 'default',
          'sending': {
            'preview': 'Do the quest todo',
            'since': '2026-11-24T15:50',
            'session': 'default@default',
          },
        },
        'runs': [
          {'run': 'default', 'state': 'running', 'detail': 'Do the quest todo'},
        ],
      }),
    );
    write(
      p.join(beats, 'w2.window-state.json'),
      jsonEncode({
        'workspace': 'gone',
        'heartbeat': _now
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'queue': {
          'sending': {'preview': 'old'},
        },
      }),
    );
    var r = await wsPush([]);
    expect(r.exit, 2);
    final m = expectMessage(r.json, 'ws-active', options: ['ignore-active']);
    final windows = (m['evidence']['windows'] as List).join('\n');
    expect(
      windows,
      contains(
        'tom_agent_container (quest build_tom), run default: sending "Do the quest todo" since 2026-11-24T15:50',
      ),
    );
    expect(windows, isNot(contains('gone')));
    expect(
      (m['options'] as List).cast<Map>().single['commandLine'],
      'buildkit :ws-push --ignore-active',
    );
    expect(status('tom_ai/core'), isNotEmpty);
    r = await wsPush(['--ignore-active']);
    expect(r.exit, 0, reason: r.text);
    expect(status('tom_ai/core'), isEmpty);
  });

  test('BK-WSP-14: an unknown clone is skipped and named first, exit 1; '
      '--include-unknown commits and pushes it [2026-11-24]', () async {
    repo('stray', 'stray');
    write(p.join(at('stray'), 's.txt'), 's\n');
    write(p.join(at('tom_ai/basics'), 'b.txt'), 'b\n');
    var r = await wsPush([]);
    expect(r.exit, 1);
    final first = (r.json!['messages'] as List).first as Map;
    expect(first['code'], 'ws-unknown');
    final m = expectMessage(
      r.json,
      'ws-unknown',
      repo: 'stray',
      options: ['include-unknown'],
    );
    expect(m['evidence']['state'], ['1 uncommitted']);
    expect(status('stray'), isNotEmpty);
    expect(remoteHead('basics'), head('tom_ai/basics'));
    r = await wsPush(['--include-unknown', 'stray']);
    expect(r.exit, 0, reason: r.text);
    expect(remoteHead('stray'), head('stray'));
  });

  test('BK-WSP-15: uncommitted binaries are a warning, not committed; '
      '--commit-binaries commits and pushes them [2026-11-24]', () async {
    write(p.join(at('tom_binaries'), 'tom/darwin-arm64/buildkit'), 'bin\n');
    var r = await wsPush([]);
    expect(r.exit, 0, reason: 'a warning does not change the exit code');
    final m = expectMessage(
      r.json,
      'ws-binaries',
      repo: 'tom_binaries',
      options: ['commit-binaries'],
    );
    expect(m['finding'], contains('1 uncommitted file(s) on darwin-arm64'));
    expect(status('tom_binaries'), isNotEmpty);
    r = await wsPush(['--commit-binaries']);
    expect(r.exit, 0, reason: r.text);
    expect(status('tom_binaries'), isEmpty);
    expect(remoteHead('bin'), head('tom_binaries'));
  });

  test('BK-WSP-16: a push still rejected after one more merge is '
      'ws-push-rejected; never forced [2026-11-24]', () async {
    final hook = File(p.join(remoteOf('basics'), 'hooks', 'pre-receive'))
      ..writeAsStringSync('#!/bin/sh\necho "protected branch" >&2\nexit 1\n');
    Process.runSync('chmod', ['+x', hook.path]);
    write(p.join(at('tom_ai/basics'), 'b.txt'), 'b\n');
    final before = remoteHead('basics');
    final r = await wsPush([]);
    expect(r.exit, 1);
    final m = expectMessage(
      r.json,
      'ws-push-rejected',
      repo: 'tom_ai/basics',
      options: ['merge-branch', 'skip'],
    );
    expect(m['evidence']['git'].first, contains('protected branch'));
    expect(m['state'], contains('nothing was forced'));
    expect(remoteHead('basics'), before);
  });

  test('BK-WSP-17: an unregistered merge driver refuses the run (ws-driver) '
      '[2026-11-24]', () async {
    write(
      p.join(at('tom_ai/core'), '.gitattributes'),
      '*.trail merge=no-such-driver-xyz\n',
    );
    final r = await wsPush([]);
    expect(r.exit, 2);
    final m = expectMessage(r.json, 'ws-driver', repo: 'tom_ai/core');
    expect(
      m['finding'],
      contains('merge=no-such-driver-xyz is named in .gitattributes'),
    );
    expect(m['options'], isEmpty, reason: 'no override');
  });

  test('BK-WSP-18: a repository mid-merge refuses the run (ws-in-progress); '
      '--skip leaves it out [2026-11-24]', () async {
    final core = at('tom_ai/core');
    incoming('core', 'shared.txt', 'line 1\nTHEIRS\nline 3\n');
    write(p.join(core, 'shared.txt'), 'line 1\nOURS\nline 3\n');
    git(core, ['commit', '-qam', 'ours']);
    git(core, ['fetch', '-q']);
    git(core, ['merge', 'origin/main'], check: false);
    write(p.join(at('tom_ai/basics'), 'b.txt'), 'b\n');
    var r = await wsPush([]);
    expect(r.exit, 2);
    final m = expectMessage(
      r.json,
      'ws-in-progress',
      repo: 'tom_ai/core',
      options: ['skip'],
    );
    expect(m['finding'], contains('in the middle of a merge'));
    expect(m['evidence']['files'], ['shared.txt  (conflicted)']);
    expect(status('tom_ai/basics'), isNotEmpty);
    r = await wsPush(['--skip', 'core']);
    expect(r.exit, 1);
    expect(status('tom_ai/basics'), isEmpty);
  });

  test('BK-WSP-19: no repos.yaml, or an invalid one, refuses the run '
      '(ws-manifest); an unknown repository name is a usage error '
      '[2026-11-24]', () async {
    var r = await wsPush(['--skip', 'nosuchrepo']);
    expect(r.exit, 2);
    expect(r.text, contains('no repository is named `nosuchrepo`'));
    File(p.join(root, 'repos.yaml')).writeAsStringSync('version: 2\n');
    r = await wsPush([]);
    expect(r.exit, 2);
    final m = expectMessage(r.json, 'ws-manifest');
    expect(m['finding'], contains('repos.yaml is not valid'));
    File(p.join(root, 'repos.yaml')).deleteSync();
    r = await wsPush([]);
    expect(r.exit, 2);
    expect(
      expectMessage(r.json, 'ws-manifest')['finding'],
      contains('No repos.yaml'),
    );
  });

  test(
    'BK-WSP-20: a remote that cannot be reached is ws-fetch-failed; an '
    'upstream with local changes is ws-upstream-dirty [2026-11-24]',
    () async {
      git(at('tom_ai/basics'), [
        'remote',
        'set-url',
        'origin',
        p.join(base.path, 'nowhere.git'),
      ]);
      write(p.join(at('tom_ai/basics'), 'b.txt'), 'b\n');
      write(p.join(at('c/up'), 'patch.c'), 'x\n');
      final r = await wsPush([]);
      expect(r.exit, 1);
      expectMessage(
        r.json,
        'ws-fetch-failed',
        repo: 'tom_ai/basics',
        options: ['skip'],
      );
      expect(status('tom_ai/basics'), isNotEmpty);
      final up = expectMessage(r.json, 'ws-upstream-dirty', repo: 'c/up');
      expect(up['evidence']['files'], ['?? patch.c']);
    },
  );

  test(
    'BK-WSP-21: -n shows the whole plan and changes nothing [2026-11-24]',
    () async {
      write(p.join(at('tom_ai/core'), 'a.txt'), 'a\n');
      incoming('basics', 'r.txt', 'r\n');
      git(at('tom_ai/basics'), ['fetch', '-q']);
      final before = head('tom_ai/core');
      final r = await wsPush(['-n']);
      expect(r.exit, 0, reason: r.text);
      final done = {
        for (final d in (r.json!['done'] as List).cast<Map>())
          d['repository']: d['actions'],
      };
      expect(done['tom_ai/core'], [
        'would commit 1 file(s)',
        'would push main',
      ]);
      expect(done['tom_ai/basics'], ['would merge 1 incoming commit(s)']);
      expect(head('tom_ai/core'), before);
      expect(status('tom_ai/core'), '?? a.txt');
    },
  );

  test('BK-WSP-22: the help page lists every option, the steps and the exit '
      'codes; every message has its topic [2026-11-24]', () {
    final help = HelpGenerator.generateCommandHelp(
      wspushCommand,
      tool: buildkitTool,
    );
    for (final o in wspushOptions) {
      expect(help, contains('--${o.name}'), reason: o.name);
    }
    for (final code in wsPushMessages.definitions.map((d) => d.code)) {
      expect(
        help.contains(code) || code == 'ws-unknown' || code == 'ws-rescue-open',
        isTrue,
        reason: code,
      );
      expect(buildkitTool.helpTopics.map((t) => t.name), contains(code));
    }
    expect(help, contains('**Exit Codes**'));
    expect(help, contains('  2  refused before anything changed'));
    expect(help, contains('buildkit :ws-push --merge-branch core'));
  });
}
