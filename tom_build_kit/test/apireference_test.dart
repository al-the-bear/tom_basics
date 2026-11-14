// BK-APIREF: `buildkit :apireference` — a package's combined API reference
// (index, module summaries, guides) rendered to PDF by tom_md2pdf, into a
// gitignored folder. BK-APIREF-1..3 collect and assemble; 4..7 and 9 run the
// real executable with a stand-in md2pdf; 8 renders with the real tom_md2pdf when
// its source is in the workspace. Fixtures live under .dart_tool and the run
// is rooted there (-R), so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/apireference/api_reference.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

const _index = '''
# Shop API Reference: Index

## Quick Navigation

| Module | Summary | Link |
| ------ | ------- | ---- |
| Cart | [api_summary_cart.md](api_summary_cart.md) | [→](api_summary_cart.md#cart) |
| Payment | [api_summary_payment.md](api_summary_payment.md) | [→](api_summary_payment.md) |
''';

const _cart = '''
# Shop API Reference: Cart Module

## Classes

### Cart

| Method | Description |
| ------ | ----------- |
| `add` | Adds an item; see [Payment](api_summary_payment.md). |
| `or` | `a \\| b` stays one cell. |

```dart
## not a heading
```
''';

const _payment =
    '# Shop API Reference: Payment Module\n\n## Classes\n\n### Payment\n';

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('apireference_test_');
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A package [name] with [files] (relative to the package).
  String package(String name, Map<String, String> files) {
    final dir = p.join(root.path, name);
    ({
      'pubspec.yaml': 'name: $name\nenvironment:\n  sdk: ^3.0.0\n',
      'lib/$name.dart': 'class A {}\n',
      ...files,
    }).forEach((path, text) {
      File(p.join(dir, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  /// The documented package: an index, two module summaries, and a guide
  /// for `cart` only (in `doc/cart/cart.md`).
  String shop({Map<String, String> extra = const {}}) => package('shop', {
    'doc/api/api_summary_index.md': _index,
    'doc/api/api_summary_cart.md': _cart,
    'doc/api/api_summary_payment.md': _payment,
    'doc/cart/cart.md': '# Cart Guide\n\n## Using a cart\n\nAdd items.\n',
    ...extra,
  });

  group('collecting and assembling', () {
    test('BK-APIREF-1: a documented package: index, summaries in order, the '
        'guides found, modules without one listed [2026-11-14]', () {
      final inputs = collectApiReferenceInputs(shop())!;
      expect(inputs.complete, isTrue, reason: '${inputs.missing}');
      expect(inputs.index, endsWith('api_summary_index.md'));
      expect(inputs.summaries.keys, ['cart', 'payment']);
      expect(inputs.guides.keys, ['cart']);
      expect(inputs.withoutGuide, ['payment']);

      final flat = collectApiReferenceInputs(
        shop(extra: {'doc/payment.md': '# Payment Guide\n'}),
      )!;
      expect(flat.guides.keys, ['cart', 'payment']);
      expect(collectApiReferenceInputs(package('bare', {})), isNull);
    });

    test('BK-APIREF-2: missing inputs are named: no index, a summary the '
        'index links to, no module summary [2026-11-14]', () {
      final noPayment = p.join(shop(), 'doc', 'api', 'api_summary_payment.md');
      File(noPayment).deleteSync();
      var inputs = collectApiReferenceInputs(p.join(root.path, 'shop'))!;
      expect(inputs.complete, isFalse);
      expect(inputs.missing, [
        'the index links to ${p.join('doc', 'api', 'api_summary_payment.md')}, '
            'which does not exist',
      ]);

      final empty = package('empty', {'doc/api/notes.txt': ''});
      inputs = collectApiReferenceInputs(empty)!;
      expect(inputs.missing, [
        'no index: ${p.join('doc', 'api', 'api_summary_index.md')}',
        'no module summary: ${p.join('doc', 'api')}/api_summary_<module>.md',
      ]);
    });

    test('BK-APIREF-3: the document: title and date, the three parts in '
        'order, headlines dropped, headings one level deeper outside code, '
        'link columns gone and links as text [2026-11-14]', () {
      final inputs = collectApiReferenceInputs(shop())!;
      final md = assembleApiReference(
        inputs,
        'shop',
        now: DateTime(2026, 11, 14, 9, 5),
      );
      expect(
        md,
        startsWith('# Shop API Reference\n\nCreated on 14.11.2026 at 09:05\n'),
      );
      final parts = [
        '# Part I: API Summary Index',
        '# Part II: Module API References',
        '## Cart Reference',
        '## Payment Reference',
        '# Part III: Module Guides',
        '## Cart Guide',
      ];
      final at = [for (final h in parts) md.indexOf('$h\n')];
      expect(at, everyElement(greaterThanOrEqualTo(0)), reason: md);
      expect(at, orderedEquals([...at]..sort()));
      expect(md, isNot(contains('Payment Guide')));
      expect(md, isNot(contains('Cart Module')), reason: 'headline dropped');
      expect(md, contains('\n### Classes\n'));
      expect(md, contains('\n#### Cart\n'));
      expect(md, contains('\n### Using a cart\n'));
      expect(md, contains('\n## not a heading\n'), reason: 'code untouched');
      expect(md, isNot(contains('](')));
      expect(md, isNot(contains('→')));
      expect(md, contains('| Module | Summary |'));
      expect(md, contains('| Cart | api_summary_cart.md |'));
      expect(md, contains('Adds an item; see Payment.'));
      expect(md, contains(r'`a \| b` stays one cell.'));
    });
  });

  group('the command', () {
    late String fakeMd2pdf;

    setUpAll(() async {
      // A stand-in md2pdf: writes `%PDF-fake` as <output>/<input name>.pdf,
      // exits 3 when the input holds FAIL, and hangs when it holds SLOW.
      final dir = Directory.systemTemp.createTempSync('fake_md2pdf_');
      final source = File(p.join(dir.path, 'fake.dart'))
        ..writeAsStringSync(r'''
import 'dart:io';
void main(List<String> args) {
  final input = args.first;
  final out = args.firstWhere((a) => a.startsWith('--output=')).substring(9);
  final text = File(input).readAsStringSync();
  if (text.contains('FAIL')) exit(3);
  if (text.contains('SLOW')) sleep(const Duration(seconds: 60));
  final name = input.split(Platform.pathSeparator).last.replaceAll('.md', '');
  File('$out${Platform.pathSeparator}$name.pdf').writeAsStringSync('%PDF-fake');
}
''');
      fakeMd2pdf = p.join(
        dir.path,
        Platform.isWindows ? 'md2pdf.exe' : 'md2pdf',
      );
      final r = await Process.run('dart', [
        'compile',
        'exe',
        source.path,
        '-o',
        fakeMd2pdf,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });

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

    test('BK-APIREF-4: renders the reference into build/api_reference, '
        'never doc/, and names the guide-less modules [2026-11-14]', () async {
      final dir = shop();
      final r = await buildkit([':apireference', '--md2pdf', fakeMd2pdf]);
      expect(r.exitCode, 0, reason: out(r));
      final outDir = p.join(dir, 'build', 'api_reference');
      expect(
        File(p.join(outDir, 'shop_api_reference.pdf')).readAsStringSync(),
        '%PDF-fake',
      );
      expect(
        File(p.join(outDir, 'shop_api_reference.md')).readAsStringSync(),
        contains('## Cart Reference'),
      );
      expect(
        Directory(
          p.join(dir, 'doc'),
        ).listSync().map((e) => p.basename(e.path)).toSet(),
        {'api', 'cart'},
        reason: 'nothing written into doc/',
      );
      final text = out(r);
      expect(text, contains('shop: no guide for payment'));
      expect(
        text,
        contains(
          'shop: ok — index, 2 summaries, 1 guide -> '
          '${p.join('build', 'api_reference', 'shop_api_reference.pdf')}',
        ),
      );
    });

    test('BK-APIREF-5: a package with missing inputs fails and names them; '
        'an undocumented one is skipped; the others still render '
        '[2026-11-14]', () async {
      shop();
      final broken = package('broken', {
        'doc/api/api_summary_index.md':
            '# Index\n\n[Gone](api_summary_gone.md)\n',
        'doc/api/api_summary_cart.md': _cart,
      });
      package('bare', {});
      final r = await buildkit([':apireference', '--md2pdf', fakeMd2pdf]);
      expect(r.exitCode, isNot(0), reason: out(r));
      final text = out(r);
      expect(
        text,
        contains(
          'broken: missing input: the index links to '
          '${p.join('doc', 'api', 'api_summary_gone.md')}, which does not exist',
        ),
      );
      expect(text, contains('broken: 1 missing input(s)'));
      expect(text, contains('bare: NOT DOCUMENTED — no doc/api/'));
      expect(text, contains('shop: ok'));
      expect(Directory(p.join(broken, 'build')).existsSync(), isFalse);
    });

    test('BK-APIREF-6: md2pdf failing, or not there, fails the package '
        '[2026-11-14]', () async {
      shop(extra: {'doc/cart/cart.md': '# Cart Guide\n\nFAIL\n'});
      var r = await buildkit([':apireference', '--md2pdf', fakeMd2pdf]);
      expect(r.exitCode, isNot(0), reason: out(r));
      expect(out(r), contains('failed (exit 3), no PDF written'));

      r = await buildkit([
        ':apireference',
        '--md2pdf',
        p.join(root.path, 'no_such_md2pdf'),
      ]);
      expect(r.exitCode, isNot(0), reason: out(r));
      expect(out(r), contains('could not be run'));
    });

    test('BK-APIREF-9: an md2pdf that does not finish within --timeout is '
        'stopped and fails the package [2026-11-14]', () async {
      shop(extra: {'doc/cart/cart.md': '# Cart Guide\n\nSLOW\n'});
      final watch = Stopwatch()..start();
      final r = await buildkit([
        ':apireference',
        '--md2pdf',
        fakeMd2pdf,
        '--timeout',
        '3',
      ]);
      expect(r.exitCode, isNot(0), reason: out(r));
      expect(out(r), contains('did not finish within 3 s'));
      expect(watch.elapsed, lessThan(const Duration(seconds: 50)));
    });

    test('BK-APIREF-7: --output inside doc/ is refused; --dry-run writes '
        'nothing [2026-11-14]', () async {
      final dir = shop();
      var r = await buildkit([
        ':apireference',
        '--md2pdf',
        fakeMd2pdf,
        '--output',
        'doc/reference',
      ]);
      expect(r.exitCode, isNot(0));
      expect(out(r), contains('hand-authored'));
      expect(Directory(p.join(dir, 'doc', 'reference')).existsSync(), isFalse);

      r = await buildkit([
        '--dry-run',
        ':apireference',
        '--md2pdf',
        fakeMd2pdf,
      ]);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('[DRY RUN] shop: index, 2 summaries, 1 guide'));
      expect(Directory(p.join(dir, 'build')).existsSync(), isFalse);
    });

    test('BK-APIREF-8: with the real tom_md2pdf the reference is a PDF '
        '[2026-11-14]', () async {
      final source = _md2pdfSource();
      if (source == null) {
        markTestSkipped('tom_md2pdf source not in this workspace');
        return;
      }
      final exe = p.join(
        root.path,
        Platform.isWindows ? 'md2pdf.exe' : 'md2pdf',
      );
      final pubGet = await Process.run('dart', [
        'pub',
        'get',
      ], workingDirectory: p.dirname(p.dirname(source)));
      expect(pubGet.exitCode, 0, reason: '${pubGet.stderr}');
      final compiled = await Process.run('dart', [
        'compile',
        'exe',
        source,
        '-o',
        exe,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stderr}');
      final dir = shop();
      final r = await buildkit([':apireference', '--md2pdf', exe]);
      expect(r.exitCode, 0, reason: out(r));
      final pdf = File(
        p.join(dir, 'build', 'api_reference', 'shop_api_reference.pdf'),
      );
      expect(String.fromCharCodes(pdf.readAsBytesSync().take(5)), '%PDF-');
      expect(pdf.lengthSync(), greaterThan(1000));
    });
  });
}

/// `tom_ai/devops/tom_md2pdf/bin/md_pdf_converter.dart` of the workspace
/// this package sits in, or null.
String? _md2pdfSource() {
  var dir = Directory.current.absolute;
  while (true) {
    final candidate = p.join(
      dir.path,
      'tom_ai',
      'devops',
      'tom_md2pdf',
      'bin',
      'md_pdf_converter.dart',
    );
    if (File(candidate).existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}
