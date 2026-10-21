/// What a seam audit reports, and the command that runs a list of them.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// One boundary crossing, named by the seam it belongs to.
class SeamViolation {
  const SeamViolation(this.seam, this.message);

  /// The seam identifier used in test names and output (`S26`, `TEST-ROOT`,
  /// …).
  final String seam;
  final String message;

  @override
  String toString() => '[$seam] $message';
}

/// One audit a seam command runs: its label and the walk, given the
/// repository root and the workspace root around it.
typedef SeamAudit = ({
  String label,
  List<SeamViolation> Function(String repositoryRoot, String workspaceRoot) run,
});

/// Runs [audits] in order against [repositoryRoot] and [workspaceRoot] and
/// prints one line per audit to [out] — `ok    <label>`, or `FAIL  <label>`
/// with each violation under it — then [holds] when nothing crossed a
/// boundary. With [quiet], passing audits and the roots are not printed.
///
/// Returns the exit code a command ends with: 0 when every audit holds, 1
/// when at least one boundary is crossed (the count goes to [err]).
int runSeamAudits({
  required List<SeamAudit> audits,
  required String repositoryRoot,
  required String workspaceRoot,
  required String holds,
  bool quiet = false,
  StringSink? out,
  StringSink? err,
}) {
  final o = out ?? stdout;
  final e = err ?? stderr;
  if (!quiet) {
    o
      ..writeln('repository root: $repositoryRoot')
      ..writeln('workspace root:  $workspaceRoot')
      ..writeln();
  }
  var failed = 0;
  for (final audit in audits) {
    final violations = audit.run(repositoryRoot, workspaceRoot);
    failed += violations.length;
    if (violations.isEmpty) {
      if (!quiet) o.writeln('ok    ${audit.label}');
      continue;
    }
    o.writeln('FAIL  ${audit.label}');
    for (final violation in violations) {
      o.writeln('        ${violation.message}');
    }
  }
  if (failed > 0) {
    e.writeln('\n$failed package-boundary violation(s).');
    return 1;
  }
  if (!quiet) o.writeln('\n$holds');
  return 0;
}

/// The workspace: the nearest ancestor of [from] holding a `.tom_metadata`
/// directory, which is what makes it the workspace.
String resolveWorkspaceRoot(String from) {
  var dir = p.normalize(p.absolute(from));
  while (!Directory(p.join(dir, '.tom_metadata')).existsSync()) {
    final parent = p.dirname(dir);
    if (parent == dir) {
      throw StateError('no .tom_metadata above $from');
    }
    dir = parent;
  }
  return dir;
}

/// The repository: the nearest ancestor of [from] holding a
/// `tom_repository.yaml`.
String resolveRepositoryRoot(String from) {
  var dir = p.normalize(p.absolute(from));
  while (!File(p.join(dir, 'tom_repository.yaml')).existsSync()) {
    final parent = p.dirname(dir);
    if (parent == dir) {
      throw StateError('no tom_repository.yaml above $from');
    }
    dir = parent;
  }
  return dir;
}
