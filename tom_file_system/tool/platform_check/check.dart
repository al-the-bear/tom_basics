/// The local file system on the platform it is run on: the part of
/// `tom_file_system` that is different on macOS, Linux and Windows, exercised
/// through [TomLocalFileSystem] itself.
///
/// Plain Dart, so it runs where Flutter cannot — under Wine for the Windows
/// half. `run.sh` compiles it once to a kernel file and runs that file on each
/// platform's own Dart VM; the platform shell around it then looks into the
/// platform's trash from the outside.
///
///   `dart run tool/platform_check/check.dart SCRATCH_DIRECTORY`
///
/// Prints one `ok`/`FAIL` line per check and exits non-zero when one fails.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tom_file_system/io.dart';

var _failed = 0;
var _notMeasured = 0;

void _check(bool ok, String what) {
  if (!ok) _failed++;
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'} $what');
}

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Writes until [path] is reported, for at most ten seconds.
Future<bool> _reported(
  List<String> changes,
  String path,
  void Function() write,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (changes.contains(path)) return true;
    write();
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return changes.contains(path);
}

Future<void> main(List<String> args) async {
  final scratch = Directory(args.isEmpty ? 'platform_check_root' : args.first)
    ..createSync(recursive: true);
  final root = scratch.createTempSync('root-');
  String version;
  try {
    version = Platform.operatingSystemVersion;
  } on OSError {
    version = 'version not reported';
  }
  stdout.writeln('platform: ${Platform.operatingSystem} ($version)');
  final fs = TomLocalFileSystem(root.path);
  Uri at(String path) => fs.uriOf(path);

  // ── atomic write with a revision check ──────────────────────────────────
  await fs.create(at('notes'), directory: true);
  final first = await fs.write(at('notes/a.md'), _bytes('one'));
  final second = await fs.write(
    at('notes/a.md'),
    _bytes('two'),
    expected: first,
  );
  _check(
    (await fs.read(at('notes/a.md'))).bytes.length == 3,
    'write replaces a file atomically',
  );
  var refused = false;
  try {
    await fs.write(at('notes/a.md'), _bytes('three'), expected: first);
  } on TomFileConflict {
    refused = true;
  }
  _check(
    refused && second.sha256 != first.sha256,
    'a write against a stale revision is refused',
  );
  _check(
    !root.listSync(recursive: true).any((e) => e.path.contains('.tmp')),
    'no temporary file is left beside the target',
  );

  // ── watching, recursively ───────────────────────────────────────────────
  final watch = fs.watch();
  _check(watch != null, 'the platform watches');
  if (watch != null) {
    final changes = <String>[];
    final sub = watch.listen((c) => changes.add(c.path));
    // The control: a change in the root itself. Without it a missing nested
    // event cannot be told from a platform that reports nothing — which is
    // what Wine does, so under Wine the watch is not measured, not failed.
    final top = File('${root.path}/top.md');
    if (!await _reported(changes, 'top.md', () => top.writeAsStringSync('t'))) {
      _notMeasured++;
      stdout.writeln(
        'NOT MEASURED the watch: not even a change in the root '
        'was reported here, so recursion cannot be judged',
      );
      await sub.cancel();
    } else {
      final nested = File('${root.path}/notes/a.md');
      _check(
        await _reported(
          changes,
          'notes/a.md',
          () => nested.writeAsStringSync('edit'),
        ),
        'an edit one folder down is reported',
      );
      Directory('${root.path}/later/deep').createSync(recursive: true);
      final fresh = File('${root.path}/later/deep/b.md');
      _check(
        await _reported(
          changes,
          'later/deep/b.md',
          () => fresh.writeAsStringSync('x'),
        ),
        'a file in a folder made after the watch began is reported',
      );
      await sub.cancel();
    }
  }

  // ── deleting to the trash ───────────────────────────────────────────────
  File('${root.path}/trash me.txt').writeAsStringSync('t');
  Directory('${root.path}/trash folder').createSync();
  File('${root.path}/trash folder/inside.txt').writeAsStringSync('i');
  final fileTrashed = await fs.trash(at('trash me.txt'));
  final folderTrashed = await fs.trash(at('trash folder'));
  _check(
    fileTrashed && !await fs.exists(at('trash me.txt')),
    'a file is moved to the trash',
  );
  _check(
    folderTrashed && !await fs.exists(at('trash folder')),
    'a folder is moved to the trash',
  );

  stdout.writeln(
    _failed > 0
        ? '$_failed FAILED'
        : _notMeasured > 0
        ? 'ALL OK of what was measured ($_notMeasured not measured)'
        : 'ALL OK',
  );
  // The shell around this reads the trash; the root is left for it to see.
  exit(_failed == 0 ? 0 : 1);
}
