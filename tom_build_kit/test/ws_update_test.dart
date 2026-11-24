/// `buildkit :ws-update` on a tree of real repositories with bare remotes,
/// made by each test in a temporary folder (never the live workspace): the
/// root, `_ai`, two code entries, a fork, `tom_binaries` and an upstream.
/// The entries' URLs (`git@fixture:<name>.git`) are mapped onto the bare
/// remotes by a git configuration of the test. Each message code of
/// `:ws-update` (§ 1.10) is produced with its options and repeat line.
///
/// Test IDs: BK-WSU-1..18.
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
import 'package:tom_build_kit/src/v2/ws/ws_update.dart';

late Directory base;
late String root;
late Map<String, String> env;
final _now = DateTime(2026, 11, 24, 16, 2);

ProcessResult git(String dir, List<String> args, {bool check = true}) {
  final r = Process.runSync(
    'git',
    args,
    workingDirectory: dir,
    environment: env,
  );
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

/// A bare remote with one commit on [branch]; cloned at [path] unless
/// [clone] is false.
void repo(String name, String? path, {String branch = 'main'}) {
  final seed = p.join(base.path, 'seed', name);
  Directory(seed).createSync(recursive: true);
  git(seed, ['init', '-q', '-b', branch]);
  write(p.join(seed, 'README.md'), '$name\n');
  write(p.join(seed, 'shared.txt'), 'line 1\nline 2\nline 3\n');
  git(seed, ['add', '-A']);
  git(seed, ['commit', '-qm', 'init $name']);
  Directory(p.dirname(remoteOf(name))).createSync(recursive: true);
  git(base.path, ['clone', '-q', '--bare', seed, remoteOf(name)]);
  if (path == null) return;
  final target = path.isEmpty ? root : p.join(root, path);
  git(base.path, [
    'clone',
    '-q',
    '-b',
    branch,
    'git@fixture:$name.git',
    target,
  ]);
}

/// Another clone of [name] commits [file] and pushes it.
void incoming(String name, String file, String text, {String branch = 'main'}) {
  final other = p.join(base.path, 'other', name);
  if (!Directory(other).existsSync()) {
    git(base.path, [
      'clone',
      '-q',
      '-b',
      branch,
      'git@fixture:$name.git',
      other,
    ]);
  } else {
    git(other, ['pull', '-q', 'origin', branch]);
  }
  write(p.join(other, file), text);
  git(other, ['add', '-A']);
  git(other, ['commit', '-qm', 'elsewhere $file']);
  git(other, ['push', '-q', 'origin', branch]);
}

/// The root's remote gets repos.yaml changed by [edit].
void manifest(String Function(String) edit) {
  final other = p.join(base.path, 'other', 'root');
  if (!Directory(other).existsSync()) {
    git(base.path, ['clone', '-q', 'git@fixture:root.git', other]);
  } else {
    git(other, ['pull', '-q', 'origin', 'main']);
  }
  final f = File(p.join(other, 'repos.yaml'));
  f.writeAsStringSync(edit(f.readAsStringSync()));
  git(other, ['commit', '-qam', 'repos.yaml']);
  git(other, ['push', '-q', 'origin', 'main']);
}

String remoteHead(String name, [String branch = 'main']) =>
    out(base.path, ['--git-dir', remoteOf(name), 'rev-parse', branch]);

String at(String rel) => rel.isEmpty ? root : p.join(root, rel);
String head(String rel) => out(at(rel), ['rev-parse', 'HEAD']);
String status(String rel) => out(at(rel), ['status', '--porcelain', '-uall']);

Future<({int exit, String text, Map<String, dynamic>? json})> wsUpdate(
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
        'ws-update': WsUpdateExecutor(
          out: buffer,
          now: _now,
          gitEnvironment: env,
        ),
      },
      output: StringBuffer(),
    ).run(['-R', root, ':ws-update', if (json) '--json', ...args]);
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
    expect(o['commandLine'], startsWith('buildkit :ws-update'));
    expect(
      o['commandLine'],
      contains((o['option'] as String).split(' ').first),
    );
  }
  return m;
}

/// Every repository's actions, in the order the run did them.
Map<String, List<String>> doneOf(Map<String, dynamic>? json) {
  final out = <String, List<String>>{};
  for (final d in (json!['done'] as List).cast<Map>()) {
    out.putIfAbsent(d['repository'] as String, () => []).addAll([
      for (final a in d['actions'] as List) '$a',
    ]);
  }
  return out;
}

