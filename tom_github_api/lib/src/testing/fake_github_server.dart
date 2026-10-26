/// An in-memory GitHub API — **git data**, **contents** and **issues** — good
/// enough to prove a storage backend's two-level compare-and-swap (ref plus
/// object) and an issue-backed store without a network. Reach it through
/// `package:tom_github_api/testing.dart`; [FakeGitHubServer.client] is the
/// `http.Client` a `GitHubApiClient` or any other caller is handed.
///
/// The git half is a real object store, not a set of canned responses: blobs,
/// trees and commits are content-addressed, so a subtree sha changes exactly
/// when something under it changes and never otherwise — which is the whole
/// premise the per-document CAS rests on. Reproducing that property is why the
/// fake hashes rather than counts.
///
/// Three behaviours are reproduced deliberately, because a fake that omitted
/// them would let a broken design pass:
///
/// * **The refusal to fast-forward a moved branch.** `PATCH /git/refs/…` with
///   `force: false` answers 422 unless the current head is an ancestor of the
///   new commit. That refusal is the outer CAS.
/// * **Transfer drops labels the target repository does not have**, assigns a
///   fresh issue number, and copies the body verbatim. Any correspondence
///   keyed on the number or on a label alone dies here — which is precisely
///   what the marker exists to survive.
/// * **Issue bodies have no compare-and-swap.** `PATCH /issues/{n}` always
///   wins, so [FakeGitHubServer.beforeIssueUpdate] can land a competing edit
///   inside another writer's read-modify-write window and the store must
///   notice by reading back.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// A repository: its default branch, its refs, the object store they resolve
/// into, and its issues.
class FakeGitHubRepo {
  String defaultBranch;

  /// `heads/<branch>` → commit sha. The **primary**: every write lands here,
  /// and every write is compare-and-swapped against it.
  final Map<String, String> refs = {};

  /// `heads/<branch>` → the sha this ref held *before* its most recent write,
  /// which a lagging read replica may still be serving. Null when the ref did
  /// not exist yet, because a replica that has not seen the create answers 404.
  final Map<String, String?> supersededRefs = {};

  /// How many more reads of `heads/<branch>` are answered from
  /// [supersededRefs] instead of [refs]. Fed by
  /// [FakeGitHubServer.staleRefReads] on every ref write.
  final Map<String, int> staleRefBudget = {};

  /// Issues by number, in creation order.
  final Map<int, FakeIssue> issues = {};

  /// The labels that **exist in this repository**. Modelled explicitly because
  /// it is the whole reason a transfer loses labels: GitHub keeps only those
  /// the target already defines.
  final Set<String> labels = {};

  int nextIssueNumber = 1;

  /// A repository that has never received a commit.
  ///
  /// Modelled explicitly rather than inferred from [refs] being empty, because
  /// the two are different situations to a writer: a repository whose *branch*
  /// does not exist yet accepts blobs and trees perfectly well, whereas one
  /// with no commits at all refuses **every** git-data write with a 409. Only
  /// the contents API can give it its first commit.
  bool uninitialized = false;

  FakeGitHubRepo({this.defaultBranch = 'main'});
}

/// An issue as the fake stores it. Mutable, because that is what an issue is.
class FakeIssue {
  int number;
  String title;
  String body;
  String state;
  final Set<String> labels;
  final String author;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? closedAt;
  final List<FakeComment> comments;

  /// The GraphQL global id. Reassigned on transfer, like the number.
  String nodeId;

  /// Real wall-clock instant from which `GET /issues` and `GET /search/issues`
  /// admit this issue exists — GitHub's index lags its writes, and a fake that
  /// pretends otherwise lets a store ship a duplicate-issue bug.
  ///
  /// Wall clock rather than the fake's own [FakeGitHubServer._now], because the
  /// behaviour under test is a real `Future.delayed`.
  DateTime visibleFrom = DateTime.fromMillisecondsSinceEpoch(0);

  FakeIssue({
    required this.number,
    required this.nodeId,
    required this.title,
    required this.body,
    required this.author,
    required this.createdAt,
    required this.updatedAt,
    this.state = 'open',
    Set<String>? labels,
    List<FakeComment>? comments,
    this.closedAt,
  })  : labels = labels ?? {},
        comments = comments ?? [];

  Map<String, dynamic> toJson() => {
        'number': number,
        'node_id': nodeId,
        'title': title,
        'body': body,
        'state': state,
        'labels': [for (final l in labels) {'name': l}],
        'user': {'login': author, 'id': author.hashCode.abs()},
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
        'comments': comments.length,
        'html_url': 'https://fake.github.test/issues/$number',
      };
}

class FakeComment {
  final int id;
  String body;
  final String author;
  final DateTime createdAt;
  DateTime updatedAt;

