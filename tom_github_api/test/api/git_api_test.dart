import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

void main() {
  group('refs', () {
    test('getRef unwraps the object sha', () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/git/ref/heads/main': MockResponse(200, {
            'ref': 'refs/heads/main',
            'object': {'sha': 'head-1', 'type': 'commit'},
          }),
        }),
      );
      addTearDown(client.close);

      final ref =
          await client.git.getRef(owner: 'o', repo: 'r', ref: 'heads/main');
      expect(ref.ref, 'refs/heads/main');
      expect(ref.sha, 'head-1');
    });

    test('getRefConditional turns an unchanged head into a free poll',
        () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/git/ref/heads/main': MockResponse(304, ''),
        }),
      );
      addTearDown(client.close);

      final result = await client.git.getRefConditional(
        owner: 'o',
        repo: 'r',
        ref: 'heads/main',
        ifNoneMatch: 'W/"head-1"',
      );

      expect(result.notModified, isTrue);
      expect(result.etag, 'W/"head-1"');
      expect(result.orElse(const GitHubGitRef(ref: 'x', sha: 'cached')).sha,
          'cached');
    });

    test('updateRef refuses non-fast-forward by default — that is the CAS',
        () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'PATCH /repos/o/r/git/refs/heads/main': MockResponse(200, {
              'ref': 'refs/heads/main',
              'object': {'sha': 'head-2'},
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      await client.git.updateRef(
        owner: 'o',
        repo: 'r',
        ref: 'heads/main',
        sha: 'head-2',
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['sha'], 'head-2');
      expect(body['force'], isFalse);
    });

    test('a lost race surfaces as a validation failure, not a silent clobber',
        () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'PATCH /repos/o/r/git/refs/heads/main':
              MockResponse(422, {'message': 'Update is not a fast forward'}),
        }),
      );
      addTearDown(client.close);

      expect(
        () => client.git.updateRef(
          owner: 'o',
          repo: 'r',
          ref: 'heads/main',
          sha: 'stale-child',
        ),
        throwsA(isA<GitHubException>()),
      );
    });

    test('createRef sends the fully qualified ref name', () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'POST /repos/o/r/git/refs': MockResponse(201, {
              'ref': 'refs/heads/webwork',
              'object': {'sha': 'head-1'},
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      await client.git.createRef(
        owner: 'o',
        repo: 'r',
        ref: 'heads/webwork',
        sha: 'head-1',
      );

      expect((jsonDecode(seen.body) as Map<String, dynamic>)['ref'],
          'refs/heads/webwork');
    });
  });

  group('blobs and trees', () {
    test('createBlob base64-encodes and returns the sha', () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {'POST /repos/o/r/git/blobs': MockResponse(201, {'sha': 'blob-1'})},
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      final sha = await client.git.createBlob(
        owner: 'o',
        repo: 'r',
        bytes: Uint8List.fromList(utf8.encode('section: yaml')),
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['encoding'], 'base64');
      expect(utf8.decode(base64Decode(body['content'] as String)),
          'section: yaml');
      expect(sha, 'blob-1');
    });

    test('getBlob asks for the raw media type so the 1 MB ceiling is moot',
        () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {'GET /repos/o/r/git/blobs/blob-1': MockResponse(200, 'raw-content')},
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      final bytes =
          await client.git.getBlob(owner: 'o', repo: 'r', sha: 'blob-1');

      expect(utf8.decode(bytes), 'raw-content');
      expect(seen.headers['Accept'], 'application/vnd.github.raw');
    });

    test('createTree sends a null sha for a deletion and keeps the base tree',
        () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'POST /repos/o/r/git/trees': MockResponse(201, {
              'sha': 'tree-2',
              'tree': <dynamic>[],
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      await client.git.createTree(
        owner: 'o',
        repo: 'r',
        baseTreeSha: 'tree-1',
        entries: const [
          GitHubTreeEntry(path: 'mydoc.webwork/webwork.yaml', sha: 'blob-m'),
          GitHubTreeEntry.deletion('mydoc.webwork/old--7f3c.webwork.yaml'),
        ],
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['base_tree'], 'tree-1');
      final tree = body['tree'] as List<dynamic>;
      expect(tree, hasLength(2));
      expect((tree[0] as Map<String, dynamic>)['sha'], 'blob-m');
      expect((tree[0] as Map<String, dynamic>)['mode'], '100644');
      final deletion = tree[1] as Map<String, dynamic>;
      expect(deletion.containsKey('sha'), isTrue);
      expect(deletion['sha'], isNull);
    });

    test('getTreeOrNull returns null instead of throwing on an unknown tree',
        () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(const {}),
      );
      addTearDown(client.close);

      expect(
        await client.git.getTreeOrNull(owner: 'o', repo: 'r', sha: 'nope'),
        isNull,
      );
    });

    test('blobsUnder keys a bundle directory by its relative paths', () {
      const tree = GitHubTree(
        sha: 'tree-1',
        truncated: false,
        entries: [
          GitHubTreeEntry(path: 'mydoc.webwork', type: 'tree', sha: 't'),
          GitHubTreeEntry(path: 'mydoc.webwork/webwork.yaml', sha: 'b1'),
          GitHubTreeEntry(
              path: 'mydoc.webwork/.history/7f3c/2026.webwork.yaml', sha: 'b2'),
          GitHubTreeEntry(path: 'other.webwork/webwork.yaml', sha: 'b3'),
        ],
      );

      final blobs = tree.blobsUnder('mydoc.webwork');

      expect(blobs.keys,
          containsAll(['webwork.yaml', '.history/7f3c/2026.webwork.yaml']));
      expect(blobs, hasLength(2));
      expect(blobs['webwork.yaml']!.sha, 'b1');
    });

    test('a truncated recursive listing announces itself', () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/git/trees/tree-1': MockResponse(200, {
            'sha': 'tree-1',
            'tree': <dynamic>[],
            'truncated': true,
          }),
        }),
      );
      addTearDown(client.close);

      final tree = await client.git
          .getTree(owner: 'o', repo: 'r', sha: 'tree-1', recursive: true);
      expect(tree.truncated, isTrue);
    });
  });

  group('commits', () {
    test('createCommit parents the new commit on the head that was read',
        () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'POST /repos/o/r/git/commits': MockResponse(201, {
              'sha': 'commit-2',
              'tree': {'sha': 'tree-2'},
              'parents': [
                {'sha': 'head-1'}
              ],
              'message': 'webwork: save Handbook (v2)',
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      final commit = await client.git.createCommit(
        owner: 'o',
        repo: 'r',
        message: 'webwork: save Handbook (v2)',
        treeSha: 'tree-2',
        parentShas: const ['head-1'],
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['tree'], 'tree-2');
      expect(body['parents'], ['head-1']);
      expect(commit.sha, 'commit-2');
      expect(commit.parentShas, ['head-1']);
    });
  });

  group('one atomic save', () {
    test('blobs, then one tree, then one commit, then one ref move', () async {
      final calls = <String>[];
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'GET /repos/o/r/git/ref/heads/main': MockResponse(200, {
              'ref': 'refs/heads/main',
              'object': {'sha': 'head-1'},
            }),
            'GET /repos/o/r/git/commits/head-1': MockResponse(200, {
              'sha': 'head-1',
              'tree': {'sha': 'tree-1'},
              'parents': <dynamic>[],
            }),
            'POST /repos/o/r/git/blobs': MockResponse(201, {'sha': 'blob-new'}),
            'POST /repos/o/r/git/trees':
                MockResponse(201, {'sha': 'tree-2', 'tree': <dynamic>[]}),
            'POST /repos/o/r/git/commits': MockResponse(201, {
              'sha': 'commit-2',
              'tree': {'sha': 'tree-2'},
              'parents': [
                {'sha': 'head-1'}
              ],
            }),
            'PATCH /repos/o/r/git/refs/heads/main': MockResponse(200, {
              'ref': 'refs/heads/main',
              'object': {'sha': 'commit-2'},
            }),
          },
          onRequest: (r) => calls.add('${r.method} ${r.url.path}'),
        ),
      );
      addTearDown(client.close);

      final head =
          await client.git.getRef(owner: 'o', repo: 'r', ref: 'heads/main');
      final base =
          await client.git.getCommit(owner: 'o', repo: 'r', sha: head.sha);
      final blob = await client.git.createBlob(
        owner: 'o',
        repo: 'r',
        bytes: Uint8List.fromList(utf8.encode('changed')),
      );
      final tree = await client.git.createTree(
        owner: 'o',
        repo: 'r',
        baseTreeSha: base.treeSha,
        entries: [
          GitHubTreeEntry(path: 'mydoc.webwork/webwork.yaml', sha: blob),
        ],
      );
      final commit = await client.git.createCommit(
        owner: 'o',
        repo: 'r',
        message: 'webwork: save Handbook (v2)',
        treeSha: tree.sha,
        parentShas: [head.sha],
      );
      final moved = await client.git.updateRef(
        owner: 'o',
        repo: 'r',
        ref: 'heads/main',
        sha: commit.sha,
      );

      expect(moved.sha, 'commit-2');
      // Exactly one tree, one commit and one ref move — readers see the old
      // commit or the new one, never a half-applied bundle.
      expect(calls.where((c) => c.endsWith('/git/trees')), hasLength(1));
      expect(calls.where((c) => c.endsWith('/git/commits')), hasLength(1));
      expect(calls.where((c) => c.startsWith('PATCH')), hasLength(1));
      expect(calls.last, 'PATCH /repos/o/r/git/refs/heads/main');
    });
  });
}
