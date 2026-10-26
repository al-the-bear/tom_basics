/// The one file-system contract of every Tom application: the Forge shell,
/// its editors and the applications built on them.
///
/// Every read and write of a file goes through a [TomFileSystem], so no
/// editor, explorer or browser touches `dart:io` directly, and a second kind
/// of folder — in memory, or a repository — attaches by implementing it.
/// Its guarantees:
///
/// - A **write is atomic**: a crash leaves the old bytes or the new ones,
///   never half of either.
/// - A write may name the **revision** it was read at, and is then refused
///   with a [TomFileConflict] when the file changed since — nothing is
///   written over somebody else's change.
/// - A **delete goes to the platform's trash** where there is one; deleting
///   for good is a separate call.
/// - A **link that leaves the root** is listed and never expanded.
/// - Results are **values**, not `dart:io` objects, so the contract links
///   into a browser build.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// How a file changed.
enum TomFileChangeType { created, modified, deleted }

/// A create, write, rename or delete made through a [TomFileSystem].
class TomFileChangeEvent {
  /// The URI that changed.
  final Uri uri;

  /// How it changed.
  final TomFileChangeType type;

  const TomFileChangeEvent({required this.uri, required this.type});
}

/// Why a file is saved.
enum TomSaveReason { manual, autoSave, focusLoss }

/// Announced before a file is saved. A listener may change [content], and the
/// changed content is what is saved.
class TomWillSaveEvent {
  /// The URI being saved.
  final Uri uri;

  /// The content to be saved. Listeners can modify this.
  String content;

  /// Why it is saved.
  final TomSaveReason reason;

  TomWillSaveEvent({
    required this.uri,
    required this.content,
    required this.reason,
  });
}

/// What an entry of a directory is.
enum TomFileEntryKind { file, directory, link }

/// One entry of a listed directory.
class TomFileEntry {
  /// The entry's own name.
  final String name;

  /// Its path relative to the file system's root, with `/` separators; `''`
  /// for the root itself.
  final String path;

  /// Its absolute URI.
  final Uri uri;

  final TomFileEntryKind kind;

  /// The size in bytes; 0 for a directory.
  final int size;

  final DateTime modified;

  /// For a link: whether it leads to a directory.
  final bool linksToDirectory;

  /// For a link: whether its target lies outside the root, or leads back into
  /// its own ancestors — such a link is shown and never expanded, so a cycle
  /// cannot make listing endless.
  final bool linkLeavesRoot;

  /// Whether the process may read it.
  final bool readable;

  const TomFileEntry({
    required this.name,
    required this.path,
    required this.uri,
    required this.kind,
    this.size = 0,
    required this.modified,
    this.linksToDirectory = false,
    this.linkLeavesRoot = false,
    this.readable = true,
  });

  /// Whether a tree shows it as a folder.
  bool get isDirectory =>
      kind == TomFileEntryKind.directory ||
      (kind == TomFileEntryKind.link && linksToDirectory);

  /// Whether a tree may expand it.
  bool get expandable => isDirectory && !linkLeavesRoot && readable;
}

/// The version of a file as it was read: what a write is checked against.
class TomFileRevision {
  final DateTime modified;
  final int size;

  /// SHA-256 of the bytes read, hex.
  final String sha256;

  const TomFileRevision({
    required this.modified,
    required this.size,
    required this.sha256,
  });

  /// The revision of [bytes] last modified at [modified].
  factory TomFileRevision.of(Uint8List bytes, DateTime modified) =>
      TomFileRevision(
        modified: modified,
        size: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
      );

  /// Two revisions are the same file content; the time is not compared, so
  /// a write of identical bytes is not a change.
  @override
  bool operator ==(Object other) =>
      other is TomFileRevision && other.size == size && other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(size, sha256);
}

/// A file's bytes and the revision they were read at.
class TomFileContent {
  final Uint8List bytes;
  final TomFileRevision revision;

  const TomFileContent(this.bytes, this.revision);
}

/// A write refused because the file is no longer the revision it was read
/// at — someone else changed it.
class TomFileConflict implements Exception {
  final Uri uri;

  /// The revision there now, or null when the file is gone.
  final TomFileRevision? current;

  const TomFileConflict(this.uri, this.current);

