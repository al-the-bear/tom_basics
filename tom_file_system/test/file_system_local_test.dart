/// The local file system: listing, reading with a revision, atomic
/// revision-checked writes, create/rename/delete and link containment.
// Moving to the trash runs the platform's helper (osascript, gio,
// PowerShell); this file states no wait of its own, so the bound is the
// helper's.
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_file_system/io.dart';

import 'support/fixture_tree.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  late Directory root;
  late TomLocalFileSystem tree;

  setUp(() {
    root = writeFixtureTree();
    tree = TomLocalFileSystem(root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('FS-T1: list is one directory, with relative / paths '
      '[1011]', () async {
    final top = await tree.list(tree.uriOf(''));
    expect(
      top.map((e) => e.name),
      containsAll(['alpha', 'beta', '.gitignore']),
    );
    expect(top.map((e) => e.path), isNot(contains('alpha/overview.alpha.md')));
    final alpha = await tree.list(tree.uriOf('alpha'));
    expect(alpha.map((e) => e.path), contains('alpha/overview.alpha.md'));
    final history = alpha.firstWhere((e) => e.name == 'history');
    expect(history.isDirectory, isTrue);
    expect(history.expandable, isTrue);
  });

  test('FS-T2: read answers the bytes and a revision; stat reads '
      'nothing [1011]', () async {
    final content = await tree.read(tree.uriOf('README.md'));
    expect(utf8.decode(content.bytes), '# Fixture\n');
    expect(content.revision.size, content.bytes.length);
    expect(content.revision.sha256, hasLength(64));
    final stat = await tree.stat(tree.uriOf('README.md'));
    expect(stat!.size, content.bytes.length);
    expect(await tree.stat(tree.uriOf('nope.md')), isNull);
  });

  test('FS-T3: a write is atomic and leaves no temporary file; '
      'checked against the revision read, a changed file is refused '
      '[1011]', () async {
    final first = await tree.read(tree.uriOf('README.md'));
    final written = await tree.write(
      tree.uriOf('README.md'),
      _bytes('one'),
      expected: first.revision,
    );
    expect(File(p.join(root.path, 'README.md')).readAsStringSync(), 'one');
    expect(
      root.listSync().where((e) => p.basename(e.path).endsWith('.tmp')),
      isEmpty,
    );
    // Someone else changes it; the stale revision is refused.
    File(p.join(root.path, 'README.md')).writeAsStringSync('two');
    await expectLater(
      tree.write(tree.uriOf('README.md'), _bytes('three'), expected: written),
      throwsA(isA<TomFileConflict>()),
    );
    expect(File(p.join(root.path, 'README.md')).readAsStringSync(), 'two');
  });

  test('FS-T4: a write against a deleted file is a conflict with no '
      'current revision [1011]', () async {
    final read = await tree.read(tree.uriOf('alpha/notes.txt'));
    File(p.join(root.path, 'alpha', 'notes.txt')).deleteSync();
    await expectLater(
      tree.write(
        tree.uriOf('alpha/notes.txt'),
        _bytes('x'),
        expected: read.revision,
      ),
      throwsA(
        isA<TomFileConflict>().having((c) => c.current, 'current', isNull),
      ),
    );
  });

  test('FS-T5: create, rename and delete-permanently; rename never '
      'overwrites [1011]', () async {
    await tree.create(tree.uriOf('beta/new.md'));
    await tree.create(tree.uriOf('beta/sub'), directory: true);
    expect(await tree.exists(tree.uriOf('beta/new.md')), isTrue);
    expect(await tree.exists(tree.uriOf('beta/sub')), isTrue);
    await tree.rename(tree.uriOf('beta/new.md'), tree.uriOf('beta/renamed.md'));
    expect(await tree.exists(tree.uriOf('beta/renamed.md')), isTrue);
    await expectLater(
      tree.rename(
        tree.uriOf('beta/renamed.md'),
        tree.uriOf('beta/script.dart'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    await tree.delete(tree.uriOf('beta/sub'));
    expect(await tree.exists(tree.uriOf('beta/sub')), isFalse);
  });

  test('FS-T6: a link out of the root, or back into its own '
      'ancestors, is listed and never expandable [1011]', () async {
    if (Platform.isWindows) {
      markTestSkipped('symbolic links need privileges on Windows');
      return;
    }
    final outside = Directory.systemTemp.createTempSync('tom_fs_out');
    addTearDown(() => outside.deleteSync(recursive: true));
    Link(p.join(root.path, 'out')).createSync(outside.path);
    Link(p.join(root.path, 'alpha', 'loop')).createSync(root.path);
    Link(p.join(root.path, 'inside')).createSync(p.join(root.path, 'beta'));
    final top = await tree.list(tree.uriOf(''));
    final out = top.firstWhere((e) => e.name == 'out');
    expect(out.kind, TomFileEntryKind.link);
    expect(out.expandable, isFalse);
    final inside = top.firstWhere((e) => e.name == 'inside');
    expect(inside.expandable, isTrue);
    final loop = (await tree.list(
      tree.uriOf('alpha'),
    )).firstWhere((e) => e.name == 'loop');
    expect(loop.expandable, isFalse);
  });
}
