/// The unreferenced-export audit: every public symbol a package exports from
/// `lib/` — a top-level declaration behind one of its `lib/*.dart` entry
/// points, or a public member of such a type — that **no other `lib/` or
/// `bin/` file names** reaches a user through nothing.
///
/// A feature that only its tests build, a getter nothing reads, a setting
/// that is edited and saved and does nothing: each looks finished, and is
/// found by a person noticing, which is the detector that does not scale.
/// This is the one that does.
///
/// **What counts as a consumer.** A `lib/` file of any audited package or of
/// any package in a consumer repository, a `bin/` file of an audited package,
/// or the `lib/` of a runnable application kept as an audited package's
/// `example/` — anywhere **outside the symbol's own declaration**: another
/// file, or the declaring file beyond the declaration itself (for a member,
/// beyond the body of the type that holds it). A `bin/` entry point is a path
/// a person can reach, which is the criterion. The declaration's own span
/// does not count, because that is where the dead shape lives: a field read by
/// its own type's codec and getter and by nothing else is named three times
/// and consumed nowhere. The rest of the file does count — a catalog that
/// registers the functions declared beside it is how they are reached. A
/// README is not a consumer, a test is not a consumer, `example/` and `tool/`
/// are not consumers. A finding says whether a test names it, because "built
/// by tests and nowhere else" is the shape worth recognising at once.
///
/// **What counts as exported.** The names each `lib/*.dart` entry point puts
/// in its export namespace (`exportedDeclarationsOf`, with `show`/`hide`
/// applied), and for a class, mixin, enum, extension or extension type among
/// them, its public members: methods, getters, setters, fields and named
/// constructors. Not members marked `@override`, not operators, not
/// `toString`/`hashCode`/`==`/`noSuchMethod`, not enum constants (reached by
/// `values` as often as by name), and not an extension's own name, which no
/// call site writes.
///
/// **Naming is textual, deliberately.** A symbol is referenced when its name
/// appears as an identifier in a consumer, comments stripped, strings kept.
/// That over-approximates, and the direction of the error is the safe one:
/// the audit can miss a dead symbol with a common name, and never reports a
/// live one. Resolving references would need every package's analysis context
/// and would still not see a name reached through a generated bridge or a
/// reflection table.
///
/// **Test seams are declared where they are.** A member that exists so a
/// suite can drive or observe what production does internally is marked
/// `@visibleForTesting`. The audit accepts such a symbol **when a test names
/// it**, and reports it when none does: a seam nothing uses is dead code with
/// a better excuse.
///
/// **The allowlist.** A symbol unreferenced by design for any other reason is
/// listed with a reason. An entry that no longer matches a finding — the
/// symbol gained a consumer, or is gone — **fails the audit**, so the list
/// cannot outlive what it excuses. An entry naming a type covers its members.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/seams.dart'
    show
        PublicDeclaration,
        dartCodeWithoutComments,
        exportedDeclarationsOf,
        packagesIn;

/// A symbol excused from the audit, and why.
class AllowedUnreferencedExport {
  const AllowedUnreferencedExport(this.package, this.symbol, this.reason);

  /// The declaring package, e.g. `my_app`.
  final String package;

  /// `Name` for a top-level declaration, `Type.member` for a member.
  final String symbol;

  /// Why nothing in `lib/` names it and nothing should. Never empty.
  final String reason;

  @override
  String toString() => '$package $symbol — $reason';
}

/// One exported symbol the audit checked.
class ExportedSymbol {
  const ExportedSymbol({
    required this.package,
    required this.file,
    required this.line,
    required this.symbol,
    required this.kind,
    required this.namedInOwnFile,
    required this.usedWithinDeclaration,
    this.declaredTestSeam = false,
  });

  final String package;

  /// Absolute path of the declaring file.
  final String file;
  final int line;

  /// `Name` or `Type.member`.
  final String symbol;

  /// `class`, `function`, `getter`, `method`, `field`, `constructor`, …
  final String kind;

