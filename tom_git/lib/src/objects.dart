/// Git's four object kinds and the encodings git hashes.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'object_id.dart';

/// The kind of a git object, with its name and its packfile type code.
enum GitObjectType {
  commit('commit', 1),
  tree('tree', 2),
  blob('blob', 3),
  tag('tag', 4);

  const GitObjectType(this.typeName, this.packCode);

  /// The name in an object header (`blob 12\0…`).
  final String typeName;

  /// The type code in a packfile entry header.
  final int packCode;

  static GitObjectType fromName(String name) => values.firstWhere(
    (t) => t.typeName == name,
    orElse: () => throw FormatException('Unknown object type', name),
  );

  static GitObjectType fromPackCode(int code) => values.firstWhere(
    (t) => t.packCode == code,
    orElse: () => throw FormatException('Unknown pack object type $code'),
  );
}

/// An object as stored: its kind and its content bytes.
class GitObject {
  GitObject(this.type, this.content);

  final GitObjectType type;
  final Uint8List content;

  GitObjectId? _id;

  /// The object's id: SHA-1 over its header and [content].
  GitObjectId get id => _id ??= GitObjectId.hash(type.typeName, content);

  /// The bytes git hashes and a loose object deflates:
  /// `"<type> <size>\0<content>"`.
  Uint8List get framed {
    final header = ascii.encode('${type.typeName} ${content.length}\x00');
    return Uint8List(header.length + content.length)
      ..setRange(0, header.length, header)
      ..setRange(header.length, header.length + content.length, content);
  }

  /// Splits [framed] bytes back into an object.
  static GitObject unframe(Uint8List framed) {
    final nul = framed.indexOf(0);
    if (nul < 0) throw const FormatException('Object header has no NUL');
    final header = ascii.decode(framed.sublist(0, nul));
    final space = header.indexOf(' ');
    if (space < 0) throw FormatException('Malformed object header', header);
    final type = GitObjectType.fromName(header.substring(0, space));
    final size = int.parse(header.substring(space + 1));
    final content = Uint8List.sublistView(framed, nul + 1);
    if (content.length != size) {
      throw FormatException(
        'Object header says $size bytes, has '
        '${content.length}',
      );
    }
    return GitObject(type, Uint8List.fromList(content));
  }

  static GitObject blob(List<int> bytes) =>
      GitObject(GitObjectType.blob, Uint8List.fromList(bytes));
}

/// One entry of a tree: a mode, a name and the object it names.
class GitTreeEntry {
  const GitTreeEntry({
    required this.mode,
    required this.name,
    required this.id,
  });

  /// A regular file.
  static const fileMode = '100644';

  /// An executable file.
  static const executableMode = '100755';

  /// A subtree.
  static const treeMode = '40000';

  /// A symbolic link.
  static const symlinkMode = '120000';

  /// A submodule commit.
  static const gitlinkMode = '160000';

  final String mode;
  final String name;
  final GitObjectId id;

  bool get isTree => mode == treeMode;
  bool get isBlob =>
      mode == fileMode || mode == executableMode || mode == symlinkMode;

  @override
  String toString() => '$mode $name $id';
}

/// A directory listing: entries sorted the way git sorts them.
class GitTree {
  GitTree(Iterable<GitTreeEntry> entries)
    : entries = List.unmodifiable(
        entries.toList()..sort((a, b) => _compareEntries(a, b)),
      );

  final List<GitTreeEntry> entries;

  GitTreeEntry? operator [](String name) {
    for (final e in entries) {
      if (e.name == name) return e;
    }
    return null;
  }

  /// Git orders entries by name as bytes, comparing a tree's name as if it
  /// ended in `/` — so `a.txt` sorts before the tree `a`, which sorts as
  /// `a/`, before `a0`.
  static int _compareEntries(GitTreeEntry a, GitTreeEntry b) {
    final ka = utf8.encode(a.isTree ? '${a.name}/' : a.name);
    final kb = utf8.encode(b.isTree ? '${b.name}/' : b.name);
    final n = ka.length < kb.length ? ka.length : kb.length;
    for (var i = 0; i < n; i++) {
      final d = ka[i] - kb[i];
      if (d != 0) return d;
    }
    return ka.length - kb.length;
  }

  Uint8List encode() {
    final out = BytesBuilder(copy: false);
    for (final e in entries) {
      out
        ..add(utf8.encode('${e.mode} ${e.name}'))
        ..addByte(0)
        ..add(e.id.bytes);
    }
    return out.takeBytes();
  }

