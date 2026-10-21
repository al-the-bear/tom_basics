/// The import graph of Dart source: closures from an entry point, the
/// packages a file or directory names, and the public names an entry point
/// exports.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'dart_source.dart';

/// The import closure of [entryPoint] **across sibling packages**: every file
/// reached, mapped to the URIs it names that the walk did not follow.
///
/// [importClosureOf] stops at its own package, which is the right question for
/// an entry point's own rules. This one answers the question a composition
/// root poses — *what does this build link?* — so a `package:` URI whose
/// package name starts with [followPrefix] is followed into the sibling
/// package of that name under [root], and only `dart:` URIs and other
/// packages are leaves.
Map<String, Set<String>> siblingImportClosureOf(
  String entryPoint,
  String root, {
  required String followPrefix,
}) {
  final closure = <String, Set<String>>{};
  final queue = <String>[p.normalize(p.absolute(entryPoint))];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    if (closure.containsKey(file)) continue;
    final handle = File(file);
    if (!handle.existsSync()) continue;
    final leaves = <String>{};
    for (final uri in directiveUris(handle.readAsStringSync())) {
      if (uri.startsWith('package:$followPrefix')) {
        final slash = uri.indexOf('/');
        final package = uri.substring('package:'.length, slash);
        queue.add(
          p.normalize(p.join(root, package, 'lib', uri.substring(slash + 1))),
        );
      } else if (uri.startsWith('dart:') || uri.startsWith('package:')) {
        leaves.add(uri);
      } else if (!uri.contains(':')) {
        queue.add(p.normalize(p.join(p.dirname(file), uri)));
      }
    }
    closure[file] = leaves;
  }
  return closure;
}

/// The import closure of [entryPoint] **within its own package**: every file
/// reached, mapped to the `dart:` and `package:` URIs it directly names.
///
/// This is the one walk a boundary audit is built on: three copies of a
/// boundary check drift exactly the way the boundaries they check do.
///
/// Traversal follows relative directives **and** self-referential
/// `package:<own package>/…` ones, so a barrel that imports itself by package
/// URI does not silently end the walk. Every other `package:` URI is a leaf:
/// what a package pulls in from outside itself is precisely the boundary in
/// question. A third-party package's own transitive `dart:io` is a dependency
/// decision rather than a slip, and is caught by a real compile instead.
Map<String, Set<String>> importClosureOf(String entryPoint) {
  final context = _PackageContext.of(entryPoint);
  final closure = <String, Set<String>>{};
  final queue = <String>[p.normalize(p.absolute(entryPoint))];
  while (queue.isNotEmpty) {
    final file = queue.removeLast();
    if (closure.containsKey(file)) continue;
    final handle = File(file);
    if (!handle.existsSync()) continue;
    final external = <String>{};
    for (final uri in directiveUris(handle.readAsStringSync())) {
      final selfPrefix = context == null ? null : 'package:${context.name}/';
      if (selfPrefix != null && uri.startsWith(selfPrefix)) {
        queue.add(
          p.normalize(
            p.join(context!.libDirectory, uri.substring(selfPrefix.length)),
          ),
        );
      } else if (uri.startsWith('dart:') || uri.startsWith('package:')) {
        external.add(uri);
      } else if (!uri.contains(':')) {
        queue.add(p.normalize(p.join(p.dirname(file), uri)));
      }
    }
    closure[file] = external;
  }
  return closure;
}

/// The union of [importClosureOf] — what [entryPoint] links, in one set.
Set<String> externalImportsOf(String entryPoint) =>
    importClosureOf(entryPoint).values.expand((uris) => uris).toSet();

/// The package a source file belongs to, found by the nearest `pubspec.yaml`.
class _PackageContext {
  const _PackageContext(this.name, this.root);

  final String name;
  final String root;

  String get libDirectory => p.join(root, 'lib');

  static _PackageContext? of(String file) {
    var dir = p.dirname(p.normalize(p.absolute(file)));
    while (true) {
      final pubspec = File(p.join(dir, 'pubspec.yaml'));
      if (pubspec.existsSync()) {
        final doc = loadYaml(pubspec.readAsStringSync());
        if (doc is YamlMap && doc['name'] != null) {
          return _PackageContext(doc['name'].toString(), dir);
        }
        return null;
      }
      final parent = p.dirname(dir);
      if (parent == dir) return null;
      dir = parent;
    }
  }
}

/// The package name of a `package:` URI (`package:kdbx/kdbx.dart` → `kdbx`).
String packageOf(String uri) => uri.substring('package:'.length).split('/')[0];

