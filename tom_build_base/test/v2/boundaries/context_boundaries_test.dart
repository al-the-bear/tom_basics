// BB-CB: the context-boundary check (ccla4) and the directive scanner it
// reads imports with. Every package here is a fixture written to a temporary
// folder; nothing reads the workspace.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

/// A fixture package: two contexts (billing, identity) and shared code.
///
///   lib/app.dart                         shared
///   lib/src/shared/util.dart             shared
///   lib/src/billing/billing.dart         billing, public; part 'invoice.dart'
///   lib/src/billing/invoice.dart         part of billing.dart
///   lib/src/billing/ledger.dart          billing, internal
///   lib/src/identity/identity.dart       identity, public
///   lib/src/identity/users.dart          identity, internal
const _rules = '''
boundaries:
  contexts:
    - name: billing
      libraries: [src/billing/**]
      public: [src/billing/billing.dart]
      dependsOn: [identity]
      tests: [billing/**]
    - name: identity
      libraries: [src/identity/**]
      public: [src/identity/identity.dart]
      tests: [identity/**]
''';

final _files = <String, String>{
  'pubspec.yaml': 'name: shop\nenvironment:\n  sdk: ^3.0.0\n',
  'lib/app.dart':
      "import 'src/billing/billing.dart';\n"
      "import 'package:shop/src/identity/identity.dart';\n",
  'lib/src/shared/util.dart': 'int one() => 1;\n',
  'lib/src/billing/billing.dart':
      "import '../identity/identity.dart';\n"
      "import '../shared/util.dart';\n"
      "import 'ledger.dart';\n"
      "part 'invoice.dart';\n",
  'lib/src/billing/invoice.dart': "part of 'billing.dart';\n",
  'lib/src/billing/ledger.dart':
      "import 'package:shop/src/shared/util.dart';\n",
  'lib/src/identity/identity.dart':
      "export 'users.dart';\n"
      "import '../shared/util.dart';\n",
  'lib/src/identity/users.dart': 'class User {}\n',
};

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('context_boundaries_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  void write(Map<String, String> files) {
    files.forEach((path, text) {
      final file = File(p.join(root.path, path));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(text);
    });
  }

  /// The fixture package with [rules] in its buildkit.yaml (none when null)
  /// and [changes] on top of the clean files.
  BoundaryReport check(
    String? rules, [
    Map<String, String> changes = const {},
    bool? includeTests,
  ]) {
    write({..._files, ...changes, 'buildkit.yaml': ?rules});
    return checkContextBoundaries(root.path, includeTests: includeTests);
  }

  group('scanDartDirectives', () {
    test('BB-CB-1: imports, exports, parts and conditional imports', () {
      final d = scanDartDirectives('''
library shop;

import 'dart:io';
import 'a.dart' as a show A;
import 'stub.dart'
    if (dart.library.io) 'io.dart';
export 'b.dart' hide B;
part 'c.dart';
part of 'd.dart';
''');
      expect(d.map((x) => x.kind).toList(), [
        DartDirectiveKind.import,
        DartDirectiveKind.import,
        DartDirectiveKind.import,
        DartDirectiveKind.export,
        DartDirectiveKind.part,
        DartDirectiveKind.partOf,
      ]);
      expect(d[1].uris, ['a.dart']);
      expect(d[1].line, 4);
      expect(d[2].uris, ['stub.dart', 'io.dart']);
      expect(d[3].uris, ['b.dart']);
    });

    test('BB-CB-2: directives in comments and strings do not count', () {
      final d = scanDartDirectives(r'''
// import 'commented.dart';
/* import 'block.dart'; /* nested */ import 'still_comment.dart'; */
import 'real.dart';
const s = """
import 'in_string.dart';
""";
const t = 'x ${ {'k': 'v'}['k'] } import \'esc.dart\';';
const r = r'import \';
void f() { import_ = 1; }
''');
      expect(d.map((x) => x.uris.single).toList(), ['real.dart']);
      expect(d.single.line, 3);
    });
  });

  group('checkContextBoundaries', () {
    test('BB-CB-3: a package that keeps its boundaries is clean', () {
      final report = check(_rules);
      expect(report.ruleErrors, isEmpty, reason: '${report.ruleErrors}');
      expect(report.violations, isEmpty, reason: '${report.violations}');
      expect(report.clean, isTrue);
      expect(report.verdict, 'clean');
      // invoice.dart is a part, not a library
      expect(report.librariesChecked, 6);
      expect(report.importsChecked, greaterThanOrEqualTo(8));
    });

    test('BB-CB-4: importing another context\'s internals is a violation', () {
      final report = check(_rules, {
        'lib/src/billing/ledger.dart':
            "import 'package:shop/src/shared/util.dart';\n"
            "import '../identity/users.dart';\n",
      });
      final v = report.violations.single;
      expect(v.kind, 'internal-import');
      expect(v.file, 'lib/src/billing/ledger.dart');
      expect(v.line, 2);
      expect(v.imported, 'lib/src/identity/users.dart');
      expect(v.context, 'billing');
      expect(report.clean, isFalse);
    });

    test('BB-CB-5: a context not in dependsOn may not be imported at all', () {
      final report = check(_rules, {
        'lib/src/identity/users.dart':
            "import 'package:shop/src/billing/billing.dart';\nclass User {}\n",
      });
      final v = report.violations.single;
      expect(v.kind, 'undeclared-dependency');
      expect(v.file, 'lib/src/identity/users.dart');
      expect(v.imported, 'lib/src/billing/billing.dart');
      expect(v.message, contains('`identity` may not depend on `billing`'));
    });

    test('BB-CB-6: an export crosses a boundary like an import', () {
      final report = check(_rules, {
        'lib/src/billing/ledger.dart': "export '../identity/users.dart';\n",
      });
      expect(report.violations.single.kind, 'internal-import');
    });

    test('BB-CB-7: a part file\'s imports are its library\'s', () {
      // Enhanced parts may import: invoice.dart belongs to billing.dart.
      final report = check(_rules, {
        'lib/src/billing/invoice.dart':
            "part of 'billing.dart';\nimport '../identity/users.dart';\n",
      });
      final v = report.violations.single;
      expect(v.file, 'lib/src/billing/invoice.dart');
      expect(v.context, 'billing');
    });

    test('BB-CB-8: shared libraries may import and be imported by anyone', () {
      final report = check(_rules, {
        'lib/app.dart':
            "import 'src/billing/ledger.dart';\n"
            "import 'src/identity/users.dart';\n",
      });
      expect(report.violations, isEmpty);
    });

    test('BB-CB-9: a rotted rule is reported, not skipped', () {
      final report = check('''
boundaries:
  contexts:
    - name: billing
      libraries: [src/billing/**, src/payments/**]
      public: [src/billing/billing.dart, src/billing/gone.dart]
      dependsOn: [identity, audit]
    - name: identity
      libraries: [src/identity/**]
      public: [src/identity/identity.dart]
''');
      expect(report.violations, isEmpty);
      expect(report.ruleErrors.map((e) => e.kind).toList()..sort(), [
        'rotted-glob',
        'rotted-public',
        'unknown-dependency',
      ]);
      expect(
        report.ruleErrors.map((e) => e.message).join('\n'),
        allOf(
          contains('src/payments/**'),
          contains('src/billing/gone.dart'),
          contains('`audit`'),
        ),
      );
      expect(report.clean, isFalse);
      expect(report.verdict, 'violations');
    });

    test('BB-CB-10: a library two contexts claim is a rule error', () {
      final report = check('''
boundaries:
  contexts:
    - name: billing
      libraries: [src/billing/**, src/shared/**]
      public: [src/billing/billing.dart]
      dependsOn: [identity]
    - name: identity
      libraries: [src/identity/**, src/shared/util.dart]
      public: [src/identity/identity.dart]
''');
      final overlap = report.ruleErrors.where((e) => e.kind == 'overlap');
      expect(overlap.single.file, 'lib/src/shared/util.dart');
      expect(report.clean, isFalse);
    });

    test('BB-CB-11: no rules is not measured, never clean', () {
      final report = check(null);
      expect(report.measured, isFalse);
      expect(report.clean, isFalse);
      expect(report.verdict, 'not-measured');
      expect(report.toJson()['verdict'], 'not-measured');
    });

    test(
      'BB-CB-12: an invalid section and a duplicate context are reported',
      () {
        final none = check('boundaries:\n  tests: true\n');
        expect(none.ruleErrors.map((e) => e.kind), contains('invalid-section'));
        final dup = check('''
boundaries:
  contexts:
    - name: a
      libraries: [src/billing/**]
    - name: a
      libraries: [src/identity/**]
''');
        expect(
          dup.ruleErrors.map((e) => e.kind),
          contains('duplicate-context'),
        );
      },
    );

    test('BB-CB-13: tests are checked when asked, and their globs can rot', () {
      final testFiles = {
        'test/billing/ledger_test.dart':
            "import 'package:shop/src/identity/users.dart';\n",
        'test/helpers.dart': "import 'package:shop/src/billing/ledger.dart';\n",
      };
      expect(
        check(_rules, testFiles).violations,
        isEmpty,
        reason: 'test/ is not read by default',
      );

      final report = check(_rules, testFiles, true);
      final v = report.violations.single;
      expect(v.file, 'test/billing/ledger_test.dart');
      expect(v.kind, 'internal-import');
      // identity's tests glob matches no file under test/
      expect(report.ruleErrors.single.message, contains('tests: identity/**'));
    });

    test('BB-CB-14: the report renders as JSON with every finding', () {
      final report = check(_rules, {
        'lib/src/billing/ledger.dart': "import '../identity/users.dart';\n",
      });
      final json = report.toJson();
      expect(json['verdict'], 'violations');
      final violation = (json['violations'] as List).single as Map;
      expect(violation['file'], 'lib/src/billing/ledger.dart');
      expect(violation['line'], 1);
      expect(violation['imported'], 'lib/src/identity/users.dart');
    });
  });
}
