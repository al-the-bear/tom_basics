import 'package:tom_file_system/tom_file_system.dart';

Future<void> main() async {
  final fs = TomMemoryFileSystem(seed: {'/notes.txt': 'first line\n'});
  final read = await fs.read(fs.uriOf('notes.txt'));
  // Refused with a TomFileConflict if somebody changed the file since.
  await fs.writeText(
    fs.uriOf('notes.txt'),
    'second line\n',
    expected: read.revision,
  );
  print(await fs.readText(fs.uriOf('notes.txt')));
}
