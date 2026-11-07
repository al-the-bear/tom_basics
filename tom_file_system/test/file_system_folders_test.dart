/// Writing into a folder that does not exist yet and reading a file that may
/// not exist, on the memory and the local file system alike.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_file_system/io.dart';

void main() {
  late Directory scratch;
  setUp(() => scratch = Directory.systemTemp.createTempSync('tom_fs_folders'));
  tearDown(() => scratch.deleteSync(recursive: true));

  final systems = <String, TomFileSystem Function()>{
    'memory': () => TomMemoryFileSystem(),
    'local': () => TomLocalFileSystem(scratch.path),
  };

  for (final MapEntry(key: name, value: make) in systems.entries) {
    test('FSF-1 ($name): writeTextMakingFolder makes the missing folders; '
        'readTextIfExists answers null for a missing file', () async {
      final fs = make();
      final uri = fs.uriOf('a/b/c.yaml');
      expect(await fs.readTextIfExists(uri), isNull);
      await fs.writeTextMakingFolder(uri, 'one');
      expect(await fs.readTextIfExists(uri), 'one');
      expect(await fs.exists(fs.folderOf(uri)), isTrue);
      await fs.writeTextMakingFolder(uri, 'two');
      expect(await fs.readText(uri), 'two', reason: 'an existing folder');
      expect(fs.folderOf(uri), fs.uriOf('a/b/'));
    });
  }
}
