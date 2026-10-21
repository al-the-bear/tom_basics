/// The unreferenced-export audit (`:unreferenced`), proved to be checkable: a
/// tree planted to break each rule makes it fire, a stale allowlist entry
/// fails it, a tree with nothing exported proves nothing — and the
/// `unreferenced:` section of `buildkit.yaml` configures it, refusing an
/// allowlist entry without a reason.
///
/// Test IDs: UNREF-1 – UNREF-9
@TestOn('!browser')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/executors/unreferenced_executor.dart';
import 'package:tom_build_kit/unreferenced_exports.dart';

void main() {
  // Scratch trees go to this package's gitignored ztmp/, never the system
  // temporary directory.
  final scratch = Directory(p.join(Directory.current.path, 'ztmp', 'unref'));
  var counter = 0;

  /// Materializes a throwaway root; [files] maps root-relative paths to
  /// contents.
  String fixture(Map<String, String> files) {
    final root = p.join(scratch.path, 'f${counter++}');
    final dir = Directory(root);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (final entry in files.entries) {
      final file = File(p.join(root, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    return root;
  }

  String pubspec(String name) => 'name: $name\nenvironment:\n  sdk: ^3.10.8\n';

  /// One producer package, one consumer package (its `bin/` entry point), a test that names some of
  /// the producer's surface, and a runnable example application.
  Map<String, String> tree({String consumer = 'AlphaUsed().usedMember();'}) => {
    'my_alpha/pubspec.yaml': pubspec('my_alpha'),
    'my_alpha/lib/my_alpha.dart': "export 'src/alpha.dart';\n",
    'my_alpha/lib/src/alpha.dart': '''
class AlphaUsed {
  void usedMember() {}
  void deadMember() {}
  int get insideOnly => _helper();
  int _helper() => insideOnly;
  @visibleForTesting
  int get seam => 1;
  @visibleForTesting
  int get deadSeam => 2;
}

void alphaDead() {}

void alphaForExample() {}

/// A comment naming alphaDead is not a use.
void alphaSiblingUser() => alphaSibling();

void alphaSibling() {}
''',
    'my_alpha/test/alpha_test.dart':
        'void main() { AlphaUsed()..seam..deadMember(); }\n',
    'my_alpha/example/pubspec.yaml': pubspec('my_alpha_example'),
    'my_alpha/example/lib/main.dart': 'void main() => alphaForExample();\n',
    'my_beta/pubspec.yaml': pubspec('my_beta'),
    'my_beta/bin/beta.dart': 'void main() { $consumer alphaSiblingUser(); }\n',
  };

  Iterable<String> symbolsOf(List<UnreferencedExport> findings) =>
      findings.map((f) => f.symbol.symbol);

  group('UNREF a planted tree', () {
    test('UNREF-1: an unreferenced export is caught, with whether a test '
        'names it; a use in another lib, in the declaring file outside the '
        'declaration, or in an example application counts', () {
      final root = fixture(tree());
      final report = auditUnreferencedExports(root: root, packagePrefix: 'my_');

      final found = {for (final f in report.unreferenced) f.symbol.symbol: f};
      expect(found.keys.toSet(), {
        'AlphaUsed.deadMember',
        'AlphaUsed.insideOnly',
        'AlphaUsed.deadSeam',
        'alphaDead',
      });
      expect(found['AlphaUsed.deadMember']!.namedByTests, isTrue);
      expect(
        found['AlphaUsed.deadMember']!.verdict,
        startsWith('named by tests only'),
      );
      expect(
        found['alphaDead']!.namedByTests,
        isFalse,
        reason: 'a doc comment naming it is not a use',
      );
      expect(
        found['AlphaUsed.insideOnly']!.verdict,
        contains('private'),
        reason: 'used inside its own type and nowhere else: wrong visibility',
      );
      expect(
        report.checked,
        contains('my_alpha alphaForExample'),
        reason:
            'the example application is a consumer, so it is checked '
            'and passes',
      );
      expect(report.holds, isFalse);
    });

    test('UNREF-2: a declared test seam passes while a test names it, and '
        'is a finding once none does', () {
      final report = auditUnreferencedExports(
        root: fixture(tree()),
        packagePrefix: 'my_',
      );
      expect(symbolsOf(report.unreferenced), isNot(contains('AlphaUsed.seam')));
      expect(report.testSeams, 1);
      final dead = report.unreferenced.singleWhere(
        (f) => f.symbol.symbol == 'AlphaUsed.deadSeam',
      );
      expect(dead.symbol.declaredTestSeam, isTrue);
      expect(dead.verdict, contains('no test names'));
    });

    test('UNREF-3: an allowlist entry excuses its symbol — a type entry its '
        'members — and a stale one fails the audit', () {
      final root = fixture(tree(consumer: ''));
      final report = auditUnreferencedExports(
        root: root,
        packagePrefix: 'my_',
        allowlist: const [
          AllowedUnreferencedExport(
            'my_alpha',
            'alphaDead',
            'planted: excused',
          ),
          AllowedUnreferencedExport(
            'my_alpha',
            'AlphaUsed',
            'planted: a type entry',
          ),
          AllowedUnreferencedExport('my_alpha', 'alphaGone', 'planted: stale'),
        ],
      );

      expect(
        symbolsOf(report.unreferenced),
        isEmpty,
        reason: report.unreferenced.join('\n'),
      );
      expect(
        {for (final (e, f) in report.allowed) f.symbol.symbol: e.symbol},
        containsPair('AlphaUsed.usedMember', 'AlphaUsed'),
        reason: 'with the consumer gone, the type entry covers its members',
      );
      expect(report.stale.map((e) => e.symbol), ['alphaGone']);
      expect(report.holds, isFalse, reason: 'a stale entry fails the audit');
    });

    test('UNREF-4: a tree with nothing exported proves nothing', () {
      final root = fixture({'my_empty/pubspec.yaml': pubspec('my_empty')});
      final report = auditUnreferencedExports(root: root, packagePrefix: 'my_');
      expect(report.symbolsChecked, 0);
      expect(report.holds, isFalse);
    });
  });

  group('UNREF the configuration and the command', () {
    String section(String allow) =>
        'unreferenced:\n'
        '  root: ..\n'
        '  package-prefix: my_\n'
        '  exclude: [my_kit]\n'
        '  consumer-repositories: [../../consumers]\n'
        '  allow:\n$allow';

    test('UNREF-5: the section is read with its paths resolved against the '
        'project; no section is no configuration', () {
      final root = fixture({
        'repo/my_host/buildkit.yaml': section(
          '    - package: my_alpha\n      symbol: alphaDead\n'
          '      reason: planted\n',
        ),
        'repo/my_other/buildkit.yaml': 'versioner: {}\n',
      });
      final config = UnreferencedExportsConfig.load(
        p.join(root, 'repo', 'my_host'),
      )!;
      expect(config.root, p.join(root, 'repo'));
      expect(config.packagePrefix, 'my_');
      expect(config.exclude, {'my_kit'});
      expect(config.consumerRepositories, [p.join(root, 'consumers')]);
      expect(config.allowlist.single.symbol, 'alphaDead');
      expect(
        UnreferencedExportsConfig.load(p.join(root, 'repo', 'my_other')),
        isNull,
      );
    });

    test('UNREF-6: an allowlist entry without a reason is refused, naming the '
        'entry', () {
      final root = fixture({
        'repo/my_host/buildkit.yaml': section(
          '    - package: my_alpha\n      symbol: alphaDead\n',
        ),
      });
      expect(
        () => UnreferencedExportsConfig.load(p.join(root, 'repo', 'my_host')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('reason'),
          ),
        ),
      );
    });

    Future<ItemResult> run(String project, {List<String>? out}) =>
        UnreferencedExecutor(write: out?.add ?? (_) {}).execute(
          CommandContext(
            fsFolder: FsFolder(path: project),
            natures: const [],
            executionRoot: project,
          ),
          CliArgs(),
        );

    test('UNREF-7: the command fails on findings and names them; a project '
        'without the section is skipped', () async {
      final root = fixture({
        ...tree(),
        'my_alpha/buildkit.yaml':
            'unreferenced:\n  root: ..\n  package-prefix: my_\n',
      });
      final out = <String>[];
      final result = await run(p.join(root, 'my_alpha'), out: out);
      expect(result.success, isFalse);
      expect(result.error, contains('unreferenced export(s)'));
      expect(out.join('\n'), contains('alphaDead'));
      final skipped = await run(p.join(root, 'my_beta'));
      expect(skipped.skipped, isTrue);
    });

    test('UNREF-8: the command passes when every finding is allowlisted, and '
        'says how much it checked', () async {
      final root = fixture({
        ...tree(),
        'my_alpha/buildkit.yaml': section(
          [
            for (final symbol in [
              'AlphaUsed.deadMember',
              'AlphaUsed.insideOnly',
              'AlphaUsed.deadSeam',
              'alphaDead',
            ])
              '    - package: my_alpha\n      symbol: $symbol\n'
                  '      reason: planted\n',
          ].join(),
        ),
      });
      final out = <String>[];
      final result = await run(p.join(root, 'my_alpha'), out: out);
      expect(result.success, isTrue, reason: result.error ?? out.join('\n'));
      expect(result.message, contains('every exported symbol is referenced'));
    });

    test('UNREF-9: a section whose prefix matches nothing is NOT MEASURED, '
        'a failure', () async {
      final root = fixture({
        'my_alpha/pubspec.yaml': pubspec('my_alpha'),
        'my_alpha/buildkit.yaml':
            'unreferenced:\n  root: ..\n  package-prefix: nothing_\n',
      });
      final result = await run(p.join(root, 'my_alpha'));
      expect(result.success, isFalse);
      expect(result.error, contains('NOT MEASURED'));
    });
  });
}
