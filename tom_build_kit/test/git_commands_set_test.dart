/// The git commands on the combined repository set: `:gitcommit` stages
/// only what `--only` names (or everything with `--all`, nothing without
/// either), `:gitpush` pushes the checked-out branch and reports a rejected
/// push, `:gitstatus` reports ahead / behind `origin/<expected branch>`, a
/// detached HEAD, a repository off its branch and an upstream off its pin,
/// also as JSON.
///
/// Every tree is made by the test in a temporary folder: real repositories
/// with bare remotes, a `repos.yaml` at the root; never the live workspace.
///
/// Test IDs: BK-GSET-1..7.
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
import 'package:tom_build_kit/src/v2/executors/git_executors.dart';

late Directory base;
late String root;

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

/// A bare remote `remotes/<name>.git` with one commit on [branch], and its
/// working clone at [path] below the root (or the root itself for '').
String repo(String name, String path, {String branch = 'main'}) {
  final work = p.join(base.path, 'seed', name);
  Directory(work).createSync(recursive: true);
  git(work, ['init', '-q', '-b', branch]);
  write(p.join(work, 'README.md'), '$name\n');
  git(work, ['add', '-A']);
  git(work, ['commit', '-qm', 'init $name']);
  final remote = p.join(base.path, 'remotes', '$name.git');
  Directory(p.dirname(remote)).createSync(recursive: true);
  git(base.path, ['clone', '-q', '--bare', work, remote]);
  final target = path.isEmpty ? root : p.join(root, path);
  git(base.path, ['clone', '-q', '-b', branch, remote, target]);
  return remote;
}

/// A second clone of [remote] that commits and pushes [file], so the first
/// clone is behind (and a push from it is rejected).
void advanceRemote(String remote, String file, {String branch = 'main'}) {
  final other = p.join(
    base.path,
    'other_${p.basenameWithoutExtension(remote)}',
  );
  if (!Directory(other).existsSync()) {
    git(base.path, ['clone', '-q', '-b', branch, remote, other]);
  }
  write(p.join(other, file), 'from elsewhere\n');
  git(other, ['add', '-A']);
  git(other, ['commit', '-qm', 'elsewhere $file']);
  git(other, ['push', '-q', 'origin', branch]);
}

Future<ToolResult> buildkit(
  List<String> args, {
  Map<String, CommandExecutor> extra = const {},
}) async {
  final previous = Directory.current;
  Directory.current = root;
  try {
    return await ToolRunner(
      tool: buildkitTool,
      executors: {...createBuildkitExecutors(), ...extra},
      output: StringBuffer(),
    ).run(['-R', root, ...args]);
  } finally {
    Directory.current = previous;
  }
}

int commits(String dir) => int.parse(out(dir, ['rev-list', '--count', 'HEAD']));

