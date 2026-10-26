/// Objects, loose objects and packs, held against a pack and a loose object
/// that git itself wrote (test/fixtures, made by `git repack -adf` over two
/// commits, so one blob is stored as an offset delta).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:tom_git/tom_git.dart';

Uint8List fixture(String name) => File('test/fixtures/$name').readAsBytesSync();

final expected =
    jsonDecode(File('test/fixtures/delta.json').readAsStringSync()) as Map;

void main() {
  group('GIT-OBJ objects', () {
    test('GIT-OBJ-1: a blob id is the SHA-1 git computes', () {
      final blob = GitObject.blob(utf8.encode(expected['looseText'] as String));
      expect(blob.id.hex, expected['loose']);
      expect(GitObjectId.fromHex(blob.id.hex), blob.id);
    });

    test('GIT-OBJ-2: a loose object git wrote inflates and unframes to its '
        'content', () {
      final object = GitObject.unframe(gitInflate(fixture('loose_object')));
      expect(object.type, GitObjectType.blob);
      expect(utf8.decode(object.content), expected['looseText']);
      expect(object.id.hex, expected['loose']);
    });

    test('GIT-OBJ-3: trees sort a folder as if its name ended in a slash', () {
      final id = GitObject.blob([1]).id;
      final tree = GitTree([
        GitTreeEntry(mode: GitTreeEntry.fileMode, name: 'a0', id: id),
        GitTreeEntry(mode: GitTreeEntry.treeMode, name: 'a', id: id),
        GitTreeEntry(mode: GitTreeEntry.fileMode, name: 'a.txt', id: id),
      ]);
      expect([for (final e in tree.entries) e.name], ['a.txt', 'a', 'a0']);
      expect(GitTree.decode(tree.encode()).entries.map((e) => e.name), [
        'a.txt',
        'a',
        'a0',
      ]);
    });

    test('GIT-OBJ-4: a commit round-trips, extra headers skipped', () {
      final commit = GitCommit(
        tree: GitObject.blob([1]).id,
        parents: [
          GitObject.blob([2]).id,
        ],
        author: GitPerson.parse('A <a@x> 1700000000 +0200'),
        committer: GitPerson.parse('C <c@x> 1700000001 -0500'),
        message: 'hello\n',
      );
      final back = GitCommit.decode(commit.encode());
      expect(back.parents, commit.parents);
      expect(back.author.encode(), 'A <a@x> 1700000000 +0200');
      expect(back.committer.timezone, '-0500');
      expect(back.message, 'hello\n');
      final signed = utf8.encode(
        utf8
            .decode(commit.encode())
            .replaceFirst('\n\n', '\ngpgsig -----BEGIN\n line\n -----END\n\n'),
      );
      expect(GitCommit.decode(Uint8List.fromList(signed)).message, 'hello\n');
    });
  });

  group('GIT-PACK packs', () {
    test('GIT-PACK-1: a pack git wrote reads to the objects git names, the '
        'offset delta resolved', () async {
      final pack = await gitReadPack(fixture('delta.pack'));
      final byId = {for (final o in pack.objects) o.object.id.hex: o.object};
      expect(byId.length, expected['objectCount']);
      expect(
        byId[expected['docOld']]!.content.length,
        expected['docOldLength'],
      );
      expect(
        byId[expected['docNew']]!.content.length,
        expected['docNewLength'],
      );
      final head = GitCommit.decode(byId[expected['head']]!.content);
      expect(head.parents.single.hex, expected['parent']);
      expect(head.tree.hex, expected['headTree']);
      expect(head.message, expected['headMessage']);
      expect(head.author.encode(), expected['author']);
    });

    test('GIT-PACK-2: the index this library builds is byte for byte the one '
        'git wrote', () async {
      final pack = await gitReadPack(fixture('delta.pack'));
      expect(pack.buildIndex(), fixture('delta.idx'));
    });

    test('GIT-PACK-3: an index looks every object up, and a single entry '
        'reads through its delta base', () async {
      final packBytes = fixture('delta.pack');
      final index = GitPackIndex.parse(fixture('delta.idx'));
      expect(index.count, expected['objectCount']);
      Future<GitObject> at(int offset) => gitReadPackEntry(
        packBytes,
        offset,
        resolveOffset: at,
        resolveId: (_) async => null,
      );
      final old = await at(
        index.offsetOf(GitObjectId.fromHex(expected['docOld'] as String))!,
      );
      expect(old.id.hex, expected['docOld']);
      expect(index.offsetOf(GitObject.blob([9, 9]).id), isNull);
    });

    test('GIT-PACK-4: a pack this library writes reads back, and a damaged '
        'one is refused', () async {
      final objects = [
        GitObject.blob(utf8.encode('one')),
        GitObject.blob(List.filled(5000, 65)),
        GitTree.empty.toObject(),
      ];
      final bytes = gitWritePack(objects);
      final back = await gitReadPack(bytes);
      expect(
        {for (final o in back.objects) o.object.id},
        {for (final o in objects) o.id},
      );
      final damaged = Uint8List.fromList(bytes)..[20] ^= 0xff;
      await expectLater(gitReadPack(damaged), throwsFormatException);
    });

    test('GIT-PACK-5: concatenated zlib streams are told apart by what each '
        'consumed', () {
      final a = gitDeflate(utf8.encode('first stream'));
      final b = gitDeflate(List.filled(3000, 7));
      final both = Uint8List.fromList([...a, ...b]);
      final first = gitInflateAt(both, 0, expectedSize: 12);
      expect(first.consumed, a.length);
      final second = gitInflateAt(both, first.consumed, expectedSize: 3000);
      expect(second.consumed, b.length);
    });
  });

  group('GIT-DELTA deltas', () {
    test('GIT-DELTA-1: copy and insert instructions rebuild the target, and a '
        'wrong base size is refused', () {
      final base = Uint8List.fromList(utf8.encode('hello world'));
      // base 11, result 11: copy offset 0 size 6 ("hello "), insert "there".
      final delta = Uint8List.fromList([
        11,
        11,
        0x80 | 0x10,
        6,
        5,
        ...utf8.encode('there'),
      ]);
      expect(utf8.decode(gitApplyDelta(base, delta)), 'hello there');
      expect(() => gitApplyDelta(Uint8List(3), delta), throwsFormatException);
    });
  });
}
