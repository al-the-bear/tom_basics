// BK-BND: `buildkit :boundaries` — tom_build_base's context-boundary check
// run through the real executable, because its exit code is the gate's
// verdict. Fixture packages live under .dart_tool and the run is rooted at
// them (-R), so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

const _rules = '''
boundaries:
  contexts:
    - name: billing
      libraries: [src/billing/**]
      public: [src/billing/billing.dart]
      dependsOn: [identity]
    - name: identity
      libraries: [src/identity/**]
      public: [src/identity/identity.dart]
''';

void main() {
  late Directory root;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('boundaries_test_');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A package [name] under the fixture root with [files] (paths relative to
  /// the package) and, when given, [rules] as its buildkit.yaml.
  String package(String name, Map<String, String> files, {String? rules}) {
    final dir = p.join(root.path, name);
    final all = {
      'pubspec.yaml': 'name: $name\nenvironment:\n  sdk: ^3.0.0\n',
      'buildkit.yaml': ?rules,
      ...files,
    };
    all.forEach((path, text) {
      File(p.join(dir, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  Map<String, String> shop({
    String billing = "import '../identity/identity.dart';\n",
  }) => {
    'lib/src/billing/billing.dart': billing,
    'lib/src/identity/identity.dart': 'class Identity {}\n',
    'lib/src/identity/users.dart': 'class User {}\n',
  };

  Future<ProcessResult> buildkit(String cwd, List<String> args) => Process.run(
    'dart',
    ['run', _buildkit, '-R', root.path, ...args],
    workingDirectory: cwd,
  );

  String out(ProcessResult r) => '${r.stdout}${r.stderr}';

  test('BK-BND-1: a package that keeps its boundaries exits 0', () async {
    final dir = package('shop', shop(), rules: _rules);
    final r = await buildkit(dir, [':boundaries']);
    expect(r.exitCode, 0, reason: out(r));
    expect(out(r), contains('shop: clean'));
  });

  test(
    'BK-BND-2: a boundary violation exits 1 and names file and line',
    () async {
      final dir = package(
        'shop',
        shop(billing: "import '../identity/users.dart';\n"),
        rules: _rules,
      );
      final r = await buildkit(dir, [':boundaries']);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('lib/src/billing/billing.dart:1'));
      expect(out(r), contains('internal-import'));
    },
  );

  test('BK-BND-3: --json prints the report as one JSON line', () async {
    final dir = package(
      'shop',
      shop(billing: "import '../identity/users.dart';\n"),
      rules: _rules,
    );
    final r = await buildkit(dir, [':boundaries', '--json']);
    expect(r.exitCode, 1, reason: out(r));
    final line = LineSplitter.split(
      '${r.stdout}',
    ).firstWhere((l) => l.startsWith('{'));
    final report = jsonDecode(line) as Map<String, dynamic>;
    expect(report['verdict'], 'violations');
    final violation = (report['violations'] as List).single as Map;
    expect(violation['kind'], 'internal-import');
    expect(violation['file'], 'lib/src/billing/billing.dart');
    expect(violation['line'], 1);
  });

  test('BK-BND-4: a rotted rule exits 1', () async {
    final dir = package(
      'shop',
      shop(),
      rules: _rules.replaceFirst('src/billing/**', 'src/payments/**'),
    );
    final r = await buildkit(dir, [':boundaries']);
    expect(r.exitCode, 1, reason: out(r));
    expect(out(r), contains('rotted-glob'));
  });

  test('BK-BND-5: asked for a package without rules, it is NOT MEASURED and '
      'exits 1', () async {
    final dir = package('plain', {'lib/plain.dart': 'int x = 1;\n'});
    final r = await buildkit(dir, [':boundaries']);
    expect(r.exitCode, 1, reason: out(r));
    expect(out(r), contains('NOT MEASURED'));
  });

  test('BK-BND-6: over a traversal, a package without rules is skipped by '
      'name', () async {
    package('shop', shop(), rules: _rules);
    package('plain', {'lib/plain.dart': 'int x = 1;\n'});
    final r = await buildkit(root.path, ['-s', root.path, ':boundaries']);
    expect(r.exitCode, 0, reason: out(r));
    expect(out(r), contains('shop: clean'));
    expect(out(r), contains('plain'));
    expect(out(r), contains('NOT MEASURED'));
  });
}