  /// Whether the declaring file names the symbol outside its own declaration
  /// — outside the body of the type that holds it, for a member.
  final bool namedInOwnFile;

  /// Whether the symbol is used **inside** its own declaration — by its own
  /// type's other members, for a member. An unreferenced symbol that is has
  /// the wrong visibility and becomes private; one that is not is deleted.
  final bool usedWithinDeclaration;

  /// Whether the declaration — or the type that holds it — is marked
  /// `@visibleForTesting`: a test seam, stated where it is.
  final bool declaredTestSeam;

  @override
  String toString() => '$package $symbol ($kind) at ${p.basename(file)}:$line';
}

/// One symbol nothing in `lib/` or `bin/` names.
class UnreferencedExport {
  const UnreferencedExport(this.symbol, {required this.namedByTests});

  final ExportedSymbol symbol;

  /// Whether some `test/` file names it — "built by tests and nowhere else".
  final bool namedByTests;

  /// What to do about it, as the runner prints it.
  String get verdict => symbol.declaredTestSeam
      ? 'a declared test seam (@visibleForTesting) that no test names: delete it'
      : namedByTests
      ? 'named by tests only: wire it if a spec requires it, else delete it, '
            'or mark it @visibleForTesting if it is a seam'
      : symbol.usedWithinDeclaration
      ? 'named nowhere outside its own declaration (make it private)'
      : 'named nowhere';

  @override
  String toString() => '$symbol — $verdict';
}

/// What one run concluded.
class UnreferencedExportReport {
  const UnreferencedExportReport({
    required this.unreferenced,
    required this.allowed,
    required this.stale,
    required this.checked,
    required this.consumerFiles,
    required this.testSeams,
  });

  /// Findings not excused by the allowlist, sorted by package, file, line.
  final List<UnreferencedExport> unreferenced;

  /// Allowlist entries that matched a finding, with the finding.
  final List<(AllowedUnreferencedExport, UnreferencedExport)> allowed;

  /// Allowlist entries that matched nothing: the symbol is referenced now,
  /// or no longer exists. Either way the entry is stale and fails the audit.
  final List<AllowedUnreferencedExport> stale;

  /// Every exported symbol the run checked, as `package symbol`.
  final List<String> checked;

  /// How many exported symbols were checked. Zero means the scan proved
  /// nothing, and the runner says so.
  int get symbolsChecked => checked.length;

  /// How many `lib/` and `bin/` files were read as consumers.
  final int consumerFiles;

  /// The `@visibleForTesting` symbols nothing in `lib/` names and some test
  /// does — accepted as declared seams, counted so a run says how many.
  final int testSeams;

  bool get holds => unreferenced.isEmpty && stale.isEmpty && symbolsChecked > 0;
}

/// Members that implement `Object` and are named by the language, not by a
/// consumer.
const _objectMembers = {'toString', 'hashCode', 'noSuchMethod', 'runtimeType'};

final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

