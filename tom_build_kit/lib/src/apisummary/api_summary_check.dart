/// The API-summary drift check behind `buildkit :apisummary`: a package's
/// public API (what its `lib/*.dart` entry points export, read with the
/// analyzer's parser) against the names its hand-authored API summaries
/// (`doc/api/api_summary_*.md`, `_copilot_guidelines/dart/api_summary_creation.md`)
/// mention. It reports, and writes nothing: `doc/` is hand-authored.
///
/// **Missing:** a public symbol the summaries never name. A type is missing
/// when its name appears nowhere in them; a member when its name appears
/// nowhere in its type's section (`### Type`), or nowhere at all when the
/// type has no section. The members of a missing type are not listed
/// separately: the type is the finding.
///
/// **Stale:** a name a summary presents as API that the package does not
/// declare. A summary claims a name by a `### Name` heading (a type or a
/// top-level function), by the first cell of a member table (Property,
/// Method, Member, Value, Constant, Operator, Constructor, Field, Factory,
/// Static member, Declaration) inside a type's section, by the first cell of a
/// Function / Constant / Typedef / Class table outside one, and by a
/// `` `Type.member` `` code span naming one of the package's types. A member
/// claim is checked against every member the type declares — overrides, enum
/// values and constructors included — and those it inherits from the
/// package's own types; when the type has a supertype from another package,
/// a name it does not declare cannot be judged and is not reported.
///
/// What is read as a declaration heading: `### Name` (an identifier, with
/// type parameters or `()`), and `#### Name` under a heading that groups
/// declarations or when the package declares `Name`. A plain capitalised
/// word (`### Codes`) counts only when the package declares it — prose
/// headings are written that way — so a removed one-word class is not
/// reported stale. All-capitals first cells (`POST`, `GET`) are a protocol's
/// words, not members. Members are also found in the sections of the type's
/// package supertypes and, for an extension, of the extended type.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:path/path.dart' as p;

import '../unreferenced/unreferenced_exports.dart';

/// One place where a summary and the code disagree.
class ApiSummaryFinding {
  /// `Name` or `Type.member`.
  final String symbol;

  /// For a missing symbol its kind (`class`, `method`, ...); for a stale one
  /// what claimed it (`heading`, `table`, `code span`).
  final String kind;

  /// The declaring file (missing) or the summary (stale), relative to the
  /// package, and the line.
  final String file;
  final int line;

  const ApiSummaryFinding({
    required this.symbol,
    required this.kind,
    required this.file,
    required this.line,
  });

  @override
  String toString() => '$symbol ($kind, $file:$line)';
}

/// The result of [checkApiSummary] for one package.
class ApiSummaryReport {
  /// The summary files read, relative to the package; empty when the
  /// package has none.
  final List<String> summaryFiles;

  /// Public symbols of the package (types, top-level declarations, members).
  final int apiSymbols;

  /// Names the summaries present as API.
  final int claims;

  /// Public API no summary names.
  final List<ApiSummaryFinding> missing;

  /// Names the summaries present as API that the package does not declare.
  final List<ApiSummaryFinding> stale;

  const ApiSummaryReport({
    required this.summaryFiles,
    this.apiSymbols = 0,
    this.claims = 0,
    this.missing = const [],
    this.stale = const [],
  });

  /// Whether there was a summary to compare.
  bool get measured => summaryFiles.isNotEmpty;

  bool get clean => missing.isEmpty && stale.isEmpty;
}

/// Where the summaries live, relative to a package.
const kApiSummaryDir = 'doc/api';

/// The summary files of the package at [packageDir]: `api_summary_*.md` in
/// `doc/api/`, the index left out.
List<String> apiSummaryFilesOf(String packageDir) {
  final dir = Directory(p.join(packageDir, kApiSummaryDir));
  if (!dir.existsSync()) return const [];
  return [
    for (final f in dir.listSync().whereType<File>())
      if (RegExp(r'^api_summary_.+\.md$').hasMatch(p.basename(f.path)) &&
          p.basename(f.path) != 'api_summary_index.md')
        f.path,
  ]..sort();
}

