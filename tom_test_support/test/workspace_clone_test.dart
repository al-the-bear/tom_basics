// WC: the workspace clone the build-tool suites run on (workspace_clone.dart).
//
// Each test builds a small live workspace — a superproject with a submodule
// that has a submodule of its own, as the real tree nests them — under this
// package's .dart_tool/, and a clone beside it.
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/workspace_clone.dart';

Future<String> _git(String dir, List<String> args) async {
  final r = await Process.run('git', [
    '-c',
    'protocol.file.allow=always',
    ...args,
  ], workingDirectory: dir);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} in $dir: ${r.stderr}');
  }
  return r.stdout.toString();
}

Future<void> _initRepo(String dir, String origin) async {
  Directory(dir).createSync(recursive: true);
  await _git(dir, ['init', '-q', '-b', 'main']);
  await _git(dir, ['config', 'user.email', 'wc@example.com']);
  await _git(dir, ['config', 'user.name', 'WC']);
  await _git(dir, ['config', 'commit.gpgsign', 'false']);
  await _git(dir, ['remote', 'add', 'origin', origin]);
}

Future<void> _commit(String dir, String file, String content) async {
  final f = File(p.join(dir, file))..parent.createSync(recursive: true);
  f.writeAsStringSync(content);
  await _git(dir, ['add', file]);
  await _git(dir, ['commit', '-q', '-m', file]);
}

Future<String> _head(String dir) async =>
    (await _git(dir, ['rev-parse', 'HEAD'])).trim();

/// Every repository's `git status --porcelain` and HEAD, to compare a tree
/// before and after.
Future<Map<String, String>> _snapshot(String root) async {
  final out = <String, String>{};
  for (final rel in ['', 'pkgs/mid', 'pkgs/mid/nested/inner']) {
    final dir = p.join(root, rel);
    out[rel] =
        '${await _head(dir)}\n${await _git(dir, ['status', '--porcelain'])}';
  }
  return out;
}

