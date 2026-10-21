/// The utilities of `package:tom_basics/utilities.dart`, where two earlier
/// implementations were merged: the behaviour each brought must survive.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_basics/utilities.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('UTIL-C cancellation', () {
    test(
      'UTIL-C1: the first reason wins and the token stays cancelled',
      () async {
        final source = TomCancellationSource();
        final token = source.token;
        expect(token.isCancelled, isFalse);
        expect(token.reason, isNull);

        source.cancel('deadline');
        source.cancel('user');

        expect(token.isCancelled, isTrue);
        expect(token.reason, 'deadline');
        expect(await token.whenCancelled, 'deadline');
      },
    );

    test('UTIL-C2: the none token is never cancelled', () async {
      expect(TomCancellationToken.none.isCancelled, isFalse);
      expect(TomCancellationToken.none.reason, isNull);
      final raced = await Future.any([
        TomCancellationToken.none.whenCancelled,
        Future<String>.delayed(Duration.zero, () => 'timer'),
      ]);
      expect(raced, 'timer');
    });

    test('UTIL-C3: an operation-cancelled exception names what and why', () {
      expect(
        const TomOperationCancelled('embed', 'deadline').toString(),
        'TomOperationCancelled(embed): deadline',
      );
    });
  });

  group('UTIL-H hash and slug', () {
    test('UTIL-H1: one SHA-256, of bytes and of text', () {
      const empty =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      expect(tomSha256Hex(const []), empty);
      expect(tomSha256OfText('a'), tomSha256Hex(utf8.encode('a')));
    });

    test('UTIL-H2: a slug is lowercase ASCII with single dashes, and falls '
        'back when nothing is left', () {
      expect(tomSlugify('  Hello,  World!  '), 'hello-world');
      expect(tomSlugify('—'), 'section');
      expect(tomSlugify('—', fallback: 'x'), 'x');
      expect(tomShortId('7f3c9e21-0000-4000-8000-000000000000'), '7f3c9e21');
    });
  });

  group('UTIL-G gitignore, the merged semantics', () {
    TomGitignore parse(String text, [String base = '']) =>
        TomGitignore.parse(base, text);

    test('UTIL-G1: a folder rule ignores what is inside the folder', () {
      final rules = parse('build/\n');
      expect(rules.verdict('build', isDirectory: true), isTrue);
      expect(rules.verdict('build/out/app.js', isDirectory: false), isTrue);
      expect(
        rules.verdict('build', isDirectory: false),
        isNull,
        reason: 'a folder-only rule says nothing about a file named build',
      );
    });

    test('UTIL-G2: escapes — a literal first character and a kept trailing '
        'space', () {
      final rules = parse('\\#notes\n\\!keep\nname\\ \nplain   \n');
      expect(rules.verdict('#notes', isDirectory: false), isTrue);
      expect(rules.verdict('!keep', isDirectory: false), isTrue);
      expect(rules.verdict('name ', isDirectory: false), isTrue);
      expect(rules.verdict('plain', isDirectory: false), isTrue);
    });

    test('UTIL-G3: anchoring, negation and later lines winning', () {
      final rules = parse('/top.txt\n*.log\n!keep.log\n');
      expect(rules.verdict('top.txt', isDirectory: false), isTrue);
      expect(rules.verdict('a/top.txt', isDirectory: false), isNull);
      expect(rules.verdict('a/b/x.log', isDirectory: false), isTrue);
      expect(rules.verdict('a/keep.log', isDirectory: false), isFalse);
    });

    test('UTIL-G4: a file speaks only under its own folder, and a deeper file '
        'overrides in a set', () {
      final set = TomGitignoreSet()
        ..add(parse('*.tmp\n'))
        ..add(parse('!wanted.tmp\n', 'sub'));
      expect(set.isIgnored('x.tmp', isDirectory: false), isTrue);
      expect(set.isIgnored('sub/wanted.tmp', isDirectory: false), isFalse);
      expect(set.isIgnored('other/wanted.tmp', isDirectory: false), isTrue);
      expect(
        set.isIgnored(r'sub\other.tmp', isDirectory: false),
        isTrue,
        reason: 'backslashes are read as separators',
      );
      expect(set.isIgnored('', isDirectory: true), isFalse);
    });

    test('UTIL-G5: globs — braces, classes and escaped metacharacters', () {
      expect(TomGlob('**/*.{md,txt}').matches('a/b/c.txt'), isTrue);
      expect(TomGlob('file[0-9].dart').matches('file7.dart'), isTrue);
      expect(TomGlob(r'star\*.md').matches('star*.md'), isTrue);
      expect(TomGlob(r'star\*.md').matches('starry.md'), isFalse);
    });
  });

  group('UTIL-Y the two YAML styles keep their bytes', () {
    test('UTIL-Y1: the canonical emitter quotes everything outside its narrow '
        'plain set and escapes as \\u', () {
      expect(
        tomEmitYamlDocument({
          'id': 'a1',
          'title': 'Fix: the parser',
          'flag': 'yes',
          'n': '42',
          'ctl': 'a\u0001b',
          'list': ['x'],
          'empty': <String, Object?>{},
        }),
        'id: a1\n'
        'title: "Fix: the parser"\n'
        'flag: "yes"\n'
        'n: "42"\n'
        'ctl: "a\\u0001b"\n'
        'list:\n'
        '  - x\n'
        'empty: {}\n',
      );
    });

    test('UTIL-Y2: a canonical fragment sorts every key', () {
      expect(
        tomEmitCanonicalFragment({
          'b': 1,
          'a': {'d': 2, 'c': 3},
        }),
        'a:\n  c: 3\n  d: 2\nb: 1\n',
      );
    });

    test('UTIL-Y3: the hand-edited style writes plain what YAML 1.1 reads '
        'back unchanged, and escapes as \\x', () {
      expect(tomYamlScalar('Fix the parser'), 'Fix the parser');
      expect(tomYamlScalar('2026-10-20'), '"2026-10-20"');
      expect(tomYamlScalar('yes'), '"yes"');
      expect(tomYamlScalar('a\u0001b'), '"a\\x01b"');
      expect(tomYamlEntry('title', 'Hi', 2, '\n'), '  title: Hi\n');
      expect(tomNewlineOf('a\r\nb\r\nc\n'), '\r\n');
    });

    test('UTIL-Y4: ordering primitives — known keys first, the rest sorted, '
        'items by id stably', () {
      expect(
        tomOrderedMapping({'z': 1, 'id': 2, 'a': 3}, ['id']).keys.toList(),
        ['id', 'a', 'z'],
      );
      expect(
        tomSortedById([
          {'id': 'b'},
          {'x': 1},
          {'id': 'a'},
        ]),
        [
          {'id': 'a'},
          {'id': 'b'},
          {'x': 1},
        ],
      );
    });

    test('UTIL-Y5: the schema a file names is read from its '
        'yaml-language-server comment, as written', () {
      expect(
        tomYamlSchemaRefOf(
          'quest: q\n# yaml-language-server: \$schema=../../schemas/t.json\n',
        ),
        '../../schemas/t.json',
      );
      expect(tomYamlSchemaRefOf('# a comment\ntodos: []\n'), isNull);
    });
  });

  group('UTIL-T text codec', () {
    test('UTIL-T1: a UTF-8 BOM is kept, so the bytes come back the same', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('héllo')];
      final decoded = tomDecodeTextBytes(bytes);
      expect(decoded.text, 'héllo');
      expect(tomEncodeText(decoded.text, decoded.encoding), bytes);
    });
  });

  group('UTIL-P reading YAML back as plain values', () {
    test('UTIL-P1: nested YAML maps and lists become plain Dart, keys as '
        'strings', () {
      final plain = tomYamlToPlain(
        loadYaml('a: 1\nb: [x, {c: true}]\n2: two\n'),
      );
      expect(plain, isA<Map<String, Object?>>());
      expect(plain, {
        'a': 1,
        'b': [
          'x',
          {'c': true},
        ],
        '2': 'two',
      });
      final list = (plain as Map)['b'] as List;
      expect(list, isNot(isA<YamlList>()));
      expect(list[1], isNot(isA<YamlMap>()));
    });

    test('UTIL-P2: scalars and null pass through', () {
      expect(tomYamlToPlain(null), isNull);
      expect(tomYamlToPlain('text'), 'text');
      expect(tomYamlToPlain(loadYaml('3.5')), 3.5);
    });
  });
}
