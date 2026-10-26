import 'dart:convert';
import 'dart:typed_data';

import '../github_exception.dart';
import '../http/github_http_client.dart';
import '../models/github_conditional.dart';
import '../models/github_git_objects.dart';

/// The low-level **git data** API — refs, commits, trees and blobs.
///
/// This is what makes a multi-file change atomic: upload blobs, compose one
/// tree over a base tree, create one commit, then move the branch ref exactly
/// once. Readers see either the old commit or the new one and never a
/// half-applied state.
class GitHubGitApi {
  final GitHubHttpClient _http;

  const GitHubGitApi(this._http);

  // --- Refs -------------------------------------------------------------

  /// The ref named [ref] (`heads/main`, not `refs/heads/main`).
  Future<GitHubGitRef> getRef({
    required String owner,
    required String repo,
    required String ref,
  }) async =>
      GitHubGitRef.fromJson(
        await _http.get('/repos/$owner/$repo/git/ref/$ref'),
      );

  /// [getRef] as a conditional request, so polling a branch head that has not
  /// moved costs no rate-limit quota.
  Future<GitHubConditional<GitHubGitRef>> getRefConditional({
    required String owner,
    required String repo,
    required String ref,
    String? ifNoneMatch,
  }) async {
    final response = await _http.getConditional(
      '/repos/$owner/$repo/git/ref/$ref',
      ifNoneMatch: ifNoneMatch,
    );
    if (response.notModified) {
      return GitHubConditional.unmodified(etag: response.etag);
    }
    return GitHubConditional.modified(
      GitHubGitRef.fromJson(response.value!),
      etag: response.etag,
    );
  }

  /// Points [ref] at [sha].
  ///
  /// With [force] false (the default) GitHub refuses any update that is not a
  /// fast-forward, raising [GitHubValidationException]. That refusal is the
  /// compare-and-swap: a commit whose parent is the head we read cannot
  /// fast-forward a branch that has since moved.
  Future<GitHubGitRef> updateRef({
    required String owner,
    required String repo,
    required String ref,
    required String sha,
    bool force = false,
  }) async =>
      GitHubGitRef.fromJson(
        await _http.patch(
          '/repos/$owner/$repo/git/refs/$ref',
          body: {'sha': sha, 'force': force},
        ),
      );

  /// Creates [ref] (`heads/main`) pointing at [sha].
  Future<GitHubGitRef> createRef({
    required String owner,
    required String repo,
    required String ref,
    required String sha,
  }) async =>
      GitHubGitRef.fromJson(
        await _http.post(
          '/repos/$owner/$repo/git/refs',
          body: {'ref': 'refs/$ref', 'sha': sha},
        ),
      );

  /// Deletes [ref] (`heads/scratch-1`).
  ///
  /// Deleting a branch is how a caller that *created* one disposes of it, so
  /// this completes [createRef] rather than standing on its own. The commits
  /// it pointed at survive until garbage collection, which is why this is a
  /// safe cleanup operation and not a destructive one.
  Future<void> deleteRef({
    required String owner,
    required String repo,
    required String ref,
  }) =>
      _http.delete('/repos/$owner/$repo/git/refs/$ref');

  // --- Commits ----------------------------------------------------------

  Future<GitHubGitCommit> getCommit({
    required String owner,
    required String repo,
    required String sha,
  }) async =>
      GitHubGitCommit.fromJson(
        await _http.get('/repos/$owner/$repo/git/commits/$sha'),
      );

  Future<GitHubGitCommit> createCommit({
    required String owner,
    required String repo,
    required String message,
    required String treeSha,
    required List<String> parentShas,
  }) async =>
      GitHubGitCommit.fromJson(
        await _http.post(
          '/repos/$owner/$repo/git/commits',
          body: {
            'message': message,
            'tree': treeSha,
            'parents': parentShas,
          },
        ),
      );

  // --- Trees ------------------------------------------------------------

  /// The tree [sha]. With [recursive] the whole subtree comes back in one
  /// call — check [GitHubTree.truncated] before trusting it to be complete.
  Future<GitHubTree> getTree({
    required String owner,
    required String repo,
    required String sha,
    bool recursive = false,
  }) async =>
      GitHubTree.fromJson(
        await _http.get(
          '/repos/$owner/$repo/git/trees/$sha',
          queryParams: {if (recursive) 'recursive': '1'},
        ),
      );

  /// [getTree], or `null` when the tree does not exist.
  Future<GitHubTree?> getTreeOrNull({
    required String owner,
    required String repo,
    required String sha,
    bool recursive = false,
  }) async {
    try {
      return await getTree(
          owner: owner, repo: repo, sha: sha, recursive: recursive);
    } on GitHubNotFoundException {
      return null;
    }
  }

  /// Composes a new tree from [entries] applied over [baseTreeSha].
  ///
  /// Entries with a null sha delete their path. Omit [baseTreeSha] to build a
  /// tree from nothing — which is also how you delete a whole directory,
  /// since there is no "remove subtree" entry.
  Future<GitHubTree> createTree({
    required String owner,
    required String repo,
    required List<GitHubTreeEntry> entries,
    String? baseTreeSha,
  }) async =>
      GitHubTree.fromJson(
        await _http.post(
          '/repos/$owner/$repo/git/trees',
          body: {
            if (baseTreeSha != null) 'base_tree': baseTreeSha,
            'tree': [for (final e in entries) e.toJson()],
          },
        ),
      );

  // --- Blobs ------------------------------------------------------------

  /// Uploads [bytes] as a blob and returns its sha.
  Future<String> createBlob({
    required String owner,
    required String repo,
    required Uint8List bytes,
  }) async {
    final json = await _http.post(
      '/repos/$owner/$repo/git/blobs',
      body: {'content': base64Encode(bytes), 'encoding': 'base64'},
    );
    return json['sha'] as String;
  }

  /// Downloads the blob [sha] as bytes, via the raw media type so the 1 MB
  /// base64-envelope limit does not apply.
  Future<Uint8List> getBlob({
    required String owner,
    required String repo,
    required String sha,
  }) async {
    final response =
        await _http.getBytes('/repos/$owner/$repo/git/blobs/$sha');
    return response.value!;
  }
}
