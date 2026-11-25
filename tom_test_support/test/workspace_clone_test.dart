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

import 'support/git_fixture.dart';

/// Every repository's `git status --porcelain` and HEAD, to compare a tree
/// before and after.
Future<Map<String, String>> _snapshot(String root) async {
  final out = <String, String>{};
  for (final rel in ['', 'pkgs/mid', 'pkgs/mid/nested/inner']) {
    final dir = p.join(root, rel);
    out[rel] =
        '${await head(dir)}\n${await git(dir, ['status', '--porcelain'])}';
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
    await initRepo(inner, 'git@example.com:al/inner.git');
    await commit(inner, 'lib/inner.dart', 'inner 1');

    final mid = p.join(upstream, 'mid');
    await initRepo(mid, 'git@example.com:al/mid.git');
    await commit(mid, 'pubspec.yaml', 'name: mid\n');
    await git(mid, ['submodule', 'add', '-q', inner, 'nested/inner']);
    await git(mid, ['commit', '-q', '-m', 'inner']);

    live = p.join(scratch.path, 'ws');
    await initRepo(live, 'git@example.com:al/ws.git');
    await commit(live, 'buildkit_master.yaml', 'master\n');
    await commit(live, '.gitignore', '.dart_tool/\n');
    await git(live, ['submodule', 'add', '-q', mid, 'pkgs/mid']);
    await git(live, ['commit', '-q', '-m', 'mid']);
    await git(live, ['submodule', 'update', '-q', '--init', '--recursive']);
    for (final rel in ['pkgs/mid', 'pkgs/mid/nested/inner']) {
      final dir = p.join(live, rel);
      await git(dir, ['config', 'user.email', 'wc@example.com']);
      await git(dir, ['config', 'user.name', 'WC']);
      await git(dir, ['config', 'commit.gpgsign', 'false']);
      await git(dir, ['checkout', '-q', 'main']);
      // As the real tree has it: origin is the hosted repository, not the
      // path the submodule was first cloned from.
      await git(dir, [
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
        await head(p.join(cloneDir.path, rel)),
        await head(p.join(live, rel)),
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
      final dotGit = p.join(cloneDir.path, rel, '.git');
      expect(FileSystemEntity.typeSync(dotGit), FileSystemEntityType.file);
      expect(File(dotGit).readAsStringSync(), startsWith('gitdir: ../'));
      expect(
        (await git(p.join(cloneDir.path, rel), [
          'branch',
          '--show-current',
        ])).trim(),
        'main',
      );
    }
    // origin as the live repository has it; pushing goes nowhere.
    final mid = p.join(cloneDir.path, 'pkgs/mid');
    expect(
      (await git(mid, ['remote', 'get-url', 'origin'])).trim(),
      'git@example.com:al/mid.git',
    );
    expect(
      (await git(mid, ['remote', 'get-url', '--push', 'origin'])).trim(),
      startsWith('disabled:'),
    );
    // The root's submodule bookkeeping is initialised.
    final status = await git(cloneDir.path, ['submodule', 'status']);
    expect(status, isNot(startsWith('-')));
  });

  test('WC-14: an update succeeds when a live gitlink names a submodule '
      'commit its origin never received [2026-11-12]', () async {
    // As on mbp on 2026-11-12: the superproject recorded a submodule commit
    // that was later dropped from the submodule and never pushed. git's
    // on-demand submodule fetch then asks the submodule's origin for it and
    // fails ('not our ref'), although the clone takes every submodule from its
    // own live repository anyway.
    final liveMid = p.join(live, 'pkgs/mid');
    final bare = p.join(scratch.path, 'bare', 'mid.git');
    Directory(bare).parent.createSync(recursive: true);
    await git(scratch.path, ['clone', '-q', '--bare', liveMid, bare]);
    await git(liveMid, ['remote', 'set-url', 'origin', bare]);
    await (await acquire()).release();

    await commit(liveMid, 'lib/dropped.dart', 'never pushed');
    await git(live, ['add', 'pkgs/mid']);
    await git(live, ['commit', '-q', '-m', 'bump mid']);
    await git(liveMid, ['reset', '-q', '--hard', 'HEAD~1']);
    await git(liveMid, ['reflog', 'expire', '--expire=now', '--all']);
    await git(liveMid, ['gc', '-q', '--prune=now']);

    final clone = await acquire();
    addTearDown(clone.release);
    expect(await head(cloneDir.path), await head(live));
    expect(await head(p.join(cloneDir.path, 'pkgs/mid')), await head(liveMid));
  });

  test('WC-2: an update follows the live commits, unpushed ones included, '
      'and takes no uncommitted edit [2026-11-07]', () async {
    await (await acquire()).release();

    final liveMid = p.join(live, 'pkgs/mid');
    await commit(liveMid, 'lib/new.dart', 'committed, never pushed');
    File(p.join(liveMid, 'pubspec.yaml')).writeAsStringSync('dirty\n');

    final clone = await acquire();
    addTearDown(clone.release);
    final cloneMid = p.join(cloneDir.path, 'pkgs/mid');
    expect(await head(cloneMid), await head(liveMid));
    expect(File(p.join(cloneMid, 'lib/new.dart')).existsSync(), isTrue);
    expect(
      File(p.join(cloneMid, 'pubspec.yaml')).readAsStringSync(),
      'name: mid\n',
    );
  });

  test('WC-3: a detached live repository is detached at the same commit in '
      'the clone [2026-11-07]', () async {
    final liveInner = p.join(live, 'pkgs/mid/nested/inner');
    final first = await head(liveInner);
    await commit(liveInner, 'lib/second.dart', '2');
    await git(liveInner, ['checkout', '-q', '--detach', first]);

    final clone = await acquire();
    addTearDown(clone.release);
    final cloneInner = p.join(cloneDir.path, 'pkgs/mid/nested/inner');
    expect(await head(cloneInner), first);
    expect((await git(cloneInner, ['branch', '--show-current'])).trim(), '');
  });

  test('WC-4: release resets every repository: tracked and untracked changes '
      'and commits go, ignored files stay [2026-11-07]', () async {
    final clone = await acquire();
    final root = cloneDir.path;
    final mid = p.join(root, 'pkgs/mid');
    final rootHead = await head(root);
    final midHead = await head(mid);

    File(p.join(root, 'buildkit_master.yaml')).writeAsStringSync('x');
    File(p.join(root, 'untracked.txt')).writeAsStringSync('x');
    File(p.join(root, '.dart_tool', 'kept.json'))
      ..parent.createSync()
      ..writeAsStringSync('resolution state');
    await git(mid, ['config', 'user.email', 'wc@example.com']);
    await git(mid, ['config', 'user.name', 'WC']);
    await git(mid, ['config', 'commit.gpgsign', 'false']);
    await commit(mid, 'lib/leak.dart', 'a commit a test made');
    File(p.join(mid, 'scratch.txt')).writeAsStringSync('x');

    await clone.release();

    expect(
      File(p.join(root, 'buildkit_master.yaml')).readAsStringSync(),
      'master\n',
    );
    expect(File(p.join(root, 'untracked.txt')).existsSync(), isFalse);
    expect(File(p.join(root, '.dart_tool', 'kept.json')).existsSync(), isTrue);
    expect(await head(root), rootHead);
    expect(await head(mid), midHead);
    expect(File(p.join(mid, 'lib/leak.dart')).existsSync(), isFalse);
    expect(File(p.join(mid, 'scratch.txt')).existsSync(), isFalse);
  });

  test(
    'WC-15: the clone carries tom_skip.yaml, kept out of its git status '
    'and through a reset; the live workspace has none [2026-11-20]',
    () async {
      final clone = await acquire();
      final root = cloneDir.path;
      final skip = File(p.join(root, tomWorkspaceCloneSkipFile));
      expect(skip.existsSync(), isTrue);
      expect(await git(root, ['status', '--porcelain']), isEmpty);
      await clone.release();
      expect(skip.existsSync(), isTrue);
      // Marking again changes nothing.
      tomMarkWorkspaceClone(Directory(root));
      final exclude = File(
        p.join(root, '.git', 'info', 'exclude'),
      ).readAsLinesSync();
      expect(exclude.where((l) => l == '/tom_skip.yaml'), hasLength(1));
      expect(
        File(p.join(live, tomWorkspaceCloneSkipFile)).existsSync(),
        isFalse,
      );
    },
  );

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
    await initRepo(extra, 'git@example.com:al/extra.git');
    await commit(extra, 'README.md', 'extra');
    await git(live, ['submodule', 'add', '-q', extra, 'pkgs/extra']);
    await git(live, ['commit', '-q', '-m', 'extra']);

    final clone = await acquire();
    addTearDown(clone.release);
    final cloneExtra = p.join(cloneDir.path, 'pkgs/extra');
    expect(await head(cloneExtra), await head(p.join(live, 'pkgs/extra')));
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

  test('WC-13: the live root is the directory with buildkit_master.yaml; '
      'the retired markers lower down mark nothing [2026-11-13]', () {
    final mid = Directory(p.join(live, 'pkgs/mid'));
    Directory(p.join(mid.path, '.tom_metadata')).createSync();
    File(
      p.join(mid.path, '.tom_metadata', 'workspace_state.yaml'),
    ).writeAsStringSync('state\n');
    File(p.join(mid.path, 'tom_workspace.yaml')).writeAsStringSync('');
    File(p.join(mid.path, 'tom.code-workspace')).writeAsStringSync('');
    expect(TomWorkspaceClone.findLiveRoot(from: mid)?.path, live);
  });

  test(
    'WC-14: release removes the leftover checkout of a submodule that '
    'is no longer recorded (an untracked nested repository) [2026-11-13]',
    () async {
      final clone = await acquire();
      final mid = p.join(cloneDir.path, 'pkgs/mid');
      // What a submodule removed upstream leaves behind in a checkout: a
      // repository of its own, now untracked in its parent.
      final leftover = Directory(p.join(mid, 'retired'))..createSync();
      await Process.run('git', ['init', '-q'], workingDirectory: leftover.path);
      File(p.join(leftover.path, 'lib.dart')).writeAsStringSync('x');

      await clone.release();

      expect(leftover.existsSync(), isFalse);
      expect(
        (await Process.run('git', [
          'status',
          '--porcelain',
        ], workingDirectory: mid)).stdout,
        isEmpty,
      );
    },
  );

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