/// Compares the public API of the package [packageName] at [packageDir]
/// with its API summaries.
ApiSummaryReport checkApiSummary(String packageDir, String packageName) {
  final summaries = apiSummaryFilesOf(packageDir);
  String rel(String path) => p.relative(path, from: packageDir);
  if (summaries.isEmpty) return const ApiSummaryReport(summaryFiles: []);

  final api = exportedSymbolsOf(
    packageDir,
    packageName,
    includeExtensionNames: true,
    includeVariables: true,
  );
  final topLevel = exportedTopLevelOf(
    packageDir,
    includeVariables: true,
  ).keys.toSet();
  final types = _PackageTypes.read(packageDir);
  final read = _SummaryText.read(
    summaries,
    typeNames: types.names,
    known: {...types.names, ...types.topLevel, ...topLevel},
  );

  final missing = <ApiSummaryFinding>[];
  final missingTypes = <String>{};
  for (final symbol in api.where((s) => !s.symbol.contains('.'))) {
    if (read.words.contains(symbol.symbol)) continue;
    missingTypes.add(symbol.symbol);
    missing.add(
      ApiSummaryFinding(
        symbol: symbol.symbol,
        kind: symbol.kind,
        file: rel(symbol.file),
        line: symbol.line,
      ),
    );
  }
  for (final symbol in api.where((s) => s.symbol.contains('.'))) {
    final dot = symbol.symbol.indexOf('.');
    final owner = symbol.symbol.substring(0, dot);
    final member = symbol.symbol.substring(dot + 1);
    if (missingTypes.contains(owner)) continue;
    // Documented in its type's section, or in the section of a type it
    // implements or extends (an interface's `#### Methods`), or of the
    // type an extension extends (the builder's table lists them).
    final scopes = [
      for (final t in types.related(owner)) ?read.sectionWords[t],
      // A type without a section of its own is documented wherever it is.
      if (!read.sectionWords.containsKey(owner)) read.words,
    ];
    if (scopes.any((words) => words.contains(member))) continue;
    missing.add(
      ApiSummaryFinding(
        symbol: symbol.symbol,
        kind: symbol.kind,
        file: rel(symbol.file),
        line: symbol.line,
      ),
    );
  }

  final stale = <ApiSummaryFinding>[];
  final seen = <String>{};
  for (final claim in read.claims) {
    final key = '${claim.owner}.${claim.name}@${claim.file}:${claim.line}';
    if (!seen.add(key)) continue;
    final exists = claim.owner == null
        ? topLevel.contains(claim.name) ||
              types.names.contains(claim.name) ||
              types.topLevel.contains(claim.name)
        : !types.names.contains(claim.owner!) ||
              types.hasMember(claim.owner!, claim.name) != false;
    if (exists) continue;
    stale.add(
      ApiSummaryFinding(
        symbol: claim.owner == null
            ? claim.name
            : '${claim.owner}.${claim.name}',
        kind: claim.kind,
        file: rel(claim.file),
        line: claim.line,
      ),
    );
  }

  return ApiSummaryReport(
    summaryFiles: [for (final s in summaries) rel(s)],
    apiSymbols: api.length,
    claims: read.claims.length,
    missing: missing,
    stale: stale,
  );
}

/// A name a summary presents as API: top-level when [owner] is null.
class _Claim {
  final String? owner;
  final String name;
  final String kind;
  final String file;
  final int line;

  const _Claim(this.owner, this.name, this.kind, this.file, this.line);
}

/// What the summaries say: every word, the words of each type's section, and
/// the names they present as API.
class _SummaryText {
  final Set<String> words = {};
  final Map<String, Set<String>> sectionWords = {};
  final List<_Claim> claims = [];

  static final _word = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');
  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// Words that head a structural section, not a declaration.
  static const _structural = {
    'Overview',
    'Classes',
    'Enums',
    'Enumerations',
    'Extensions',
    'Mixins',
    'Typedefs',
    'Functions',
    'Constants',
    'Variables',
    'Constructors',
    'Properties',
    'Methods',
    'Operators',
    'Fields',
    'Getters',
    'Setters',
    'Examples',
    'Example',
    'Usage',
    'Notes',
    'Exceptions',
    'Errors',
    'Installation',
    'Values',
    'Parameters',
    'Returns',
    'Throws',
    'Members',
    'Factories',
    'Configuration',
    'Introduction',
    'Summary',
    'See',
  };

