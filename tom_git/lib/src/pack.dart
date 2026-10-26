/// Packfiles: many objects in one file, some stored as deltas against others.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' show getCrc32;
import 'package:crypto/crypto.dart';

import 'delta.dart';
import 'object_id.dart';
import 'objects.dart';
import 'zlib.dart';

const _ofsDelta = 6;
const _refDelta = 7;

/// One object of a parsed pack, with where it sits in the pack.
class GitPackedObject {
  GitPackedObject(this.object, this.offset, this.crc32);

  final GitObject object;

  /// Where the entry starts in the pack.
  final int offset;

  /// CRC-32 of the entry's bytes as stored — what a pack index records.
  final int crc32;
}

/// The objects of a pack, its checksum, and an index over them.
class GitParsedPack {
  GitParsedPack(this.objects, this.checksum);

  final List<GitPackedObject> objects;

  /// The SHA-1 trailer of the pack.
  final Uint8List checksum;

  /// A version-2 pack index for this pack.
  Uint8List buildIndex() => gitBuildPackIndex(objects, checksum);
}

/// Reads every object of a version-2 pack, resolving deltas.
///
/// [external] supplies a base an entry refers to by id that is not in the
/// pack (a thin pack); a missing base is an error.
Future<GitParsedPack> gitReadPack(
  Uint8List pack, {
  Future<GitObject?> Function(GitObjectId id)? external,
}) async {
  if (pack.length < 32 || ascii.decode(pack.sublist(0, 4)) != 'PACK') {
    throw const FormatException('Not a pack');
  }
  final data = ByteData.sublistView(pack);
  final version = data.getUint32(4);
  if (version != 2 && version != 3) {
    throw FormatException('Pack version $version is not supported');
  }
  final count = data.getUint32(8);
  final body = pack.length - 20;
  final checksum = Uint8List.fromList(pack.sublist(body));
  if (!_sameBytes(
    sha1.convert(Uint8List.sublistView(pack, 0, body)).bytes,
    checksum,
  )) {
    throw const FormatException('Pack checksum does not match');
  }

  final entries = <_Entry>[];
  var pos = 12;
  for (var n = 0; n < count; n++) {
    final start = pos;
    var c = pack[pos++];
    final type = (c >> 4) & 0x07;
    var size = c & 0x0f;
    var shift = 4;
    while (c & 0x80 != 0) {
      c = pack[pos++];
      size |= (c & 0x7f) << shift;
      shift += 7;
    }
    int? baseOffset;
    GitObjectId? baseId;
    if (type == _ofsDelta) {
      c = pack[pos++];
      var back = c & 0x7f;
      while (c & 0x80 != 0) {
        c = pack[pos++];
        back = ((back + 1) << 7) | (c & 0x7f);
      }
      baseOffset = start - back;
    } else if (type == _refDelta) {
      baseId = GitObjectId.fromBytes(pack.sublist(pos, pos + 20));
      pos += 20;
    }
    final inflated = gitInflateAt(pack, pos, expectedSize: size);
    pos += inflated.consumed;
    entries.add(
      _Entry(
        offset: start,
        type: type,
        data: inflated.data,
        baseOffset: baseOffset,
        baseId: baseId,
        crc32: getCrc32(Uint8List.sublistView(pack, start, pos)),
      ),
    );
  }
  if (pos != body) {
    throw FormatException('Pack has ${body - pos} bytes after its last entry');
  }

  final byOffset = {for (final e in entries) e.offset: e};
  final byId = <GitObjectId, _Entry>{};
  // Resolves an entry to its object, recursively through its delta base; a
  // base is resolved once and remembered.
  Future<GitObject> resolve(_Entry e) async {
    final done = e.resolved;
    if (done != null) return done;
    GitObject object;
    if (e.type == _ofsDelta || e.type == _refDelta) {
      GitObject base;
      if (e.baseOffset != null) {
        final b = byOffset[e.baseOffset];
        if (b == null) {
          throw FormatException(
            'Delta base at ${e.baseOffset} is not an '
            'entry of the pack',
          );
        }
        base = await resolve(b);
      } else {
        final inPack = byId[e.baseId];
        final b = inPack != null
            ? await resolve(inPack)
            : await external?.call(e.baseId!);
        if (b == null) {
          throw FormatException(
            'Delta base ${e.baseId} is neither in the '
            'pack nor available',
          );
        }
        base = b;
      }
      object = GitObject(base.type, gitApplyDelta(base.content, e.data));
    } else {
      object = GitObject(GitObjectType.fromPackCode(e.type), e.data);
    }
    e.resolved = object;
    byId[object.id] = e;
    return object;
  }

  // Non-delta entries first, so a ref-delta can find its base by id however
  // the pack is ordered.
  for (final e in entries) {
    if (e.type != _ofsDelta && e.type != _refDelta) await resolve(e);
  }
  final objects = <GitPackedObject>[];
  for (final e in entries) {
    objects.add(GitPackedObject(await resolve(e), e.offset, e.crc32));
  }
  return GitParsedPack(objects, checksum);
}

