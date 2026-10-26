/// The contract's values — change and save events — and the in-memory file
/// system, as an application sees them.
library;

import 'package:test/test.dart';
import 'package:tom_file_system/tom_file_system.dart';

void main() {
  group('TomFileChangeType', () {
    test('values', () {
      expect(
        TomFileChangeType.values,
        containsAll([
          TomFileChangeType.created,
          TomFileChangeType.modified,
          TomFileChangeType.deleted,
        ]),
      );
    });
  });

  group('TomSaveReason', () {
    test('values', () {
      expect(
        TomSaveReason.values,
        containsAll([
          TomSaveReason.manual,
          TomSaveReason.autoSave,
          TomSaveReason.focusLoss,
        ]),
      );
    });
  });

  group('TomFileChangeEvent', () {
    test('construction', () {
      final event = TomFileChangeEvent(
        uri: Uri.parse('file:///src/main.dart'),
        type: TomFileChangeType.modified,
      );
      expect(event.type, TomFileChangeType.modified);
      expect(event.uri.path, '/src/main.dart');
    });
  });

  group('TomWillSaveEvent', () {
    test('construction and mutation', () {
      final event = TomWillSaveEvent(
        uri: Uri.parse('file:///test.txt'),
        content: 'hello',
        reason: TomSaveReason.manual,
      );
      expect(event.content, 'hello');
      event.content = 'modified';
      expect(event.content, 'modified');
    });
  });

  group('TomMemoryFileSystem', () {
    late TomMemoryFileSystem fs;

    setUp(() {
      fs = TomMemoryFileSystem(seed: {'/test.txt': 'hello world'});
    });

    test('read seeded file', () async {
      final content = await fs.readText(Uri.parse('file:///test.txt'));
      expect(content, 'hello world');
    });

    test('read missing file throws', () {
      expect(
        () => fs.read(Uri.parse('file:///missing.txt')),
        throwsA(isA<TomFileSystemException>()),
      );
    });

    test('read answers the bytes and the revision', () async {
      final content = await fs.read(Uri.parse('file:///test.txt'));
      expect(content.bytes, isNotEmpty);
      expect(content.revision.size, content.bytes.length);
    });

    test('write creates new file', () async {
      await fs.writeText(Uri.parse('file:///new.txt'), 'content');
      final content = await fs.readText(Uri.parse('file:///new.txt'));
      expect(content, 'content');
    });

    test('write emits created event for new file', () async {
      final future = fs.onDidChange.first;
      await fs.writeText(Uri.parse('file:///brand_new.txt'), 'data');
      final event = await future;
      expect(event.type, TomFileChangeType.created);
    });

    test('write emits modified event for existing file', () async {
      final future = fs.onDidChange.first;
      await fs.writeText(Uri.parse('file:///test.txt'), 'updated');
      final event = await future;
      expect(event.type, TomFileChangeType.modified);
    });

    test('delete removes file', () async {
      await fs.delete(Uri.parse('file:///test.txt'));
      expect(await fs.exists(Uri.parse('file:///test.txt')), isFalse);
    });

    test('delete emits event', () async {
      final future = fs.onDidChange.first;
      await fs.delete(Uri.parse('file:///test.txt'));
      final event = await future;
      expect(event.type, TomFileChangeType.deleted);
    });

    test('exists returns true for seeded file', () async {
      expect(await fs.exists(Uri.parse('file:///test.txt')), isTrue);
    });

    test('exists returns false for missing file', () async {
      expect(await fs.exists(Uri.parse('file:///nope.txt')), isFalse);
    });

    test('stat returns size', () async {
      final stat = await fs.stat(Uri.parse('file:///test.txt'));
      expect(stat!.size, greaterThan(0));
    });

    test('list returns directory content', () async {
      fs = TomMemoryFileSystem(
        seed: {'/dir/a.txt': 'a', '/dir/b.txt': 'b', '/dir/sub/c.txt': 'c'},
      );
      final entries = await fs.list(Uri.parse('file:///dir'));
      expect(entries.length, greaterThanOrEqualTo(2));
    });

    test('list names a folder once, as a folder', () async {
      fs = TomMemoryFileSystem(
        seed: {'/dir/a.txt': 'a', '/dir/sub/b.txt': 'b'},
      );
      final entries = await fs.list(Uri.parse('file:///dir'));
      expect(
        {for (final e in entries) e.name: e.isDirectory},
        {'a.txt': false, 'sub': true},
      );
      expect(entries.firstWhere((e) => e.name == 'sub').path, 'dir/sub');
    });

    test('save triggers onWillSave and onDidSave', () async {
      final willSaveFuture = fs.onWillSave.first;
      final didSaveFuture = fs.onDidSave.first;

      await fs.save(Uri.parse('file:///test.txt'));

      final willSave = await willSaveFuture;
      final didSave = await didSaveFuture;
      expect(willSave.reason, TomSaveReason.manual);
      expect(didSave.path, '/test.txt');
    });

    test('paths returns all file paths', () {
      expect(fs.paths, contains('/test.txt'));
    });

    test('dispose closes streams', () async {
      await fs.dispose();
    });
  });
}
