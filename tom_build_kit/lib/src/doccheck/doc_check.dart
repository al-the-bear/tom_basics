/// The per-package documentation check behind `buildkit :doccheck`: the
/// documents `_copilot_guidelines/component_module_readme_example.md` and
/// `documentation_guidelines.md` ask every package to carry, and the README
/// sections both of them name.
///
/// **The checks** (`checks:` in `buildkit_master.yaml` picks them; default
/// all):
///
/// | Check | Holds when |
/// | ----- | ---------- |
/// | `readme` | `README.md` exists |
/// | `attribution` | a blockquote sits between the README's title and its first `##` section |
/// | `readme-sections` | every required section has a heading (level 2 to 4) whose text contains its words |
/// | `changelog` | `CHANGELOG.md` exists |
/// | `example` | `example/` holds a `.dart` file |
/// | `doc` | `doc/` holds a `.md` file |
/// | `guidelines-index` | a `_copilot_guidelines/` folder, where there is one, has `index.md` |
///
/// The required sections default to the ones both guidelines name — Features,
/// Installation, Quick start, Documentation (which `Further documentation`
/// satisfies) — and are matched by their words, spaces and hyphens aside
/// (`Quick-start`, `Quickstart`), in any case.
///
/// **Opting out** is per package, in its `buildkit.yaml`, and always with a
/// reason: `doccheck: skip: <reason>` leaves the package out;
/// `doccheck: exclude: {<check>: <reason>}` drops single checks; `readme-sections:`
/// replaces the list for the package. An unknown check name or an empty
/// reason is a configuration error, never an opt-out.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart' show TomBuildConfig;

/// The checks, in the order they are reported.
const kDocChecks = [
  'readme',
  'attribution',
  'readme-sections',
  'changelog',
  'example',
  'doc',
  'guidelines-index',
];

/// The README sections required when no configuration names others.
const kDefaultReadmeSections = [
  'Features',
  'Installation',
  'Quick start',
  'Documentation',
];

/// What applies to one package: the workspace's checks and sections with
/// the package's opt-outs.
class DocCheckConfig {
  /// The checks that apply before the package's exclusions.
  final List<String> checks;

  /// The README sections required.
  final List<String> readmeSections;

  /// Why the whole package is left out, or null.
  final String? skip;

  /// Checks the package drops, with the reason for each.
  final Map<String, String> exclude;

  /// What is wrong with the configuration (an unknown check, an empty
  /// reason); a package with errors fails whatever its documents.
  final List<String> errors;

  const DocCheckConfig({
    this.checks = kDocChecks,
    this.readmeSections = kDefaultReadmeSections,
    this.skip,
    this.exclude = const {},
    this.errors = const [],
  });

  /// The `doccheck:` sections of `buildkit_master.yaml` in [workspaceRoot]
  /// and of the package's `buildkit.yaml` in [packageDir], merged.
  static DocCheckConfig load(String packageDir, {String? workspaceRoot}) {
    final errors = <String>[];
    final master = workspaceRoot == null
        ? null
        : TomBuildConfig.loadMaster(
            dir: workspaceRoot,
            toolKey: 'doccheck',
          )?.toolOptions;
    final project = TomBuildConfig.load(
      dir: packageDir,
      toolKey: 'doccheck',
    )?.toolOptions;

    List<String>? strings(Object? value, String where) {
      if (value == null) return null;
      if (value is List) return [for (final v in value) '$v'];
      errors.add('$where must be a list');
      return null;
    }

    final checks =
        strings(master?['checks'], 'buildkit_master.yaml doccheck.checks') ??
        kDocChecks;
    for (final c in checks) {
      if (!kDocChecks.contains(c)) {
        errors.add(
          'buildkit_master.yaml doccheck.checks: unknown check "$c" '
          '(${kDocChecks.join(', ')})',
        );
      }
    }
    final sections =
        strings(
          project?['readme-sections'],
          'buildkit.yaml doccheck.readme-sections',
        ) ??
        strings(
          master?['readme-sections'],
          'buildkit_master.yaml doccheck.readme-sections',
        ) ??
        kDefaultReadmeSections;

    String? skip;
    final skipValue = project?['skip'];
    if (skipValue != null) {
      skip = '$skipValue'.trim();
      if (skip.isEmpty || skipValue is bool) {
        errors.add(
          'buildkit.yaml doccheck.skip needs the reason, not "$skipValue"',
        );
        skip = null;
      }
    }

    final exclude = <String, String>{};
    final excludeValue = project?['exclude'];
    if (excludeValue is Map) {
      excludeValue.forEach((key, reason) {
        final check = '$key';
        final why = reason == null ? '' : '$reason'.trim();
        if (!kDocChecks.contains(check)) {
          errors.add(
            'buildkit.yaml doccheck.exclude: unknown check "$check" '
            '(${kDocChecks.join(', ')})',
          );
        } else if (why.isEmpty || reason is bool) {
          errors.add('buildkit.yaml doccheck.exclude.$check needs the reason');
        } else {
          exclude[check] = why;
        }
      });
    } else if (excludeValue != null) {
      errors.add('buildkit.yaml doccheck.exclude must map checks to reasons');
    }

    return DocCheckConfig(
      checks: [
        for (final c in kDocChecks)
          if (checks.contains(c)) c,
      ],
      readmeSections: sections,
      skip: skip,
      exclude: exclude,
      errors: errors,
    );
  }
}

