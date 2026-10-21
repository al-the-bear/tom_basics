/// Reading Dart source without a parser: directives, comments, top-level
/// declarations, and a call's arguments.
///
/// Each answers one question a source-level rule asks and is careful about
/// the shapes that make a naive scan wrong — a `//` inside a string, a quote
/// inside an interpolation, a directive's conditional continuation, a body's
/// braces inside a string.
library;

import 'dart:convert';

/// An `import` or `export` directive on one line; group 1 is its URI.
final directiveLinePattern = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
);

/// Every `import` / `export` URI in [source], directives only.
///
/// Comment-aware, and it stops at the first real declaration — a `dart:io`
/// named in a doc comment or a string literal is not a dependency, and a rule
/// that counted one would be unfixable without rewording prose.
///
/// It deliberately stops at the URI itself: `show` / `hide` clauses and the
/// trailing `as` alias are irrelevant to every question asked here, and a
/// stricter pattern that silently matched nothing would make each caller pass
/// for the wrong reason.
Iterable<String> directiveUris(String source) sync* {
  var inBlockComment = false;
  for (final rawLine in const LineSplitter().convert(source)) {
    var line = rawLine;
    if (inBlockComment) {
      final end = line.indexOf('*/');
      if (end < 0) continue;
      inBlockComment = false;
      line = line.substring(end + 2);
    }
    // A block comment that closes on its own line is removed in place, so a
    // `/* … */` before or between directives does not end the scan; one that
    // stays open runs to a later line.
    var blockStart = line.indexOf('/*');
    while (blockStart >= 0) {
      final end = line.indexOf('*/', blockStart + 2);
      if (end < 0) {
        inBlockComment = true;
        line = line.substring(0, blockStart);
        break;
      }
      line = line.substring(0, blockStart) + line.substring(end + 2);
      blockStart = line.indexOf('/*');
    }
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('//')) continue;
    final match = directiveLinePattern.firstMatch(line);
    if (match != null) {
      yield match.group(1)!;
      continue;
    }
    if (trimmed.startsWith('library') ||
        trimmed.startsWith('part') ||
        trimmed.startsWith('@')) {
      continue;
    }
    // The continuation lines of a directive. A conditional import puts its
    // alternative on a line of its own — `if (dart.library.io) 'x.dart'` — and
    // that alternative is linked on the platform it names, so it is a
    // dependency like any other. Treating the line as "the first declaration"
    // ended the scan there and dropped every directive after it.
    final conditional = _conditionalUri.firstMatch(trimmed);
    if (conditional != null) {
      yield conditional.group(1)!;
      continue;
    }
    if (_directiveContinuation.hasMatch(trimmed)) continue;
    return; // first real declaration — directives are done
  }
}

final _conditionalUri = RegExp(r"""^if\s*\([^)]*\)\s*['"]([^'"]+)['"]""");
final _directiveContinuation = RegExp(
  r'^(?:show|hide|as|deferred)\b|^[A-Za-z_$][\w$]*\s*[,;]',
);

/// [source] with comments removed and line breaks preserved.
///
/// The distinction between prose and code is what a source rule needs: a
/// doc comment may explain a rule in the words the rule bans, and a scan that
/// could not tell a comment from code would be unfixable without rewording
/// the notes that justify it.
///
/// The scanner tracks string literals rather than cutting at the first `//`,
/// because `'https://…'` is not a comment.
String stripDartComments(String source) {
  final out = StringBuffer();
  var i = 0;
  while (i < source.length) {
    final c = source[i];

    if (c == '/' && i + 1 < source.length) {
      final next = source[i + 1];
      if (next == '/') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        continue;
      }
      if (next == '*') {
        i += 2;
        while (i < source.length &&
            !(source[i] == '*' &&
                i + 1 < source.length &&
                source[i + 1] == '/')) {
          // Newlines survive, so a violation's line number still points at the
          // line it is on.
          if (source[i] == '\n') out.write('\n');
          i++;
        }
        i += 2;
        continue;
      }
    }

    if (c == "'" || c == '"') {
      final triple = source.startsWith(c * 3, i);
      final terminator = triple ? c * 3 : c;
      // A raw string has no escapes, so a trailing backslash must not swallow
      // its closing quote.
      final raw = i > 0 && (source[i - 1] == 'r' || source[i - 1] == 'R');
      out.write(terminator);
      i += terminator.length;
      while (i < source.length && !source.startsWith(terminator, i)) {
        if (!raw && source[i] == r'\' && i + 1 < source.length) {
          out.write(source[i]);
          i++;
        }
        out.write(source[i]);
        i++;
      }
      if (i < source.length) {
        out.write(terminator);
        i += terminator.length;
      }
      continue;
    }

    out.write(c);
    i++;
  }
  return out.toString();
}

