// BK-CLEAN: which changes make the workspace "dirty" for the integration
// protocol (`TestWorkspace.requireCleanWorkspace`).
//
// The protocol reverts files (`git checkout -- .` in the root AND in every
// first-level submodule) and checks that no HEAD moved; it never moves a
// submodule's HEAD. So a gitlink pointer that already differs from the
// superproject's recorded commit cannot be harmed by a run and must not block
// it; a modified or untracked file, in the root or inside a submodule, would be
// destroyed by the revert, and must.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

Future<void> _git(List<String> args, String dir) async {
  final r = await Process.run('git', args, workingDirectory: dir);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed in $dir: ${r.stderr}');
  }
}

Future<void> _initRepo(String dir) async {
  Directory(dir).createSync(recursive: true);
  await _git(['init', '-q', '-b', 'main'], dir);
  await _git(['config', 'user.email', 'test@example.com'], dir);
  await _git(['config', 'user.name', 'Test'], dir);
  await _git(['config', 'commit.gpgsign', 'false'], dir);
}

Future<void> _commitFile(String dir, String name, String content) async {
  File(p.join(dir, name)).writeAsStringSync(content);
  await _git(['add', name], dir);
  await _git(['commit', '-q', '-m', name], dir);
}

void main() {
  late Directory scratch;
  late String root;
  late String sub;

  setUp(() async {
    // Package-local scratch, never the system temp directory.
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync();
    scratch = base.createTempSync('bk_clean_');
    final upstream = p.join(scratch.path, 'upstream');
    await _initRepo(upstream);
    await _commitFile(upstream, 'a.txt', 'one');

    root = p.join(scratch.path, 'root');
    await _initRepo(root);
    await _commitFile(root, 'tracked.txt', 'base');
    await _git([
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      '-q',
      upstream,
      'child',
    ], root);
    await _git(['commit', '-q', '-m', 'add child'], root);
    sub = p.join(root, 'child');
    await _git(['config', 'user.email', 'test@example.com'], sub);
    await _git(['config', 'user.name', 'Test'], sub);
    await _git(['config', 'commit.gpgsign', 'false'], sub);
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  test('BK-CLEAN-1: a clean superproject has no uncommitted changes '
      '[2026-11-06]', () async {
    expect(await uncommittedChangesIn(root), isEmpty);
  });

  test('BK-CLEAN-2: a submodule whose HEAD moved on does not make it dirty '
      '[2026-11-06]', () async {
    await _commitFile(sub, 'b.txt', 'two');
    expect(await uncommittedChangesIn(root), isEmpty);
  });

  test('BK-CLEAN-3: a modified tracked file does [2026-11-06]', () async {
    File(p.join(root, 'tracked.txt')).writeAsStringSync('changed');
    expect(await uncommittedChangesIn(root), [contains('tracked.txt')]);
  });

  test('BK-CLEAN-4: an untracked file does [2026-11-06]', () async {
    File(p.join(root, 'new.txt')).writeAsStringSync('x');
    expect(await uncommittedChangesIn(root), [contains('new.txt')]);
  });

  test('BK-CLEAN-5: a modified file inside a submodule does — the tear-down '
      'reverts submodules too [2026-11-06]', () async {
    File(p.join(sub, 'a.txt')).writeAsStringSync('edited by another session');
    expect(await uncommittedChangesIn(root), [contains('child')]);
  });

  test('BK-CLEAN-6: an untracked file inside a submodule does '
      '[2026-11-06]', () async {
    File(p.join(sub, 'scratch.txt')).writeAsStringSync('x');
    expect(await uncommittedChangesIn(root), [contains('child')]);
  });

  group('a submodule with a submodule of its own', () {
    late String grandchild;

    setUp(() async {
      final deep = p.join(scratch.path, 'deep');
      await _initRepo(deep);
      await _commitFile(deep, 'd.txt', 'deep');
      await _git([
        '-c',
        'protocol.file.allow=always',
        'submodule',
        'add',
        '-q',
        deep,
        'grandchild',
      ], sub);
      await _git(['commit', '-q', '-m', 'add grandchild'], sub);
      await _git(['add', 'child'], root);
      await _git(['commit', '-q', '-m', 'move child'], root);
      grandchild = p.join(sub, 'grandchild');
      await _git(['config', 'user.email', 'test@example.com'], grandchild);
      await _git(['config', 'user.name', 'Test'], grandchild);
      await _git(['config', 'commit.gpgsign', 'false'], grandchild);
      expect(await uncommittedChangesIn(root), isEmpty);
    });

    test('BK-CLEAN-7: only its own submodule moved on: not dirty — the state '
        'of every superproject between pushes of its tree [2026-11-07]',
        () async {
      await _commitFile(grandchild, 'e.txt', 'moved on');
      expect(await uncommittedChangesIn(root), isEmpty);
    });

    test('BK-CLEAN-8: a modified file two levels down is dirty '
        '[2026-11-07]', () async {
      File(p.join(grandchild, 'd.txt')).writeAsStringSync('edited');
      expect(await uncommittedChangesIn(root), [contains('child')]);
    });
  });
}
