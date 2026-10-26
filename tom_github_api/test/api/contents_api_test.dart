import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

import '../helpers/mock_http_client.dart';

void main() {
  group('GitHubContentsApi.encodePath', () {
    test('escapes each segment but keeps the separators', () {
      expect(
        GitHubContentsApi.encodePath('docs/my notes/handbook.webwork.kdbx'),
        'docs/my%20notes/handbook.webwork.kdbx',
      );
    });

    test('survives unicode', () {
      expect(GitHubContentsApi.encodePath('日記/a.yaml'),
          '%E6%97%A5%E8%A8%98/a.yaml');
    });
  });

  group('readFile', () {
    test('returns the body verbatim, not a base64 envelope', () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'GET /repos/o/r/contents/doc.webwork.kdbx':
                MockResponse(200, 'kdbx-bytes', headers: {'etag': 'W/"v1"'}),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      final result = await client.contents
          .readFile(owner: 'o', repo: 'r', path: 'doc.webwork.kdbx');

      expect(result.notModified, isFalse);
      expect(utf8.decode(result.value!), 'kdbx-bytes');
      expect(result.etag, 'W/"v1"');
      expect(seen.headers['Accept'], 'application/vnd.github.raw');
    });

    test('reports 304 as unmodified rather than as an error', () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/contents/doc.webwork.kdbx': MockResponse(304, ''),
        }),
      );
      addTearDown(client.close);

      final result = await client.contents.readFile(
        owner: 'o',
        repo: 'r',
        path: 'doc.webwork.kdbx',
        ifNoneMatch: 'W/"v1"',
      );

      expect(result.notModified, isTrue);
      expect(result.value, isNull);
      expect(result.etag, 'W/"v1"');
    });

    test('passes the ref through as a query parameter', () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {'GET /repos/o/r/contents/doc.webwork.kdbx': MockResponse(200, 'x')},
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      await client.contents.readFile(
        owner: 'o',
        repo: 'r',
        path: 'doc.webwork.kdbx',
        ref: 'feature/branch',
      );

      expect(seen.url.queryParameters['ref'], 'feature/branch');
    });
  });

  group('stat / listDirectory', () {
    test('stat returns null for a path that does not exist', () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(const {}),
      );
      addTearDown(client.close);

      expect(
        await client.contents.stat(owner: 'o', repo: 'r', path: 'nope.yaml'),
        isNull,
      );
    });

    test('lists a bundle directory', () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'GET /repos/o/r/contents/mydoc.webwork': MockResponse(200, [
            {
              'name': 'webwork.yaml',
              'path': 'mydoc.webwork/webwork.yaml',
              'type': 'file',
              'sha': 'sha-manifest',
              'size': 120,
            },
            {
              'name': '.history',
              'path': 'mydoc.webwork/.history',
              'type': 'dir',
              'sha': 'sha-history',
              'size': 0,
            },
          ]),
        }),
      );
      addTearDown(client.close);

      final entries = await client.contents
          .listDirectory(owner: 'o', repo: 'r', path: 'mydoc.webwork');

      expect(entries, hasLength(2));
      expect(entries.first.isFile, isTrue);
      expect(entries.first.sha, 'sha-manifest');
      expect(entries.last.isDirectory, isTrue);
      expect(entries.last.type, GitHubContentType.dir);
    });

    test('an absent directory reads as an empty one — git has no dir objects',
        () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(const {}),
      );
      addTearDown(client.close);

      expect(
        await client.contents
            .listDirectory(owner: 'o', repo: 'r', path: 'gone.webwork'),
        isEmpty,
      );
    });
  });

  group('writeFile / deleteFile', () {
    test('sends base64 content and omits sha when creating', () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'PUT /repos/o/r/contents/doc.webwork.kdbx': MockResponse(201, {
              'content': {'sha': 'blob-sha'},
              'commit': {
                'sha': 'commit-sha',
                'tree': {'sha': 'tree-sha'},
              },
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      final result = await client.contents.writeFile(
        owner: 'o',
        repo: 'r',
        path: 'doc.webwork.kdbx',
        message: 'webwork: save Handbook (v2)',
        bytes: Uint8List.fromList(utf8.encode('payload')),
        branch: 'main',
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['message'], 'webwork: save Handbook (v2)');
      expect(utf8.decode(base64Decode(body['content'] as String)), 'payload');
      expect(body.containsKey('sha'), isFalse);
      expect(body['branch'], 'main');
      expect(result.contentSha, 'blob-sha');
      expect(result.commitSha, 'commit-sha');
      // The tree is read as well as the commit: a caller that has just moved a
      // branch through this endpoint can then describe the state it created
      // without reading the ref back.
      expect(result.treeSha, 'tree-sha');
    });

    test('sends the prior blob sha when overwriting — the per-path CAS',
        () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'PUT /repos/o/r/contents/doc.webwork.kdbx': MockResponse(200, {
              'content': {'sha': 'blob-2'},
              'commit': {
                'sha': 'commit-2',
                'tree': {'sha': 'tree-2'},
              },
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      await client.contents.writeFile(
        owner: 'o',
        repo: 'r',
        path: 'doc.webwork.kdbx',
        message: 'm',
        bytes: Uint8List.fromList([1, 2, 3]),
        sha: 'blob-1',
      );

      expect((jsonDecode(seen.body) as Map<String, dynamic>)['sha'], 'blob-1');
    });

    test('a stale sha is rejected as a conflict, not silently clobbered',
        () async {
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient({
          'PUT /repos/o/r/contents/doc.webwork.kdbx':
              MockResponse(409, {'message': 'is at abc but expected def'}),
        }),
      );
      addTearDown(client.close);

      expect(
        () => client.contents.writeFile(
          owner: 'o',
          repo: 'r',
          path: 'doc.webwork.kdbx',
          message: 'm',
          bytes: Uint8List.fromList([1]),
          sha: 'stale',
        ),
        throwsA(isA<GitHubException>()),
      );
    });

    test('deleteFile carries the sha in the DELETE body', () async {
      late http.Request seen;
      final client = GitHubApiClient(
        token: 'test',
        httpClient: createMockClient(
          {
            'DELETE /repos/o/r/contents/doc.webwork.kdbx': MockResponse(200, {
              'commit': {
                'sha': 'commit-del',
                'tree': {'sha': 'tree-del'},
              },
            }),
          },
          onRequest: (r) => seen = r,
        ),
      );
      addTearDown(client.close);

      final result = await client.contents.deleteFile(
        owner: 'o',
        repo: 'r',
        path: 'doc.webwork.kdbx',
        message: 'webwork: delete',
        sha: 'blob-1',
      );

      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(seen.method, 'DELETE');
      expect(body['sha'], 'blob-1');
      expect(result.commitSha, 'commit-del');
      expect(result.treeSha, 'tree-del');
      expect(result.contentSha, isNull);
    });
  });
}