  FakeComment({
    required this.id,
    required this.body,
    required this.author,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'body': body,
        'user': {'login': author, 'id': author.hashCode.abs()},
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

class FakeCommit {
  final String treeSha;
  final List<String> parents;
  final String message;

  const FakeCommit(this.treeSha, this.parents, this.message);
}

/// The fake server. Wire it into a client with
/// `GitHubApiClient(token: 'x', httpClient: server.client,
/// baseUrl: FakeGitHubServer.baseUrl)`.
class FakeGitHubServer {
  static const baseUrl = 'https://fake.github.test';

  /// `owner/repo` → repository.
  final Map<String, FakeGitHubRepo> repos = {};

  /// Content-addressed object stores, shared across repositories exactly as
  /// the fake's simplicity allows — shas are content hashes, so sharing is
  /// invisible.
  final Map<String, Uint8List> blobs = {};

  /// tree sha → flat `path` → blob sha. Flat because the recursive listing is
  /// the only tree read the fake serves, and a flat map is the honest model of
  /// one.
  final Map<String, Map<String, String>> trees = {};

  final Map<String, FakeCommit> commits = {};

  /// Every request path this server has answered, in order. Lets a test assert
  /// that a conditional poll really did cost nothing.
  final List<String> requestLog = [];

  /// How many requests were answered `304 Not Modified`.
  int notModifiedCount = 0;

  /// Fired once, immediately before the next `PATCH /git/refs/…` is applied.
  /// This is the seam a test uses to land a competing commit inside another
  /// writer's read-modify-write window.
  void Function()? beforeRefUpdate;

  /// Fired once, immediately before the next `PATCH /issues/{n}` is applied —
  /// the issue-body equivalent of [beforeRefUpdate]. Unlike a ref update the
  /// patch still succeeds, because GitHub offers no compare-and-swap here;
  /// noticing is the writer's job.
  void Function()? beforeIssueUpdate;

  /// How many issues a page of `GET /issues` **and `GET /search/issues`** holds,
  /// whatever `per_page` asks for. Set it low to exercise a paginated walk on a
  /// handful of issues instead of the several hundred it would otherwise take.
  ///
  /// It covers search as well as the list because a caller that *enumerates*
  /// the search has a paging loop too, and a fake that answered every search in
  /// one page would leave that loop unexercised while the test claiming to
  /// drive it passed.
  int? pageSizeOverride;

  /// The login every fake-authored issue and comment carries.
  String actor = 'fake-user';

  /// When true, every search answers `incomplete_results: true` — GitHub's way
  /// of saying it gave up before seeing everything, which it does under load
  /// and past its 1000-result ceiling.
  ///
  /// Here so that a caller which *enumerates* can be shown a result set it must
  /// not treat as whole. Without it that branch is unreachable from a test and
  /// the caller's caution is unverifiable.
  bool searchIncomplete = false;

  /// How long a newly created issue stays invisible to the *list* and *search*
  /// endpoints while `GET /issues/{n}` already serves it.
  ///
  /// Zero by default so the suite stays fast; set it to model the read-after-
  /// write lag measured against a real repository (roughly five seconds), which
  /// is what makes "the label query found nothing" an unreliable answer.
  Duration indexLag = Duration.zero;

  /// Issue numbers the **search** index has not absorbed, though the issue is
  /// in the repository and the *list* endpoint serves it.
  ///
  /// The two indexes are independent and lag independently, which no single
  /// call reveals: measured against a real repository holding 460 markered
  /// issues, the label-filtered list served all 460 while the marker search
  /// answered `total_count: 283` and `incomplete_results: false` — a third of
  /// the repository missing, reported as a complete answer, because from
  /// search's point of view it was one. [indexLag] cannot express that: it
  /// delays list and search together, so a caller that cross-checks one
  /// against the other sees them agree at every instant.
  final Set<int> searchIndexExcludes = {};

  /// Whether [issue] has reached the index yet.
  bool _indexed(FakeIssue issue) => !DateTime.now().isBefore(issue.visibleFrom);

  /// Whether [issue] has reached the *search* index — a strictly smaller set.
  bool _searchIndexed(FakeIssue issue) =>
      _indexed(issue) && !searchIndexExcludes.contains(issue.number);

  /// How many reads of a ref answer with the sha it held *before* its most
  /// recent write — a read replica that has not caught up.
  ///
  /// Zero by default, because a fake that lags on every read would make every
  /// other test slow and non-obvious. Set it to model what GitHub actually
  /// does: a ref write goes to the primary, but `GET /git/ref/…` is served
  /// from a replica and carries **no read-after-write guarantee**, so a reader
  /// can be handed the commit it just replaced. That is not a rare pathology —
  /// it is the documented contract, and a fake that pretends the ref is
  /// linearizable lets a backend ship a head that silently reads back null
  /// after a successful save.
  ///
  /// Only ref *reads* lag. Objects are content-addressed, so a read by sha
  /// cannot be stale and is never delayed here.
  int staleRefReads = 0;

  /// Arms the replica lag for [ref] after a write moved it off [previous].
  void _markRefStale(FakeGitHubRepo r, String ref, String? previous) {
    if (staleRefReads <= 0) return;
    r.supersededRefs[ref] = previous;
    r.staleRefBudget[ref] = staleRefReads;
  }

  int _nextCommentId = 1000;
  DateTime _clock = DateTime.utc(2026, 7, 27, 12);

  /// The fake's clock, advanced one second per mutation so `created_at` and
  /// `updated_at` are distinguishable without a test sleeping.
  DateTime get _now => _clock = _clock.add(const Duration(seconds: 1));

  /// Status codes to answer the next requests with before serving normally.
  /// Used to exercise the rate-limit and 5xx backoff paths.
  final List<http.Response> canned = [];

  /// While true, issue and comment **writes** are refused with a
  /// content-creation block, and everything else is served.
  ///
  /// That is the shape GitHub was measured to give a block (woneprpc126):
  /// reads and git-data writes went through while one was in force. [canned]
  /// cannot model it, since it answers the next request whatever it is, and a
  /// block that refused the read before a write would test a block GitHub
  /// does not impose.
  bool contentCreationBlocked = false;

  /// The writes [contentCreationBlocked] refused, as `METHOD path`.
  final List<String> refusedLog = [];

  http.Client get client => _FakeClient(this);

  // ── Fixture helpers ─────────────────────────────────────────────────────

  FakeGitHubRepo repo(String slug) =>
      repos.putIfAbsent(slug, () => FakeGitHubRepo());

  /// Commits [files] (path → text) onto [branch], creating it if needed.
  /// The direct way for a test to play the part of a competing writer.
  String commitFiles(
    String slug,
    Map<String, String> files, {
    String branch = 'main',
    String message = 'test',
  }) {
    final r = repo(slug);
    final ref = 'heads/$branch';
    final parent = r.refs[ref];
    final base = parent == null
        ? <String, String>{}
        : {...trees[commits[parent]!.treeSha]!};
    for (final file in files.entries) {
      base[file.key] = _putBlob(utf8.encode(file.value));
    }
    final treeSha = _putTree(base);
    final commitSha = _putCommit(FakeCommit(treeSha, [?parent], message));
    r.refs[ref] = commitSha;
    return commitSha;
  }

  /// The bytes at [path] on [branch], or null. The general accessor: a
  /// repository holds encrypted containers as readily as YAML.
  Uint8List? bytesAt(String slug, String path, {String branch = 'main'}) {
    final commit = repos[slug]?.refs['heads/$branch'];
    if (commit == null) return null;
    final sha = trees[commits[commit]!.treeSha]![path];
    return sha == null ? null : blobs[sha];
  }

  /// The text at [path] on [branch], or null. Only valid for the textual
  /// serializations — a KDBX container is not UTF-8 and must be read with
  /// [bytesAt].
  String? fileAt(String slug, String path, {String branch = 'main'}) {
    final bytes = bytesAt(slug, path, branch: branch);
    return bytes == null ? null : utf8.decode(bytes);
  }

  /// Every path on [branch].
  Set<String> pathsOn(String slug, {String branch = 'main'}) {
    final commit = repos[slug]?.refs['heads/$branch'];
    if (commit == null) return {};
    return trees[commits[commit]!.treeSha]!.keys.toSet();
  }

  // ── Object store ────────────────────────────────────────────────────────

  String _putBlob(List<int> bytes) {
    final sha = _sha1('blob ${bytes.length}\x00', bytes);
    blobs[sha] = Uint8List.fromList(bytes);
    return sha;
  }

  String _putTree(Map<String, String> flat) {
    final sha = _treeShaOf(flat, '');
    trees[sha] = Map.of(flat);
    return sha;
  }

  String _putCommit(FakeCommit commit) {
    final sha = _sha1(
      'commit ${commit.treeSha} ${commit.parents.join(',')} ${commit.message}',
      const [],
    );
    commits[sha] = commit;
    return sha;
  }

  /// The sha of the subtree at [prefix] (empty for the root): a hash over the
  /// sorted `relative-path\x00blob-sha` pairs beneath it. Content-addressed,
  /// so it is stable across rebuilds and moves only with its content.
  static String _treeShaOf(Map<String, String> flat, String prefix) {
    final root = prefix.isEmpty ? '' : '$prefix/';
    final lines = <String>[];
    for (final entry in flat.entries) {
      if (!entry.key.startsWith(root)) continue;
      lines.add('${entry.key.substring(root.length)}\x00${entry.value}');
    }
    lines.sort();
    return _sha1('tree ${lines.join('\n')}', const []);
  }

  static String _sha1(String prefix, List<int> bytes) =>
      sha1.convert([...utf8.encode(prefix), ...bytes]).toString();

  /// The recursive listing of [treeSha]: a blob entry per file plus a tree
  /// entry per directory, which is what makes a bundle directory addressable
  /// by a single object sha.
  List<Map<String, dynamic>> _listing(String treeSha) {
    final flat = trees[treeSha]!;
    final out = <Map<String, dynamic>>[];
    final dirs = <String>{};
    for (final entry in flat.entries) {
      out.add({
        'path': entry.key,
        'mode': '100644',
        'type': 'blob',
        'sha': entry.value,
        'size': blobs[entry.value]!.length,
      });
      final parts = entry.key.split('/');
      for (var i = 1; i < parts.length; i++) {
        dirs.add(parts.take(i).join('/'));
      }
    }
    for (final dir in dirs) {
      out.add({
        'path': dir,
        'mode': '040000',
        'type': 'tree',
        'sha': _treeShaOf(flat, dir),
      });
    }
    out.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
    return out;
  }

  bool _isAncestor(String? ancestor, String descendant) {
    if (ancestor == null) return true;
    final seen = <String>{};
    final queue = [descendant];
    while (queue.isNotEmpty) {
      final sha = queue.removeLast();
      if (sha == ancestor) return true;
      if (!seen.add(sha)) continue;
      queue.addAll(commits[sha]?.parents ?? const []);
    }
    return false;
  }

  // ── Routing ─────────────────────────────────────────────────────────────

  http.Response handle(http.Request request) {
    if (canned.isNotEmpty) return canned.removeAt(0);

    final path = request.url.path;
    requestLog.add('${request.method} $path');
    final segments = request.url.pathSegments;

    if (contentCreationBlocked &&
        (request.method == 'POST' || request.method == 'PATCH') &&
        segments.length >= 4 &&
        segments[0] == 'repos' &&
        segments[3] == 'issues') {
      refusedLog.add('${request.method} $path');
      return secondaryRateLimited(blocked: true);
    }

    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;

    // The two endpoints that are not repository-scoped.
    if (segments.length == 2 && segments[0] == 'search' &&
        segments[1] == 'issues') {
      return _searchIssues(
        request.url.queryParameters['q'] ?? '',
        perPage: int.tryParse(request.url.queryParameters['per_page'] ?? ''),
        page: int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1,
      );
    }
    if (segments.length == 1 && segments[0] == 'graphql') {
      return _graphql(body);
    }

    // /repos/<owner>/<repo>/…
    if (segments.length < 3 || segments[0] != 'repos') {
      return _json(404, {'message': 'Not Found'});
    }
    final slug = '${segments[1]}/${segments[2]}';
    final rest = segments.sublist(3);
    final r = repos[slug];
    if (r == null) return _json(404, {'message': 'Not Found'});

    if (rest.isEmpty) {
      // `full_name` is echoed from the slug that was *asked for*, which is the
      // honest fake: this server has no rename redirects, so every name it
      // knows is its own. A fake that omitted the field would let a caller
      // that depends on it pass here and fail against GitHub.
      return _json(200, {
        'id': slug.hashCode.abs(),
        'full_name': slug,
        'name': segments[2],
        'owner': {'login': segments[1]},
        'node_id': _repoNodeId(slug),
        'default_branch': r.defaultBranch,
        'fork': false,
      });
    }
    if (rest.first == 'issues') {
      return _issueRoute(request, slug, r, rest.sublist(1), body);
    }
    if (rest.first == 'contents' && request.method == 'PUT') {
      return _writeContents(r, rest.sublist(1).join('/'), body);
    }
    if (rest.first != 'git') return _json(404, {'message': 'Not Found'});
    if (r.uninitialized) {
      // Every git-data endpoint, not just the ref update: with no commits
      // there is nothing for an object to hang off, so a blob upload fails
      // just as a ref read does.
      return _json(409, {'message': 'Git Repository is empty.'});
    }

    switch ((request.method, rest.length > 1 ? rest[1] : '')) {
      case ('GET', 'ref'):
        return _getRef(r, rest.sublist(2).join('/'), request);
      case ('POST', 'refs'):
        return _createRef(r, body);
      case ('PATCH', 'refs'):
        return _updateRef(r, rest.sublist(2).join('/'), body);
      // GitHub answers 204 for a deleted ref and 422 for one that does not
      // exist ("Reference does not exist").
      case ('DELETE', 'refs'):
        final ref = rest.sublist(2).join('/');
        if (r.refs.remove(ref) == null) {
          return _json(422, {'message': 'Reference does not exist'});
        }
        return http.Response('', 204);
      case ('GET', 'commits'):
        return _getCommit(rest[2]);
      case ('POST', 'commits'):
        return _createCommit(body);
      case ('GET', 'trees'):
        return _getTree(rest[2]);
      case ('POST', 'trees'):
        return _createTree(body);
      case ('GET', 'blobs'):
        return _getBlob(rest[2]);
      case ('POST', 'blobs'):
        return _createBlob(body);
    }
    return _json(404, {'message': 'Not Found'});
  }

  /// `PUT /repos/{owner}/{repo}/contents/{path}` — the only endpoint that can
  /// author a repository's first commit, and the fake serves it for that.
  http.Response _writeContents(
    FakeGitHubRepo r,
    String path,
    Map<String, dynamic> body,
  ) {
    final branch = body['branch'] as String? ?? r.defaultBranch;
    final parent = r.refs['heads/$branch'];
    final sha = commitFiles(
      _slugOf(r),
      {path: utf8.decode(base64.decode(body['content'] as String))},
      branch: branch,
      message: body['message'] as String? ?? '',
    );
    r.uninitialized = false;
    // A replica lags behind a ref move regardless of which endpoint moved it.
    // The contents API authors a commit and advances the branch exactly as the
    // git-data path does, so a fake that armed the lag only on `POST`/`PATCH
    // /git/refs` would make the bootstrap path look linearizable when it is
    // not — and that is the one path a first save into a fresh repository
    // takes.
    _markRefStale(r, 'heads/$branch', parent);
    return _json(201, {
      'content': {'path': path},
      // The tree as well as the commit, which is what GitHub answers: a caller
      // that has just moved a branch here knows the state it created and need
      // not read the ref back to learn it.
      'commit': {
        'sha': sha,
        'tree': {'sha': commits[sha]!.treeSha},
      },
    });
  }

  String _slugOf(FakeGitHubRepo r) =>
      repos.entries.firstWhere((e) => identical(e.value, r)).key;

  http.Response _getRef(FakeGitHubRepo r, String ref, http.Request request) {
    var sha = r.refs[ref];
    final budget = r.staleRefBudget[ref] ?? 0;
    if (budget > 0) {
      // A replica that has not caught up. It answers with the sha it still
      // holds — and with *that* sha's ETag, because a replica is consistent
      // with itself even when it is behind the primary.
      r.staleRefBudget[ref] = budget - 1;
      sha = r.supersededRefs[ref];
    }
    if (sha == null) return _json(404, {'message': 'Not Found'});
    final etag = 'W/"$sha"';
    if (request.headers['If-None-Match'] == etag) {
      notModifiedCount++;
      return http.Response('', 304, headers: {'etag': etag});
    }
    return _json(
      200,
      {
        'ref': 'refs/$ref',
        'object': {'sha': sha, 'type': 'commit'},
      },
      headers: {'etag': etag},
    );
  }

  http.Response _createRef(FakeGitHubRepo r, Map<String, dynamic> body) {
    final ref = (body['ref'] as String).replaceFirst('refs/', '');
    if (r.refs.containsKey(ref)) {
      return _json(422, {'message': 'Reference already exists'});
    }
    r.refs[ref] = body['sha'] as String;
    _markRefStale(r, ref, null);
    return _json(201, {
      'ref': 'refs/$ref',
      'object': {'sha': r.refs[ref], 'type': 'commit'},
    });
  }

  http.Response _updateRef(
    FakeGitHubRepo r,
    String ref,
    Map<String, dynamic> body,
  ) {
    final hook = beforeRefUpdate;
    if (hook != null) {
      beforeRefUpdate = null;
      hook();
    }
    final sha = body['sha'] as String;
    final force = body['force'] as bool? ?? false;
    // GitHub updates only a ref that exists; creating one is `POST /git/refs`.
    // Answering 200 here would let a stale holder resurrect a released ref.
    if (!r.refs.containsKey(ref)) {
      return _json(422, {'message': 'Reference does not exist'});
    }
    if (!force && !_isAncestor(r.refs[ref], sha)) {
      return _json(422, {
        'message': 'Update is not a fast forward',
      });
    }
    final previous = r.refs[ref];
    r.refs[ref] = sha;
    _markRefStale(r, ref, previous);
    return _json(200, {
      'ref': 'refs/$ref',
      'object': {'sha': sha, 'type': 'commit'},
    });
  }

  http.Response _getCommit(String sha) {
    final commit = commits[sha];
    if (commit == null) return _json(404, {'message': 'Not Found'});
    return _json(200, {
      'sha': sha,
      'message': commit.message,
      'tree': {'sha': commit.treeSha},
      'parents': [for (final p in commit.parents) {'sha': p}],
    });
  }

  http.Response _createCommit(Map<String, dynamic> body) {
    final sha = _putCommit(FakeCommit(
      body['tree'] as String,
      [for (final p in body['parents'] as List<dynamic>) p as String],
      body['message'] as String? ?? '',
    ));
    return _json(201, {
      'sha': sha,
      'message': body['message'],
      'tree': {'sha': body['tree']},
      'parents': [for (final p in body['parents'] as List<dynamic>) {'sha': p}],
    });
  }

  http.Response _getTree(String sha) {
    if (!trees.containsKey(sha)) return _json(404, {'message': 'Not Found'});
    return _json(200, {
      'sha': sha,
      'tree': _listing(sha),
      'truncated': false,
    });
  }

  http.Response _createTree(Map<String, dynamic> body) {
    final baseSha = body['base_tree'] as String?;
    final flat = baseSha == null
        ? <String, String>{}
        : {...?trees[baseSha]};
    for (final raw in body['tree'] as List<dynamic>) {
      final entry = raw as Map<String, dynamic>;
      final path = entry['path'] as String;
      final sha = entry['sha'] as String?;
      if (sha == null) {
        flat.remove(path);
      } else {
        flat[path] = sha;
      }
    }
    final sha = _putTree(flat);
    return _json(201, {'sha': sha, 'tree': _listing(sha), 'truncated': false});
  }

  http.Response _getBlob(String sha) {
    final bytes = blobs[sha];
    if (bytes == null) return _json(404, {'message': 'Not Found'});
    return http.Response.bytes(bytes, 200);
  }

  http.Response _createBlob(Map<String, dynamic> body) {
    final sha = _putBlob(base64Decode(body['content'] as String));
    return _json(201, {'sha': sha});
  }

  // ── Issues ──────────────────────────────────────────────────────────────

  static String _repoNodeId(String slug) => 'R_$slug';

  /// Creates an issue directly — the fixture path, and the way a test plays
  /// the part of a human who opened the issue in the GitHub UI.
  FakeIssue seedIssue(
    String slug, {
    required String title,
    String body = '',
    Set<String> labels = const {},
    String state = 'open',
  }) {
    final r = repo(slug);
    final number = r.nextIssueNumber++;
    final at = _now;
    final issue = FakeIssue(
      number: number,
      nodeId: 'I_${slug}_$number',
      title: title,
      body: body,
      author: actor,
      createdAt: at,
      updatedAt: at,
      state: state,
      labels: {...labels},
    );
    r.labels.addAll(labels);
    r.issues[number] = issue;
    return issue;
  }

  /// Appends a comment directly — the fixture path for a comment written in
  /// the GitHub UI rather than by the code under test.
  FakeComment seedComment(String slug, int number, String body,
      {String? author}) {
    final at = _now;
    final comment = FakeComment(
      id: _nextCommentId++,
      body: body,
      author: author ?? actor,
      createdAt: at,
      updatedAt: at,
    );
    repo(slug).issues[number]!.comments.add(comment);
    return comment;
  }

  http.Response _issueRoute(
    http.Request request,
    String slug,
    FakeGitHubRepo r,
    List<String> rest,
    Map<String, dynamic> body,
  ) {
    // `/issues/comments/{id}` is a comment, not issue number "comments".
    if (rest.length == 2 && rest[0] == 'comments') {
      final id = int.tryParse(rest[1]);
      if (id == null) return _json(404, {'message': 'Not Found'});
      return switch (request.method) {
        'PATCH' => _editComment(r, id, body['body'] as String),
        'DELETE' => _deleteComment(r, id),
        _ => _json(404, {'message': 'Not Found'}),
      };
    }

    if (rest.isEmpty) {
      return switch (request.method) {
        'GET' => _listIssues(r, request.url.queryParameters, request.url),
        'POST' => _createIssue(r, slug, body),
        _ => _json(404, {'message': 'Not Found'}),
      };
    }

    final number = int.tryParse(rest[0]);
    if (number == null) return _json(404, {'message': 'Not Found'});
    final issue = r.issues[number];
    if (issue == null) return _json(404, {'message': 'Not Found'});

    final tail = rest.length > 1 ? rest[1] : '';
    return switch ((request.method, tail)) {
      ('GET', '') => _json(200, issue.toJson()),
      ('PATCH', '') => _patchIssue(r, issue, body),
      ('POST', 'labels') => _addLabels(r, issue, body),
      // `DELETE /issues/{n}/labels/{name}` — the label is in the path, not the
      // body, so this one needs `rest[2]` and cannot be keyed on `tail` alone.
      ('DELETE', 'labels') =>
        _removeLabel(issue, rest.length > 2 ? rest.sublist(2).join('/') : ''),
      ('GET', 'comments') => _listComments(issue, request),
      ('POST', 'comments') => _addComment(issue, body['body'] as String),
      _ => _json(404, {'message': 'Not Found'}),
    };
  }

  /// Removes one label, answering 404 for a label the issue does not carry.
  ///
  /// GitHub really does 404 there, and the D11 §5 retirement is written to
  /// avoid it by consulting `issue.labels` first — so a fake that answered 200
  /// unconditionally would leave that check untested and let it rot.
  http.Response _removeLabel(FakeIssue issue, String label) {
    final name = Uri.decodeComponent(label);
    if (name.isEmpty || !issue.labels.remove(name)) {
      return _json(404, {'message': 'Label does not exist'});
    }
    issue.updatedAt = _now;
    return _jsonList(200, [
      for (final l in issue.labels) {'name': l},
    ]);
  }

  http.Response _listIssues(
    FakeGitHubRepo r,
    Map<String, String> params,
    Uri url,
  ) {
    final state = params['state'] ?? 'open';
    final wanted = (params['labels'] ?? '')
        .split(',')
        .where((l) => l.isNotEmpty)
        .toSet();

    final matched = [
      for (final issue in r.issues.values)
        if (_indexed(issue))
          if (state == 'all' || issue.state == state)
            if (wanted.every(issue.labels.contains)) issue,
    ];

    final perPage = pageSizeOverride ??
        int.tryParse(params['per_page'] ?? '') ??
        30;
    final page = int.tryParse(params['page'] ?? '') ?? 1;
    final from = (page - 1) * perPage;
    final slice = from >= matched.length
        ? const <FakeIssue>[]
        : matched.sublist(from, (from + perPage).clamp(0, matched.length));

    final headers = <String, String>{};
    if (from + perPage < matched.length) {
      final next = url.replace(queryParameters: {
        ...url.queryParameters,
        'page': '${page + 1}',
      });
      headers['link'] = '<$next>; rel="next"';
    }
    return _jsonList(200, [for (final i in slice) i.toJson()], headers: headers);
  }

  /// GitHub caps a label name at **50 characters** and answers 422
  /// `resource: Label, code: invalid` above it.
  ///
  /// Enforced here because the fake was silently accepting a name the real API
  /// refuses, which is precisely the kind of belief a fake is not allowed to
  /// hold on its own: a 52-character label (`<prefix>:section:<uuid>`) passed
  /// every offline test while being impossible against GitHub.
  static const labelNameLimit = 50;

  http.Response? _rejectOversizedLabels(Set<String> labels) {
    for (final name in labels) {
      if (name.length <= labelNameLimit) continue;
      return _json(422, {
        'message': 'Validation Failed',
        'errors': [
          {'value': name, 'resource': 'Label', 'field': 'name', 'code': 'invalid'},
        ],
      });
    }
    return null;
  }

  http.Response _createIssue(
      FakeGitHubRepo r, String slug, Map<String, dynamic> body) {
    final labels = {
      for (final l in (body['labels'] as List<dynamic>? ?? const []))
        l as String,
    };
    final rejected = _rejectOversizedLabels(labels);
    if (rejected != null) return rejected;
    // Creating an issue with an unknown label creates the label, exactly as
    // the real API does — which is how a repository comes to "have" one.
    r.labels.addAll(labels);
    final number = r.nextIssueNumber++;
    final at = _now;
    final issue = FakeIssue(
      number: number,
      nodeId: 'I_${slug}_$number',
      title: body['title'] as String,
      body: body['body'] as String? ?? '',
      author: actor,
      createdAt: at,
      updatedAt: at,
      labels: labels,
    );
    issue.visibleFrom = DateTime.now().add(indexLag);
    r.issues[number] = issue;
    return _json(201, issue.toJson());
  }

  http.Response _patchIssue(
      FakeGitHubRepo r, FakeIssue issue, Map<String, dynamic> body) {
    final hook = beforeIssueUpdate;
    if (hook != null) {
      beforeIssueUpdate = null;
      hook();
    }
    if (body['title'] != null) issue.title = body['title'] as String;
    if (body['body'] != null) issue.body = body['body'] as String;
    if (body['state'] != null) {
      issue.state = body['state'] as String;
      issue.closedAt = issue.state == 'closed' ? _now : null;
    }
    if (body['labels'] != null) {
      final labels = {for (final l in body['labels'] as List<dynamic>) l as String};
      final rejected = _rejectOversizedLabels(labels);
      if (rejected != null) return rejected;
      r.labels.addAll(labels);
      issue.labels
        ..clear()
        ..addAll(labels);
    }
    issue.updatedAt = _now;
    return _json(200, issue.toJson());
  }

  http.Response _addLabels(
      FakeGitHubRepo r, FakeIssue issue, Map<String, dynamic> body) {
    final labels = {
      for (final l in body['labels'] as List<dynamic>) l as String,
    };
    final rejected = _rejectOversizedLabels(labels);
    if (rejected != null) return rejected;
    r.labels.addAll(labels);
    issue.labels.addAll(labels);
    issue.updatedAt = _now;
    return _jsonList(200, [for (final l in issue.labels) {'name': l}]);
  }

  /// The thread, with an entity tag over its content: GitHub tags a list
  /// response by its body, so a comment created, edited or deleted changes
  /// the tag and an unchanged thread answers `304` to `If-None-Match`.
  http.Response _listComments(FakeIssue issue, http.Request request) {
    final body = [for (final c in issue.comments) c.toJson()];
    final etag = 'W/"thread-${jsonEncode(body).hashCode.toRadixString(16)}"';
    if (request.headers['If-None-Match'] == etag) {
      notModifiedCount++;
      return http.Response('', 304, headers: {'etag': etag});
    }
    return _jsonList(200, body, headers: {'etag': etag});
  }

  http.Response _addComment(FakeIssue issue, String body) {
    final at = _now;
    final comment = FakeComment(
      id: _nextCommentId++,
      body: body,
      author: actor,
      createdAt: at,
      updatedAt: at,
    );
    issue.comments.add(comment);
    return _json(201, comment.toJson());
  }

  http.Response _editComment(FakeGitHubRepo r, int id, String body) {
    for (final issue in r.issues.values) {
      for (final comment in issue.comments) {
        if (comment.id != id) continue;
        comment.body = body;
        comment.updatedAt = _now;
        return _json(200, comment.toJson());
      }
    }
    return _json(404, {'message': 'Not Found'});
  }

  http.Response _deleteComment(FakeGitHubRepo r, int id) {
    for (final issue in r.issues.values) {
      final before = issue.comments.length;
      issue.comments.removeWhere((c) => c.id == id);
      if (issue.comments.length != before) return http.Response('', 204);
    }
    return _json(404, {'message': 'Not Found'});
  }

  /// `repo:<slug> is:issue "<phrase>" in:body` — the one search shape the
  /// fake serves.
  ///
  /// A query naming neither `is:issue` nor `is:pull-request` is refused with
  /// the 422 GitHub answers it with (observed 2026-10-20), so a caller that
  /// leaves the qualifier out fails here rather than only against GitHub.
  ///
  /// Substring matching, not GitHub's tokenizer: the fake must be at least as
  /// permissive as the real thing, because the store *verifies* every hit
  /// against the marker anyway and a fake that were stricter would hide the
  /// case where that verification matters.
  http.Response _searchIssues(String query, {int? perPage, int page = 1}) {
    final terms =
        query.replaceAll(RegExp(r'"[^"]*"'), ' ').split(RegExp(r'\s+'));
    if (!terms.contains('is:issue') && !terms.contains('is:pull-request')) {
      return _json(422, {
        'message': "Query must include 'is:issue' or 'is:pull-request'",
      });
    }
    String? slug;
    final phrases = <String>[];
    final quoted = RegExp(r'"([^"]*)"');
    for (final match in quoted.allMatches(query)) {
      phrases.add(match.group(1)!);
    }
    for (final token in query.replaceAll(quoted, ' ').split(RegExp(r'\s+'))) {
      if (token.startsWith('repo:')) slug = token.substring('repo:'.length);
    }

    final items = <Map<String, dynamic>>[];
    for (final entry in repos.entries) {
      if (slug != null && entry.key != slug) continue;
      for (final issue in entry.value.issues.values) {
        if (!_searchIndexed(issue)) continue;
        if (phrases.every(issue.body.contains)) items.add(issue.toJson());
      }
    }
    // Paginated like the real endpoint, so a caller that enumerates can be
    // driven past one page. `total_count` is the whole match set, not the
    // page — which is how a caller knows there is more.
    final total = items.length;
    final size = pageSizeOverride ?? perPage ?? total;
    final from = (page - 1) * size;
    final slice = from >= total
        ? const <Map<String, dynamic>>[]
        : items.sublist(from, math.min(from + size, total));
    return _json(200, {
      'total_count': total,
      'incomplete_results': searchIncomplete,
      'items': slice,
    });
  }

  /// The `transferIssue` mutation — the only GraphQL operation the fake serves.
  http.Response _graphql(Map<String, dynamic> body) {
    final query = body['query'] as String? ?? '';
    if (!query.contains('transferIssue')) {
      return _json(200, {
        'errors': [
          {'message': 'The fake GitHub server serves only transferIssue'}
        ]
      });
    }
    final variables = body['variables'] as Map<String, dynamic>;
    final issueId = variables['issueId'] as String;
    final repositoryId = variables['repositoryId'] as String;

    String? sourceSlug;
    FakeIssue? issue;
    for (final entry in repos.entries) {
      for (final candidate in entry.value.issues.values) {
        if (candidate.nodeId == issueId) {
          sourceSlug = entry.key;
          issue = candidate;
        }
      }
    }
    final targetSlug = repos.keys.cast<String?>().firstWhere(
          (s) => _repoNodeId(s!) == repositoryId,
          orElse: () => null,
        );
    if (issue == null || sourceSlug == null || targetSlug == null) {
      return _json(200, {
        'errors': [
          {'message': 'Could not resolve issue $issueId or repo $repositoryId'}
        ]
      });
    }

    final source = repos[sourceSlug]!;
    final target = repos[targetSlug]!;
    source.issues.remove(issue.number);

    final number = target.nextIssueNumber++;
    // The three transfer facts, verbatim: a fresh number, a fresh node id,
    // the body copied byte for byte, and **only** the labels the target
    // already defines.
    final moved = FakeIssue(
      number: number,
      nodeId: 'I_${targetSlug}_$number',
      title: issue.title,
      body: issue.body,
      author: issue.author,
      createdAt: issue.createdAt,
      updatedAt: _now,
      state: issue.state,
      labels: issue.labels.where(target.labels.contains).toSet(),
      comments: issue.comments,
      closedAt: issue.closedAt,
    );
    target.issues[number] = moved;

    return _json(200, {
      'data': {
        'transferIssue': {
          'issue': {'number': number}
        }
      }
    });
  }

  static http.Response _jsonList(
    int status,
    List<Map<String, dynamic>> body, {
    Map<String, String> headers = const {},
  }) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json', ...headers},
      );

  static http.Response _json(
    int status,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json', ...headers},
      );
}

// ── Canned failure responses ──────────────────────────────────────────────
//
// The object store above models GitHub *working*. These model it refusing, and
// they are pushed onto [FakeGitHubServer.canned] so the very next request —
// whichever it happens to be — fails. That is deliberate: the retry policy is a
// property of the HTTP layer, so it must hold no matter which endpoint trips
// the limit, and pinning a failure to a specific route would test less.

/// A **primary** rate-limit refusal: quota exhausted until [reset].
///
/// The distinguishing header is `x-ratelimit-remaining: 0` — that is what tells
/// the policy to wait for the reset rather than back off exponentially, and it
/// is why a 403 here is a wait while a 403 without it is an authorization
/// failure.
http.Response rateLimited(DateTime reset) => http.Response(
      jsonEncode({
        'message': 'API rate limit exceeded',
        'documentation_url': 'https://docs.github.com/rest/rate-limit',
      }),
      403,
      headers: {
        'content-type': 'application/json',
        'x-ratelimit-remaining': '0',
        'x-ratelimit-reset':
            '${reset.toUtc().millisecondsSinceEpoch ~/ 1000}',
      },
    );

/// A transient server-side failure — the one class of error that gets
/// exponential backoff, because GitHub advertises no wait for it.
http.Response serverError() => http.Response(
      jsonEncode({'message': 'Server Error'}),
      502,
      headers: const {'content-type': 'application/json'},
    );

/// A **secondary** rate-limit refusal — GitHub saying "too fast", not "not
/// allowed".
///
/// Deliberately carries a healthy `x-ratelimit-remaining`: that is the whole
/// difficulty, since the headers are then byte-for-byte an authorization
/// failure and only the body says otherwise. [blocked] switches between the
/// ordinary throttle (clears in about a minute) and the abuse-detection block
/// (one to two minutes for a client that stops at the refusal, a quarter of an
/// hour for one that keeps sending), which are recovered from differently.
///
/// [retryAfter] models the header GitHub sends on *some* secondary refusals and
/// omits on others. Both cases are real and they are recovered from
/// differently — a stated wait is the backend's own instruction, an absent one
/// leaves the caller to choose — so the fake has to be able to produce either.
http.Response secondaryRateLimited({
  bool blocked = false,
  Duration? retryAfter,
}) =>
    http.Response(
      jsonEncode({
        'message': blocked
            ? 'You have exceeded a secondary rate limit and have been '
                'temporarily blocked from content creation. Please retry your '
                'request again later.'
            : 'You have exceeded a secondary rate limit. Please wait a few '
                'minutes before trying again.',
        'documentation_url':
            'https://docs.github.com/rest/overview/rate-limits-for-the-rest-api',
      }),
      403,
      headers: {
        'content-type': 'application/json',
        'x-ratelimit-remaining': '4321',
        if (retryAfter != null) 'retry-after': '${retryAfter.inSeconds}',
      },
    );

/// A refused credential. Never retried: waiting cannot make a bad token good.
http.Response unauthorized() => http.Response(
      jsonEncode({'message': 'Bad credentials'}),
      401,
      headers: const {'content-type': 'application/json'},
    );

class _FakeClient extends http.BaseClient {
  final FakeGitHubServer server;

  _FakeClient(this.server);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final replayed = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = bytes;
    final response = server.handle(replayed);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
