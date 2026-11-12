/// The context-boundary check of a modular-monolith package: several bounded
/// contexts as libraries of one package, kept apart by rules in the package's
/// `buildkit.yaml` instead of by convention.
///
/// ```yaml
/// boundaries:
///   tests: true                       # also check test/ (default false)
///   contexts:
///     - name: billing
///       libraries: [src/billing/**]   # globs under lib/
///       public: [src/billing/billing.dart]
///       dependsOn: [identity]
///       tests: [billing/**]           # globs under test/
///     - name: identity
///       libraries: [src/identity/**]
///       public: [src/identity/identity.dart]
/// ```
///
/// A library matched by no context is shared: anyone may import it. A library
/// of context A may import a library of another context B only when A lists B
/// in `dependsOn` and the library is one of B's `public` entries. Imports and
/// exports both count; a `part` file belongs to its library.
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dart_directives.dart';

/// The `buildkit.yaml` key the rules are read from.
const kBoundariesSection = 'boundaries';

/// One bounded context of a [ContextBoundaryRules].
class BoundedContext {
  /// The context's name, unique in the rules.
  final String name;

  /// Globs under `lib/` of the libraries forming the context.
  final List<String> libraries;

  /// Globs under `lib/` of its public entry libraries.
  final List<String> public;

  /// The contexts its libraries may import from.
  final List<String> dependsOn;

  /// Globs under `test/` of its tests (checked when the rules include tests).
  final List<String> tests;

  /// Creates a context.
  const BoundedContext({
    required this.name,
    required this.libraries,
    this.public = const [],
    this.dependsOn = const [],
    this.tests = const [],
  });
}

/// One finding of a [BoundaryReport]: a broken boundary or a broken rule.
class BoundaryFinding {
  /// `undeclared-dependency`, `internal-import` (violations) or
  /// `invalid-section`, `duplicate-context`, `overlap`, `rotted-glob`,
  /// `rotted-public`, `unknown-dependency` (rule errors).
  final String kind;

  /// What is wrong, in a sentence.
  final String message;

  /// The importing file, package-relative (`lib/src/a.dart`).
  final String? file;

  /// The 1-based line of the import in [file].
  final int? line;

  /// The imported library, package-relative.
  final String? imported;

  /// The context the finding is about.
  final String? context;

  /// Creates a finding.
  const BoundaryFinding({
    required this.kind,
    required this.message,
    this.file,
    this.line,
    this.imported,
    this.context,
  });

  /// The finding as JSON.
  Map<String, Object?> toJson() => {
    'kind': kind,
    'message': message,
    if (file != null) 'file': file,
    if (line != null) 'line': line,
    if (imported != null) 'imported': imported,
    if (context != null) 'context': context,
  };

  @override
  String toString() {
    final where = file == null ? '' : '$file${line == null ? '' : ':$line'}: ';
    return '$where[$kind] $message';
  }
}

/// The rules of a package, read from its `buildkit.yaml`.
class ContextBoundaryRules {
  /// The contexts in the order the file lists them.
  final List<BoundedContext> contexts;

  /// Whether `test/` is checked too.
  final bool includeTests;

  /// Problems in the section itself (`invalid-section`, `duplicate-context`).
  final List<BoundaryFinding> errors;

  /// Creates rules.
  const ContextBoundaryRules({
    required this.contexts,
    this.includeTests = false,
    this.errors = const [],
  });

