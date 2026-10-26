/// The freedesktop.org Trash specification's home trash, written directly.
///
/// A Linux trash first asks `gio trash` and `trash-put`, which know about
/// every mount's own trash directory. A desktop without either — a minimal
/// install, a container — still has the home trash every file manager reads,
/// and moving an item there is two steps the specification states exactly: a
/// `.trashinfo` record saying where it came from, then the item itself.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Moves [absolute] into the home trash: `$XDG_DATA_HOME/Trash`, or
/// `~/.local/share/Trash`. Answers false, with nothing changed, when there is
/// no home to put a trash in or the item is on another filesystem than the
/// trash — the specification gives such an item its mount's own trash, which
/// only the desktop's tools know how to find.
///
/// [environment] and [now] are for tests; the defaults are the process's.
bool tomXdgTrash(
  String absolute, {
  Map<String, String>? environment,
  DateTime? now,
}) {
  final env = environment ?? Platform.environment;
  final dataHome =
      env['XDG_DATA_HOME'] ??
      (env['HOME'] == null ? null : p.join(env['HOME']!, '.local', 'share'));
  if (dataHome == null || dataHome.isEmpty) return false;
  final trash = p.join(dataHome, 'Trash');
  final files = Directory(p.join(trash, 'files'));
  final info = Directory(p.join(trash, 'info'));
  try {
    files.createSync(recursive: true);
    info.createSync(recursive: true);
  } on FileSystemException {
    return false;
  }

  // The name in the trash is the item's own, made unique; the record is
  // created exclusively, so two deletes of the same name cannot claim it.
  final base = p.basename(absolute);
  File? record;
  var name = base;
  for (var n = 1; record == null; n++) {
    final candidate = File(p.join(info.path, '$name.trashinfo'));
    if (FileSystemEntity.typeSync(p.join(files.path, name)) ==
        FileSystemEntityType.notFound) {
      try {
        candidate.createSync(exclusive: true);
        record = candidate;
        break;
      } on FileSystemException {
        // Taken by now; try the next name.
      }
    }
    name = '$base.$n';
    if (n > 10000) return false;
  }
  final at = (now ?? DateTime.now()).toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final date =
      '${at.year.toString().padLeft(4, '0')}-${two(at.month)}-'
      '${two(at.day)}T${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  try {
    record.writeAsStringSync(
      '[Trash Info]\n'
      'Path=${Uri(path: absolute).toString()}\n'
      'DeletionDate=$date\n',
      flush: true,
    );
    final target = p.join(files.path, name);
    if (FileSystemEntity.isDirectorySync(absolute)) {
      Directory(absolute).renameSync(target);
    } else {
      File(absolute).renameSync(target);
    }
    return true;
  } on FileSystemException {
    // Another filesystem, or the item could not be moved: take the record
    // back, since a record with no item is a phantom in every file manager.
    try {
      record.deleteSync();
    } on FileSystemException {
      // Nothing more to do.
    }
    return false;
  }
}