/// What [entryPoint] links, named the way a rule names it: a package name for
/// `package:` URIs, the bare library for `dart:` ones (`dart:io`).
///
/// The two live in one set because a seam rule does not care which kind of
/// boundary it is guarding — `dart:io` and `tom_github_api` are both "something
/// this entry point must not reach", and splitting them would mean two rule
/// fields that are always written together.
Set<String> reachableNamesOf(String entryPoint) => {
  for (final uri in externalImportsOf(entryPoint))
    uri.startsWith('dart:') ? uri.split('/')[0] : packageOf(uri),
};

/// Every `package:` import appearing anywhere under [directory], mapped to the
/// files that carry it.
///
/// Unlike [externalImportsOf] this walks files rather than the reachable
/// closure — which is the stricter question, and the one that matters for a
/// rule about what a *package* may touch: a barrel walk only proves that
/// nothing exported today reaches the banned dependency, and says nothing
/// about a file that is clean by accident because no one has exported it yet.
Map<String, List<String>> packageImportsUnder(String directory) {
  final byPackage = <String, List<String>>{};
  final dir = Directory(directory);
  if (!dir.existsSync()) return byPackage;
  for (final entity in dir.listSync(recursive: true).whereType<File>()) {
    if (!entity.path.endsWith('.dart')) continue;
    for (final line in const LineSplitter().convert(
      entity.readAsStringSync(),
    )) {
      final match = directiveLinePattern.firstMatch(line);
      if (match == null) continue;
      final uri = match.group(1)!;
      if (!uri.startsWith('package:')) continue;
      byPackage.putIfAbsent(packageOf(uri), () => []).add(entity.path);
    }
  }
  return byPackage;
}

/// One public top-level declaration in an entry point's export namespace.
class PublicDeclaration {
  const PublicDeclaration(this.name, this.kind, this.file);

  final String name;

  /// `class`, `mixin`, `enum`, `extension`, `typedef`, `function`, `getter`
  /// or `setter`.
  final String kind;

  /// The declaring file.
  final String file;

  bool get isType =>
      const {'class', 'mixin', 'enum', 'extension', 'typedef'}.contains(kind);
}

final _exportDirective = RegExp(
  r'''^\s*export\s+(['"])([^'"]+)\1([^;]*);''',
  multiLine: true,
);
final _partDirective = RegExp(
  r'''^\s*part\s+(['"])([^'"]+)\1\s*;''',
  multiLine: true,
);

/// The public declarations [entryPoint] exports, keyed by name: its own,
/// its parts', and those of every file it re-exports within its package,
/// with `show` / `hide` applied.
///
/// A `package:` export of another package is not followed: those names are
/// that package's, re-exported for convenience, and are not this package's
/// to name.
Map<String, PublicDeclaration> exportedDeclarationsOf(String entryPoint) {
  final context = _PackageContext.of(entryPoint);
  final visiting = <String>{};

  Map<String, PublicDeclaration> namespaceOf(String file) {
    final path = p.normalize(p.absolute(file));
    final handle = File(path);
    if (!handle.existsSync() || !visiting.add(path)) return const {};
    final source = handle.readAsStringSync();
    final stripped = dartCodeWithoutComments(source);
    final names = <String, PublicDeclaration>{};
    void declareFrom(String declaringFile, String text) {
      for (final d in topLevelDeclarations(text)) {
        if (d.name.startsWith('_')) continue;
        names.putIfAbsent(
          d.name,
          () => PublicDeclaration(d.name, d.kind, declaringFile),
        );
      }
    }

    declareFrom(path, source);
    for (final part in _partDirective.allMatches(stripped)) {
      final partFile = p.normalize(p.join(p.dirname(path), part.group(2)!));
      if (File(partFile).existsSync()) {
        declareFrom(partFile, File(partFile).readAsStringSync());
      }
    }
    for (final export in _exportDirective.allMatches(stripped)) {
      final uri = export.group(2)!;
      String? target;
      final selfPrefix = context == null ? null : 'package:${context.name}/';
      if (selfPrefix != null && uri.startsWith(selfPrefix)) {
        target = p.join(
          context!.libDirectory,
          uri.substring(selfPrefix.length),
        );
      } else if (!uri.contains(':')) {
        target = p.join(p.dirname(path), uri);
      }
      if (target == null) continue;
      var exported = namespaceOf(target);
      final combinators = export.group(3)!;
      for (final c in RegExp(
        r'\b(show|hide)\b([^;]*?)(?=\b(?:show|hide)\b|$)',
      ).allMatches(combinators)) {
        final listed = {for (final n in c.group(2)!.split(',')) n.trim()}
          ..remove('');
        exported = {
          for (final e in exported.entries)
            if (listed.contains(e.key) == (c.group(1) == 'show'))
              e.key: e.value,
        };
      }
      for (final e in exported.entries) {
        names.putIfAbsent(e.key, () => e.value);
      }
    }
    visiting.remove(path);
    return names;
  }

  return namespaceOf(entryPoint);
}
