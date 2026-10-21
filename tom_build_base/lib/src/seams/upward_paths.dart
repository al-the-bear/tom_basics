/// Finding where a source derives a real directory by climbing a fixed
/// number of levels (`Directory('..')`, a `join` with an upward segment,
/// `.parent` off the working directory).
///
/// A count is right at one depth. What a test reaches for up there is usually
/// optional, so a wrong root is not an error but a skip whose stated reason is
/// untrue — the shape [upwardPathDerivations] reports, so a rule can ban it.
library;

import 'dart_source.dart';

/// One place a source derives a directory by climbing.
class UpwardDerivation {
  const UpwardDerivation(this.line, this.text);

  /// One-based.
  final int line;
  final String text;
}

/// A quoted literal that climbs: `..` alone, or as a path segment.
final _climbingLiteral = RegExp(
  r'''r?(['"])(?:\.\.|\.\./(?:(?!\1).)*|(?:(?!\1).)*/\.\.(?:/(?:(?!\1).)*)?)\1''',
);

/// The calls whose argument is a path on this machine.
final _pathCall = RegExp(
  r'\b(?:File|Directory|Link|join|joinAll|normalize|canonicalize|absolute)'
  r'\s*\(',
);

/// Climbing from the working directory without a literal at all.
final _parentOfCurrent = RegExp(
  r'Directory\s*\.\s*current(?:\s*\.\s*absolute)?\s*\.\s*parent\b',
);

/// An interpolated working directory with a climb after it.
final _interpolatedClimb = RegExp(
  r'''\$\{?\s*Directory\.current[^'"\n]*/\.\.(?:['"/])''',
);

final _directiveLine = RegExp(r'^\s*(?:import|export|part)\s');

/// Every place [source] derives a real directory by climbing a fixed number
/// of levels.
///
/// **What is matched is the shape, not the characters.** The two dots appear
/// legitimately all over a test suite — in a directive, which the compiler
/// resolves against the file; in a locator inside a document under test,
/// which is data; in a cascade and a spread. The defect is narrower: a path
/// *on this machine*, built by counting. So a finding is a climbing literal
/// **inside the arguments of a call that takes a path** (`File`, `Directory`,
/// `join`, `normalize` and their kin), or a climb from `Directory.current` by
/// `.parent` or by interpolation.
///
/// Comments are stripped first, so a doc comment may still spell the rule out.
List<UpwardDerivation> upwardPathDerivations(String source) {
  final stripped = stripDartComments(source);
  final found = <int, String>{};

  int lineOf(int offset) =>
      '\n'.allMatches(stripped.substring(0, offset)).length + 1;
  String textOf(int line) => stripped.split('\n')[line - 1].trim();

  bool inDirective(int offset) {
    final start = stripped.lastIndexOf('\n', offset == 0 ? 0 : offset - 1) + 1;
    // A directive may wrap, so look back to the statement's first line.
    final statementStart = stripped.lastIndexOf(';', offset) + 1;
    final head = stripped.substring(
      statementStart < start ? statementStart : start,
      offset,
    );
    return _directiveLine.hasMatch(
      head.trimLeft().isEmpty
          ? stripped.substring(start, offset)
          : '${head.trimLeft()} ',
    );
  }

  for (final call in _pathCall.allMatches(stripped)) {
    final arguments = callArgumentsFrom(stripped, call.end);
    for (final literal in _climbingLiteral.allMatches(arguments)) {
      final line = lineOf(call.end + literal.start);
      found[line] = textOf(line);
    }
  }
  for (final pattern in [_parentOfCurrent, _interpolatedClimb]) {
    for (final match in pattern.allMatches(stripped)) {
      if (inDirective(match.start)) continue;
      final line = lineOf(match.start);
      found[line] = textOf(line);
    }
  }

  final lines = found.keys.toList()..sort();
  return [for (final line in lines) UpwardDerivation(line, found[line]!)];
}