/// Runs the audit over the packages directly under [root] whose name starts
/// with [packagePrefix], except those in [exclude].
///
/// Consumers are the `lib/` and `bin/` of every audited package, the `lib/`
/// of a runnable application kept as an audited package's `example/` (its own
/// pubspec, named with [packagePrefix]), and the `lib/` of every package
/// directly under each of [consumerRepositories] — code that uses the audited
/// packages without being audited itself. Tests are the audited packages'
/// `test/`.
UnreferencedExportReport auditUnreferencedExports({
  required String root,
  required String packagePrefix,
  Set<String> exclude = const {},
  List<String> consumerRepositories = const [],
  List<AllowedUnreferencedExport> allowlist = const [],
}) {
  final auditedPackages = [
    for (final pubspec in packagesIn(root))
      if (pubspec.name.startsWith(packagePrefix) &&
          !exclude.contains(pubspec.name))
        pubspec,
  ];
  final consumerRoots = <String>[
    for (final pubspec in auditedPackages) ...[
      p.join(pubspec.directory, 'lib'),
      p.join(pubspec.directory, 'bin'),
      for (final app in packagesIn(pubspec.directory))
        if (p.basename(app.directory) == 'example' &&
            app.name.startsWith(packagePrefix))
          p.join(app.directory, 'lib'),
    ],
    for (final repository in consumerRepositories)
      for (final pubspec in packagesIn(repository))
        p.join(pubspec.directory, 'lib'),
  ];
  final testRoots = [
    for (final pubspec in auditedPackages) p.join(pubspec.directory, 'test'),
  ];

  // name → the consumer files that contain it as an identifier.
  final namedIn = <String, Set<String>>{};
  var consumerFiles = 0;
  for (final file in _dartFilesUnder(consumerRoots)) {
    consumerFiles++;
    for (final name in _identifiersIn(file)) {
      namedIn.putIfAbsent(name, () => {}).add(file);
    }
  }
  final namedInTests = <String>{};
  for (final file in _dartFilesUnder(testRoots)) {
    namedInTests.addAll(_identifiersIn(file));
  }

  bool referenced(String name, String declaringFile) {
    final files = namedIn[name];
    if (files == null) return false;
    return files.any((f) => f != declaringFile);
  }

  final findings = <UnreferencedExport>[];
  final checked = <String>[];
  var testSeams = 0;
  for (final pubspec in auditedPackages) {
    final exported = <String, PublicDeclaration>{};
    for (final entryPoint in _entryPointsOf(pubspec.directory)) {
      for (final e in exportedDeclarationsOf(entryPoint).entries) {
        exported.putIfAbsent(e.key, () => e.value);
      }
    }
    final byFile = <String, List<PublicDeclaration>>{};
    for (final d in exported.values) {
      byFile.putIfAbsent(p.normalize(p.absolute(d.file)), () => []).add(d);
    }
    for (final entry in byFile.entries) {
      final file = entry.key;
      final wanted = {for (final d in entry.value) d.name};
      for (final symbol in _symbolsDeclaredIn(file, pubspec.name, wanted)) {
        checked.add('${pubspec.name} ${symbol.symbol}');
        final name = symbol.symbol.contains('.')
            ? symbol.symbol.substring(symbol.symbol.indexOf('.') + 1)
            : symbol.symbol;
        if (symbol.namedInOwnFile || referenced(name, file)) continue;
        final namedByTests = namedInTests.contains(name);
        if (symbol.declaredTestSeam && namedByTests) {
          testSeams++;
          continue;
        }
        findings.add(UnreferencedExport(symbol, namedByTests: namedByTests));
      }
    }
  }
  findings.sort((a, b) {
    final byPackage = a.symbol.package.compareTo(b.symbol.package);
    if (byPackage != 0) return byPackage;
    final byFile = a.symbol.file.compareTo(b.symbol.file);
    if (byFile != 0) return byFile;
    return a.symbol.line.compareTo(b.symbol.line);
  });

  final allowed = <(AllowedUnreferencedExport, UnreferencedExport)>[];
  final stale = <AllowedUnreferencedExport>[];
  final remaining = <UnreferencedExport>[];
  final matched = <UnreferencedExport>{};
  for (final entry in allowlist) {
    final hits = [
      for (final f in findings)
        if (f.symbol.package == entry.package &&
            (f.symbol.symbol == entry.symbol ||
                f.symbol.symbol.startsWith('${entry.symbol}.')))
          f,
    ];
    if (hits.isEmpty) {
      stale.add(entry);
    } else {
      for (final hit in hits) {
        allowed.add((entry, hit));
        matched.add(hit);
      }
    }
  }
  for (final finding in findings) {
    if (!matched.contains(finding)) remaining.add(finding);
  }

  return UnreferencedExportReport(
    unreferenced: remaining,
    allowed: allowed,
    stale: stale,
    checked: List.unmodifiable(checked),
    consumerFiles: consumerFiles,
    testSeams: testSeams,
  );
}