class _Entry {
  _Entry({
    required this.offset,
    required this.type,
    required this.data,
    required this.crc32,
    this.baseOffset,
    this.baseId,
  });

  final int offset;
  final int type;
  final Uint8List data;
  final int crc32;
  final int? baseOffset;
  final GitObjectId? baseId;
  GitObject? resolved;
}

/// A version-2 pack holding [objects], none of them stored as deltas.
///
/// Every receiver accepts a pack without deltas; the size it costs is the
/// price of not computing them, and a storage backend's commits are small.
Uint8List gitWritePack(Iterable<GitObject> objects) {
  final list = objects.toList();
  final out = BytesBuilder(copy: false);
  final header = ByteData(12)
    ..setUint32(0, 0x5041434b) // PACK
    ..setUint32(4, 2)
    ..setUint32(8, list.length);
  out.add(header.buffer.asUint8List());
  for (final o in list) {
    var size = o.content.length;
    final head = <int>[];
    var c = (o.type.packCode << 4) | (size & 0x0f);
    size >>= 4;
    while (size != 0) {
      head.add(c | 0x80);
      c = size & 0x7f;
      size >>= 7;
    }
    head.add(c);
    out
      ..add(head)
      ..add(gitDeflate(o.content));
  }
  final body = out.takeBytes();
  final trailer = sha1.convert(body).bytes;
  return Uint8List(body.length + 20)
    ..setRange(0, body.length, body)
    ..setRange(body.length, body.length + 20, trailer);
}

/// A version-2 pack index (`.idx`) over [objects] of the pack whose trailer
/// is [packChecksum].
Uint8List gitBuildPackIndex(
  List<GitPackedObject> objects,
  Uint8List packChecksum,
) {
  final sorted = [...objects]
    ..sort((a, b) => a.object.id.compareTo(b.object.id));
  final out = BytesBuilder(copy: false);
  out.add([0xff, 0x74, 0x4f, 0x63, 0, 0, 0, 2]);
  final fanout = ByteData(256 * 4);
  var i = 0;
  for (var b = 0; b < 256; b++) {
    while (i < sorted.length && sorted[i].object.id.bytes[0] <= b) {
      i++;
    }
    fanout.setUint32(b * 4, i);
  }
  out.add(fanout.buffer.asUint8List());
  for (final o in sorted) {
    out.add(o.object.id.bytes);
  }
  final crcs = ByteData(sorted.length * 4);
  for (var n = 0; n < sorted.length; n++) {
    crcs.setUint32(n * 4, sorted[n].crc32);
  }
  out.add(crcs.buffer.asUint8List());
  final large = <int>[];
  final offsets = ByteData(sorted.length * 4);
  for (var n = 0; n < sorted.length; n++) {
    final offset = sorted[n].offset;
    if (offset < 0x80000000) {
      offsets.setUint32(n * 4, offset);
    } else {
      offsets.setUint32(n * 4, 0x80000000 | large.length);
      large.add(offset);
    }
  }
  out.add(offsets.buffer.asUint8List());
  final largeTable = ByteData(large.length * 8);
  for (var n = 0; n < large.length; n++) {
    // Two 32-bit halves: ByteData's 64-bit accessors throw under dart2js.
    largeTable
      ..setUint32(n * 8, large[n] ~/ 0x100000000)
      ..setUint32(n * 8 + 4, large[n] % 0x100000000);
  }
  out
    ..add(largeTable.buffer.asUint8List())
    ..add(packChecksum);
  final body = out.takeBytes();
  final trailer = sha1.convert(body).bytes;
  return Uint8List(body.length + 20)
    ..setRange(0, body.length, body)
    ..setRange(body.length, body.length + 20, trailer);
}

