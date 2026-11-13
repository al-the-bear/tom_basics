// BK-APISUM: `buildkit :apisummary` — a package's public API against its
// hand-authored doc/api/api_summary_*.md. BK-APISUM-1..6 call the check on
// fixture packages; 7..8 run the real executable, rooted at the fixtures
// under .dart_tool (-R) so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/apisummary/api_summary_check.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

/// The package's code: one entry point exporting a class, an enum, an
/// extension, a function and a constant from src/, and an internal class.
const _code = {
  'lib/shop.dart':
      "export 'src/cart.dart';\nexport 'src/internal.dart' show Base;\n",
  'lib/src/cart.dart': '''
import 'internal.dart';

/// A cart.
class Cart extends Base {
  Cart(this.owner);
  Cart.empty() : owner = '';

  /// Who owns it.
  final String owner;

  /// Adds an item.
  void add(String item) {}

  /// The total.
  int get total => 0;

  @override
  String toString() => owner;
}

/// How a cart is paid.
enum Payment { card, cash }

/// Cart helpers.
extension CartTools on Cart {
  /// Empties the cart.
  void clear() {}
}

/// Opens a cart.
Cart openCart(String owner) => Cart(owner);

/// The most items a cart holds.
const maxItems = 50;
''',
  'lib/src/internal.dart': '''
/// The base every cart extends.
abstract class Base {
  /// Saves it.
  void save() {}
}

class Hidden {}
''',
};