  /// A first cell holding only a modifier names no member.
  static const _keywords = {
    'static',
    'const',
    'final',
    'factory',
    'get',
    'set',
    'abstract',
    'late',
    'external',
    'var',
    'new',
    'operator',
  };

  /// Member-table headers (first cell, lower case, `static ` removed).
  static const _memberTables = {
    'property',
    'properties',
    'method',
    'methods',
    'member',
    'members',
    'value',
    'values',
    'constant',
    'constants',
    'operator',
    'operators',
    'constructor',
    'constructors',
    'field',
    'fields',
    'factory',
    'declaration',
    'getter',
    'setter',
  };

  /// Top-level tables outside a type's section.
  static const _topLevelTables = {
    'function',
    'functions',
    'constant',
    'constants',
    'typedef',
    'typedefs',
    'class',
    'classes',
    'declaration',
    'variable',
    'variables',
  };

  static _SummaryText read(
    List<String> files, {
    required Set<String> typeNames,
    required Set<String> known,
  }) {
    final text = _SummaryText();
    for (final file in files) {
      text._readFile(file, typeNames, known);
    }
    return text;
  }

  void _readFile(String file, Set<String> typeNames, Set<String> known) {
    final lines = File(file).readAsLinesSync();
    final groups = _groupHeadings(lines, known);
    String? section; // the declaration whose section we are in
    var sectionLevel = 0;
    var inGroup = false; // under a `### Group` heading of declarations
    var inFence = false;
    String? tableHeader;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lineNo = i + 1;
      final lineWords = {for (final m in _word.allMatches(line)) m.group(0)!};
      words.addAll(lineWords);
      if (section != null) {
        sectionWords.putIfAbsent(section, () => {}).addAll(lineWords);
      }

      if (line.trimLeft().startsWith('```')) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        tableHeader = null;
        final level = heading.group(1)!.length;
        if (level <= 3) inGroup = groups.contains(i);
        var name = _declarationAt(level, heading.group(2)!, known);
        // A `#### Word` is a declaration under a group heading, or when it
        // names one of the package's types; else it is a section's prose.
        if (level == 4 && !inGroup && !typeNames.contains(name)) name = null;
        if (name != null && !groups.contains(i)) {
          // `### Type` (or `#### Type` under a group heading) opens its
          // section; the section's `#### Methods` and the like do not.
          section = name;
          sectionLevel = level;
          sectionWords.putIfAbsent(name, () => {}).addAll(lineWords);
          claims.add(_Claim(null, name, 'heading', file, lineNo));
        } else if (level <= 3 || level <= sectionLevel) {
          section = null;
          sectionLevel = 0;
        }
        continue;
      }

