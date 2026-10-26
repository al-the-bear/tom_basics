/// The in-memory file system keeps the contract the local one keeps: paths
/// and URIs map both ways, a write checks the revision it was given, a rename
/// carries a folder's contents, there is no trash, and the watch reports
/// every change made through it.
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:tom_file_system/tom_file_system.dart';

void main() {
  late TomMemoryFileSystem fs;
  setUp(
    () => fs = TomMemoryFileSystem(
      root: Uri.directory('/work/'),
      seed: {'/work/a/b.txt': 'b', '/work/c.txt': 'c'},
    ),
  );
  tearDown(() => fs.dispose());

  test('MEMFS-1: a root-relative path and its URI map both ways', () {
    final uri = fs.uriOf('a/b.txt');
    expect(uri, Uri.file('/work/a/b.txt'));
    expect(fs.pathOf(uri), 'a/b.txt');
    expect(fs.pathOf(fs.root), '');
    expect(
      fs.pathOf(Uri.parse('a/b.txt')),
      'a/b.txt',
      reason: 'a relative URI resolves against the root',
    );
  });

  test('MEMFS-2: list names the root\'s entries with their kinds', () async {
    final entries = await fs.list(fs.root);
    expect(
      {for (final e in entries) e.name: e.isDirectory},
      {'a': true, 'c.txt': false},
    );
    expect(entries.firstWhere((e) => e.name == 'a').path, 'a');
  });

  test('MEMFS-3: a write with a stale revision is a conflict and writes '
      'nothing', () async {
    final uri = fs.uriOf('c.txt');
    final first = (await fs.read(uri)).revision;
    final second = await fs.writeText(uri, 'c2');
    expect(second, isNot(first));
    await expectLater(
      fs.writeText(uri, 'mine', expected: first),
      throwsA(isA<TomFileConflict>()),
    );
    expect(await fs.readText(uri), 'c2');
    await fs.writeText(uri, 'mine', expected: second);
    expect(await fs.readText(uri), 'mine');
  });

  test('MEMFS-4: renaming a folder carries what is in it; a taken target is '
      'refused', () async {
    await fs.rename(fs.uriOf('a'), fs.uriOf('z'));
    expect(await fs.exists(fs.uriOf('a/b.txt')), isFalse);
    expect(await fs.readText(fs.uriOf('z/b.txt')), 'b');
    await expectLater(
      fs.rename(fs.uriOf('c.txt'), fs.uriOf('z')),
      throwsA(isA<TomFileSystemException>()),
    );
  });

  test('MEMFS-5: there is no trash; delete removes a folder with its '
      'contents', () async {
    expect(await fs.trash(fs.uriOf('c.txt')), isFalse);
    expect(await fs.exists(fs.uriOf('c.txt')), isTrue);
    await fs.delete(fs.uriOf('a'));
    expect(fs.paths, ['/work/c.txt']);
  });

  test('MEMFS-6: the watch reports a write, a create and a delete', () async {
    final changes = <String>[];
    final sub = fs.watch()!.listen((c) => changes.add(c.path));
    addTearDown(sub.cancel);
    await fs.writeText(fs.uriOf('c.txt'), 'x');
    await fs.create(fs.uriOf('new'), directory: true);
    await fs.delete(fs.uriOf('a/b.txt'));
    await Future<void>.delayed(Duration.zero);
    expect(changes, containsAllInOrder(['c.txt', 'new', 'a/b.txt']));
  });

  test('MEMFS-7: readSlice reads the end a log grows at', () async {
    await fs.writeText(fs.uriOf('log.md'), 'one\ntwo\nthree\n');
    final tail = await fs.readSlice(
      fs.uriOf('log.md'),
      maxBytes: 8,
      fromEnd: true,
    );
    expect(tail, endsWith('three\n'));
    expect(tail!.length, lessThanOrEqualTo(8));
  });
}