void main() {
  late String coreRemote;
  setUp(() {
    base = Directory(
      Directory.systemTemp
          .createTempSync('bk_gset_')
          .resolveSymbolicLinksSync(),
    );
    root = p.join(base.path, 'tree');
    repo('root', '');
    coreRemote = repo('core', 'core');
    repo('fork', 'xternal/fork', branch: 'tom/1.0-fixes');
    repo('up', 'up');
    final pin = out(p.join(root, 'up'), ['rev-parse', 'HEAD']);
    write(p.join(root, 'repos.yaml'), '''
version: 1
root: {url: git@fixture:root.git, branch: main}
repos:
  - {path: core, url: git@fixture:core.git, kind: code, branch: main}
  - {path: xternal/fork, url: git@fixture:fork.git, kind: fork, branch: tom/1.0-fixes}
  - {path: up, url: git@fixture:up.git, kind: upstream, pin: $pin}
''');
    write(p.join(root, '.gitignore'), '/core/\n/xternal/fork/\n/up/\n');
    git(root, ['add', '-A']);
    git(root, ['commit', '-qm', 'manifest']);
    git(root, ['push', '-q', 'origin', 'main']);
  });
  tearDown(() => base.deleteSync(recursive: true));

  test('BK-GSET-1: :gitcommit without --only or --all stages nothing; what '
      'is already staged is committed [2026-11-24]', () async {
    final core = p.join(root, 'core');
    write(p.join(core, 'a.txt'), 'a\n');
    write(p.join(core, 'README.md'), 'changed\n');
    final before = commits(core);
    var r = await buildkit(['-i', ':gitcommit', '-m', 'nothing named']);
    expect(r.success, isTrue, reason: r.errorMessage);
    expect(commits(core), before, reason: 'nothing staged, nothing committed');
    expect(out(core, ['status', '--porcelain']), contains('?? a.txt'));

    git(core, ['add', 'README.md']);
    r = await buildkit(['-i', ':gitcommit', '-m', 'the staged one']);
    expect(r.success, isTrue, reason: r.errorMessage);
    expect(commits(core), before + 1);
    expect(
      out(core, ['show', '--name-only', '--format=', 'HEAD']),
      'README.md',
    );
    expect(out(core, ['status', '--porcelain']), '?? a.txt');
  });

  test('BK-GSET-2: --only stages and commits exactly the named paths, an '
      'untracked one included; a path of another repository is not this '
      'one\'s [2026-11-24]', () async {
    final core = p.join(root, 'core');
    final fork = p.join(root, 'xternal', 'fork');
    write(p.join(core, 'new.txt'), 'new\n');
    write(p.join(core, 'keep.txt'), 'keep\n');
    write(p.join(core, 'README.md'), 'changed\n');
    write(p.join(fork, 'f.txt'), 'f\n');
    final forkBefore = commits(fork);
    final r = await buildkit([
      '-i',
      ':gitcommit',
      '-m',
      'named',
      '--only',
      'new.txt,README.md',
    ]);
    expect(r.success, isTrue, reason: r.errorMessage);
    expect(
      out(core, ['show', '--name-only', '--format=', 'HEAD']).split('\n')
        ..sort(),
      ['README.md', 'new.txt'],
    );
    expect(out(core, ['status', '--porcelain']), '?? keep.txt');
    expect(commits(fork), forkBefore, reason: 'no named path changed there');

    final abs = await buildkit([
      '-i',
      ':gitcommit',
      '-m',
      'absolute',
      '--only',
      p.join(fork, 'f.txt'),
    ]);
    expect(abs.success, isTrue, reason: abs.errorMessage);
    expect(commits(fork), forkBefore + 1);
    expect(out(core, ['status', '--porcelain']), '?? keep.txt');
  });

  test('BK-GSET-3: --all stages every change first; --only with --all is '
      'refused [2026-11-24]', () async {
    final core = p.join(root, 'core');
    write(p.join(core, 'x.txt'), 'x\n');
    write(p.join(core, 'README.md'), 'changed\n');
    final r = await buildkit(['-i', ':gitcommit', '-m', 'all', '--all']);
    expect(r.success, isTrue, reason: r.errorMessage);
    expect(out(core, ['status', '--porcelain']), isEmpty);
    write(p.join(core, 'y.txt'), 'y\n');
    final both = await buildkit([
      '-i',
      ':gitcommit',
      '-m',
      'both',
      '--all',
      '--only',
      'y.txt',
    ]);
    expect(both.success, isFalse);
    expect(out(core, ['status', '--porcelain']), '?? y.txt');
  });

  test('BK-GSET-4: :gitpush pushes the checked-out branch, says when it is '
      'up to date, and reports a rejected push without forcing; a detached '
      'HEAD is not pushed [2026-11-24]', () async {
    final core = p.join(root, 'core');
    write(p.join(core, 'p.txt'), 'p\n');
    git(core, ['add', '-A']);
    git(core, ['commit', '-qm', 'to push']);
    final local = out(core, ['rev-parse', 'HEAD']);
    var r = await buildkit(['-i', ':gitpush']);
    expect(r.success, isTrue, reason: r.errorMessage);
    expect(
      out(base.path, ['--git-dir', coreRemote, 'rev-parse', 'main']),
      local,
    );

    r = await buildkit(['-i', ':gitpush']);
    expect(r.success, isTrue);
    expect(
      r.itemResults.firstWhere((i) => i.path == core).message,
      contains('up to date'),
    );

    advanceRemote(coreRemote, 'elsewhere.txt');
    write(p.join(core, 'q.txt'), 'q\n');
    git(core, ['add', '-A']);
    git(core, ['commit', '-qm', 'diverged']);
    final remoteBefore = out(base.path, [
      '--git-dir',
      coreRemote,
      'rev-parse',
      'main',
    ]);
    r = await buildkit(['-i', ':gitpush']);
    expect(r.success, isFalse);
    final failed = r.itemResults.firstWhere((i) => i.path == core);
    expect(failed.error, contains('rejected'));
    expect(failed.error, contains('nothing is forced'));
    expect(
      out(base.path, ['--git-dir', coreRemote, 'rev-parse', 'main']),
      remoteBefore,
    );

    git(core, ['checkout', '-q', '--detach']);
    r = await buildkit(['-i', ':gitpush']);
    expect(
      r.itemResults.firstWhere((i) => i.path == core).error,
      contains('detached'),
    );
  });

  test('BK-GSET-5: :gitstatus --json: every repository of the set with its '
      'branch and ahead / behind origin/<expected branch>; detached, off '
      'branch and off pin are messages [2026-11-24]', () async {
    final core = p.join(root, 'core');
    final fork = p.join(root, 'xternal', 'fork');
    // core: 1 ahead, 1 behind.
    advanceRemote(coreRemote, 'remote.txt');
    git(core, ['fetch', '-q']);
    write(p.join(core, 'local.txt'), 'l\n');
    git(core, ['add', '-A']);
    git(core, ['commit', '-qm', 'local']);
    // fork: on another branch than its entry's.
    git(fork, ['checkout', '-q', '-b', 'feature']);
    // the upstream off its pin.
    final up = p.join(root, 'up');
    write(p.join(up, 'extra.txt'), 'x\n');
    git(up, ['add', '-A']);
    git(up, ['commit', '-qm', 'off pin']);
    // the root detached.
    git(root, ['checkout', '-q', '--detach']);

    final buffer = StringBuffer();
    final r = await buildkit(
      [':gitstatus', '--json', '--no-fetch'],
      extra: {'gitstatus': GitStatusExecutor(out: buffer)},
    );
    expect(r.success, isTrue, reason: r.errorMessage);
    final json = jsonDecode('$buffer') as Map<String, dynamic>;
    expect(json['command'], 'buildkit :gitstatus');
    expect(json['root'], root);
    final repos = {
      for (final r in json['repositories'] as List)
        (r as Map<String, dynamic>)['path']: r,
    };
    expect(repos.keys.toSet(), {'.', 'core', 'xternal/fork', 'up'});
    expect(
      repos['core'],
      allOf(
        containsPair('branch', 'main'),
        containsPair('expectedBranch', 'main'),
        containsPair('expectedFrom', 'repos.yaml'),
        containsPair('compareWith', 'origin/main'),
        containsPair('ahead', 1),
        containsPair('behind', 1),
        containsPair('kind', 'code'),
      ),
    );
    expect(
      repos['xternal/fork'],
      allOf(
        containsPair('branch', 'feature'),
        containsPair('expectedBranch', 'tom/1.0-fixes'),
        containsPair('offBranch', true),
        containsPair('kind', 'fork'),
        containsPair('ahead', 0),
        containsPair('behind', 0),
      ),
    );
    expect(
      repos['up'],
      allOf(
        containsPair('kind', 'upstream'),
        containsPair('offPin', true),
        containsPair('ahead', null),
      ),
    );
    expect(
      repos['.'],
      allOf(
        containsPair('kind', 'root'),
        containsPair('detached', true),
        containsPair('expectedBranch', 'main'),
      ),
    );
    final codes = {
      for (final m in json['messages'] as List)
        '${(m as Map)['code']} ${(m['repository'] as Map)['path']}',
    };
    expect(codes, {
      'git-detached .',
      'git-off-branch xternal/fork',
      'git-off-pin up',
    });
    expect(json['exitCode'], 0, reason: 'warnings do not change the exit code');
  });

  test('BK-GSET-6: :gitstatus as text, and against the branch checked out '
      'without repos.yaml [2026-11-24]', () async {
    final buffer = StringBuffer();
    final r = await buildkit(
      [':gitstatus', '--no-fetch'],
      extra: {'gitstatus': GitStatusExecutor(out: buffer)},
    );
    expect(r.success, isTrue, reason: r.errorMessage);
    expect('$buffer', contains('  core: [main], even with origin/main, clean'));
    expect('$buffer', contains('  xternal/fork: [tom/1.0-fixes], even with'));
    expect('$buffer', contains('  up: [upstream at '));

    File(p.join(root, 'repos.yaml')).deleteSync();
    final plain = StringBuffer();
    final r2 = await buildkit(
      [':gitstatus', '--no-fetch', '--json'],
      extra: {'gitstatus': GitStatusExecutor(out: plain)},
    );
    expect(r2.success, isTrue, reason: r2.errorMessage);
    final repos = (jsonDecode('$plain') as Map)['repositories'] as List;
    final fork = repos.cast<Map>().firstWhere((r) => r['name'] == 'fork');
    expect(fork['expectedBranch'], 'tom/1.0-fixes');
    expect(fork['expectedFrom'], 'checked out');
    expect(fork['kind'], isNull);
  });

  test('BK-GSET-7: the help: :gitpush listed, :gitcommit names --only and '
      '--all, one topic per :gitstatus message [2026-11-24]', () async {
    expect(buildkitTool.findCommand('gitpush'), isNotNull);
    expect(buildkitTool.findCommand('gp')?.name, 'gitpush');
    final commit = buildkitTool.findCommand('gitcommit')!;
    expect(commit.options.map((o) => o.name), containsAll(['only', 'all']));
    expect(
      commit.options.firstWhere((o) => o.name == 'all').description,
      contains('nothing is staged'),
    );
    final status = buildkitTool.findCommand('gitstatus')!;
    expect(status.options.map((o) => o.name), contains('json'));
    final topics = buildkitTool.helpTopics.map((t) => t.name).toSet();
    expect(
      topics,
      containsAll([
        'git-detached',
        'git-off-branch',
        'git-off-pin',
        'git-no-remote-branch',
      ]),
    );
  });
}