      if (!line.trimLeft().startsWith('|')) {
        tableHeader = null;
        _codeSpanClaims(line, typeNames, file, lineNo);
        continue;
      }
      final cells = line.trim().replaceAll(RegExp(r'^\||\|$'), '').split('|');
      final first = cells.first.trim();
      if (tableHeader == null) {
        // A header row is followed by the separator row.
        final next = i + 1 < lines.length ? lines[i + 1].trim() : '';
        if (RegExp(r'^\|?\s*:?-{3,}').hasMatch(next)) {
          tableHeader = first.toLowerCase().replaceFirst('static ', '').trim();
          i++; // the separator
        }
        continue;
      }
      _codeSpanClaims(cells.skip(1).join('|'), typeNames, file, lineNo);
      final span = RegExp(r'^`([^`]+)`').firstMatch(first);
      if (span == null) continue;
      final token = span.group(1)!.trim();
      if (token.startsWith('operator') ||
          token.startsWith('==') ||
          _keywords.contains(token)) {
        continue;
      }
      final name = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$.]*')
          .firstMatch(
            token.replaceFirst(
              RegExp(r'^(static|factory|const|get|set)\s+'),
              '',
            ),
          )
          ?.group(0);
      // `POST`, `GET`: a protocol's words in a table, not Dart members
      // (Dart names its constants in lowerCamelCase).
      if (name == null || RegExp(r'^[A-Z][A-Z0-9_]+$').hasMatch(name)) {
        continue;
      }
      if (section != null && _memberTables.contains(tableHeader)) {
        if (name == section) continue; // the unnamed constructor
        if (name.startsWith('$section.')) {
          claims.add(
            _Claim(
              section,
              name.substring(section.length + 1),
              'table',
              file,
              lineNo,
            ),
          );
        } else if (!name.contains('.')) {
          claims.add(_Claim(section, name, 'table', file, lineNo));
        }
      } else if (section == null && _topLevelTables.contains(tableHeader)) {
        if (!name.contains('.')) {
          claims.add(_Claim(null, name, 'table', file, lineNo));
        }
      }
    }
  }

  /// `` `Type.member` `` and `` `Type.member(...)` `` spans naming one of
  /// the package's types.
  void _codeSpanClaims(
    String text,
    Set<String> typeNames,
    String file,
    int line,
  ) {
    for (final m in RegExp(
      r'`([A-Z][A-Za-z0-9_$]*)\.([A-Za-z_$][A-Za-z0-9_$]*)(\([^`]*\))?`',
    ).allMatches(text)) {
      if (!typeNames.contains(m.group(1))) continue;
      claims.add(_Claim(m.group(1), m.group(2)!, 'code span', file, line));
    }
  }

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');

  /// The declaration a level-3 or level-4 heading names, or null. A plain
  /// capitalised word (`### Codes`) is prose unless the package declares it.
  static String? _declarationAt(int level, String text, Set<String> known) {
    if (level != 3 && level != 4) return null;
    final name = _declarationName(text);
    if (name == null || _structural.contains(name)) return null;
    if (RegExp(r'^[A-Z][a-z]+$').hasMatch(name) && !known.contains(name)) {
      return null;
    }
    return name;
  }

  /// The line indexes of group headings outside fences: a declaration-like
  /// `### Name` whose next heading is a `#### Type` (`### Analyzer` over
  /// `#### TomAnnotationAnalyzer`), which groups declarations and is none.
  static Set<int> _groupHeadings(List<String> lines, Set<String> known) {
    final headings = <(int, int, String?)>[];
    var fence = false;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('```')) fence = !fence;
      if (fence) continue;
      final m = _heading.firstMatch(lines[i]);
      if (m == null) continue;
      final level = m.group(1)!.length;
      headings.add((i, level, _declarationAt(level, m.group(2)!, known)));
    }
    return {
      for (var h = 0; h + 1 < headings.length; h++)
        if (headings[h].$2 == 3 &&
            headings[h + 1].$2 == 4 &&
            headings[h + 1].$3 != null)
          headings[h].$1,
    };
  }

  /// The declaration a heading names, or null for prose: one identifier,
  /// optionally in backticks, with type parameters or `()`.
  static String? _declarationName(String heading) {
    var h = heading
        .trim()
        .replaceAll('`', '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    h = h.replaceFirst(RegExp(r'<.*>$'), '').replaceFirst(RegExp(r'\(\)$'), '');
    return _identifier.hasMatch(h) ? h : null;
  }
}

/// Every type the package declares in `lib/`, exported or not, with every
/// member name it declares and its supertypes.
class _PackageTypes {
  final Map<String, Set<String>> _members = {};
  final Map<String, Set<String>> _supertypes = {};

  /// Members extensions of the package add, by the extended type's name.
  final Map<String, Set<String>> _extended = {};

  /// The type each extension of the package extends.
  final Map<String, String> _extensionOn = {};

  /// Top-level functions, variables and typedefs the package declares.
  final Set<String> topLevel = {};

  /// Members every object has.
  static const _objectMembers = {
    'toString',
    'hashCode',
    'noSuchMethod',
    'runtimeType',
    '==',
  };

  Set<String> get names => _members.keys.toSet();

  static _PackageTypes read(String packageDir) {
    final types = _PackageTypes();
    final lib = Directory(p.join(packageDir, 'lib'));
    if (!lib.existsSync()) return types;
    for (final f in lib.listSync(recursive: true, followLinks: false)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final unit = parseString(
        content: f.readAsStringSync(),
        path: f.path,
        throwIfDiagnostics: false,
      ).unit;
      for (final d in unit.declarations) {
        types._add(d);
      }
    }
    return types;
  }