/// A summary documenting all of [_code]'s public API.
const _complete = '''
# Shop API Reference: Cart Module

## Classes

### Cart

A cart. Created with `Cart.empty()` when nobody owns it yet.

#### Properties

| Property | Type | Description |
| -------- | ---- | ----------- |
| `owner` | `String` | Who owns it. |
| `total` | `int` | *(getter)* The total. |

#### Methods

| Method | Signature | Description |
| ------ | --------- | ----------- |
| `add` | `void add(String item)` | Adds an item. |
| `toString` | `String toString()` | The owner. |
| `clear` | `void clear()` | Empties the cart (extension `CartTools`). |

### Base

#### Methods

| Method | Signature | Description |
| ------ | --------- | ----------- |
| `save` | `void save()` | Saves it. |

### Payment

| Value | Description |
| ----- | ----------- |
| `card` | By card. |
| `cash` | In cash. |

### CartTools

Cart helpers; its members are listed with `Cart`.

## Global Functions and Constants

| Function | Signature | Description |
| -------- | --------- | ----------- |
| `openCart` | `Cart openCart(String owner)` | Opens a cart. |

| Constant | Type | Description |
| -------- | ---- | ----------- |
| `maxItems` | `int` | The most items a cart holds. |
''';

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('apisummary_test_');
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A package `shop` with [_code] and, when given, [summary] as
  /// doc/api/api_summary_cart.md.
  String package(String name, {String? summary}) {
    final dir = p.join(root.path, name);
    ({
      'pubspec.yaml': 'name: shop\nenvironment:\n  sdk: ^3.0.0\n',
      ..._code,
      'doc/api/api_summary_cart.md': ?summary,
      // The index is not a summary of its own.
      if (summary != null)
        'doc/api/api_summary_index.md': '# Index\n\n### Ghost\n',
    }).forEach((path, text) {
      File(p.join(dir, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  test('BK-APISUM-1: a complete summary has no finding [2026-11-14]', () {
    final r = checkApiSummary(package('shop', summary: _complete), 'shop');
    expect(r.measured, isTrue);
    expect(r.summaryFiles, [p.join('doc', 'api', 'api_summary_cart.md')]);
    expect(r.missing, isEmpty, reason: '${r.missing}');
    expect(r.stale, isEmpty, reason: '${r.stale}');
    expect(r.apiSymbols, greaterThan(0));
    expect(r.claims, greaterThan(0));
  });

  test('BK-APISUM-2: a summary missing a class reports the class, not its '
      'members one by one [2026-11-14]', () {
    final summary = _complete.replaceFirst(
      RegExp(r'### Base\n.*?(?=### Payment)', dotAll: true),
      '',
    );
    final r = checkApiSummary(package('shop', summary: summary), 'shop');
    expect(r.missing.map((f) => f.symbol), ['Base']);
    expect(r.missing.single.kind, 'class');
    expect(r.missing.single.file, p.join('lib', 'src', 'internal.dart'));
    expect(r.stale, isEmpty);
  });

  test('BK-APISUM-3: a summary naming a removed member, function or class '
      'reports each, with the summary line [2026-11-14]', () {
    final summary = _complete
        .replaceFirst(
          '| `add` | `void add(String item)` | Adds an item. |',
          '| `add` | `void add(String item)` | Adds an item. |\n'
              '| `checkout` | `void checkout()` | Removed in 2.0. |',
        )
        .replaceFirst(
          '| `openCart` |',
          '| `closeCart` | `void closeCart()` | Gone. |\n| `openCart` |',
        )
        .replaceFirst(
          '### CartTools',
          '### SavedCart\n\nGone.\n\n### CartTools',
        );
    final r = checkApiSummary(package('shop', summary: summary), 'shop');
    expect(r.stale.map((f) => f.symbol).toSet(), {
      'Cart.checkout',
      'closeCart',
      'SavedCart',
    });
    final checkout = r.stale.singleWhere((f) => f.symbol == 'Cart.checkout');
    expect(checkout.kind, 'table');
    expect(checkout.file, p.join('doc', 'api', 'api_summary_cart.md'));
    expect(checkout.line, greaterThan(0));
    expect(r.missing, isEmpty);
  });

  test('BK-APISUM-4: a member missing from its type\'s section, a missing '
      'constant, and a `Type.member` code span to a removed member '
      '[2026-11-14]', () {
    final summary = _complete
        .replaceFirst('| `total` | `int` | *(getter)* The total. |\n', '')
        .replaceFirst(
          '| `maxItems` | `int` | The most items a cart holds. |\n',
          '',
        )
        .replaceFirst(
          'A cart. Created with',
          'A cart; `Cart.discount()` applies a code. Created with',
        );
    final r = checkApiSummary(package('shop', summary: summary), 'shop');
    expect(r.missing.map((f) => f.symbol).toSet(), {'Cart.total', 'maxItems'});
    expect(r.stale.map((f) => f.symbol), ['Cart.discount']);
    expect(r.stale.single.kind, 'code span');
  });

  test('BK-APISUM-5: members found in the section of a supertype or of the '
      'extended type; inherited and Object members are no stale claims '
      '[2026-11-14]', () {
    final summary = _complete.replaceFirst(
      '| `toString` | `String toString()` | The owner. |',
      '| `toString` | `String toString()` | The owner. |\n'
          '| `save` | `void save()` | Inherited from `Base`. |\n'
          '| `hashCode` | `int` | Object\'s. |',
    );
    final r = checkApiSummary(package('shop', summary: summary), 'shop');
    expect(r.stale, isEmpty, reason: '${r.stale}');
    expect(r.missing, isEmpty, reason: 'CartTools.clear is in Cart\'s table');
  });

  test('BK-APISUM-6: a package without a summary is not measured; the index '
      'alone is no summary [2026-11-14]', () {
    final dir = package('bare');
    expect(apiSummaryFilesOf(dir), isEmpty);
    expect(checkApiSummary(dir, 'shop').measured, isFalse);
    File(p.join(dir, 'doc', 'api', 'api_summary_index.md'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('# Index\n');
    expect(checkApiSummary(dir, 'shop').measured, isFalse);
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

    test('BK-APISUM-7: findings in both directions are printed; --strict '
        'exits 1, without it the run passes [2026-11-14]', () async {
      package(
        'shop',
        summary: _complete
            .replaceFirst(
              RegExp(r'### Base\n.*?(?=### Payment)', dotAll: true),
              '',
            )
            .replaceFirst(
              '| `openCart` |',
              '| `closeCart` | `x` | Gone. |\n| `openCart` |',
            ),
      );
      var r = await buildkit([':apisummary']);
      expect(r.exitCode, 0, reason: out(r));
      final text = out(r);
      expect(
        text,
        contains(
          'shop: missing from the summary: Base (class, '
          '${p.join('lib', 'src', 'internal.dart')}:2)',
        ),
      );
      expect(text, contains('shop: not in the API: closeCart (table, '));
      expect(text, contains('shop: out of date — '));
      expect(text, contains('1 missing, 1 not in the API'));

      r = await buildkit([':apisummary', '--strict']);
      expect(r.exitCode, 1, reason: out(r));
    });

    test('BK-APISUM-8: an up-to-date summary passes --strict; a package '
        'without one is named NOT MEASURED and skipped [2026-11-14]', () async {
      package('shop', summary: _complete);
      package('bare');
      final r = await buildkit([':apisummary', '--strict']);
      expect(r.exitCode, 0, reason: out(r));
      final text = out(r);
      expect(text, contains('shop: up to date — '));
      expect(
        text,
        contains(
          'bare: NOT MEASURED — no API summary (doc/api/api_summary_*.md)',
        ),
      );
    });
  });
}