void main() {
  late Directory scratch;
  late String live;
  late Directory cloneDir;

  setUp(() async {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync();
    scratch = base.createTempSync('workspace_clone_test_');
    final upstream = p.join(scratch.path, 'upstream');

    final inner = p.join(upstream, 'inner');
    await _initRepo(inner, 'git@example.com:al/inner.git');
    await _commit(inner, 'lib/inner.dart', 'inner 1');

    final mid = p.join(upstream, 'mid');
    await _initRepo(mid, 'git@example.com:al/mid.git');
    await _commit(mid, 'pubspec.yaml', 'name: mid\n');
    await _git(mid, ['submodule', 'add', '-q', inner, 'nested/inner']);
    await _git(mid, ['commit', '-q', '-m', 'inner']);

    live = p.join(scratch.path, 'ws');
    await _initRepo(live, 'git@example.com:al/ws.git');
    await _commit(live, '.tom_metadata/tom_master.yaml', 'master\n');
    await _commit(live, 'tom_workspace.yaml', 'name: ws\n');
    await _commit(live, '.gitignore', '.dart_tool/\n');
    await _git(live, ['submodule', 'add', '-q', mid, 'pkgs/mid']);
    await _git(live, ['commit', '-q', '-m', 'mid']);
    await _git(live, ['submodule', 'update', '-q', '--init', '--recursive']);
    for (final rel in ['pkgs/mid', 'pkgs/mid/nested/inner']) {
      final dir = p.join(live, rel);
      await _git(dir, ['config', 'user.email', 'wc@example.com']);
      await _git(dir, ['config', 'user.name', 'WC']);
      await _git(dir, ['config', 'commit.gpgsign', 'false']);
      await _git(dir, ['checkout', '-q', 'main']);
      // As the real tree has it: origin is the hosted repository, not the
      // path the submodule was first cloned from.
      await _git(dir, [
        'remote',
        'set-url',
        'origin',
        'git@example.com:al/${p.basename(rel)}.git',
      ]);
    }
    cloneDir = Directory(p.join(scratch.path, 'ws_testclone'));
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  Future<TomWorkspaceClone> acquire({Duration? lockTimeout}) =>
      TomWorkspaceClone.acquire(
        liveRoot: Directory(live),
        cloneRoot: cloneDir,
        lockTimeout: lockTimeout ?? const Duration(minutes: 1),
        log: (_) {},
      );

  test('WC-1: the clone is created on first use, laid out like the live '
      'workspace [2026-11-07]', () async {
    expect(cloneDir.existsSync(), isFalse);
    final clone = await acquire();
    addTearDown(clone.release);

    expect(clone.root.path, cloneDir.path);
    expect(tomIsWorkspaceClone(cloneDir), isTrue);
    for (final rel in ['', 'pkgs/mid', 'pkgs/mid/nested/inner']) {
      expect(
        await _head(p.join(cloneDir.path, rel)),
        await _head(p.join(live, rel)),
        reason: '$rel is at the live commit',
      );
    }
    expect(
      File(
        p.join(cloneDir.path, 'pkgs/mid/nested/inner/lib/inner.dart'),
      ).readAsStringSync(),
      'inner 1',
    );
    // Submodules are `.git` files into the parent's modules, as in the live
    // tree, and on the live branch.
    for (final rel in ['pkgs/mid', 'pkgs/mid/nested/inner']) {
      final git = p.join(cloneDir.path, rel, '.git');
      expect(FileSystemEntity.typeSync(git), FileSystemEntityType.file);
      expect(File(git).readAsStringSync(), startsWith('gitdir: ../'));
      expect(
        (await _git(p.join(cloneDir.path, rel), [
          'branch',
          '--show-current',
        ])).trim(),
        'main',
      );
    }
    // origin as the live repository has it; pushing goes nowhere.
    final mid = p.join(cloneDir.path, 'pkgs/mid');
    expect(
      (await _git(mid, ['remote', 'get-url', 'origin'])).trim(),
      'git@example.com:al/mid.git',
    );
    expect(
      (await _git(mid, ['remote', 'get-url', '--push', 'origin'])).trim(),
      startsWith('disabled:'),
    );
    // The root's submodule bookkeeping is initialised.
    final status = await _git(cloneDir.path, ['submodule', 'status']);
    expect(status, isNot(startsWith('-')));
  });

  test('WC-2: an update follows the live commits, unpushed ones included, '
      'and takes no uncommitted edit [2026-11-07]', () async {
    await (await acquire()).release();

    final liveMid = p.join(live, 'pkgs/mid');
    await _commit(liveMid, 'lib/new.dart', 'committed, never pushed');
    File(p.join(liveMid, 'pubspec.yaml')).writeAsStringSync('dirty\n');

    final clone = await acquire();
    addTearDown(clone.release);
    final cloneMid = p.join(cloneDir.path, 'pkgs/mid');
    expect(await _head(cloneMid), await _head(liveMid));
    expect(File(p.join(cloneMid, 'lib/new.dart')).existsSync(), isTrue);
    expect(
      File(p.join(cloneMid, 'pubspec.yaml')).readAsStringSync(),
      'name: mid\n',
    );
  });

  test('WC-3: a detached live repository is detached at the same commit in '
      'the clone [2026-11-07]', () async {
    final liveInner = p.join(live, 'pkgs/mid/nested/inner');
    final first = await _head(liveInner);
    await _commit(liveInner, 'lib/second.dart', '2');
    await _git(liveInner, ['checkout', '-q', '--detach', first]);

    final clone = await acquire();
    addTearDown(clone.release);
    final cloneInner = p.join(cloneDir.path, 'pkgs/mid/nested/inner');
    expect(await _head(cloneInner), first);
    expect((await _git(cloneInner, ['branch', '--show-current'])).trim(), '');
  });

  test('WC-4: release resets every repository: tracked and untracked changes '
      'and commits go, ignored files stay [2026-11-07]', () async {
    final clone = await acquire();
    final root = cloneDir.path;
    final mid = p.join(root, 'pkgs/mid');
    final rootHead = await _head(root);
    final midHead = await _head(mid);

    File(p.join(root, '.tom_metadata/tom_master.yaml')).writeAsStringSync('x');
    File(p.join(root, 'untracked.txt')).writeAsStringSync('x');
    File(p.join(root, '.dart_tool', 'kept.json'))
      ..parent.createSync()
      ..writeAsStringSync('resolution state');
    await _git(mid, ['config', 'user.email', 'wc@example.com']);
    await _git(mid, ['config', 'user.name', 'WC']);
    await _git(mid, ['config', 'commit.gpgsign', 'false']);
    await _commit(mid, 'lib/leak.dart', 'a commit a test made');
    File(p.join(mid, 'scratch.txt')).writeAsStringSync('x');

    await clone.release();

    expect(
      File(p.join(root, '.tom_metadata/tom_master.yaml')).readAsStringSync(),
      'master\n',
    );
    expect(File(p.join(root, 'untracked.txt')).existsSync(), isFalse);
    expect(File(p.join(root, '.dart_tool', 'kept.json')).existsSync(), isTrue);
    expect(await _head(root), rootHead);
    expect(await _head(mid), midHead);
    expect(File(p.join(mid, 'lib/leak.dart')).existsSync(), isFalse);
    expect(File(p.join(mid, 'scratch.txt')).existsSync(), isFalse);
  });

  test('WC-5: nothing in the live workspace changes [2026-11-07]', () async {
    File(p.join(live, 'pkgs/mid/pubspec.yaml')).writeAsStringSync('edited\n');
    File(p.join(live, 'notes.txt')).writeAsStringSync('another session');
    final before = await _snapshot(live);

    final clone = await acquire();
    File(p.join(cloneDir.path, 'pkgs/mid/pubspec.yaml')).writeAsStringSync('t');
    await clone.release();
    await (await acquire()).release();

    expect(await _snapshot(live), before);
  });

  test('WC-6: a submodule added to the live workspace appears in the clone '
      '[2026-11-07]', () async {
    await (await acquire()).release();

    final extra = p.join(scratch.path, 'upstream', 'extra');
    await _initRepo(extra, 'git@example.com:al/extra.git');
    await _commit(extra, 'README.md', 'extra');
    await _git(live, ['submodule', 'add', '-q', extra, 'pkgs/extra']);
    await _git(live, ['commit', '-q', '-m', 'extra']);

    final clone = await acquire();
    addTearDown(clone.release);
    final cloneExtra = p.join(cloneDir.path, 'pkgs/extra');
    expect(await _head(cloneExtra), await _head(p.join(live, 'pkgs/extra')));
    expect(
      FileSystemEntity.typeSync(p.join(cloneExtra, '.git')),
      FileSystemEntityType.file,
    );
  });

  test('WC-7: an existing directory that is not a clone is refused and left '
      'alone [2026-11-07]', () async {
    cloneDir.createSync();
    final keep = File(p.join(cloneDir.path, 'keep.txt'))
      ..writeAsStringSync('k');

    await expectLater(acquire(), throwsStateError);
    expect(keep.readAsStringSync(), 'k');
    expect(File('${cloneDir.path}.lock').existsSync(), isFalse);
  });

  test('WC-8: a clone location overlapping the live workspace is refused '
      '[2026-11-07]', () async {
    await expectLater(
      TomWorkspaceClone.acquire(
        liveRoot: Directory(live),
        cloneRoot: Directory(p.join(live, 'ztmp', 'clone')),
        log: (_) {},
      ),
      throwsStateError,
    );
  });

  test('WC-9: one run at a time — a second waits, then times out naming the '
      'holder [2026-11-07]', () async {
    final clone = await acquire();
    await expectLater(
      acquire(lockTimeout: const Duration(seconds: 3)),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('$pid')),
      ),
    );
    await clone.release();
    await (await acquire()).release();
  });

  test('WC-10: a lock left by a process that is gone is taken over '
      '[2026-11-07]', () async {
    await (await acquire()).release();
    File('${cloneDir.path}.lock').writeAsStringSync(
      jsonEncode({'pid': 999999, 'started': 'then', 'cwd': '/gone'}),
    );
    final clone = await acquire(lockTimeout: const Duration(seconds: 5));
    await clone.release();
    expect(File('${cloneDir.path}.lock').existsSync(), isFalse);
  });

  test('WC-11: tomRequireWorkspaceClone refuses the live tree and accepts '
      'the clone [2026-11-07]', () async {
    final clone = await acquire();
    addTearDown(clone.release);
    expect(() => tomRequireWorkspaceClone(Directory(live)), throwsStateError);
    tomRequireWorkspaceClone(Directory(p.join(cloneDir.path, 'pkgs/mid')));
  });

  test('WC-13: the live root is the directory with .tom_metadata/ AND '
      'tom_workspace.yaml, not a stray .tom_metadata/ a tool left lower down '
      '[2026-11-07]', () {
    final mid = Directory(p.join(live, 'pkgs/mid'));
    Directory(p.join(mid.path, '.tom_metadata')).createSync();
    File(
      p.join(mid.path, '.tom_metadata', 'workspace_state.yaml'),
    ).writeAsStringSync('state\n');
    expect(TomWorkspaceClone.findLiveRoot(from: mid)?.path, live);
  });

  test('WC-12: the default location is a sibling named <name>_testclone, '
      'unless TOM_TEST_WORKSPACE says otherwise [2026-11-07]', () {
    final env = Platform.environment[tomTestWorkspaceEnv];
    final where = TomWorkspaceClone.locationFor(Directory(live));
    if (env == null || env.trim().isEmpty) {
      expect(where.path, p.join(scratch.path, 'ws_testclone'));
    } else {
      expect(where.path, p.normalize(p.absolute(env.trim())));
    }
  });
}