  void _add(CompilationUnitMember d) {
    switch (d) {
      case FunctionDeclaration():
        topLevel.add(d.name.lexeme);
      case TopLevelVariableDeclaration():
        topLevel.addAll(d.variables.variables.map((v) => v.name.lexeme));
      case TypeAlias():
        topLevel.add(d.name.lexeme);
      default:
        break;
    }
    final (
      String? name,
      List<ClassMember> body,
      List<String> supers,
      Set<String> extra,
    ) = switch (d) {
      ClassDeclaration() => (
        d.namePart.typeName.lexeme,
        d.body.members,
        [
          ?d.extendsClause?.superclass.name.lexeme,
          ...?d.withClause?.mixinTypes.map((t) => t.name.lexeme),
          ...?d.implementsClause?.interfaces.map((t) => t.name.lexeme),
        ],
        <String>{},
      ),
      MixinDeclaration() => (
        d.name.lexeme,
        d.body.members,
        [
          ...?d.onClause?.superclassConstraints.map((t) => t.name.lexeme),
          ...?d.implementsClause?.interfaces.map((t) => t.name.lexeme),
        ],
        <String>{},
      ),
      EnumDeclaration() => (
        d.namePart.typeName.lexeme,
        d.body.members,
        [
          ...?d.withClause?.mixinTypes.map((t) => t.name.lexeme),
          ...?d.implementsClause?.interfaces.map((t) => t.name.lexeme),
        ],
        {
          'values',
          'index',
          'name',
          for (final c in d.body.constants) c.name.lexeme,
        },
      ),
      ExtensionDeclaration() => (
        d.name?.lexeme,
        d.body.members,
        <String>[],
        <String>{},
      ),
      ExtensionTypeDeclaration() => (
        d.namePart.typeName.lexeme,
        d.body.members,
        [...?d.implementsClause?.interfaces.map((t) => t.name.lexeme)],
        <String>{},
      ),
      _ => (null, const <ClassMember>[], const <String>[], const <String>{}),
    };
    if (name == null) return;
    final members = _members.putIfAbsent(name, () => {})..addAll(extra);
    _supertypes.putIfAbsent(name, () => {}).addAll(supers);
    for (final m in body) {
      switch (m) {
        case MethodDeclaration():
          members.add(m.name.lexeme);
        case FieldDeclaration():
          members.addAll(m.fields.variables.map((v) => v.name.lexeme));
        case ConstructorDeclaration():
          final ctor = m.name?.lexeme;
          if (ctor != null) members.add(ctor);
        default:
          break;
      }
    }
    if (d is ExtensionDeclaration) {
      final on = d.onClause?.extendedType;
      if (on is NamedType) {
        _extended.putIfAbsent(on.name.lexeme, () => {}).addAll(members);
        _extensionOn[name] = on.name.lexeme;
      }
    }
  }

  /// [type], the type an extension of that name extends, and every
  /// supertype the package declares, transitively.
  List<String> related(String type) {
    final seen = <String>[];
    void walk(String t) {
      if (seen.contains(t) || !_members.containsKey(t)) return;
      seen.add(t);
      (_supertypes[t] ?? const {}).forEach(walk);
      if (_extensionOn[t] case final on?) walk(on);
    }

    walk(type);
    return seen;
  }

  /// Whether [type] has [member], declared or inherited from the package's
  /// own types; null when it cannot be told (a supertype from elsewhere).
  bool? hasMember(String type, String member) {
    if (_objectMembers.contains(member)) return true;
    final visited = <String>{};
    var unknownSuper = false;
    bool walk(String t) {
      if (!visited.add(t)) return false;
      final own = _members[t];
      if (own == null) {
        if (t != 'Object') unknownSuper = true;
        return false;
      }
      if (own.contains(member) || (_extended[t]?.contains(member) ?? false)) {
        return true;
      }
      return (_supertypes[t] ?? const {}).any(walk);
    }

    if (walk(type)) return true;
    return unknownSuper ? null : false;
  }
}
