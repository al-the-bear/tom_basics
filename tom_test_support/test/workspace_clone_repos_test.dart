// WC-R: the workspace clone of a tree of independent clones listed in
// `repos.yaml` (workspace_clone.dart), as the real tree is laid out since it
// left submodules: each nested repository is a clone of its own, ignored by
// its parent, and `repos.yaml` sits in a folder above the live workspace.
//
// Each test builds the tree under this package's .dart_tool/:
//
//   top/                    the root (repos.yaml)
//     other/                an entry outside the live workspace: not cloned
//     container/            the live workspace (buildkit_master.yaml), an entry
//       pkgs/a/             an entry, on branch dev
//         inner/            an entry inside an entry
//       tools/b/            an entry its parent does not ignore
//       up/                 kind upstream: skipped
//       um/                 under unmanaged: skipped
//       unk/                a clone that is no entry: skipped
//
// and the clone beside `top/`.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/workspace_clone.dart';

import 'support/git_fixture.dart';

void main() {
  late Directory scratch;
  late String live;
  late Directory cloneDir;

  String livePath(String rel) => p.join(live, rel);
  String clonePath(String rel) => p.join(cloneDir.path, rel);

  setUp(() async {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync();
    scratch = base.createTempSync('workspace_clone_repos_test_');
    final top = p.join(scratch.path, 'top');
    live = p.join(top, 'container');

    await initRepo(top, 'git@example.com:al/top.git');
    await commit(top, '.gitignore', '/container/\n/other/\n');
    final upSha = 'a' * 40;
    await commit(
      top,
      'repos.yaml',
      'version: 1\n'
          'root: {url: git@example.com:al/top.git, branch: main}\n'
          'repos:\n'
          '  - {path: container, url: git@example.com:al/container.git, '
          'kind: code, branch: main}\n'
          '  - {path: container/pkgs/a, url: git@example.com:al/a.git, '
          'kind: code, branch: dev}\n'
          '  - {path: container/pkgs/a/inner, url: git@example.com:al/inner.git, '
          'kind: fork, branch: main}\n'
          '  - {path: container/tools/b, url: git@example.com:al/b.git, '
          'kind: code, branch: main}\n'
          '  - {path: container/up, url: git@example.com:al/up.git, '
          'kind: upstream, pin: $upSha}\n'
          '  - {path: other, url: git@example.com:al/other.git, '
          'kind: code, branch: main}\n'
          'unmanaged:\n'
          '  - {path: container/um}\n',
    );

    await initRepo(live, 'git@example.com:al/container.git');
    await commit(live, 'buildkit_master.yaml', 'master\n');
    await commit(
      live,
      '.gitignore',
      '/pkgs/a/\n/up/\n/um/\n/unk/\n.dart_tool/\n',
    );

    final a = livePath('pkgs/a');
    await initRepo(a, 'git@example.com:al/a.git');
    await commit(a, '.gitignore', '/inner/\n');
    await git(a, ['checkout', '-q', '-b', 'dev']);
    await commit(a, 'lib/a.dart', 'a 1');

    final inner = livePath('pkgs/a/inner');
    await initRepo(inner, 'git@example.com:al/inner.git');
    await commit(inner, 'lib/inner.dart', 'inner 1');

    await initRepo(livePath('tools/b'), 'git@example.com:al/b.git');
    await commit(livePath('tools/b'), 'lib/b.dart', 'b 1');

    for (final rel in ['up', 'um', 'unk']) {
      await initRepo(livePath(rel), 'git@example.com:al/$rel.git');
      await commit(livePath(rel), 'README.md', rel);
    }
    await initRepo(p.join(top, 'other'), 'git@example.com:al/other.git');
    await commit(p.join(top, 'other'), 'README.md', 'other');

    cloneDir = Directory(p.join(scratch.path, 'container_testclone'));
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  Future<TomWorkspaceClone> acquire() => TomWorkspaceClone.acquire(
    liveRoot: Directory(live),
    cloneRoot: cloneDir,
    lockTimeout: const Duration(minutes: 1),
    log: (_) {},
  );

  test('WC-R1: every entry of the git set below the live workspace is an '
      'independent clone at its path, at the live commit and branch, origin '
      'as live, pushing disabled [2026-11-25]', () async {
    final clone = await acquire();
    addTearDown(clone.release);

    for (final rel in ['', 'pkgs/a', 'pkgs/a/inner', 'tools/b']) {
      expect(
        await head(clonePath(rel)),
        await head(livePath(rel)),
        reason: rel,
      );
      expect(
        (await git(clonePath(rel), ['branch', '--show-current'])).trim(),
        (await git(livePath(rel), ['branch', '--show-current'])).trim(),
        reason: rel,
      );
      expect(
        (await git(clonePath(rel), ['remote', 'get-url', 'origin'])).trim(),
        (await git(livePath(rel), ['remote', 'get-url', 'origin'])).trim(),
        reason: rel,
      );
      expect(
        (await git(clonePath(rel), [
          'remote',
          'get-url',
          '--push',
          'origin',
        ])).trim(),
        startsWith('disabled:'),
        reason: rel,
      );
    }
    // A clone of its own: `.git` is a directory, not a submodule's file.
    for (final rel in ['pkgs/a', 'pkgs/a/inner', 'tools/b']) {
      expect(
        FileSystemEntity.typeSync(p.join(clonePath(rel), '.git')),
        FileSystemEntityType.directory,
        reason: rel,
      );
    }
    expect(File(clonePath('pkgs/a/lib/a.dart')).readAsStringSync(), 'a 1');
    expect(
      File(clonePath('pkgs/a/inner/lib/inner.dart')).readAsStringSync(),
      'inner 1',
    );
    // Upstreams, unmanaged and unknown clones are left out, and so is
    // everything outside the live workspace.
    for (final rel in ['up', 'um', 'unk']) {
      expect(Directory(clonePath(rel)).existsSync(), isFalse, reason: rel);
    }
    expect(Directory(p.join(scratch.path, 'other')).existsSync(), isFalse);
  });

  test('WC-R2: uncommitted live edits are not carried; unpushed commits are '
      '[2026-11-25]', () async {
    File(livePath('pkgs/a/lib/a.dart')).writeAsStringSync('edited');
    File(livePath('pkgs/a/new.txt')).writeAsStringSync('untracked');
    await commit(livePath('pkgs/a/inner'), 'lib/inner.dart', 'inner 2');

    final clone = await acquire();
    addTearDown(clone.release);

    expect(File(clonePath('pkgs/a/lib/a.dart')).readAsStringSync(), 'a 1');
    expect(File(clonePath('pkgs/a/new.txt')).existsSync(), isFalse);
    expect(
      File(clonePath('pkgs/a/inner/lib/inner.dart')).readAsStringSync(),
      'inner 2',
    );
    expect(
      await git(livePath('pkgs/a'), ['status', '--porcelain']),
      isNotEmpty,
      reason: 'the live edits stay where they are',
    );
  });

  test('WC-R3: release resets each repository and keeps the nested clones; '
      'the next acquire follows new live commits [2026-11-25]', () async {
    var clone = await acquire();
    File(clonePath('pkgs/a/lib/a.dart')).writeAsStringSync('dirty');
    File(clonePath('stray.txt')).writeAsStringSync('stray');
    await clone.release();

    expect(File(clonePath('pkgs/a/lib/a.dart')).readAsStringSync(), 'a 1');
    expect(File(clonePath('stray.txt')).existsSync(), isFalse);
    // The parents' clean leaves their nested clones alone, ignored by the
    // parent or not.
    expect(File(clonePath('tools/b/lib/b.dart')).existsSync(), isTrue);
    expect(File(clonePath('pkgs/a/inner/lib/inner.dart')).existsSync(), isTrue);

    await commit(livePath('pkgs/a'), 'lib/a.dart', 'a 2');
    clone = await acquire();
    addTearDown(clone.release);
    expect(File(clonePath('pkgs/a/lib/a.dart')).readAsStringSync(), 'a 2');
    expect(await head(clonePath('pkgs/a')), await head(livePath('pkgs/a')));
  });
}
