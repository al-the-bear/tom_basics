/// Entry-point confinement: what an entry point may not reach, and what it
/// must.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'import_graph.dart';
import 'seam_audit.dart';

/// What a single entry point may **not** reach.
class EntryPointRule {
  const EntryPointRule({
    required this.package,
    required this.entryPoint,
    required this.banned,
    this.bannedUris = const {},
    this.required = const {},
  });

  final String package;

  /// Path of the entry point relative to the package directory.
  final String entryPoint;

  /// Packages the closure must not contain.
  final Set<String> banned;

  /// Individual library URIs the closure must not contain, where the *package*
  /// is legitimate but one of its entry points is not.
  ///
  /// [banned] cannot express this, because it collapses a URI to its package
  /// name: a package may be a required dependency while its default barrel
  /// reaches `dart:io`, and the closure walk stops at the package boundary, so
  /// a web breakage through that barrel would be invisible to a `dart:io` ban.
  /// dart2js **accepts** `dart:io`, linking stubs that throw when called, so
  /// the breakage would arrive as a crash in a browser rather than a failed
  /// build.
  final Set<String> bannedUris;

  /// Packages the closure **must** contain.
  ///
  /// This half is not decoration. Deleting a feature outright satisfies every
  /// ban perfectly, so a rule that only bans is a rule that passes hardest
  /// when the feature is gone.
  final Set<String> required;
}

/// Checks every rule in [rules] against the packages under [root], reporting
/// each crossing under [seam].
///
/// A declared entry point that does not exist is a violation rather than a
/// pass: a renamed or deleted entry point must fail here, not pass by having
/// nothing to walk.
List<SeamViolation> auditEntryPointRules(
  String root,
  List<EntryPointRule> rules, {
  required String seam,
}) {
  final violations = <SeamViolation>[];
  for (final rule in rules) {
    final file = p.join(root, rule.package, rule.entryPoint);
    if (!File(file).existsSync()) {
      // A renamed or deleted entry point must fail here rather than pass by
      // having nothing to walk.
      violations.add(
        SeamViolation(
          seam,
          '${rule.package}: declared entry point ${rule.entryPoint} does not '
          'exist — the rule cannot be checked, so it is a violation.',
        ),
      );
      continue;
    }
    final uris = externalImportsOf(file);
    for (final banned in rule.bannedUris) {
      if (uris.contains(banned)) {
        violations.add(
          SeamViolation(
            seam,
            '${rule.package}/${rule.entryPoint} reaches "$banned". The package '
            'is permitted; that entry point of it is not.',
          ),
        );
      }
    }
    final names = reachableNamesOf(file);
    for (final banned in rule.banned) {
      if (names.contains(banned)) {
        violations.add(
          SeamViolation(
            seam,
            '${rule.package}/${rule.entryPoint} reaches "$banned", which that '
            'entry point must not link.',
          ),
        );
      }
    }
    for (final needed in rule.required) {
      if (!names.contains(needed)) {
        violations.add(
          SeamViolation(
            seam,
            '${rule.package}/${rule.entryPoint} no longer reaches "$needed" — '
            'the seam it exists to expose is gone, so the matching ban '
            'elsewhere now passes vacuously.',
          ),
        );
      }
    }
  }
  return violations;
}
