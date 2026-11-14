/// The documentation site behind `buildkit :docsite`: each selected
/// package's dartdoc output (`buildkit :apidoc`, `build/api_doc`) copied into
/// one folder, its README rendered beside it, and an index page listing
/// every package — name, version and description from its pubspec, links to
/// its API docs and its README. The site is a build output: gitignored,
/// served locally, never published.
///
/// ```text
/// <site>/
///   index.html                 the packages
///   <package>/api/...          its dartdoc output, as generated
///   <package>/readme.html      its README.md, rendered
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One package as the site shows it.
class DocSitePackage {
  /// The pubspec `name:`, else the folder name.
  final String name;

  /// The pubspec `version:`, or null.
  final String? version;

  /// The pubspec `description:`, or null.
  final String? description;

  /// The package folder relative to the workspace root, for the index.
  final String path;

  /// The package's dartdoc output folder, or null when it has none
  /// (`index.html` missing).
  final String? apiDocDir;

  /// The package's `README.md`, or null.
  final String? readme;

  const DocSitePackage({
    required this.name,
    required this.path,
    this.version,
    this.description,
    this.apiDocDir,
    this.readme,
  });

  /// Reads the package at [packageDir]: its pubspec, its README and the
  /// dartdoc output in [apiDoc] (relative to the package).
  factory DocSitePackage.read(
    String packageDir, {
    required String path,
    required String apiDoc,
  }) {
    String? name, version, description;
    final pubspec = File(p.join(packageDir, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      try {
        final yaml = loadYaml(pubspec.readAsStringSync());
        if (yaml is YamlMap) {
          name = yaml['name']?.toString();
          version = yaml['version']?.toString();
          description = yaml['description']
              ?.toString()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
      } on YamlException {
        // An unreadable pubspec: the folder name stands in, nothing else.
      }
    }
    final apiDir = p.join(packageDir, apiDoc);
    final readme = File(p.join(packageDir, 'README.md'));
    return DocSitePackage(
      name: name ?? p.basename(packageDir),
      version: version,
      description: description,
      path: path,
      apiDocDir: File(p.join(apiDir, 'index.html')).existsSync()
          ? apiDir
          : null,
      readme: readme.existsSync() ? readme.path : null,
    );
  }

  bool get hasApiDocs => apiDocDir != null;
}

/// Rebuilds the site in [siteDir] from [packages]: the folder is replaced
/// as a whole, so a package left out of this run leaves no stale pages.
void buildDocSite(
  String siteDir,
  List<DocSitePackage> packages, {
  required DateTime now,
}) {
  final site = Directory(siteDir);
  if (site.existsSync()) site.deleteSync(recursive: true);
  site.createSync(recursive: true);
  for (final package in packages.where((p) => p.hasApiDocs)) {
    _copyDir(package.apiDocDir!, p.join(siteDir, package.name, 'api'));
    if (package.readme != null) {
      File(p.join(siteDir, package.name, 'readme.html')).writeAsStringSync(
        renderReadme(package.name, File(package.readme!).readAsStringSync()),
      );
    }
  }
  File(
    p.join(siteDir, 'index.html'),
  ).writeAsStringSync(renderDocSiteIndex(packages, now: now));
}

/// The index page: a table of the packages with API docs, sorted by name,
/// and the packages without them named below it.
String renderDocSiteIndex(
  List<DocSitePackage> packages, {
  required DateTime now,
}) {
  final withDocs = packages.where((p) => p.hasApiDocs).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final without = packages.where((p) => !p.hasApiDocs).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final e = const HtmlEscape();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${now.year}-${two(now.month)}-${two(now.day)} '
      '${two(now.hour)}:${two(now.minute)}';

  final rows = [
    for (final pkg in withDocs)
      '      <tr>\n'
          '        <td><a href="${e.convert(pkg.name)}/api/index.html">'
          '${e.convert(pkg.name)}</a></td>\n'
          '        <td>${e.convert(pkg.version ?? '')}</td>\n'
          '        <td>${e.convert(pkg.description ?? '')}</td>\n'
          '        <td>${pkg.readme == null ? '' : '<a href="${e.convert(pkg.name)}/readme.html">README</a>'}</td>\n'
          '      </tr>',
  ];
  final missing = without.isEmpty
      ? ''
      : '\n  <h2>Without API docs</h2>\n'
            '  <p>Selected, but no <code>build/api_doc</code> was found: run '
            '<code>buildkit :apidoc</code> for them first.</p>\n'
            '  <ul>\n'
            '${without.map((p) => '    <li>${e.convert(p.name)} <span class="path">(${e.convert(p.path)})</span></li>').join('\n')}\n'
            '  </ul>\n';
  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>API documentation</title>
  <style>$_css</style>
</head>
<body>
  <h1>API documentation</h1>
  <p class="meta">${withDocs.length} package${withDocs.length == 1 ? '' : 's'}, built $stamp by <code>buildkit :docsite</code>.</p>
  <table>
    <thead>
      <tr><th>Package</th><th>Version</th><th>Description</th><th>README</th></tr>
    </thead>
    <tbody>
${rows.join('\n')}
    </tbody>
  </table>$missing
</body>
</html>
''';
}

/// [markdown] (a README) as a page of its own, titled [name].
String renderReadme(String name, String markdown) {
  final body = md.markdownToHtml(
    markdown,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final e = const HtmlEscape();
  return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>${e.convert(name)} README</title>
  <style>$_css</style>
</head>
<body>
  <p class="meta"><a href="../index.html">All packages</a> · <a href="api/index.html">${e.convert(name)} API</a></p>
$body
</body>
</html>
''';
}

const _css =
    'body{font-family:system-ui,sans-serif;max-width:60rem;margin:2rem auto;'
    'padding:0 1rem;line-height:1.5}table{border-collapse:collapse;width:100%}'
    'th,td{text-align:left;padding:.4rem .6rem;border-bottom:1px solid #ddd;'
    'vertical-align:top}.meta,.path{color:#666}pre{background:#f6f8fa;'
    'padding:.8rem;overflow:auto}code{font-family:ui-monospace,monospace}';

void _copyDir(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final entity in Directory(from).listSync(recursive: true)) {
    final target = p.join(to, p.relative(entity.path, from: from));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      File(target).parent.createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
