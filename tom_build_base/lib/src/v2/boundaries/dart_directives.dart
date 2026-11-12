/// The `import` / `export` / `part` / `part of` directives of a Dart source
/// file, read without the analyzer.
///
/// Comments and the bodies of string literals (with their interpolations) are
/// skipped, so a directive written inside a string or a comment is not taken
/// for one; only statements at the top level (brace depth 0) count.
library;

/// The kind of a [DartDirective].
enum DartDirectiveKind { import, export, part, partOf }

/// One directive: its kind, the URIs it names (a conditional import names
/// more than one) and the 1-based line of its first URI.
class DartDirective {
  /// What the directive is.
  final DartDirectiveKind kind;

  /// The URI literals in source order; empty for `part of <library name>`.
  final List<String> uris;

  /// The 1-based line of the first URI (of the keyword when there is none).
  final int line;

  /// Creates a directive.
  const DartDirective(this.kind, this.uris, this.line);

  @override
  String toString() => '${kind.name} ${uris.join(' | ')} (line $line)';
}

/// The directives of [source], in order.
List<DartDirective> scanDartDirectives(String source) {
  final tokens = _Tokenizer(source).tokens();
  final directives = <DartDirective>[];
  var depth = 0;
  _Token? previous;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.kind == _TokenKind.punct) {
      if (token.text == '{') depth++;
      if (token.text == '}' && depth > 0) depth--;
    }
    final atStatementStart =
        previous == null ||
        (previous.kind == _TokenKind.punct &&
            (previous.text == ';' || previous.text == '}'));
    if (depth == 0 &&
        atStatementStart &&
        token.kind == _TokenKind.ident &&
        (token.text == 'import' ||
            token.text == 'export' ||
            token.text == 'part')) {
      var kind = switch (token.text) {
        'import' => DartDirectiveKind.import,
        'export' => DartDirectiveKind.export,
        _ => DartDirectiveKind.part,
      };
      final uris = <String>[];
      int? line;
      var j = i + 1;
      if (kind == DartDirectiveKind.part &&
          j < tokens.length &&
          tokens[j].kind == _TokenKind.ident &&
          tokens[j].text == 'of') {
        kind = DartDirectiveKind.partOf;
        j++;
      }
      for (; j < tokens.length; j++) {
        final t = tokens[j];
        if (t.kind == _TokenKind.punct && t.text == ';') break;
        if (t.kind == _TokenKind.string) {
          uris.add(t.text);
          line ??= t.line;
        }
      }
      directives.add(DartDirective(kind, uris, line ?? token.line));
      i = j;
      previous = j < tokens.length ? tokens[j] : null;
      continue;
    }
    previous = token;
  }
  return directives;
}

enum _TokenKind { ident, string, punct }

class _Token {
  final _TokenKind kind;
  final String text;
  final int line;
  const _Token(this.kind, this.text, this.line);
}

class _Tokenizer {
  final String s;
  int pos = 0;
  int line = 1;

  _Tokenizer(this.s);

  List<_Token> tokens() {
    final out = <_Token>[];
    while (true) {
      final token = next();
      if (token == null) return out;
      out.add(token);
    }
  }

  bool _at(String text) => s.startsWith(text, pos);

  void _advance([int n = 1]) {
    for (var k = 0; k < n && pos < s.length; k++) {
      if (s.codeUnitAt(pos) == 0x0A) line++;
      pos++;
    }
  }

  static bool _isIdentStart(int c) =>
      (c >= 0x41 && c <= 0x5A) ||
      (c >= 0x61 && c <= 0x7A) ||
      c == 0x5F ||
      c == 0x24;

  static bool _isIdentPart(int c) =>
      _isIdentStart(c) || (c >= 0x30 && c <= 0x39);

  /// The next token, or null at the end. Comments and whitespace are skipped.
  _Token? next() {
    while (pos < s.length) {
      final c = s.codeUnitAt(pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _advance();
        continue;
      }
      if (_at('//')) {
        while (pos < s.length && s.codeUnitAt(pos) != 0x0A) {
          pos++;
        }
        continue;
      }
      if (_at('/*')) {
        _skipBlockComment();
        continue;
      }
      final startLine = line;
      if (c == 0x27 || c == 0x22) {
        return _Token(_TokenKind.string, _string(raw: false), startLine);
      }
      if (_isIdentStart(c)) {
        final start = pos;
        while (pos < s.length && _isIdentPart(s.codeUnitAt(pos))) {
          pos++;
        }
        final ident = s.substring(start, pos);
        if (ident == 'r' &&
            pos < s.length &&
            (s.codeUnitAt(pos) == 0x27 || s.codeUnitAt(pos) == 0x22)) {
          return _Token(_TokenKind.string, _string(raw: true), startLine);
        }
        return _Token(_TokenKind.ident, ident, startLine);
      }
      _advance();
      return _Token(_TokenKind.punct, String.fromCharCode(c), startLine);
    }
    return null;
  }

  void _skipBlockComment() {
    var depth = 0;
    while (pos < s.length) {
      if (_at('/*')) {
        depth++;
        _advance(2);
      } else if (_at('*/')) {
        depth--;
        _advance(2);
        if (depth == 0) return;
      } else {
        _advance();
      }
    }
  }

  /// Reads a string literal at [pos] (its opening quote) and returns its
  /// text; interpolations are skipped and stand for nothing in the result.
  String _string({required bool raw}) {
    final quote = s[pos];
    final triple = _at(quote * 3);
    final delimiter = triple ? quote * 3 : quote;
    _advance(delimiter.length);
    final buffer = StringBuffer();
    while (pos < s.length) {
      if (_at(delimiter)) {
        _advance(delimiter.length);
        return buffer.toString();
      }
      final c = s[pos];
      if (!triple && c == '\n') return buffer.toString();
      if (!raw && c == r'\') {
        if (pos + 1 < s.length) buffer.write(s[pos + 1]);
        _advance(2);
        continue;
      }
      if (!raw && _at(r'${')) {
        _advance(2);
        _skipInterpolation();
        continue;
      }
      buffer.write(c);
      _advance();
    }
    return buffer.toString();
  }

  /// Skips the code of a `${...}` up to its closing brace.
  void _skipInterpolation() {
    var depth = 1;
    while (pos < s.length) {
      final token = next();
      if (token == null) return;
      if (token.kind != _TokenKind.punct) continue;
      if (token.text == '{') depth++;
      if (token.text == '}') {
        depth--;
        if (depth == 0) return;
      }
    }
  }
}
