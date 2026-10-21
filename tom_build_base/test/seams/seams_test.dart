/// The seam engine (`package:tom_build_base/seams.dart`): each primitive on
/// the shapes that make a naive scan wrong, each walk on a fixture tree, and
/// each rule with a case that must fail as well as one that must pass.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/seams.dart';

/// A snippet with `UP` standing for the two dots and `CWD` for the working
/// directory, so this file never holds the shapes it tests for.
String snippet(String withPlaceholder) => withPlaceholder
    .replaceAll('UP', '..')
    .replaceAll('CWD', 'Directory.current');

void main() {
  late Directory scratch;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, 'ztmp'))
      ..createSync(recursive: true);
    scratch = base.createTempSync('seams_test_');
  });
  tearDown(() {
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  /// Writes [files] (path → content) under the scratch directory.
  String tree(Map<String, String> files) {
    for (final entry in files.entries) {
      File(p.join(scratch.path, entry.key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    return scratch.path;
  }

  group('SEAMS-SRC reading source', () {
    test('SEAMS-SRC-1: directives are read up to the first declaration, '
        'comments and strings are not directives, and a conditional '
        'alternative is one', () {
      final source = '''
// import 'package:fake/in_comment.dart';
/* import 'package:fake/in_block.dart'; */
library;

import 'dart:io';
import 'package:a/a.dart'
    if (dart.library.html) 'package:b/b.dart';
export 'src/x.dart' show X;

const note = "import 'package:fake/in_string.dart';";
import 'package:late/after_declaration.dart';
''';
      expect(directiveUris(source).toList(), [
        'dart:io',
        'package:a/a.dart',
        'package:b/b.dart',
        'src/x.dart',
      ]);
    });

    test('SEAMS-SRC-2: comment stripping keeps strings whole, raw strings '
        'too, and keeps line breaks', () {
      const source =
          "final u = 'https://x.y'; // gone\n"
          "final r = r'C:\\\\';  /* gone\n still gone */ final z = 1;\n";
      final stripped = stripDartComments(source);
      expect(stripped, contains("'https://x.y'"));
      expect(stripped, isNot(contains('gone')));
      expect(stripped, contains("r'C:\\\\'"));
      expect('\n'.allMatches(stripped).length, '\n'.allMatches(source).length);
    });

    test('SEAMS-SRC-3: a quote inside an interpolation does not end the '
        'string', () {
      const source = r'''final s = '"${v.replaceAll('"', '""')}"'; // gone''';
      final code = dartCodeWithoutComments(source);
      expect(code, isNot(contains('gone')));
      expect(code, contains('replaceAll'));
    });

    test('SEAMS-SRC-4: top-level declarations are classified, including a '
        'return type on its own line and a record return type', () {
      const source = '''
class A {}
abstract interface class B {}
mixin M {}
enum E { a }
extension X on A {}
typedef T = int;
Map<String, int>
    f() => {};
(int, String) g() => (1, '');
int get h => 1;
final v = 1;
String _private() => '';
''';
      final found = {
        for (final d in topLevelDeclarations(source)) d.name: d.kind,
      };
      expect(found['A'], 'class');
      expect(found['B'], 'class');
      expect(found['M'], 'mixin');
      expect(found['E'], 'enum');
      expect(found['X'], 'extension');
      expect(found['T'], 'typedef');
      expect(found['f'], 'function');
      expect(found['g'], 'function');
      expect(found['h'], 'getter');
      expect(found, contains('_private'));
    });

    test('SEAMS-SRC-5: a call\'s arguments end at its matching parenthesis, '
        'past a parenthesis inside a string', () {
      const source = "f(a, ')', g(b)) + rest";
      expect(callArgumentsFrom(source, 2), "a, ')', g(b))");
    });
  });

  group('SEAMS-GRAPH the import and package graphs', () {
    Map<String, String> twoPackages() => {
      'one/pubspec.yaml':
          'name: one\ndependencies:\n  two:\n    path: '
          '../two\n  http: ^1.0.0\ndev_dependencies:\n  test: any\n',
      'one/lib/one.dart':
          "import 'src/a.dart';\n"
          "import 'package:one/src/b.dart';\n",
      'one/lib/src/a.dart':
          "import 'dart:io';\nimport 'package:http/http.dart';"
          '\n',
      'one/lib/src/b.dart': "import 'package:two/two.dart';\n",
      'two/pubspec.yaml': 'name: two\n',
      'two/lib/two.dart': "import 'dart:convert';\n",
    };

    test('SEAMS-GRAPH-1: a package closure follows relative and own-package '
        'URIs and stops at other packages', () {
      final root = tree(twoPackages());
      final entry = p.join(root, 'one', 'lib', 'one.dart');
      expect(importClosureOf(entry), hasLength(3));
      expect(externalImportsOf(entry), {
        'dart:io',
        'package:http/http.dart',
        'package:two/two.dart',
      });
      expect(reachableNamesOf(entry), {'dart:io', 'http', 'two'});
    });

    test('SEAMS-GRAPH-2: a sibling closure follows packages with the prefix '
        'into their own lib', () {
      final root = tree(twoPackages());
      final closure = siblingImportClosureOf(
        p.join(root, 'one', 'lib', 'src', 'b.dart'),
        root,
        followPrefix: 'tw',
      );
      expect(closure.keys.map(p.basename), containsAll(['b.dart', 'two.dart']));
      expect(closure.values.expand((e) => e), contains('dart:convert'));
    });

    test('SEAMS-GRAPH-3: every package import under a directory is found, '
        'with the files that carry it', () {
      final root = tree(twoPackages());
      final imports = packageImportsUnder(p.join(root, 'one', 'lib'));
      expect(imports.keys, containsAll(['one', 'http', 'two']));
      expect(imports['http']!.single, endsWith('a.dart'));
    });

    test('SEAMS-GRAPH-4: a pubspec reads its three blocks, path, runtime and '
        'SDK dependencies apart; packages are found one level down', () {
      final root = tree({
        ...twoPackages(),
        'three/pubspec.yaml':
            'name: three\ndependencies:\n  flutter:\n'
            '    sdk: flutter\ndependency_overrides:\n  two:\n    path: ../two\n',
      });
      final one = Pubspec.read(p.join(root, 'one'))!;
      expect(one.dependencies, {'two', 'http', 'test'});
      expect(one.runtimeDependencies, {'two', 'http'});
      expect(one.pathDependencies['two'], p.join(root, 'two'));
      final three = Pubspec.read(p.join(root, 'three'))!;
      expect(three.sdkDependencies, {'flutter'});
      expect(three.dependencies, contains('two'));
      expect(packagesIn(root).map((x) => x.name), ['one', 'three', 'two']);
      expect(Pubspec.read(p.join(root, 'nowhere')), isNull);
    });

    test('SEAMS-GRAPH-5: packages by prefix are found below the top level, '
        'never inside hidden folders', () {
      final root = tree({
        'repo/tom_x_a/pubspec.yaml': 'name: tom_x_a\n',
        'repo/nested/tom_x_b/pubspec.yaml': 'name: tom_x_b\n',
        '.hidden/tom_x_c/pubspec.yaml': 'name: tom_x_c\n',
      });
      expect(prefixedPackagesIn(root, 'tom_x_').map((x) => x.name), [
        'tom_x_a',
        'tom_x_b',
      ]);
    });

    test('SEAMS-GRAPH-6: dependency reach follows path dependencies and '
        'names the chain; an unresolved hosted one is reported, not '
        'assumed clean', () {
      final root = tree({
        'a/pubspec.yaml':
            'name: a\ndependencies:\n  b:\n    path: ../b\n  hosted: ^1.0.0\n',
        'b/pubspec.yaml': 'name: b\ndependencies:\n  banned: any\n',
      });
      final a = Pubspec.read(p.join(root, 'a'))!;
      final reach = dependencyReach(a, isBanned: (n) => n == 'banned');
      expect(reach.reached['banned'], ['a', 'b']);
      expect(reach.unresolved, containsAll(['hosted']));
      expect(resolvedPackagesOf(p.join(root, 'a')), isNull);
    });

    test('SEAMS-GRAPH-7: a resolved graph is read from package_config.json, '
        'and a hosted package is followed through it', () {
      final root = tree({
        'a/pubspec.yaml': 'name: a\ndependencies:\n  hosted: ^1.0.0\n',
        'cache/hosted/pubspec.yaml':
            'name: hosted\ndependencies:\n  banned: any\n',
        'a/.dart_tool/package_config.json':
            '{"configVersion":2,"packages":[{"name":"hosted",'
            '"rootUri":"../../cache/hosted"}]}',
      });
      final resolved = resolvedPackagesOf(p.join(root, 'a'))!;
      expect(resolved['hosted'], p.join(root, 'cache', 'hosted'));
      final a = Pubspec.read(p.join(root, 'a'))!;
      final reach = dependencyReach(a, isBanned: (n) => n == 'banned');
      expect(reach.reached['banned'], ['a', 'hosted']);
      expect(reach.unresolved, isEmpty);
    });

    test('SEAMS-GRAPH-8: declared type names and exported declarations, with '
        'show, hide and parts applied', () {
      final root = tree({
        'one/pubspec.yaml': 'name: one\n',
        'one/lib/one.dart':
            "part 'part.dart';\n"
            "export 'src/a.dart' show A, a;\n"
            "export 'src/b.dart' hide Hidden;\n"
            "class Own {}\n",
        'one/lib/part.dart': "part of 'one.dart';\nclass FromPart {}\n",
        'one/lib/src/a.dart': 'class A {}\nclass NotShown {}\nvoid a() {}\n',
        'one/lib/src/b.dart': 'class B {}\nclass Hidden {}\nclass _P {}\n',
      });
      final exported = exportedDeclarationsOf(
        p.join(root, 'one', 'lib', 'one.dart'),
      );
      expect(exported.keys.toSet(), {'Own', 'FromPart', 'A', 'a', 'B'});
      expect(exported['A']!.isType, isTrue);
      expect(exported['a']!.isType, isFalse);
      expect(
        declaredTypeNamesUnder(p.join(root, 'one', 'lib')),
        containsAll(['A', 'B', 'Hidden', 'Own']),
      );
    });
  });

  group('SEAMS-RULE entry-point rules', () {
    String fixture() => tree({
      'pkg/pubspec.yaml': 'name: pkg\n',
      'pkg/lib/pkg.dart':
          "import 'dart:io';\nimport 'package:net/net.dart';\n"
          "import 'package:dep/web.dart';\n",
      'pkg/lib/pure.dart': "import 'package:dep/dep.dart';\n",
    });

    test('SEAMS-RULE-1: a banned package, a banned URI and a missing '
        'required package each fail, under the seam named', () {
      final root = fixture();
      final violations = auditEntryPointRules(root, const [
        EntryPointRule(
          package: 'pkg',
          entryPoint: 'lib/pkg.dart',
          banned: {'dart:io', 'net'},
          bannedUris: {'package:dep/web.dart'},
          required: {'gone'},
        ),
      ], seam: 'TEST');
      expect(violations.map((v) => v.seam).toSet(), {'TEST'});
      expect(violations, hasLength(4));
    });

    test('SEAMS-RULE-2: an entry point that keeps its rule passes', () {
      final root = fixture();
      expect(
        auditEntryPointRules(root, const [
          EntryPointRule(
            package: 'pkg',
            entryPoint: 'lib/pure.dart',
            banned: {'dart:io', 'net'},
            bannedUris: {'package:dep/web.dart'},
            required: {'dep'},
          ),
        ], seam: 'TEST'),
        isEmpty,
      );
    });

    test('SEAMS-RULE-3: an entry point that is gone fails rather than '
        'passing with nothing to walk', () {
      final root = fixture();
      final violations = auditEntryPointRules(root, const [
        EntryPointRule(package: 'pkg', entryPoint: 'lib/gone.dart', banned: {}),
      ], seam: 'TEST');
      expect(violations.single.message, contains('does not exist'));
    });
  });

  group('SEAMS-UP climbing to a root', () {
    test('SEAMS-UP-1: a directory or file built from an upward literal is '
        'reported', () {
      for (final source in [
        "final root = Directory('UP');",
        "final f = File('UP/pkg/pubspec.yaml');",
        "final d = Directory(\"UP/pkg/lib\").listSync();",
        "final f = File(\n    'UP/UP/notes/x.md',\n);",
      ]) {
        expect(
          upwardPathDerivations(snippet(source)),
          isNotEmpty,
          reason: snippet(source),
        );
      }
    });

    test('SEAMS-UP-2: a join or normalize that climbs is reported, wherever '
        'in the arguments the climb is', () {
      for (final source in [
        "final root = p.join(Directory.current.path, 'UP', 'UP');",
        "final root = p.normalize(p.join(here, 'UP/UP/notes'));",
        "final f = File(p.join(Directory.current.path, 'UP', 'x.yaml'));",
        "final root = p.canonicalize('UP');",
      ]) {
        expect(
          upwardPathDerivations(snippet(source)),
          isNotEmpty,
          reason: snippet(source),
        );
      }
    });

    test('SEAMS-UP-3: climbing from the working directory by `.parent` or by '
        'interpolation is the same count, and is reported', () {
      for (final source in [
        'final root = CWD.parent.parent;',
        'final root = CWD.absolute.parent;',
        r"final root = '${CWD.path}/UP/UP';",
      ]) {
        expect(
          upwardPathDerivations(snippet(source)),
          isNotEmpty,
          reason: snippet(source),
        );
      }
    });

    test('SEAMS-UP-4: what is not a derivation is left alone', () {
      for (final source in [
        // A directive is resolved by the compiler against the file.
        "import 'UP/tool/x.dart';",
        "export 'UP/UP/UP/pkg/test/support/x.dart';",
        // A locator inside a document under test is data.
        "const locatorB = 'UP/library.doc';",
        "final ref = Ref.parse('UP/handbook.doc#\$id');",
        "paths: {'pkg': 'UP/pkg'},",
        // A comment may explain the rule.
        "// never write Directory('UP') here\nfinal x = 1;",
        "/// `p.join(root, 'UP')` is the shape this forbids.\nfinal x = 1;",
        // A landmark walk climbs by asking, not by counting.
        'final root = findRoot();',
        "final f = File(p.join(findRoot().path, 'a', 'b.dart'));",
        "final d = Directory('lib');",
        // A spread and a cascade are not a path.
        'final all = [...first, ...second];',
        'buffer..write(1)..write(2);',
      ]) {
        expect(
          upwardPathDerivations(snippet(source)),
          isEmpty,
          reason: snippet(source),
        );
      }
    });

    test('SEAMS-UP-5: a finding names the line it is on', () {
      final found = upwardPathDerivations(
        snippet("void main() {\n  final x = 1;\n  Directory('UP');\n}\n"),
      );
      expect(found.single.line, 3);
      expect(found.single.text, contains('Directory('));
    });
  });

  group('SEAMS-RUN running audits', () {
    SeamAudit audit(String label, List<SeamViolation> found) =>
        (label: label, run: (_, _) => found);

    test('SEAMS-RUN-1: every audit holding exits 0 and prints the sentence '
        'it was given; a quiet run prints nothing', () {
      final out = StringBuffer();
      final code = runSeamAudits(
        audits: [audit('one', const []), audit('two', const [])],
        repositoryRoot: '/r',
        workspaceRoot: '/w',
        holds: 'All two hold.',
        out: out,
        err: StringBuffer(),
      );
      expect(code, 0);
      expect(out.toString(), contains('ok    one'));
      expect(out.toString().trimRight(), endsWith('All two hold.'));
      final quiet = StringBuffer();
      runSeamAudits(
        audits: [audit('one', const [])],
        repositoryRoot: '/r',
        workspaceRoot: '/w',
        holds: 'held',
        quiet: true,
        out: quiet,
      );
      expect(quiet.toString(), isEmpty);
    });

    test('SEAMS-RUN-2: a crossing exits 1, names its audit and every '
        'violation, and counts them', () {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = runSeamAudits(
        audits: [
          audit('fine', const []),
          audit('bad', const [
            SeamViolation('B', 'first'),
            SeamViolation('B', 'second'),
          ]),
        ],
        repositoryRoot: '/r',
        workspaceRoot: '/w',
        holds: 'never printed',
        quiet: true,
        out: out,
        err: err,
      );
      expect(code, 1);
      expect(out.toString(), contains('FAIL  bad'));
      expect(out.toString(), contains('first'));
      expect(out.toString(), contains('second'));
      expect(out.toString(), isNot(contains('never printed')));
      expect(err.toString(), contains('2 package-boundary violation(s)'));
    });

    test('SEAMS-RUN-3: the roots are found by their landmarks, and their '
        'absence is an error naming the landmark', () {
      final root = tree({
        'ws/.tom_metadata/x': '',
        'ws/repo/tom_repository.yaml': '',
        'ws/repo/pkg/lib/a.dart': '',
      });
      final from = p.join(root, 'ws', 'repo', 'pkg', 'lib');
      expect(resolveRepositoryRoot(from), p.join(root, 'ws', 'repo'));
      expect(resolveWorkspaceRoot(from), p.join(root, 'ws'));
      expect(
        // From the filesystem root, where no repository can be above.
        () => resolveRepositoryRoot(p.rootPrefix(root)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('tom_repository.yaml'),
          ),
        ),
      );
    });
  });
}
