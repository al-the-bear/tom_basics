// BK-CLEAN: which changes make the workspace "dirty" for the integration
// protocol (`TestWorkspace.requireCleanWorkspace`).
//
// The protocol reverts files and checks that no HEAD moved; it never moves a
// submodule's HEAD. So a gitlink pointer that already differs from the
// superproject's recorded commit (the normal state of a superproject between
// pushes of its submodule tree) cannot be harmed by a run and must not block
// it. A modified tracked file can, and must.
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
    scratch = Directory.systemTemp.createTempSync('bk_clean_');
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
}