/// [source] with its comments removed and everything else — string literals
/// included — kept, newlines and all.
///
/// [stripDartComments] reads a string as running to the next quote of its
/// kind, which is right for the prose scans it serves and wrong for a
/// structural one: `'"${v.replaceAll('"', '""')}"'` ends early there, and
/// every comment after it is read as code. This one follows an
/// interpolation's braces, so a quote inside `${…}` does not end the string.
String dartCodeWithoutComments(String source) {
  final s = source;
  final out = StringBuffer();
  late final int Function(int, bool) code;

  int string(int i) {
    final raw = i > 0 && (s[i - 1] == 'r' || s[i - 1] == 'R');
    final quote = s[i];
    final terminator = s.startsWith(quote * 3, i) ? quote * 3 : quote;
    out.write(terminator);
    i += terminator.length;
    while (i < s.length && !s.startsWith(terminator, i)) {
      if (!raw && s[i] == r'\' && i + 1 < s.length) {
        out.write(s.substring(i, i + 2));
        i += 2;
        continue;
      }
      if (!raw && s.startsWith(r'${', i)) {
        out.write(r'${');
        i = code(i + 2, true);
        continue;
      }
      out.write(s[i]);
      i++;
    }
    if (i < s.length) out.write(terminator);
    return i + terminator.length;
  }

  code = (int i, bool untilBrace) {
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      if (s.startsWith('//', i)) {
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        continue;
      }
      if (s.startsWith('/*', i)) {
        var nesting = 0;
        while (i < s.length) {
          if (s.startsWith('/*', i)) {
            nesting++;
            i += 2;
          } else if (s.startsWith('*/', i)) {
            i += 2;
            if (--nesting == 0) break;
          } else {
            if (s[i] == '\n') out.write('\n');
            i++;
          }
        }
        continue;
      }
      if (c == "'" || c == '"') {
        i = string(i);
        continue;
      }
      if (untilBrace) {
        if (c == '{') depth++;
        if (c == '}') {
          if (depth == 0) {
            out.write('}');
            return i + 1;
          }
          depth--;
        }
      }
      out.write(c);
      i++;
    }
    return i;
  };

  code(0, false);
  return out.toString();
}

