/// Minimal **canonical** YAML emitter: one byte sequence per value.
///
/// `package:yaml` only parses; this emitter produces stable, human-readable
/// block-style YAML for maps, lists, strings, numbers, booleans and null.
/// Determinism is the point: a format that compares its files byte-wise — for
/// history snapshots, change detection or round-trip tests — needs the same
/// value to be written the same way every time, on every platform.
///
/// The rules, numbered as the emitter applies them:
///
/// 1. Keys are written in the order the caller's map holds them (see
///    `tomOrderedMapping` and `tomDeepSortKeys` for the two canonical orders).
/// 2. Block style throughout; an empty collection is `{}` or `[]`.
/// 3. A string is written plain only when it is a run of letters, digits and
///    ` _./@-` that starts with a letter or digit, is no YAML keyword
///    (`true`, `yes`, `on`, …) and does not read as a number.
/// 4. Every other string is double-quoted, `\\`, `\"`, `\n`, `\t`, `\r` by
///    name and every non-printable code point as `\uXXXX` — except for the
///    one designated block-scalar key, written as a literal block.
///
/// For files people also edit by hand, `yaml_lines.dart` writes single keys in
/// the style the workspace's tools use; the two are different styles on
/// purpose, and neither changes the other's bytes.
library;

/// Emits [value] (a map or list) as a YAML document string.
///
/// [blockScalarPath] names the one **designated block-scalar key** — the
/// mapping path, from the top, of a string emitted as a literal block scalar
/// instead of the double-quoted form of rule 4 ([tomEmitLiteralBlock]). A
/// format uses it for the one field that holds source code or prose people
/// read in the file; every other caller passes none.
String tomEmitYamlDocument(Object? value, {List<String>? blockScalarPath}) {
  final buffer = StringBuffer();
  _emit(buffer, value, 0,
      atLineStart: true,
      path: blockScalarPath == null ? null : const [],
      blockScalarPath: blockScalarPath);
  return buffer.toString();
}

/// The canonical literal-block emission of [value] under a key written at
/// [keyIndent] spaces: the text that follows `key:` — header and content lines
/// — or **null** when [value] has no canonical block form and is emitted by
/// rule 4 instead.
///
/// * **Chomping** — `|` when [value] ends with one `\n`, `|-` when it ends
///   with none; never `|+`.
/// * **Indentation** — every content line, an empty one included, is indented
///   exactly two spaces deeper than the key.
/// * **Indentation indicator** — written iff the first line is empty or begins
///   with a space, since YAML would otherwise infer the block indentation from
///   the first non-empty line and silently re-indent the source. The digit is
///   `2`: a YAML indentation indicator counts from the indentation of the
///   mapping that holds the key, and the content sits two columns deeper than
///   that key (so `source: |2-` puts content at column 4 under `content:`).
/// * **Empty or whitespace-only** — null, so rule 4 writes `""`.
///
/// Null too for a value no literal block can carry byte-for-byte — a `\r`
/// (YAML folds it into a line break), two or more trailing newlines (would
/// need `|+`), trailing whitespace or a tab in a line's leading whitespace, or
/// a character YAML does not admit in a block scalar. The double-quoted
/// fallback keeps any such value round-tripping.
String? tomEmitLiteralBlock(String value, int keyIndent) {
  if (value.trim().isEmpty) return null;
  if (value.contains('\r') || value.endsWith('\n\n')) return null;
  for (final rune in value.runes) {
    if (!_blockPrintable(rune)) return null;
  }
  final clip = value.endsWith('\n');
  final body = clip ? value.substring(0, value.length - 1) : value;
  final lines = body.split('\n');
  for (final line in lines) {
    if (line.endsWith(' ') || line.endsWith('\t')) return null;
    final lead = line.length - line.trimLeft().length;
    if (line.substring(0, lead).contains('\t')) return null;
  }
  final first = lines.first;
  final indicator = first.isEmpty || first.startsWith(' ') ? '2' : '';
  final pad = ' ' * (keyIndent + 2);
  final out = StringBuffer('|$indicator${clip ? '' : '-'}\n');
  for (final line in lines) {
    out.writeln('$pad$line');
  }
  return out.toString();
}

/// Whether [rune] may appear in a literal block scalar's content: YAML's
/// printable set without the characters some readers treat as line breaks
/// (NEL, LS, PS) and without a byte-order mark.
bool _blockPrintable(int rune) =>
    rune == 0x09 ||
    rune == 0x0A ||
    (rune >= 0x20 && rune <= 0x7E) ||
    (rune >= 0xA0 && rune <= 0xD7FF && rune != 0x2028 && rune != 0x2029) ||
    (rune >= 0xE000 && rune <= 0xFFFD && rune != 0xFEFF) ||
    (rune >= 0x10000 && rune <= 0x10FFFF);

/// Recursively re-orders every mapping in [value] by key.
///
/// A structure with a *fixed* key set gets its determinism from the order its
/// schema prescribes, so it needs none of this. A structure with an **open**
/// key set has no such schema to appeal to, and sorting is the only ordering
/// that stays deterministic when a later version adds a key this build has
/// never heard of.
Object? tomDeepSortKeys(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: tomDeepSortKeys(value[key]),
    };
  }
  if (value is List) return [for (final item in value) tomDeepSortKeys(item)];
  return value;
}

