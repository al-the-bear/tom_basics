/// The glob language of path filters and of `.gitignore` lines.
///
/// `*` is any run of characters within one path segment, `**` any run across
/// segments (so `**/x` matches `x` at every depth, the root included), `?` one
/// character within a segment, `{a,b}` either alternative and `[…]` a
/// character class. A glob is matched against a whole path relative to the
/// root, with `/` separators, case-sensitively.
library;

/// A compiled glob.
class TomGlob {
  /// The glob as written.
  final String pattern;

  final RegExp _regExp;

  TomGlob(this.pattern) : _regExp = RegExp('^${_translate(pattern)}\$');

  /// Whether [path] (relative, `/`-separated) matches.
  bool matches(String path) => _regExp.hasMatch(path);

  static String _translate(String glob) {
    final out = StringBuffer();
    var i = 0;
    var braces = 0;
    while (i < glob.length) {
      final c = glob[i];
      switch (c) {
        case '*':
          if (i + 1 < glob.length && glob[i + 1] == '*') {
            final slashAfter = i + 2 < glob.length && glob[i + 2] == '/';
            if (slashAfter) {
              // `**/` — any number of whole segments, none included.
              out.write('(?:.*/)?');
              i += 3;
            } else {
              out.write('.*');
              i += 2;
            }
          } else {
            out.write('[^/]*');
            i += 1;
          }
        case '?':
          out.write('[^/]');
          i += 1;
        case '{':
          braces++;
          out.write('(?:');
          i += 1;
        case '}' when braces > 0:
          braces--;
          out.write(')');
          i += 1;
        case ',' when braces > 0:
          out.write('|');
          i += 1;
        case '[':
          final end = glob.indexOf(']', i + 1);
          if (end == -1) {
            out.write(r'\[');
            i += 1;
          } else {
            var body = glob.substring(i + 1, end);
            if (body.startsWith('!')) body = '^${body.substring(1)}';
            out.write('[${body.replaceAll(r'\', r'\\')}]');
            i = end + 1;
          }
        case r'\' when i + 1 < glob.length:
          // An escaped character stands for itself (`\*`, `\ `, `\[`).
          out.write(RegExp.escape(glob[i + 1]));
          i += 2;
        default:
          out.write(RegExp.escape(c));
          i += 1;
      }
    }
    return out.toString();
  }

  @override
  String toString() => pattern;
}

/// The rules of one `.gitignore` file, in the folder [base] (relative to the
/// root, `''` for the root itself).
///
/// The parts of git's matching a file browser or a search needs: comments,
/// blank lines, `\#` and `\!` for a literal first character, trailing spaces
/// dropped unless escaped, `!` negation, a trailing `/` for folders only, a
/// leading or inner `/` anchoring the pattern to [base], and otherwise a match
/// at any depth below it. A path inside a matched folder is matched too, as
/// git ignores a folder's contents with the folder. Later lines override
/// earlier ones, as in git.
class TomGitignore {
  final String base;
  final List<_IgnoreLine> _lines;

  TomGitignore._(this.base, this._lines);

  /// Parses the text of the `.gitignore` in [base].
  factory TomGitignore.parse(String base, String text) {
    final lines = <_IgnoreLine>[];
    for (var raw in text.split('\n')) {
      if (raw.endsWith('\r')) raw = raw.substring(0, raw.length - 1);
      raw = _trimTrailingSpaces(raw);
      if (raw.isEmpty || raw.startsWith('#')) continue;
      var negate = false;
      if (raw.startsWith('!')) {
        negate = true;
        raw = raw.substring(1);
      } else if (raw.startsWith(r'\!') || raw.startsWith(r'\#')) {
        raw = raw.substring(1);
      }
      var directoryOnly = false;
      if (raw.endsWith('/')) {
        directoryOnly = true;
        raw = raw.substring(0, raw.length - 1);
      }
      if (raw.isEmpty) continue;
      final anchored = raw.contains('/');
      if (raw.startsWith('/')) raw = raw.substring(1);
      final glob = anchored ? raw : '**/$raw';
      lines.add(_IgnoreLine(TomGlob(glob), negate, directoryOnly));
    }
    return TomGitignore._(base, lines);
  }

  /// This file's verdict on [path] — ignored, re-included, or null when no
  /// line speaks to it. [path] is relative to the root.
  bool? verdict(String path, {required bool isDirectory}) {
    final String local;
    if (base.isEmpty) {
      local = path;
    } else if (path.startsWith('$base/')) {
      local = path.substring(base.length + 1);
    } else {
      return null;
    }
    // The path itself, then each folder above it: a line that matches a
    // folder matches everything inside it.
    final segments = local.split('/');
    final ancestors = [
      for (var n = 1; n < segments.length; n++) segments.take(n).join('/'),
    ];
    bool? result;
    for (final line in _lines) {
      final self = !(line.directoryOnly && !isDirectory) &&
          line.glob.matches(local);
      if (self || ancestors.any(line.glob.matches)) result = !line.negate;
    }
    return result;
  }

  /// Drops trailing spaces, except one escaped with a backslash.
  static String _trimTrailingSpaces(String line) {
    var end = line.length;
    while (end > 0 && line[end - 1] == ' ') {
      if (end >= 2 && line[end - 2] == r'\') break;
      end--;
    }
    return line.substring(0, end);
  }
}

/// Several `.gitignore` files, as git reads them together: each speaks for
/// the paths under its own folder, and a later file's verdict overrides an
/// earlier one's. Add the files root first, so a deeper file wins.
class TomGitignoreSet {
  final List<TomGitignore> _files = [];

  /// The files, in the order they are consulted.
  List<TomGitignore> get files => List.unmodifiable(_files);

  void add(TomGitignore file) => _files.add(file);

  void clear() => _files.clear();

  /// Whether [path] (relative to the root, `/`-separated) is ignored.
  bool isIgnored(String path, {required bool isDirectory}) {
    final normalized = path.replaceAll(r'\', '/');
    if (normalized.isEmpty) return false;
    bool? ignored;
    for (final file in _files) {
      final verdict = file.verdict(normalized, isDirectory: isDirectory);
      if (verdict != null) ignored = verdict;
    }
    return ignored ?? false;
  }
}

class _IgnoreLine {
  final TomGlob glob;
  final bool negate;
  final bool directoryOnly;

  const _IgnoreLine(this.glob, this.negate, this.directoryOnly);
}