/// A version-2 pack index read for lookups: id → offset in the pack.
class GitPackIndex {
  GitPackIndex._(this._data, this.count);

  /// Reads an index; versions other than 2 are refused.
  factory GitPackIndex.parse(Uint8List idx) {
    final data = ByteData.sublistView(idx);
    if (idx.length < 8 + 1024 + 40 ||
        data.getUint32(0) != 0xff744f63 ||
        data.getUint32(4) != 2) {
      throw const FormatException('Not a version-2 pack index');
    }
    return GitPackIndex._(data, data.getUint32(8 + 255 * 4));
  }

  final ByteData _data;

  /// How many objects the pack holds.
  final int count;

  int get _idsAt => 8 + 1024;
  int get _offsetsAt => _idsAt + count * 20 + count * 4;
  int get _largeAt => _offsetsAt + count * 4;

  GitObjectId idAt(int n) => GitObjectId.fromBytes(
    _data.buffer.asUint8List(_data.offsetInBytes + _idsAt + n * 20, 20),
  );

  /// Every id the pack holds, sorted.
  Iterable<GitObjectId> get ids sync* {
    for (var n = 0; n < count; n++) {
      yield idAt(n);
    }
  }

  /// Where [id] starts in the pack, or null when the pack does not hold it.
  int? offsetOf(GitObjectId id) {
    final first = id.bytes[0];
    var lo = first == 0 ? 0 : _data.getUint32(8 + (first - 1) * 4);
    var hi = _data.getUint32(8 + first * 4);
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final cmp = idAt(mid).compareTo(id);
      if (cmp == 0) return _offsetAtIndex(mid);
      if (cmp < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return null;
  }

  int _offsetAtIndex(int n) {
    final value = _data.getUint32(_offsetsAt + n * 4);
    if (value & 0x80000000 == 0) return value;
    final at = _largeAt + (value & 0x7fffffff) * 8;
    return _data.getUint32(at) * 0x100000000 + _data.getUint32(at + 4);
  }
}

/// Reads the single object at [offset] of [pack], resolving a delta through
/// [resolveOffset] (another entry of the same pack) or [resolveId] (any
/// object, for a ref-delta).
Future<GitObject> gitReadPackEntry(
  Uint8List pack,
  int offset, {
  required Future<GitObject> Function(int offset) resolveOffset,
  required Future<GitObject?> Function(GitObjectId id) resolveId,
}) async {
  var pos = offset;
  var c = pack[pos++];
  final type = (c >> 4) & 0x07;
  var size = c & 0x0f;
  var shift = 4;
  while (c & 0x80 != 0) {
    c = pack[pos++];
    size |= (c & 0x7f) << shift;
    shift += 7;
  }
  if (type == _ofsDelta) {
    c = pack[pos++];
    var back = c & 0x7f;
    while (c & 0x80 != 0) {
      c = pack[pos++];
      back = ((back + 1) << 7) | (c & 0x7f);
    }
    final delta = gitInflateAt(pack, pos, expectedSize: size).data;
    final base = await resolveOffset(offset - back);
    return GitObject(base.type, gitApplyDelta(base.content, delta));
  }
  if (type == _refDelta) {
    final baseId = GitObjectId.fromBytes(pack.sublist(pos, pos + 20));
    pos += 20;
    final delta = gitInflateAt(pack, pos, expectedSize: size).data;
    final base = await resolveId(baseId);
    if (base == null) {
      throw FormatException('Delta base $baseId is not available');
    }
    return GitObject(base.type, gitApplyDelta(base.content, delta));
  }
  return GitObject(
    GitObjectType.fromPackCode(type),
    gitInflateAt(pack, pos, expectedSize: size).data,
  );
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