  /// The rules in [section] (the value of the `boundaries:` key).
  factory ContextBoundaryRules.fromYaml(Object? section) {
    final errors = <BoundaryFinding>[];
    BoundaryFinding invalid(String message) =>
        BoundaryFinding(kind: 'invalid-section', message: message);

    if (section is! Map) {
      return ContextBoundaryRules(
        contexts: const [],
        errors: [invalid('`$kBoundariesSection:` must be a map')],
      );
    }
    final rawContexts = section['contexts'];
    if (rawContexts is! List || rawContexts.isEmpty) {
      errors.add(invalid('`contexts:` must be a non-empty list'));
    }
    final contexts = <BoundedContext>[];
    final names = <String>{};
    for (final (index, raw)
        in (rawContexts is List ? rawContexts : []).indexed) {
      if (raw is! Map || raw['name'] is! String) {
        errors.add(invalid('context #${index + 1} has no `name:`'));
        continue;
      }
      final name = raw['name'] as String;
      if (!names.add(name)) {
        errors.add(
          BoundaryFinding(
            kind: 'duplicate-context',
            message: 'context `$name` is defined twice',
            context: name,
          ),
        );
        continue;
      }
      List<String> strings(String key) {
        final value = raw[key];
        if (value == null) return const [];
        if (value is String) return [value];
        if (value is List && value.every((e) => e is String)) {
          return value.cast<String>();
        }
        errors.add(
          invalid('context `$name`: `$key:` must be a list of strings'),
        );
        return const [];
      }

      final libraries = strings('libraries');
      if (libraries.isEmpty) {
        errors.add(invalid('context `$name` has no `libraries:`'));
      }
      contexts.add(
        BoundedContext(
          name: name,
          libraries: libraries,
          public: strings('public'),
          dependsOn: strings('dependsOn'),
          tests: strings('tests'),
        ),
      );
    }
    return ContextBoundaryRules(
      contexts: contexts,
      includeTests: section['tests'] == true,
      errors: errors,
    );
  }

  /// The rules of the package at [projectPath], or null when its
  /// `buildkit.yaml` has no `boundaries:` section (the check is then not
  /// measured, never clean).
  static ContextBoundaryRules? load(String projectPath) {
    final file = File(p.join(projectPath, 'buildkit.yaml'));
    if (!file.existsSync()) return null;
    final Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      return ContextBoundaryRules(
        contexts: const [],
        errors: [
          BoundaryFinding(
            kind: 'invalid-section',
            message: 'buildkit.yaml does not parse: ${e.message}',
          ),
        ],
      );
    }
    if (yaml is! Map || !yaml.containsKey(kBoundariesSection)) return null;
    return ContextBoundaryRules.fromYaml(yaml[kBoundariesSection]);
  }
}

/// The outcome of [checkContextBoundaries].
class BoundaryReport {
  /// The package checked.
  final String projectPath;

  /// False when the package has no rules: nothing was checked.
  final bool measured;

  /// Imports that cross a boundary they may not.
  final List<BoundaryFinding> violations;

  /// Problems in the rules: invalid, rotted or overlapping entries.
  final List<BoundaryFinding> ruleErrors;

  /// How many libraries (part files not counted) were read.
  final int librariesChecked;

  /// How many imports and exports of the package's own libraries were checked.
  final int importsChecked;

  /// Creates a report.
  const BoundaryReport({
    required this.projectPath,
    required this.measured,
    this.violations = const [],
    this.ruleErrors = const [],
    this.librariesChecked = 0,
    this.importsChecked = 0,
  });

  /// Measured, and neither a violation nor a rule error.
  bool get clean => measured && violations.isEmpty && ruleErrors.isEmpty;

  /// `clean`, `violations` or `not-measured`.
  String get verdict => !measured
      ? 'not-measured'
      : clean
      ? 'clean'
      : 'violations';

  /// The report as JSON.
  Map<String, Object?> toJson() => {
    'project': projectPath,
    'verdict': verdict,
    'librariesChecked': librariesChecked,
    'importsChecked': importsChecked,
    'violations': [for (final f in violations) f.toJson()],
    'ruleErrors': [for (final f in ruleErrors) f.toJson()],
  };
}

