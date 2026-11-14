// BK-DOCSITE: `buildkit :docsite` — the selected packages' dartdoc output
// in one browsable site with an index page. BK-DOCSITE-1..3 read, render and
// build; 4..5 run the real executable on fixture packages under .dart_tool,
// rooted there (-R) so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/docsite/doc_site.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('docsite_test_');
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A package [name]; with [apiDocs] a stand-in dartdoc output in
  /// build/api_doc, with [readme] a README.md.
  String package(
    String name, {
    String version = '1.2.3',
    String description = 'Does <things> & more.',
    bool apiDocs = true,
    bool readme = true,
  }) {
    final dir = p.join(root.path, name);
    ({
      'pubspec.yaml':
          'name: $name\nversion: $version\ndescription: >-\n  '
          '$description\nenvironment:\n  sdk: ^3.0.0\n',
      'lib/$name.dart': 'class A {}\n',
      if (apiDocs) 'build/api_doc/index.html': '<html>$name API</html>\n',
      if (apiDocs) 'build/api_doc/$name/A-class.html': '<html>A</html>\n',
      if (readme)
        'README.md': '# $name\n\n> Attribution.\n\n## Quick start\n\n`go()`\n',
    }).forEach((path, text) {
      File(p.join(dir, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  DocSitePackage read(String dir) => DocSitePackage.read(
    dir,
    path: p.basename(dir),
    apiDoc: p.join('build', 'api_doc'),
  );

  test('BK-DOCSITE-1: a package is read from its pubspec, README and '
      'dartdoc output [2026-11-14]', () {
    final shop = read(package('shop'));
    expect(
      (shop.name, shop.version, shop.description, shop.hasApiDocs),
      ('shop', '1.2.3', 'Does <things> & more.', true),
    );
    expect(shop.readme, endsWith('README.md'));
    final bare = read(package('bare', apiDocs: false, readme: false));
    expect((bare.hasApiDocs, bare.readme), (false, null));
  });

  test('BK-DOCSITE-2: the index links every package with API docs to its '
      'API docs and README, sorted, escaped; the others are named without a '
      'link [2026-11-14]', () {
    final html = renderDocSiteIndex([
      read(package('zeta')),
      read(package('alpha', readme: false)),
      read(package('bare', apiDocs: false)),
    ], now: DateTime(2026, 11, 14, 9, 5));
    expect(html, contains('<a href="alpha/api/index.html">alpha</a>'));
    expect(html, contains('<a href="zeta/api/index.html">zeta</a>'));
    expect(html, contains('<a href="zeta/readme.html">README</a>'));
    expect(html, isNot(contains('alpha/readme.html')));
    expect(html.indexOf('alpha/api'), lessThan(html.indexOf('zeta/api')));
    expect(html, contains('<td>1.2.3</td>'));
    expect(html, contains('Does &lt;things&gt; &amp; more.'));
    expect(html, contains('2 packages, built 2026-11-14 09:05'));
    expect(html, contains('<h2>Without API docs</h2>'));
    expect(html, contains('<li>bare'));
    expect(html, isNot(contains('bare/api')));
  });

  test('BK-DOCSITE-3: building copies each package\'s API docs, renders its '
      'README and replaces an older site whole [2026-11-14]', () {
    final site = p.join(root.path, 'site');
    File(p.join(site, 'gone', 'api', 'index.html'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('old');
    buildDocSite(site, [read(package('shop'))], now: DateTime(2026, 11, 14));
    expect(
      File(p.join(site, 'shop', 'api', 'shop', 'A-class.html')).existsSync(),
      isTrue,
    );
    final readme = File(p.join(site, 'shop', 'readme.html')).readAsStringSync();
    expect(readme, contains('<h2>Quick start</h2>'));
    expect(readme, contains('<blockquote>'));
    expect(readme, contains('href="../index.html"'));
    expect(File(p.join(site, 'index.html')).existsSync(), isTrue);
    expect(Directory(p.join(site, 'gone')).existsSync(), isFalse);
  });

  group('the command', () {
    Future<ProcessResult> buildkit(List<String> args) => Process.run('dart', [
      'run',
      _buildkit,
      '-R',
      root.path,
      '-s',
      root.path,
      ...args,
    ], workingDirectory: root.path);

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    test('BK-DOCSITE-4: one command builds the site of the selected packages '
        'into build/doc_site; the index links each with API docs '
        '[2026-11-14]', () async {
      package('shop');
      package('cart');
      package('bare', apiDocs: false);
      final r = await buildkit([':docsite']);
      expect(r.exitCode, 0, reason: out(r));
      final site = p.join(root.path, 'build', 'doc_site');
      final index = File(p.join(site, 'index.html')).readAsStringSync();
      for (final name in ['shop', 'cart']) {
        expect(index, contains('<a href="$name/api/index.html">$name</a>'));
        expect(
          File(p.join(site, name, 'api', 'index.html')).readAsStringSync(),
          contains('$name API'),
        );
      }
      expect(index, contains('<li>bare'));
      final text = out(r);
      expect(text, contains('bare: no API docs'));
      expect(text, contains('docsite: 2 of 3 package(s) with API docs'));
      expect(text, contains('dhttpd --path build/doc_site'));
    });

    test('BK-DOCSITE-5: --output inside doc/ is refused; --dry-run writes '
        'nothing [2026-11-14]', () async {
      package('shop');
      var r = await buildkit([':docsite', '--output', 'doc/site']);
      expect(r.exitCode, isNot(0), reason: out(r));
      expect(out(r), contains('hand-authored'));
      expect(Directory(p.join(root.path, 'doc')).existsSync(), isFalse);

      r = await buildkit(['--dry-run', ':docsite']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('[DRY RUN] docsite: 1 of 1 package(s)'));
      expect(Directory(p.join(root.path, 'build')).existsSync(), isFalse);
    });
  });
}