/// The top-level declarations of [source], public and private, in order.
///
/// A scanner rather than a line pattern, because the declarations a line
/// pattern misses are exactly the awkward ones: a return type on the line
/// above its function, a record return type, a named-parameter brace that is
/// not a body, a brace inside a string. Comments go first; strings, including
/// interpolations, are skipped as units; a body is skipped by balance; what is
/// left at the top level is a header, classified by its keyword.
List<({String name, String kind})> topLevelDeclarations(String source) {
  final s = dartCodeWithoutComments(source);
  final found = <({String name, String kind})>[];

  // Index just past the bracket that closes the one opening at its argument;
  // declared first because a string's interpolation and a bracket's string
  // each skip the other.
  late final int Function(int) skipBalanced;

  // Index just past the string literal opening at [i].
  int skipString(int i) {
    final raw = i > 0 && (s[i - 1] == 'r' || s[i - 1] == 'R');
    final quote = s[i];
    final triple = s.startsWith(quote * 3, i);
    final terminator = triple ? quote * 3 : quote;
    i += terminator.length;
    while (i < s.length && !s.startsWith(terminator, i)) {
      if (!raw && s[i] == r'\') {
        i += 2;
        continue;
      }
      if (!raw && s.startsWith(r'${', i)) {
        i = skipBalanced(i + 1);
        continue;
      }
      i++;
    }
    return i + terminator.length;
  }

  skipBalanced = (int i) {
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == "'" || c == '"') {
        i = skipString(i);
        continue;
      }
      if (c == '{' || c == '(' || c == '[') depth++;
      if (c == '}' || c == ')' || c == ']') {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return i;
  };

  // Index just past the `;` that ends the expression starting at [i].
  int skipToSemicolon(int i) {
    while (i < s.length) {
      final c = s[i];
      if (c == "'" || c == '"') {
        i = skipString(i);
      } else if (c == '{' || c == '(' || c == '[') {
        i = skipBalanced(i);
      } else if (c == ';') {
        return i + 1;
      } else {
        i++;
      }
    }
    return i;
  }

  final typeHeader = RegExp(
    r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)'
    r'|^(?:base\s+)?mixin\s+(\w+)'
    r'|^enum\s+(\w+)'
    r'|^extension\s+type\s+(?:const\s+)?(\w+)'
    r'|^extension\s+(?!on\b)(\w+)'
    r'|^typedef\s+(\w+)',
  );
  const typeKinds = [
    'class', 'mixin', 'enum', 'extension', 'extension', 'typedef', //
  ];
  final directive = RegExp(r'^(?:library|import|export|part)\b');
  final accessor = RegExp(r'\b(get|set)\s+(\w+)\s*$');
  // A generic function's own type parameters sit between its name and the
  // list: `List<T> merge<T>(`. They may nest one level (`<K, List<V>>`) and
  // never span a `>` — so a return type's arguments are not read as the
  // function's and its type name as the function's name.
  final parameterList = RegExp(
    r'([A-Za-z_$][\w$]*)\s*(?:<(?:[^()<>]|<[^()<>]*>)*>)?\s*\(',
  );

  String withoutAnnotations(String header) {
    var h = header.trimLeft();
    while (h.startsWith('@')) {
      final name = RegExp(r'^@[\w.]+').firstMatch(h)!;
      h = h.substring(name.end).trimLeft();
      if (h.startsWith('(')) {
        var depth = 0;
        var j = 0;
        for (; j < h.length; j++) {
          if (h[j] == '(') depth++;
          if (h[j] == ')' && --depth == 0) break;
        }
        h = h.substring(j + 1).trimLeft();
      }
    }
    return h.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void classify(String rawHeader, {required bool initializer}) {
    final header = withoutAnnotations(rawHeader);
    if (header.isEmpty || directive.hasMatch(header)) return;
    final type = typeHeader.firstMatch(header);
    if (type != null) {
      for (var g = 1; g <= typeKinds.length; g++) {
        final name = type.group(g);
        if (name != null) {
          found.add((name: name, kind: typeKinds[g - 1]));
          return;
        }
      }
    }
    if (initializer) return; // a variable
    // The parameter list is the first `name(` at bracket depth 0 that is not
    // a function type — a record return type opens with a parenthesis too.
    RegExpMatch? call;
    for (final m in parameterList.allMatches(header)) {
      final before = header.substring(0, m.start);
      final depth =
          '('.allMatches(before).length - ')'.allMatches(before).length;
      if (depth == 0 && m.group(1) != 'Function') {
        call = m;
        break;
      }
    }
    final signature = call == null
        ? header
        : header.substring(0, call.start + call.group(1)!.length);
    final asAccessor = accessor.firstMatch(signature);
    if (asAccessor != null) {
      found.add((
        name: asAccessor.group(2)!,
        kind: asAccessor.group(1) == 'get' ? 'getter' : 'setter',
      ));
      return;
    }
    if (call != null) found.add((name: call.group(1)!, kind: 'function'));
  }

  final header = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"') {
      final end = skipString(i);
      header.write(s.substring(i, end));
      i = end;
    } else if (c == '(' || c == '[') {
      final end = skipBalanced(i);
      header.write(s.substring(i, end));
      i = end;
    } else if (c == '{') {
      classify(header.toString(), initializer: false);
      header.clear();
      i = skipBalanced(i);
    } else if (c == ';') {
      classify(header.toString(), initializer: false);
      header.clear();
      i++;
    } else if (s.startsWith('=>', i)) {
      classify(header.toString(), initializer: false);
      header.clear();
      i = skipToSemicolon(i + 2);
    } else if (c == '=') {
      classify(header.toString(), initializer: true);
      header.clear();
      i = skipToSemicolon(i + 1);
    } else {
      header.write(c);
      i++;
    }
  }
  return found;
}

/// The text between the parenthesis that ends at [open] and its match.
///
/// Counts parentheses and steps over string literals, so a `)` inside a path
/// does not end the call early. Returns what is left of the source when the
/// call never closes — a syntax error is the analyzer's to report.
String callArgumentsFrom(String source, int open) {
  var depth = 1;
  var i = open;
  while (i < source.length && depth > 0) {
    final c = source[i];
    if (c == "'" || c == '"') {
      i++;
      while (i < source.length && source[i] != c) {
        if (source[i] == r'\') i++;
        i++;
      }
    } else if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
    }
    i++;
  }
  return source.substring(open, i > source.length ? source.length : i);
}