/// Checks the package at [projectPath] against its `boundaries:` rules
/// ([rules] when given, else read from its `buildkit.yaml`). [includeTests]
/// overrides the rules' `tests:` flag.
BoundaryReport checkContextBoundaries(
  String projectPath, {
  ContextBoundaryRules? rules,
  bool? includeTests,
}) {
  final effective = rules ?? ContextBoundaryRules.load(projectPath);
  if (effective == null) {
    return BoundaryReport(projectPath: projectPath, measured: false);
  }
  return _Checker(
    projectPath,
    effective,
    includeTests ?? effective.includeTests,
  ).run();
}

class _Checker {
  final String root;
  final ContextBoundaryRules rules;
  final bool includeTests;
  final violations = <BoundaryFinding>[];
  final ruleErrors = <BoundaryFinding>[];

  _Checker(this.root, this.rules, this.includeTests);

  static final _posix = p.Context(style: p.Style.posix);

  /// Package-relative posix paths of the Dart files under [dir].
  List<String> _dartFiles(String dir) {
    final directory = Directory(p.join(root, dir));
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('.dart'))
          _posix.joinAll(p.split(p.relative(entity.path, from: root))),
    ]..sort();
  }

  String? _packageName() {
    final file = File(p.join(root, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    try {
      final yaml = loadYaml(file.readAsStringSync());
      return yaml is Map ? yaml['name'] as String? : null;
    } on YamlException {
      return null;
    }
  }

  BoundaryReport run() {
    ruleErrors.addAll(rules.errors);
    final libFiles = _dartFiles('lib');
    final testFiles = includeTests ? _dartFiles('test') : const <String>[];
    final directives = <String, List<DartDirective>>{
      for (final f in [...libFiles, ...testFiles])
        f: scanDartDirectives(File(p.join(root, f)).readAsStringSync()),
    };

    // part file -> its library
    final ownerOf = <String, String>{};
    for (final entry in directives.entries) {
      for (final d in entry.value) {
        if (d.kind != DartDirectiveKind.part) continue;
        for (final uri in d.uris) {
          final target = _resolve(entry.key, uri, null);
          if (target != null) ownerOf[target] = entry.key;
        }
      }
    }
    String libraryOf(String file) => ownerOf[file] ?? file;
    final libraries = libFiles.where((f) => !ownerOf.containsKey(f)).toList();

    final contextOf = _assignContexts(libraries, testFiles, ownerOf);
    final publicOf = _publicEntries(libraries, contextOf);
    final byName = {for (final c in rules.contexts) c.name: c};
    for (final c in rules.contexts) {
      for (final dep in c.dependsOn) {
        if (!byName.containsKey(dep)) {
          ruleErrors.add(
            BoundaryFinding(
              kind: 'unknown-dependency',
              message:
                  'context `${c.name}` depends on `$dep`, which no '
                  'context is named',
              context: c.name,
            ),
          );
        }
      }
    }

    final packageName = _packageName();
    var importsChecked = 0;
    for (final entry in directives.entries) {
      final file = entry.key;
      final importer = contextOf[libraryOf(file)];
      for (final d in entry.value) {
        if (d.kind != DartDirectiveKind.import &&
            d.kind != DartDirectiveKind.export) {
          continue;
        }
        for (final uri in d.uris) {
          final target = _resolve(file, uri, packageName);
          if (target == null || !target.startsWith('lib/')) continue;
          importsChecked++;
          if (importer == null || importer == _overlap) continue;
          final owner = contextOf[target];
          if (owner == null || owner == _overlap || owner == importer) {
            continue;
          }
          final from = byName[importer]!;
          if (!from.dependsOn.contains(owner)) {
            violations.add(
              BoundaryFinding(
                kind: 'undeclared-dependency',
                message:
                    'context `$importer` may not depend on `$owner` '
                    '(not in its dependsOn)',
                file: file,
                line: d.line,
                imported: target,
                context: importer,
              ),
            );
          } else if (!(publicOf[owner] ?? const {}).contains(target)) {
            violations.add(
              BoundaryFinding(
                kind: 'internal-import',
                message:
                    '`$target` is internal to context `$owner`; import '
                    'one of its public entries',
                file: file,
                line: d.line,
                imported: target,
                context: importer,
              ),
            );
          }
        }
      }
    }

    return BoundaryReport(
      projectPath: root,
      measured: true,
      violations: violations,
      ruleErrors: ruleErrors,
      librariesChecked:
          libraries.length +
          testFiles.where((f) => !ownerOf.containsKey(f)).length,
      importsChecked: importsChecked,
    );
  }

  static const _overlap = '\u0000overlap';

  /// Library (and test) file -> context name; [_overlap] for a file two
  /// contexts claim. Records rotted globs and overlaps.
  Map<String, String> _assignContexts(
    List<String> libraries,
    List<String> testFiles,
    Map<String, String> ownerOf,
  ) {
    final contextOf = <String, String>{};
    void claim(String file, String context) {
      final existing = contextOf[file];
      if (existing == null) {
        contextOf[file] = context;
      } else if (existing != context && existing != _overlap) {
        ruleErrors.add(
          BoundaryFinding(
            kind: 'overlap',
            message:
                '`$file` is matched by contexts `$existing` and '
                '`$context`',
            file: file,
          ),
        );
        contextOf[file] = _overlap;
      }
    }

    for (final c in rules.contexts) {
      for (final pattern in c.libraries) {
        final glob = Glob(pattern, context: _posix);
        var matched = false;
        for (final lib in libraries) {
          if (glob.matches(lib.substring('lib/'.length))) {
            matched = true;
            claim(lib, c.name);
          }
        }
        if (!matched) {
          ruleErrors.add(
            BoundaryFinding(
              kind: 'rotted-glob',
              message:
                  'context `${c.name}`: `libraries: $pattern` matches '
                  'no library under lib/',
              context: c.name,
            ),
          );
        }
      }
      if (!includeTests) continue;
      for (final pattern in c.tests) {
        final glob = Glob(pattern, context: _posix);
        var matched = false;
        for (final test in testFiles) {
          if (ownerOf.containsKey(test)) continue;
          if (glob.matches(test.substring('test/'.length))) {
            matched = true;
            claim(test, c.name);
          }
        }
        if (!matched) {
          ruleErrors.add(
            BoundaryFinding(
              kind: 'rotted-glob',
              message:
                  'context `${c.name}`: `tests: $pattern` matches no '
                  'file under test/',
              context: c.name,
            ),
          );
        }
      }
    }
    return contextOf;
  }

  /// Context name -> its public entry libraries. Records public entries that
  /// match none of the context's own libraries.
  Map<String, Set<String>> _publicEntries(
    List<String> libraries,
    Map<String, String> contextOf,
  ) {
    final result = <String, Set<String>>{};
    for (final c in rules.contexts) {
      final entries = result[c.name] = <String>{};
      for (final pattern in c.public) {
        final glob = Glob(pattern, context: _posix);
        final matched = [
          for (final lib in libraries)
            if (contextOf[lib] == c.name &&
                glob.matches(lib.substring('lib/'.length)))
              lib,
        ];
        if (matched.isEmpty) {
          ruleErrors.add(
            BoundaryFinding(
              kind: 'rotted-public',
              message:
                  'context `${c.name}`: `public: $pattern` matches none '
                  'of its libraries',
              context: c.name,
            ),
          );
        }
        entries.addAll(matched);
      }
    }
    return result;
  }

  /// The package-relative path [uri] in [from] points to, or null for a URI
  /// outside the package (`dart:`, another package) or a missing file.
  String? _resolve(String from, String uri, String? packageName) {
    String? path;
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0 || packageName == null) return null;
      if (rest.substring(0, slash) != packageName) return null;
      path = 'lib/${rest.substring(slash + 1)}';
    } else if (uri.contains(':')) {
      return null;
    } else {
      path = _posix.normalize(_posix.join(_posix.dirname(from), uri));
    }
    if (path.startsWith('..')) return null;
    return File(p.join(root, path)).existsSync() ? path : null;
  }
}