/// The `lib/*.dart` files of [packageDir]: its public entry points.
List<String> _entryPointsOf(String packageDir) {
  final lib = Directory(p.join(packageDir, 'lib'));
  if (!lib.existsSync()) return const [];
  return [
    for (final entity in lib.listSync().whereType<File>())
      if (entity.path.endsWith('.dart')) entity.path,
  ]..sort();
}

Iterable<String> _dartFilesUnder(List<String> roots) sync* {
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        yield p.normalize(p.absolute(entity.path));
      }
    }
  }
}

/// Every identifier in [file], comments stripped, strings kept.
Set<String> _identifiersIn(String file) {
  final code = dartCodeWithoutComments(File(file).readAsStringSync());
  return {for (final m in _identifier.allMatches(code)) m.group(0)!};
}

/// The exported symbols declared in [file]: the top-level declarations whose
/// names are in [wanted], and the public members of those that are types.
List<ExportedSymbol> _symbolsDeclaredIn(
  String file,
  String package,
  Set<String> wanted,
) {
  final result = parseString(
    content: File(file).readAsStringSync(),
    path: file,
    throwIfDiagnostics: false,
  );
  final lines = result.lineInfo;
  final found = <ExportedSymbol>[];

  // Every identifier occurrence in the file with its offset — identifier
  // tokens, and identifiers inside string literals, so a name a table holds
  // as a string is a use. Comments are not tokens, so they do not count.
  final occurrences = <String, List<int>>{};
  for (
    var token = result.unit.beginToken;
    token.type != TokenType.EOF;
    token = token.next!
  ) {
    if (token.isIdentifier) {
      occurrences.putIfAbsent(token.lexeme, () => []).add(token.offset);
    } else if (token.type == TokenType.STRING ||
        token.type == TokenType.STRING_INTERPOLATION_IDENTIFIER) {
      for (final m in _identifier.allMatches(token.lexeme)) {
        occurrences
            .putIfAbsent(m.group(0)!, () => [])
            .add(token.offset + m.start);
      }
    }
  }

  bool namedOutside(String name, int start, int end) =>
      (occurrences[name] ?? const []).any((o) => o < start || o >= end);

  /// Named inside [start]–[end] more than once: the declaration and a use.
  bool usedInside(String name, int declaredAt, int start, int end) =>
      (occurrences[name] ?? const []).any(
        (o) => o != declaredAt && o >= start && o < end,
      );

  ExportedSymbol symbol(
    String name,
    String kind,
    int offset, {
    required AstNode self,
    bool seam = false,
  }) => ExportedSymbol(
    declaredTestSeam: seam,
    package: package,
    file: file,
    line: lines.getLocation(offset).lineNumber,
    symbol: name,
    kind: kind,
    namedInOwnFile: namedOutside(
      name.contains('.') ? name.substring(name.indexOf('.') + 1) : name,
      self.offset,
      self.end,
    ),
    usedWithinDeclaration: usedInside(
      name.contains('.') ? name.substring(name.indexOf('.') + 1) : name,
      offset,
      self.offset,
      self.end,
    ),
  );

  void members(
    String owner,
    AstNode self,
    List<ClassMember> list, {
    required bool ownerIsSeam,
  }) {
    for (final member in list) {
      if (member.metadata.any((a) => a.name.name == 'override')) continue;
      final seam = ownerIsSeam || _isTestSeam(member.metadata);
      switch (member) {
        case MethodDeclaration():
          final name = member.name.lexeme;
          if (member.isOperator ||
              name.startsWith('_') ||
              _objectMembers.contains(name)) {
            continue;
          }
          found.add(
            symbol(
              '$owner.$name',
              member.isGetter
                  ? 'getter'
                  : member.isSetter
                  ? 'setter'
                  : 'method',
              member.name.offset,
              self: self,
              seam: seam,
            ),
          );
        case FieldDeclaration():
          for (final variable in member.fields.variables) {
            final name = variable.name.lexeme;
            if (name.startsWith('_')) continue;
            found.add(
              symbol(
                '$owner.$name',
                'field',
                variable.name.offset,
                self: self,
                seam: seam,
              ),
            );
          }
        case ConstructorDeclaration():
          final name = member.name?.lexeme;
          if (name == null || name.startsWith('_')) continue;
          found.add(
            symbol(
              '$owner.$name',
              'constructor',
              member.name!.offset,
              self: self,
              seam: seam,
            ),
          );
        case PrimaryConstructorBody():
          // The body of a primary constructor; the constructor itself is
          // named by the type.
          break;
      }
    }
  }

  for (final declaration in result.unit.declarations) {
    switch (declaration) {
      case ClassDeclaration():
        final name = declaration.namePart.typeName;
        if (!wanted.contains(name.lexeme)) continue;
        final seam = _isTestSeam(declaration.metadata);
        found.add(
          symbol(
            name.lexeme,
            'class',
            name.offset,
            self: declaration,
            seam: seam,
          ),
        );
        members(
          name.lexeme,
          declaration,
          declaration.body.members,
          ownerIsSeam: seam,
        );
      case MixinDeclaration():
        final name = declaration.name;
        if (!wanted.contains(name.lexeme)) continue;
        final seam = _isTestSeam(declaration.metadata);
        found.add(
          symbol(
            name.lexeme,
            'mixin',
            name.offset,
            self: declaration,
            seam: seam,
          ),
        );
        members(
          name.lexeme,
          declaration,
          declaration.body.members,
          ownerIsSeam: seam,
        );
      case EnumDeclaration():
        final name = declaration.namePart.typeName;
        if (!wanted.contains(name.lexeme)) continue;
        final seam = _isTestSeam(declaration.metadata);
        found.add(
          symbol(
            name.lexeme,
            'enum',
            name.offset,
            self: declaration,
            seam: seam,
          ),
        );
        members(
          name.lexeme,
          declaration,
          declaration.body.members,
          ownerIsSeam: seam,
        );
      case ExtensionDeclaration():
        // An extension's name is never written at a call site — its members
        // are reached through the extended type — so the name is not a
        // symbol a consumer names; its members are, and each is checked.
        final name = declaration.name;
        if (name == null || !wanted.contains(name.lexeme)) continue;
        members(
          name.lexeme,
          declaration,
          declaration.body.members,
          ownerIsSeam: _isTestSeam(declaration.metadata),
        );
      case ExtensionTypeDeclaration():
        final name = declaration.namePart.typeName;
        if (!wanted.contains(name.lexeme)) continue;
        final seam = _isTestSeam(declaration.metadata);
        found.add(
          symbol(
            name.lexeme,
            'extension type',
            name.offset,
            self: declaration,
            seam: seam,
          ),
        );
        members(
          name.lexeme,
          declaration,
          declaration.body.members,
          ownerIsSeam: seam,
        );
      case FunctionDeclaration():
        final name = declaration.name.lexeme;
        if (!wanted.contains(name)) continue;
        found.add(
          symbol(
            name,
            declaration.isGetter
                ? 'getter'
                : declaration.isSetter
                ? 'setter'
                : 'function',
            declaration.name.offset,
            self: declaration,
            seam: _isTestSeam(declaration.metadata),
          ),
        );
      case TopLevelVariableDeclaration():
        for (final variable in declaration.variables.variables) {
          final name = variable.name.lexeme;
          if (!wanted.contains(name)) continue;
          found.add(
            symbol(
              name,
              'variable',
              variable.name.offset,
              self: declaration,
              seam: _isTestSeam(declaration.metadata),
            ),
          );
        }
      case TypeAlias():
        final name = declaration.name.lexeme;
        if (!wanted.contains(name)) continue;
        found.add(
          symbol(
            name,
            'typedef',
            declaration.name.offset,
            self: declaration,
            seam: _isTestSeam(declaration.metadata),
          ),
        );
      default:
        break;
    }
  }
  return found;
}

/// Whether [metadata] carries `@visibleForTesting` (from `package:meta`, or
/// re-exported by `package:flutter/foundation.dart`).
bool _isTestSeam(List<Annotation> metadata) =>
    metadata.any((a) => a.name.name == 'visibleForTesting');