/// Emits [value] as a **canonical fragment**: rule 1 with every key sorted.
String tomEmitCanonicalFragment(Object? value) =>
    tomEmitYamlDocument(tomDeepSortKeys(value));

final _plainScalarRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 _.\/@-]*$');
final _plainKeyRe = RegExp(r'^[A-Za-z0-9_$][A-Za-z0-9_.$-]*$');
const _reservedWords = {'true', 'false', 'null', 'yes', 'no', 'on', 'off'};

String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final s = value.toString();
  if (_plainScalarRe.hasMatch(s) &&
      !_reservedWords.contains(s.toLowerCase()) &&
      !s.endsWith(' ') &&
      num.tryParse(s) == null) {
    return s;
  }
  return _quote(s);
}

/// The rule-4 double-quoted form of [s].
///
/// `\\`, `\"`, `\n`, `\t` and `\r` by name; every other code point outside
/// YAML's printable set — the C0 controls, DEL, the C1 controls, the line and
/// paragraph separators, a byte-order mark and an unpaired surrogate — as `\u`
/// with four uppercase hex digits. Written raw,
/// a `\r` is folded into a line break by the reader and most other controls
/// are rejected outright, so without the escape such a string could not
/// round-trip. Iterates code units, so an astral character (a valid pair)
/// passes through whole and a lone surrogate is escaped.
String _quote(String s) {
  final out = StringBuffer('"');
  for (var i = 0; i < s.length; i++) {
    final unit = s.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < s.length) {
      final next = s.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        out.writeCharCode(unit);
        out.writeCharCode(next);
        i++;
        continue;
      }
    }
    switch (unit) {
      case 0x5C:
        out.write(r'\\');
      case 0x22:
        out.write(r'\"');
      case 0x0A:
        out.write(r'\n');
      case 0x09:
        out.write(r'\t');
      case 0x0D:
        out.write(r'\r');
      default:
        if (_needsUnicodeEscape(unit)) {
          out.write(
              '\\u${unit.toRadixString(16).toUpperCase().padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
  return out.toString();
}

bool _needsUnicodeEscape(int unit) =>
    unit < 0x20 ||
    (unit >= 0x7F && unit <= 0x9F) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0xFEFF ||
    (unit >= 0xD800 && unit <= 0xDFFF);

bool _isPath(List<String>? path, List<String>? target) {
  if (path == null || target == null || path.length != target.length) {
    return false;
  }
  for (var i = 0; i < path.length; i++) {
    if (path[i] != target[i]) return false;
  }
  return true;
}

String _key(String key) => _plainKeyRe.hasMatch(key) ? key : _quote(key);

void _emit(
  StringBuffer out,
  Object? value,
  int indent, {
  required bool atLineStart,
  List<String>? path,
  List<String>? blockScalarPath,
}) {
  final pad = '  ' * indent;
  if (value is Map) {
    if (value.isEmpty) {
      out.writeln(atLineStart ? '$pad{}' : '{}');
      return;
    }
    var first = true;
    for (final entry in value.entries) {
      final prefix = (first && !atLineStart) ? '' : pad;
      first = false;
      final k = _key(entry.key.toString());
      final v = entry.value;
      final childPath = path == null ? null : [...path, entry.key.toString()];
      final block = v is String && _isPath(childPath, blockScalarPath)
          ? tomEmitLiteralBlock(v, indent * 2)
          : null;
      if (block != null) {
        out.write('$prefix$k: $block');
      } else if (v is Map && v.isNotEmpty) {
        out.writeln('$prefix$k:');
        _emit(out, v, indent + 1,
            atLineStart: true,
            path: childPath,
            blockScalarPath: blockScalarPath);
      } else if (v is List && v.isNotEmpty) {
        out.writeln('$prefix$k:');
        _emit(out, v, indent + 1, atLineStart: true);
      } else if (v is Map) {
        out.writeln('$prefix$k: {}');
      } else if (v is List) {
        out.writeln('$prefix$k: []');
      } else {
        out.writeln('$prefix$k: ${_scalar(v)}');
      }
    }
  } else if (value is List) {
    if (value.isEmpty) {
      out.writeln(atLineStart ? '$pad[]' : '[]');
      return;
    }
    for (final item in value) {
      if (item is Map && item.isNotEmpty) {
        out.write('$pad- ');
        _emit(out, item, indent + 1, atLineStart: false);
      } else if (item is List && item.isNotEmpty) {
        out.writeln('$pad-');
        _emit(out, item, indent + 1, atLineStart: true);
      } else if (item is Map) {
        out.writeln('$pad- {}');
      } else if (item is List) {
        out.writeln('$pad- []');
      } else {
        out.writeln('$pad- ${_scalar(item)}');
      }
    }
  } else {
    out.writeln('$pad${_scalar(value)}');
  }
}