void main() {
  late String pin;
  setUp(() {
    base = Directory(
      Directory.systemTemp.createTempSync('bk_wsu_').resolveSymbolicLinksSync(),
    );
    root = p.join(base.path, 'tree');
    final config = File(p.join(base.path, 'gitconfig'))
      ..writeAsStringSync('''
[user]
\tname = t
\temail = t@t
[init]
\tdefaultBranch = main
[url "${base.path}/remotes/"]
\tinsteadOf = git@fixture:
[protocol "file"]
\tallow = always
''');
    env = {
      'GIT_CONFIG_GLOBAL': config.path,
      'GIT_CONFIG_NOSYSTEM': '1',
      'TOM_REPOS_HOST': 'testhost',
    };
    repo('root', '');
    repo('ai', '_ai');
    repo('core', 'tom_ai/core');
    repo('basics', 'tom_ai/basics');
    repo('fork', 'tom_ai/xternal/fork', branch: 'tom/1.0-fixes');
    repo('bin', 'tom_binaries');
    repo('up', 'c/up');
    pin = out(at('c/up'), ['rev-parse', 'HEAD']);
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
    write(
      p.join(root, '.gitignore'),
      '/_ai/\n/tom_ai/\n/tom_binaries/\n/c/\n/apps/\n/stray/\n',
    );
    git(root, ['add', '-A']);
    git(root, ['commit', '-qm', 'manifest']);
    git(root, ['push', '-q', 'origin', 'main']);
  });
  tearDown(() => base.deleteSync(recursive: true));

  test('BK-WSU-1: a tree behind its remotes is brought up to them, forks '
      'fast-forwarded; nothing is pushed; exit 0 [2026-11-24]', () async {
    incoming('core', 'c.txt', 'c\n');
    incoming('ai', 'a.md', 'a\n');
    incoming('fork', 'f.txt', 'f\n', branch: 'tom/1.0-fixes');
    incoming('root', 'r.txt', 'r\n');
    write(p.join(at('tom_ai/core'), 'local.txt'), 'mine\n');
    final remotes = {
      for (final n in ['root', 'ai', 'core', 'basics', 'bin']) n: remoteHead(n),
    };
    final r = await wsUpdate([]);
    expect(r.exit, 0, reason: r.text);
    for (final (rel, name, branch) in [
      ('', 'root', 'main'),
      ('_ai', 'ai', 'main'),
      ('tom_ai/core', 'core', 'main'),
      ('tom_ai/xternal/fork', 'fork', 'tom/1.0-fixes'),
    ]) {
      expect(
        git(at(rel), [
          'merge-base',
          '--is-ancestor',
          remoteHead(name, branch),
          'HEAD',
        ], check: false).exitCode,
        0,
        reason: '$rel at or ahead of origin',
      );
    }
    expect(
      out(at('tom_ai/xternal/fork'), ['rev-parse', 'HEAD']),
      remoteHead('fork', 'tom/1.0-fixes'),
      reason: 'fast-forwarded, no merge commit',
    );
    expect(
      File(p.join(at('tom_ai/core'), 'local.txt')).readAsStringSync(),
      'mine\n',
      reason: 'an uncommitted file the merge does not touch stays',
    );
    for (final e in remotes.entries) {
      expect(remoteHead(e.key), e.value, reason: 'nothing pushed to ${e.key}');
    }
    final done = doneOf(r.json);
    expect(done['tom_ai/core'], ['merged 1 incoming commit(s)']);
    expect(
      done.values.expand((a) => a),
      isNot(contains(startsWith('re-pointed'))),
      reason: 'an insteadOf rewrite is no changed origin',
    );
    expect(done['tom_ai/xternal/fork'], [
      'fast-forwarded 1 incoming commit(s)',
    ]);
  });

  test('BK-WSU-2: the root first, repos.yaml read again: a new entry is '
      'cloned on its branch, a new upstream at its pin [2026-11-24]', () async {
    repo('extra', null);
    repo('up2', null);
    final up2Seed = p.join(base.path, 'seed', 'up2');
    final up2Pin = out(up2Seed, ['rev-parse', 'HEAD']);
    write(p.join(up2Seed, 'later.txt'), 'later\n');
    git(up2Seed, ['add', '-A']);
    git(up2Seed, ['commit', '-qm', 'after the pin']);
    git(up2Seed, ['push', '-q', remoteOf('up2'), 'main']);
    manifest(
      (t) =>
          '$t'
          '  - {path: tom_ai/extra, url: git@fixture:extra.git, kind: code, branch: main}\n'
          '  - {path: c/up2, url: git@fixture:up2.git, kind: upstream, pin: $up2Pin}\n',
    );
    final r = await wsUpdate([]);
    expect(r.exit, 0, reason: r.text);
    expect(head('tom_ai/extra'), remoteHead('extra'));
    expect(
      out(at('tom_ai/extra'), ['symbolic-ref', '--short', 'HEAD']),
      'main',
    );
    expect(head('c/up2'), up2Pin);
    final done = doneOf(r.json);
    expect(done['tom_ai/extra'], ['cloned on main']);
    expect(done['c/up2'], ['cloned at its pin ${up2Pin.substring(0, 7)}']);
  });

  test('BK-WSU-3: a missing entry that cannot be cloned is ws-clone-failed '
      '[2026-11-24]', () async {
    manifest(
      (t) =>
          '$t  - {path: tom_ai/gone, url: git@fixture:nosuch.git, kind: code, branch: main}\n',
    );
    final r = await wsUpdate([]);
    expect(r.exit, 1);
    final m = expectMessage(
      r.json,
      'ws-clone-failed',
      repo: 'tom_ai/gone',
      options: ['skip'],
    );
    expect(m['evidence']['url'], ['git@fixture:nosuch.git']);
    expect(
      (m['options'] as List).cast<Map>().single['commandLine'],
      'buildkit :ws-update --skip gone',
    );
    expect(Directory(at('tom_ai/gone')).existsSync(), isFalse);
  });

  test('BK-WSU-4: a moved entry is moved when clean and pushed; a dirty old '
      'checkout is ws-move-blocked [2026-11-24]', () async {
    manifest(
      (t) => t.replaceFirst('path: tom_ai/basics,', 'path: apps/basics,'),
    );
    write(p.join(at('tom_ai/basics'), 'wip.txt'), 'wip\n');
    var r = await wsUpdate([]);
    expect(r.exit, 1, reason: r.text);
    final m = expectMessage(
      r.json,
      'ws-move-blocked',
      repo: 'apps/basics',
      options: ['skip'],
    );
    expect(m['evidence']['paths'], ['tom_ai/basics -> apps/basics']);
    expect(m['evidence']['files'], ['?? wip.txt']);
    expect(Directory(at('tom_ai/basics')).existsSync(), isTrue);
    expect(Directory(at('apps/basics')).existsSync(), isFalse);

    File(p.join(at('tom_ai/basics'), 'wip.txt')).deleteSync();
    r = await wsUpdate([]);
    expect(r.exit, 0, reason: r.text);
    expect(Directory(at('tom_ai/basics')).existsSync(), isFalse);
    expect(head('apps/basics'), remoteHead('basics'));
    expect(doneOf(r.json)['apps/basics'], ['moved from tom_ai/basics']);
  });

  test('BK-WSU-5: a changed origin URL is re-pointed [2026-11-24]', () async {
    git(base.path, [
      'clone',
      '-q',
      '--bare',
      remoteOf('core'),
      remoteOf('core2'),
    ]);
    manifest(
      (t) => t.replaceFirst('git@fixture:core.git', 'git@fixture:core2.git'),
    );
    final r = await wsUpdate([]);
    expect(r.exit, 0, reason: r.text);
    expect(
      out(at('tom_ai/core'), ['config', '--get', 'remote.origin.url']),
      'git@fixture:core2.git',
    );
    expect(doneOf(r.json)['tom_ai/core'], [
      're-pointed origin from git@fixture:core.git to git@fixture:core2.git',
    ]);
  });

  test('BK-WSU-6: uncommitted files the merge would overwrite hold the '
      'repository (ws-held); untouched ones go through [2026-11-24]', () async {
    incoming('core', 'shared.txt', 'line 1\nline 2\nTHEIRS\n');
    incoming('basics', 'shared.txt', 'line 1\nline 2\nTHEIRS\n');
    write(p.join(at('tom_ai/core'), 'shared.txt'), 'MINE\nline 2\nline 3\n');
    write(p.join(at('tom_ai/basics'), 'other.txt'), 'untouched\n');
    final before = head('tom_ai/core');
    final r = await wsUpdate([]);
    expect(r.exit, 1);
    final m = expectMessage(
      r.json,
      'ws-held',
      repo: 'tom_ai/core',
      options: ['commit-first', 'stash-merge', 'skip'],
    );
    expect(m['evidence']['files'], ['shared.txt']);
    expect(m['evidence']['commits'].single, contains('elsewhere shared.txt'));
    expect(
      (m['options'] as List).cast<Map>().first['commandLine'],
      'buildkit :ws-update --commit-first core',
    );
    expect(head('tom_ai/core'), before);
    expect(
      File(p.join(at('tom_ai/core'), 'shared.txt')).readAsStringSync(),
      startsWith('MINE'),
    );
    expect(head('tom_ai/basics'), remoteHead('basics'));
    expect(File(p.join(at('tom_ai/basics'), 'other.txt')).existsSync(), isTrue);
  });

  test(
    'BK-WSU-7: --commit-first commits and merges (not pushed); '
    '--stash-merge stashes, merges and puts the files back [2026-11-24]',
    () async {
      incoming('core', 'shared.txt', 'line 1\nline 2\nTHEIRS\n');
      write(p.join(at('tom_ai/core'), 'shared.txt'), 'MINE\nline 2\nline 3\n');
      var r = await wsUpdate(['--commit-first', 'core', '-m', 'before update']);
      expect(r.exit, 0, reason: r.text);
      expect(
        File(p.join(at('tom_ai/core'), 'shared.txt')).readAsStringSync(),
        'MINE\nline 2\nTHEIRS\n',
      );
      expect(
        out(at('tom_ai/core'), ['log', '-1', '--format=%s', 'HEAD^1']),
        'before update',
      );
      expect(
        remoteHead('core'),
        isNot(head('tom_ai/core')),
        reason: 'not pushed',
      );

      incoming('basics', 'shared.txt', 'line 1\nline 2\nTHEIRS\n');
      write(
        p.join(at('tom_ai/basics'), 'shared.txt'),
        'MINE\nline 2\nline 3\n',
      );
      r = await wsUpdate(['--stash-merge', 'basics']);
      expect(r.exit, 0, reason: r.text);
      expect(head('tom_ai/basics'), remoteHead('basics'));
      expect(
        File(p.join(at('tom_ai/basics'), 'shared.txt')).readAsStringSync(),
        'MINE\nline 2\nTHEIRS\n',
      );
      expect(
        '${git(at('tom_ai/basics'), ['status', '--porcelain']).stdout}',
        ' M shared.txt\n',
        reason: 'back in place, unstaged',
      );
      expect(out(at('tom_ai/basics'), ['stash', 'list']), isEmpty);
    },
  );

  test(
    'BK-WSU-8: a conflict is aborted (ws-conflict); --theirs merges again '
    'with the incoming side; --leave-conflict leaves it [2026-11-24]',
    () async {
      incoming('core', 'shared.txt', 'line 1\nTHEIRS\nline 3\n');
      write(p.join(at('tom_ai/core'), 'shared.txt'), 'line 1\nOURS\nline 3\n');
      git(at('tom_ai/core'), ['commit', '-qam', 'ours']);
      final before = head('tom_ai/core');
      var r = await wsUpdate([]);
      expect(r.exit, 1);
      final m = expectMessage(
        r.json,
        'ws-conflict',
        repo: 'tom_ai/core',
        options: ['ours', 'theirs', 'leave-conflict', 'skip'],
      );
      expect(m['evidence']['files'], ['shared.txt  both changed']);
      expect(
        (m['options'] as List).cast<Map>().map((o) => o['option']),
        isNot(contains(startsWith('--merge-branch'))),
      );
      expect(
        (m['options'] as List).cast<Map>().first['commandLine'],
        'buildkit :ws-update --ours core',
      );
      expect(head('tom_ai/core'), before);
      expect(
        File(p.join(at('tom_ai/core'), '.git', 'MERGE_HEAD')).existsSync(),
        isFalse,
      );

      r = await wsUpdate(['--leave-conflict', 'core']);
      expect(r.exit, 1);
      expect(
        File(p.join(at('tom_ai/core'), '.git', 'MERGE_HEAD')).existsSync(),
        isTrue,
      );
      git(at('tom_ai/core'), ['merge', '--abort']);

      r = await wsUpdate(['--theirs', 'core']);
      expect(r.exit, 0, reason: r.text);
      expect(
        File(p.join(at('tom_ai/core'), 'shared.txt')).readAsStringSync(),
        contains('THEIRS'),
      );
    },
  );

  test('BK-WSU-9: a diverged fork is ws-fork-diverged; --merge-fork merges '
      'it like code [2026-11-24]', () async {
    final fork = at('tom_ai/xternal/fork');
    incoming('fork', 'f.txt', 'f\n', branch: 'tom/1.0-fixes');
    write(p.join(fork, 'mine.txt'), 'm\n');
    git(fork, ['add', '-A']);
    git(fork, ['commit', '-qm', 'local patch']);
    final before = head('tom_ai/xternal/fork');
    var r = await wsUpdate([]);
    expect(r.exit, 1);
    final m = expectMessage(
      r.json,
      'ws-fork-diverged',
      repo: 'tom_ai/xternal/fork',
      options: ['merge-fork', 'skip'],
    );
    expect(
      m['finding'],
      contains('1 commit(s) ahead of and 1 behind origin/tom/1.0-fixes'),
    );
    expect(head('tom_ai/xternal/fork'), before);
    r = await wsUpdate(['--merge-fork', 'fork']);
    expect(r.exit, 0, reason: r.text);
    expect(File(p.join(fork, 'f.txt')).existsSync(), isTrue);
    expect(File(p.join(fork, 'mine.txt')).existsSync(), isTrue);
  });

  test('BK-WSU-10: an upstream goes to a changed pin; a dirty one is left '
      'alone (ws-upstream-dirty) [2026-11-24]', () async {
    incoming('up', 'u.txt', 'u\n');
    final newPin = remoteHead('up');
    manifest((t) => t.replaceFirst('pin: $pin', 'pin: $newPin'));
    var r = await wsUpdate([]);
    expect(r.exit, 0, reason: r.text);
    expect(head('c/up'), newPin);
    expect(doneOf(r.json)['c/up'], [
      'put at its pin ${newPin.substring(0, 7)}',
    ]);

    manifest((t) => t.replaceFirst('pin: $newPin', 'pin: $pin'));
    write(p.join(at('c/up'), 'patch.c'), 'x\n');
    r = await wsUpdate([]);
    expect(head('c/up'), newPin, reason: 'left alone');
    final m = expectMessage(r.json, 'ws-upstream-dirty', repo: 'c/up');
    expect(m['finding'], contains('off its pin'));
  });

  test(
    'BK-WSU-11: tom_binaries takes the remote: latest wins [2026-11-24]',
    () async {
      incoming('bin', 'shared.txt', 'line 1\nREMOTE\nline 3\n');
      write(
        p.join(at('tom_binaries'), 'shared.txt'),
        'line 1\nLOCAL\nline 3\n',
      );
      git(at('tom_binaries'), ['commit', '-qam', 'local build']);
      final r = await wsUpdate([]);
      expect(r.exit, 0, reason: r.text);
      expect(
        File(p.join(at('tom_binaries'), 'shared.txt')).readAsStringSync(),
        contains('REMOTE'),
      );
      expect(doneOf(r.json)['tom_binaries'], [
        'merged 1 incoming commit(s) (-X theirs)',
      ]);
    },
  );

  test(
    'BK-WSU-12: off its branch (ws-off-branch, --to-branch) and a '
    'detached HEAD with commits on no branch (ws-detached) [2026-11-24]',
    () async {
      final core = at('tom_ai/core');
      incoming('core', 'c.txt', 'c\n');
      git(core, ['checkout', '-q', '-b', 'feature']);
      write(p.join(core, 'feature.txt'), 'feature\n');
      var r = await wsUpdate([]);
      expect(r.exit, 1);
      final m = expectMessage(
        r.json,
        'ws-off-branch',
        repo: 'tom_ai/core',
        options: ['to-branch', 'set-branch', 'skip'],
      );
      expect(m['finding'], contains('On feature; repos.yaml expects main'));
      expect(
        (m['options'] as List).cast<Map>().first['commandLine'],
        'buildkit :ws-update --to-branch core',
      );
      r = await wsUpdate(['--to-branch', 'core']);
      expect(r.exit, 0, reason: r.text);
      expect(out(core, ['symbolic-ref', '--short', 'HEAD']), 'main');
      for (final ancestor in [remoteHead('core'), 'feature']) {
        expect(
          git(core, ['merge-base', '--is-ancestor', ancestor, 'HEAD']).exitCode,
          0,
          reason: '$ancestor in main',
        );
      }
      expect(File(p.join(core, 'feature.txt')).existsSync(), isTrue);
      expect(status('tom_ai/core'), isEmpty, reason: 'committed on feature');
      expect(
        doneOf(r.json)['tom_ai/core'],
        contains('merged feature into main (not pushed)'),
      );
      expect(
        remoteHead('core'),
        isNot(head('tom_ai/core')),
        reason: 'not pushed',
      );

      final basics = at('tom_ai/basics');
      git(basics, ['checkout', '-q', '--detach']);
      write(p.join(basics, 'lost.txt'), 'l\n');
      git(basics, ['add', '-A']);
      git(basics, ['commit', '-qm', 'on no branch']);
      r = await wsUpdate([]);
      expect(r.exit, 1);
      final d = expectMessage(
        r.json,
        'ws-detached',
        repo: 'tom_ai/basics',
        options: ['rescue-detached', 'skip'],
      );
      expect(d['evidence']['commits'].single, contains('on no branch'));
    },
  );

  test('BK-WSU-13: the ignore blocks are written; unknown clones are reported '
      '(ws-unknown-seen) [2026-11-24]', () async {
    repo('stray', 'stray');
    final r = await wsUpdate([]);
    expect(r.exit, 0, reason: r.text);
    final m = expectMessage(r.json, 'ws-unknown-seen');
    expect(m['evidence']['paths'], ['stray']);
    final gitignore = File(p.join(root, '.gitignore')).readAsStringSync();
    expect(gitignore, contains('# >>> repos.yaml (generated, tom_repos) >>>'));
    expect(gitignore, contains('/tom_ai/core/'));
    expect(
      doneOf(r.json)['.'],
      contains('wrote the ignore block of ./.gitignore'),
    );
  });

  test('BK-WSU-14: refusals: ws-driver, ws-in-progress, ws-manifest '
      '[2026-11-24]', () async {
    write(
      p.join(at('tom_ai/core'), '.gitattributes'),
      '*.x merge=no-such-driver-xyz\n',
    );
    var r = await wsUpdate([]);
    expect(r.exit, 2);
    expectMessage(r.json, 'ws-driver', repo: 'tom_ai/core');
    File(p.join(at('tom_ai/core'), '.gitattributes')).deleteSync();

    final basics = at('tom_ai/basics');
    incoming('basics', 'shared.txt', 'line 1\nTHEIRS\nline 3\n');
    write(p.join(basics, 'shared.txt'), 'line 1\nOURS\nline 3\n');
    git(basics, ['commit', '-qam', 'ours']);
    git(basics, ['fetch', '-q']);
    git(basics, ['merge', 'origin/main'], check: false);
    r = await wsUpdate([]);
    expect(r.exit, 2);
    expectMessage(
      r.json,
      'ws-in-progress',
      repo: 'tom_ai/basics',
      options: ['skip'],
    );
    git(basics, ['merge', '--abort']);

    File(p.join(root, 'repos.yaml')).writeAsStringSync('version: 2\n');
    r = await wsUpdate([]);
    expect(r.exit, 2);
    expect(
      expectMessage(r.json, 'ws-manifest')['finding'],
      contains('repos.yaml is not valid'),
    );
  });

  test('BK-WSU-15: a remote that cannot be reached is ws-fetch-failed '
      '[2026-11-24]', () async {
    manifest(
      (t) =>
          t.replaceFirst('git@fixture:basics.git', 'git@fixture:nowhere.git'),
    );
    final r = await wsUpdate([]);
    expect(r.exit, 1);
    expectMessage(
      r.json,
      'ws-fetch-failed',
      repo: 'tom_ai/basics',
      options: ['skip'],
    );
  });

  test(
    'BK-WSU-16: -n shows the plan and changes nothing [2026-11-24]',
    () async {
      incoming('core', 'c.txt', 'c\n');
      git(at('tom_ai/core'), ['fetch', '-q']);
      final before = head('tom_ai/core');
      final r = await wsUpdate(['-n']);
      expect(r.exit, 0, reason: r.text);
      expect(doneOf(r.json)['tom_ai/core'], [
        'would merge 1 incoming commit(s)',
      ]);
      expect(head('tom_ai/core'), before);
    },
  );

  test('BK-WSU-17: the help page lists every option, the steps and the exit '
      'codes; every message has its topic [2026-11-24]', () {
    final help = HelpGenerator.generateCommandHelp(
      wsupdateCommand,
      tool: buildkitTool,
    );
    for (final o in wsupdateOptions) {
      expect(help, contains('--${o.name}'), reason: o.name);
    }
    for (final d in wsUpdateMessages.definitions) {
      expect(buildkitTool.helpTopics.map((t) => t.name), contains(d.code));
    }
    expect(
      buildkitTool.helpTopics.where((t) => t.name == 'ws-conflict'),
      hasLength(1),
      reason: 'a shared message has one topic',
    );
    expect(help, contains('**Exit Codes**'));
    expect(help, contains('buildkit :ws-update --stash-merge basics'));
  });

  test('BK-WSU-18: --skip leaves a held repository out (exit 1); --ours, '
      '--set-branch and --rescue-detached [2026-11-24]', () async {
    final core = at('tom_ai/core');
    incoming('core', 'shared.txt', 'line 1\nline 2\nTHEIRS\n');
    write(p.join(core, 'shared.txt'), 'MINE\nline 2\nline 3\n');
    final before = head('tom_ai/core');
    var r = await wsUpdate(['--skip', 'core']);
    expect(r.exit, 1, reason: 'a repository left out needs you');
    expect(messages(r.json, 'ws-held'), isEmpty);
    expect(head('tom_ai/core'), before);

    final basics = at('tom_ai/basics');
    incoming('basics', 'shared.txt', 'line 1\nTHEIRS\nline 3\n');
    write(p.join(basics, 'shared.txt'), 'line 1\nOURS\nline 3\n');
    git(basics, ['commit', '-qam', 'ours']);
    r = await wsUpdate(['--ours', 'basics', '--skip', 'core']);
    expect(
      git(basics, [
        'merge-base',
        '--is-ancestor',
        remoteHead('basics'),
        'HEAD',
      ]).exitCode,
      0,
    );
    expect(
      File(p.join(basics, 'shared.txt')).readAsStringSync(),
      contains('OURS'),
    );
    expect(
      File(p.join(basics, 'shared.txt')).readAsStringSync(),
      isNot(contains('THEIRS')),
    );

    git(basics, ['checkout', '-q', '-b', 'topic']);
    r = await wsUpdate(['--set-branch', 'basics', '--skip', 'core']);
    expect(messages(r.json, 'ws-off-branch'), isEmpty);
    expect(
      File(p.join(root, 'repos.yaml')).readAsStringSync(),
      contains(
        'path: tom_ai/basics, url: git@fixture:basics.git, kind: code, branch: topic}',
      ),
    );
    expect(
      doneOf(r.json)['tom_ai/basics'],
      contains('recorded topic as its branch in repos.yaml'),
    );

    final fork = at('tom_ai/xternal/fork');
    git(fork, ['checkout', '-q', '--detach']);
    write(p.join(fork, 'lost.txt'), 'l\n');
    git(fork, ['add', '-A']);
    git(fork, ['commit', '-qm', 'on no branch']);
    final lost = head('tom_ai/xternal/fork');
    r = await wsUpdate(['--rescue-detached', 'fork', '--skip', 'core']);
    final rescue = 'ws-push/${r.json!['host']}/261124-1602';
    expect(
      remoteHead('fork', rescue),
      lost,
      reason: 'the rescue branch is pushed',
    );
    expect(out(fork, ['symbolic-ref', '--short', 'HEAD']), 'tom/1.0-fixes');
    expect(
      remoteHead('fork', 'tom/1.0-fixes'),
      isNot(lost),
      reason: 'only the rescue branch',
    );
    expect(
      doneOf(r.json)['tom_ai/xternal/fork'],
      contains('rescued the detached commits to $rescue'),
    );
  });
}
