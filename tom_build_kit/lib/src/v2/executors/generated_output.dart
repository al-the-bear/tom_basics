/// Where a buildkit command may write what it generates (API docs, a
/// reference PDF): a folder of the package, never inside `doc/`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Why [output] (relative to the [base] folder — the package, or the
/// workspace root) may not take a command's generated files, or null: it
/// must stay inside [base], not be [base] itself, and not lie in a `doc/`
/// folder, which holds hand-authored documents only. [defaultDir] is named
/// in the refusal.
String? refuseGeneratedOutput(
  String output, {
  required String defaultDir,
  String base = 'package',
}) {
  if (p.isAbsolute(output)) {
    return '--output $output: give a folder relative to the $base';
  }
  final parts = p.split(p.normalize(output));
  if (parts.first == '..' || parts.first == '.') {
    return '--output $output: the folder must lie inside the $base';
  }
  if (parts.contains('doc')) {
    return '--output $output is in a doc/ folder, which holds hand-authored '
        'documents only; the default is $defaultDir';
  }
  return null;
}

/// Whether git would track [file]: it lies in a git work tree of
/// [packageDir] and no `.gitignore` covers it. Generated output should be
/// ignored; a command says so when it is not.
Future<bool> trackedByGit(String packageDir, String file) async {
  final r = await Process.run(
    'git',
    ['check-ignore', '-q', file],
    workingDirectory: packageDir,
    runInShell: Platform.isWindows,
  );
  // 0: ignored; 1: not ignored; 128: not a git work tree.
  return r.exitCode == 1;
}