  GitObject toObject() => GitObject(GitObjectType.tree, encode());

  static GitTree decode(Uint8List content) {
    final entries = <GitTreeEntry>[];
    var i = 0;
    while (i < content.length) {
      final space = content.indexOf(0x20, i);
      final nul = content.indexOf(0, space);
      if (space < 0 ||
          nul < 0 ||
          nul + 1 + GitObjectId.byteLength > content.length) {
        throw const FormatException('Malformed tree entry');
      }
      final mode = ascii.decode(content.sublist(i, space));
      final name = utf8.decode(content.sublist(space + 1, nul));
      final id = GitObjectId.fromBytes(
        content.sublist(nul + 1, nul + 1 + GitObjectId.byteLength),
      );
      entries.add(
        GitTreeEntry(
          // Git writes a tree's mode as "40000"; older writers padded it.
          mode: mode == '040000' ? GitTreeEntry.treeMode : mode,
          name: name,
          id: id,
        ),
      );
      i = nul + 1 + GitObjectId.byteLength;
    }
    return GitTree(entries);
  }

  static final GitTree empty = GitTree(const []);
}

/// Who did something, and when: `Name <email> <seconds> <+hhmm>`.
class GitPerson {
  const GitPerson({
    required this.name,
    required this.email,
    required this.seconds,
    this.timezone = '+0000',
  });

  /// [name] and [email] now, in UTC.
  factory GitPerson.now(String name, String email, {DateTime? at}) => GitPerson(
    name: name,
    email: email,
    seconds: (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000,
  );

  final String name;
  final String email;

  /// Seconds since the epoch.
  final int seconds;

  /// The offset as git writes it, `+0200`.
  final String timezone;

  String encode() => '$name <$email> $seconds $timezone';

  static GitPerson parse(String line) {
    final open = line.lastIndexOf('<');
    final close = line.lastIndexOf('>');
    if (open < 0 || close < open) {
      throw FormatException('Malformed person line', line);
    }
    final tail = line.substring(close + 1).trim().split(' ');
    return GitPerson(
      name: line.substring(0, open).trim(),
      email: line.substring(open + 1, close),
      seconds: int.parse(tail[0]),
      timezone: tail.length > 1 ? tail[1] : '+0000',
    );
  }
}

/// A commit: a root tree, its parents, who and when, and the message.
class GitCommit {
  const GitCommit({
    required this.tree,
    required this.parents,
    required this.author,
    required this.committer,
    required this.message,
  });

  final GitObjectId tree;
  final List<GitObjectId> parents;
  final GitPerson author;
  final GitPerson committer;
  final String message;

  Uint8List encode() {
    final b = StringBuffer()..write('tree ${tree.hex}\n');
    for (final p in parents) {
      b.write('parent ${p.hex}\n');
    }
    b
      ..write('author ${author.encode()}\n')
      ..write('committer ${committer.encode()}\n')
      ..write('\n')
      ..write(message);
    return Uint8List.fromList(utf8.encode(b.toString()));
  }

  GitObject toObject() => GitObject(GitObjectType.commit, encode());

  /// Reads a commit. Headers this library has no use for (`gpgsig`,
  /// `encoding`, `mergetag`, continuation lines) are skipped.
  static GitCommit decode(Uint8List content) {
    final text = utf8.decode(content, allowMalformed: true);
    final split = text.indexOf('\n\n');
    final headers = split < 0 ? text : text.substring(0, split);
    final message = split < 0 ? '' : text.substring(split + 2);
    GitObjectId? tree;
    final parents = <GitObjectId>[];
    GitPerson? author;
    GitPerson? committer;
    for (final line in headers.split('\n')) {
      if (line.startsWith(' ')) continue;
      final space = line.indexOf(' ');
      if (space < 0) continue;
      final key = line.substring(0, space);
      final value = line.substring(space + 1);
      switch (key) {
        case 'tree':
          tree = GitObjectId.fromHex(value);
        case 'parent':
          parents.add(GitObjectId.fromHex(value));
        case 'author':
          author = GitPerson.parse(value);
        case 'committer':
          committer = GitPerson.parse(value);
      }
    }
    if (tree == null || author == null || committer == null) {
      throw const FormatException('Commit lacks tree, author or committer');
    }
    return GitCommit(
      tree: tree,
      parents: parents,
      author: author,
      committer: committer,
      message: message,
    );
  }
}
