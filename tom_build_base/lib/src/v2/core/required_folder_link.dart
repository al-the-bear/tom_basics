/// What to say about a required folder (`required-environment: folders:`)
/// that is a link which cannot be followed.
library;

import 'dart:io';

/// A note for a required folder at [path] that is not there as a folder:
/// null unless [path] is a link; else its target, whether that target is
/// there, and the command that recreates the link.
///
/// On Windows a junction can be unreadable although its target exists: one
/// made by MSYS with forward slashes, or without the `\??\` prefix, in its
/// substitute name (legiondary01, 2026-11-19). Windows does not follow it,
/// and neither does Dart; .NET's `Directory.Exists`, which checks only the
/// link's own attributes, says it is there. Recreating it with `mklink /J`
/// writes a link Windows follows.
///
/// [windows] defaults to this host; [readTarget] stands in for reading the
/// link's target (tests).
String? requiredFolderLinkNote(
  String path, {
  bool? windows,
  String Function(String link)? readTarget,
}) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.link) {
    return null;
  }
  final win = windows ?? Platform.isWindows;
  String target;
  try {
    target = (readTarget ?? (link) => Link(link).targetSync())(path);
  } on FileSystemException {
    return '$path is a link whose target cannot be read; recreate it';
  }
  if (win) {
    target = target.replaceAll('/', r'\');
    if (target.startsWith(r'\??\')) target = target.substring(4);
  }
  final recreate = win
      ? 'rmdir "$path" && mklink /J "$path" "$target"'
      : 'ln -sfn "$target" "$path"';
  final targetThere = Directory(target).existsSync();
  return targetThere
      ? '$path is a link to $target, which exists, but the link cannot be '
            'followed; recreate it: $recreate'
      : '$path is a link to $target, which cannot be followed: the target is '
            'not there (create it, or point the link elsewhere: $recreate)';
}