/// One document the package lacks, or a section its README lacks.
class DocGap {
  /// The check that found it.
  final String check;

  /// What is missing, as a sentence fragment (`no CHANGELOG.md`).
  final String message;

  const DocGap(this.check, this.message);

  @override
  String toString() => '$check: $message';
}

/// The gaps of one package, and the checks it was spared.
class DocCheckReport {
  final List<DocGap> gaps;

  /// The checks run.
  final List<String> checked;

  /// Checks the package dropped, with their reasons.
  final Map<String, String> excluded;

  const DocCheckReport({
    required this.gaps,
    required this.checked,
    required this.excluded,
  });

  bool get complete => gaps.isEmpty;
}

/// Checks the package at [packageDir] against [config]; [config.skip] and
/// [config.errors] are the caller's to act on first.
DocCheckReport checkPackageDocs(String packageDir, DocCheckConfig config) {
  final run = [
    for (final c in config.checks)
      if (!config.exclude.containsKey(c)) c,
  ];
  final gaps = <DocGap>[];
  final readme = File(p.join(packageDir, 'README.md'));
  final readmeText = readme.existsSync() ? readme.readAsStringSync() : null;

  for (final check in run) {
    switch (check) {
      case 'readme':
        if (readmeText == null) {
          gaps.add(const DocGap('readme', 'no README.md'));
        }
      case 'attribution':
        if (readmeText != null && !_hasAttribution(readmeText)) {
          gaps.add(
            const DocGap(
              'attribution',
              'README.md has no attribution blockquote under its title',
            ),
          );
        }
      case 'readme-sections':
        if (readmeText == null) break;
        final headings = _headings(readmeText);
        for (final section in config.readmeSections) {
          final words = _normalize(section);
          if (!headings.any((h) => _normalize(h).contains(words))) {
            gaps.add(
              DocGap('readme-sections', 'README.md has no "$section" section'),
            );
          }
        }
      case 'changelog':
        if (!File(p.join(packageDir, 'CHANGELOG.md')).existsSync()) {
          gaps.add(const DocGap('changelog', 'no CHANGELOG.md'));
        }
      case 'example':
        if (!_holds(p.join(packageDir, 'example'), '.dart')) {
          gaps.add(const DocGap('example', 'no example/ with a .dart file'));
        }
      case 'doc':
        if (!_holds(p.join(packageDir, 'doc'), '.md')) {
          gaps.add(const DocGap('doc', 'no user documentation (doc/*.md)'));
        }
      case 'guidelines-index':
        final guidelines = Directory(p.join(packageDir, '_copilot_guidelines'));
        if (guidelines.existsSync() &&
            !File(p.join(guidelines.path, 'index.md')).existsSync()) {
          gaps.add(
            const DocGap(
              'guidelines-index',
              '_copilot_guidelines/ has no index.md',
            ),
          );
        }
    }
  }
  return DocCheckReport(
    gaps: gaps,
    checked: run,
    excluded: {
      for (final c in config.checks)
        if (config.exclude.containsKey(c)) c: config.exclude[c]!,
    },
  );
}

/// The README's headings of level 2 to 4, outside fenced code.
List<String> _headings(String markdown) {
  final headings = <String>[];
  var fence = false;
  for (final line in markdown.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      fence = !fence;
      continue;
    }
    if (fence) continue;
    final m = RegExp(r'^#{2,4}\s+(.+)$').firstMatch(line);
    if (m != null) headings.add(m.group(1)!);
  }
  return headings;
}

/// Lower case, letters and digits only: `Quick-start` and `Quick start`
/// read alike.
String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Whether a `>` blockquote sits between the first `# ` title and the first
/// `## ` section.
bool _hasAttribution(String markdown) {
  var afterTitle = false;
  for (final line in markdown.split('\n')) {
    if (line.startsWith('# ')) {
      afterTitle = true;
      continue;
    }
    if (line.startsWith('## ')) return false;
    if (afterTitle && line.trimLeft().startsWith('>')) return true;
  }
  return false;
}

/// Whether [dir] holds a file ending in [extension], `.dart_tool` and
/// `build` aside.
bool _holds(String dir, String extension) {
  final d = Directory(dir);
  if (!d.existsSync()) return false;
  for (final entity in d.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith(extension)) continue;
    final parts = p.split(p.relative(entity.path, from: dir));
    if (parts.contains('.dart_tool') || parts.contains('build')) continue;
    return true;
  }
  return false;
}
