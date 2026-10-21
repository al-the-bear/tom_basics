/// A boundary audit on `package:tom_build_base/seams.dart`: this package's
/// two entry points `ci.dart` and `seams.dart` must not reach `dcli`, and no
/// file under their source trees imports it.
///
/// ```sh
/// dart run example/seams_example.dart          # from tom_build_base
/// ```
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/seams.dart';

const rules = [
  EntryPointRule(
    package: 'tom_build_base',
    entryPoint: 'lib/seams.dart',
    banned: {'dcli'},
  ),
  EntryPointRule(
    package: 'tom_build_base',
    entryPoint: 'lib/ci.dart',
    banned: {'dcli'},
  ),
];

List<SeamViolation> noDcliUnder(String root) => [
  for (final tree in ['ci', 'seams'])
    for (final file
        in packageImportsUnder(
              p.join(root, 'tom_build_base', 'lib', 'src', tree),
            )['dcli'] ??
            const <String>[])
      SeamViolation('IMPORTS', '$file imports package:dcli'),
];

void main() {
  // The audit's root is the directory holding the package, so a rule names
  // the package the way a repository's rules name theirs.
  final root = p.dirname(Directory.current.absolute.path);
  exitCode = runSeamAudits(
    audits: [
      (
        label: 'ENTRY the entry points reach no dcli',
        run: (r, _) => auditEntryPointRules(r, rules, seam: 'ENTRY'),
      ),
      (
        label: 'IMPORTS no file of ci or seams imports dcli',
        run: (r, _) => noDcliUnder(r),
      ),
    ],
    repositoryRoot: root,
    workspaceRoot: root,
    holds: 'Both boundaries hold.',
  );
}