  @override
  String toString() => current == null
      ? '"${uri.path}" was deleted since it was read'
      : '"${uri.path}" changed on disk since it was read';
}

/// A change under a watched root. Advisory: a watch may miss a change, and
/// a caller that must know compares revisions.
class TomFileChange {
  /// The changed entry's path relative to the root.
  final String path;

  /// Its absolute URI.
  final Uri uri;

  const TomFileChange(this.path, this.uri);
}

/// The contract. A file system has a [root]; a relative URI resolves against
/// it, and [path]s in entries and changes are relative to it.
abstract interface class TomFileSystem {
  /// The root directory, as an absolute directory URI (trailing `/`).
  Uri get root;

  /// The absolute URI of [path], relative to [root] with `/` separators.
  Uri uriOf(String path);

  /// [uri]'s path relative to [root], or null when it lies outside it.
  String? pathOf(Uri uri);

  /// The entries of the directory [directory] — one level, unsorted.
  Future<List<TomFileEntry>> list(Uri directory);

  /// [uri]'s entry without reading it, or null when it does not exist.
  Future<TomFileEntry?> stat(Uri uri);

  /// The bytes of [uri] and the revision they were read at.
  Future<TomFileContent> read(Uri uri);

  /// The text of [uri], decoded as UTF-8.
  Future<String> readText(Uri uri);

  /// At most [maxBytes] of [uri] as text, from its end when [fromEnd] and
  /// from its start otherwise — or null when it does not exist.
  ///
  /// A cut slice drops the partial line at the cut, so the first (or last)
  /// line is whole; a slice with no line break is kept as it is. Bytes that
  /// are not UTF-8 are replaced rather than refused: a log is read to be
  /// looked at.
  Future<String?> readSlice(
    Uri uri, {
    required int maxBytes,
    required bool fromEnd,
  });

  /// Writes [bytes] to [uri] **atomically**. With [expected], refuses with a
  /// [TomFileConflict] when the file is no longer that revision. Answers
  /// the revision written.
  Future<TomFileRevision> write(
    Uri uri,
    Uint8List bytes, {
    TomFileRevision? expected,
  });

  /// [write] of [text] as UTF-8.
  Future<TomFileRevision> writeText(
    Uri uri,
    String text, {
    TomFileRevision? expected,
  });

  /// Creates an empty file, or with [directory] a folder with its parents.
  /// A file that already exists is refused.
  Future<void> create(Uri uri, {bool directory = false});

  /// Renames or moves [from] to [to]; an existing [to] is refused.
  Future<void> rename(Uri from, Uri to);

  /// Deletes [uri] by moving it to the platform's trash. Answers false when
  /// there is no trash to move it to — the caller then asks before [delete]:
  /// nothing is unlinked without a way back unless somebody said so.
  Future<bool> trash(Uri uri);

  /// Deletes [uri] for good — a folder with everything in it.
  Future<void> delete(Uri uri);

  /// Whether [uri] exists.
  Future<bool> exists(Uri uri);

  /// Changes under [root], or null when the platform refuses to watch.
  ///
  /// [descend] is asked, with a folder's path relative to the root, whether
  /// changes inside it are wanted, so a folder a tree does not enter need not
  /// be watched. An implementation may watch more than it is asked to — a
  /// native recursive watch costs the same either way — but never less.
  Stream<TomFileChange>? watch({bool Function(String path)? descend});

  /// Announces that [uri] is saved: [onWillSave] with its text, then
  /// [onDidSave].
  Future<void> save(Uri uri);

  /// Every create, write, rename and delete made through this file system.
  Stream<TomFileChangeEvent> get onDidChange;

  Stream<Uri> get onDidSave;

  Stream<TomWillSaveEvent> get onWillSave;

  /// Ends the event streams.
  Future<void> dispose();
}

/// [text] without its first, partial line — a tail slice's cut. Text with no
/// line break is returned whole: there is nothing to snap to.
String tomTrimToLineStart(String text) {
  final nl = text.indexOf('\n');
  return nl < 0 ? text : text.substring(nl + 1);
}

/// [text] without its last, partial line — a head slice's cut.
String tomTrimToLineEnd(String text) {
  final nl = text.lastIndexOf('\n');
  return nl < 0 ? text : text.substring(0, nl + 1);
}
