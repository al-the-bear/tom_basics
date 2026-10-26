import 'dart:convert';
import 'dart:typed_data';

import '../github_exception.dart';
import '../http/github_http_client.dart';
import '../models/github_conditional.dart';
import '../models/github_content.dart';

/// The repository **contents** API — read, write and delete a single path.
///
/// Each write is its own commit, which makes this the right tool for
/// single-file artifacts and the wrong one for a multi-file change; for that
/// use the git data API, where blobs, a tree and a commit compose into one
/// atomic update.
class GitHubContentsApi {
  final GitHubHttpClient _http;

  const GitHubContentsApi(this._http);

  /// Percent-encodes each segment so paths with spaces or unicode survive.
  static String encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  /// The file at [path] as bytes.
  ///
  /// Uses the raw media type, so this works up to GitHub's 100 MB ceiling
  /// rather than the 1 MB limit of the base64 JSON envelope.
  Future<GitHubConditional<Uint8List>> readFile({
    required String owner,
    required String repo,
    required String path,
    String? ref,
    String? ifNoneMatch,
  }) {
    final query = ref == null ? '' : '?ref=${Uri.encodeQueryComponent(ref)}';
    return _http.getBytes(
      '/repos/$owner/$repo/contents/${encodePath(path)}$query',
      ifNoneMatch: ifNoneMatch,
    );
  }

  /// Metadata for a single path, or `null` when it does not exist.
  Future<GitHubContentEntry?> stat({
    required String owner,
    required String repo,
    required String path,
    String? ref,
  }) async {
    try {
      final json = await _http.get(
        '/repos/$owner/$repo/contents/${encodePath(path)}',
        queryParams: {if (ref != null) 'ref': ref},
      );
      return GitHubContentEntry.fromJson(json);
    } on GitHubNotFoundException {
      return null;
    }
  }

  /// The children of the directory at [path]. An empty [path] lists the root.
  ///
  /// Returns an empty list when the directory does not exist — an absent
  /// directory and an empty one are the same thing in git, which has no
  /// directory objects of its own.
  Future<List<GitHubContentEntry>> listDirectory({
    required String owner,
    required String repo,
    required String path,
    String? ref,
  }) async {
    try {
      final json = await _http.getList(
        '/repos/$owner/$repo/contents/${encodePath(path)}',
        queryParams: {if (ref != null) 'ref': ref},
      );
      return [
        for (final e in json)
          GitHubContentEntry.fromJson(e as Map<String, dynamic>),
      ];
    } on GitHubNotFoundException {
      return const [];
    }
  }

  /// Creates or replaces the file at [path] in its own commit.
  ///
  /// [sha] is the blob sha of the version being replaced; it MUST be supplied
  /// when overwriting and MUST be omitted when creating. Passing a stale sha
  /// is rejected with `409`, which is the API's per-path compare-and-swap.
  Future<GitHubContentWriteResult> writeFile({
    required String owner,
    required String repo,
    required String path,
    required String message,
    required Uint8List bytes,
    String? sha,
    String? branch,
  }) async {
    final json = await _http.put(
      '/repos/$owner/$repo/contents/${encodePath(path)}',
      body: {
        'message': message,
        'content': base64Encode(bytes),
        if (sha != null) 'sha': sha,
        if (branch != null) 'branch': branch,
      },
    );
    return GitHubContentWriteResult.fromJson(json);
  }

  /// Deletes the file at [path] in its own commit. [sha] is required.
  Future<GitHubContentWriteResult> deleteFile({
    required String owner,
    required String repo,
    required String path,
    required String message,
    required String sha,
    String? branch,
  }) async {
    final json = await _http.deleteWithBody(
      '/repos/$owner/$repo/contents/${encodePath(path)}',
      body: {
        'message': message,
        'sha': sha,
        if (branch != null) 'branch': branch,
      },
    );
    return GitHubContentWriteResult.fromJson(json);
  }
}
