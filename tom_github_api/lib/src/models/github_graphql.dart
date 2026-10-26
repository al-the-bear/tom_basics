/// GitHub's GraphQL surface: one response, three error classes, and a budget
/// that is a different currency from REST's (woneprpc78).
///
/// The client has posted GraphQL since `transferIssue` landed, privately, for
/// that one caller. Everything else in the workspace that needed GraphQL built
/// its own `http.Client` — and a second HTTP stack beside this one is a second
/// place that handles auth, retries and the rate-limit headers.
///
/// The shapes here are **wire-established**, not guessed: `woneprpb22` ran the
/// three error classes against a live endpoint and found that `path` is the
/// discriminator. The client's job is to hand a caller that distinction, not
/// to re-derive it from message substrings or HTTP statuses — GraphQL answers
/// `200` for all of them.
library;

/// One entry of a GraphQL `errors` array.
///
/// [path] is the **discriminator**, and reading anything else is reading the
/// wrong thing:
///
/// * a **query-fatal** error (`INSUFFICIENT_SCOPES` is the one measured)
///   arrives with **no `data` key at all** and **no `path`** — nothing in the
///   document resolved;
/// * a **field-scoped** error (`NOT_FOUND`, `VALIDATION`) arrives with `data`
///   present, the offending field null, and `path` naming it — every sibling
///   field still resolved, so discarding the response would throw away the
///   half that worked.
class GitHubGraphQlError {
  /// GitHub's `type`, e.g. `NOT_FOUND`, `INSUFFICIENT_SCOPES`, `VALIDATION`.
  ///
  /// Nullable because the field is GitHub's convention rather than the
  /// GraphQL spec's: a validation failure raised by the parser carries a
  /// message and no type.
  final String? type;

  /// The path of the field that failed, or null when the whole query did.
  final List<Object?>? path;

  final String message;

  /// The entry as it arrived, so a caller can read a key this class does not
  /// model without the client having to grow one.
  final Map<String, dynamic> raw;

  const GitHubGraphQlError({
    required this.type,
    required this.path,
    required this.message,
    required this.raw,
  });

  factory GitHubGraphQlError.fromJson(Map<String, dynamic> json) =>
      GitHubGraphQlError(
        type: json['type'] as String?,
        path: (json['path'] as List?)?.cast<Object?>(),
        message: json['message'] as String? ?? '$json',
        raw: json,
      );

  /// Whether this error killed one field and left its siblings alive.
  bool get isFieldScoped => path != null;

  @override
  String toString() => '${type ?? 'ERROR'}'
      '${path == null ? '' : ' at ${path!.join('.')}'}: $message';
}

/// What a query's own `rateLimit { … }` field reported.
///
/// **Not** the REST budget under another name. GraphQL bills 5000 **points**
/// an hour, where `cost = max(1, round(totalRequests / 100))` is computed from
/// the `first`/`last` maxima the *document asks for* rather than from what it
/// gets back — so a query that requests 100×100 nodes and matches none still
/// costs what it asked for.
///
/// Readable only where GitHub offers it: `rateLimit` exists on `Query` and
/// **not** on `Mutation`, so a mutation's cost can be read from the response
/// headers alone. That asymmetry is why [GitHubApiClient.lastGraphQlRateLimit]
/// exists beside this: one is what the document asked for, the other is what
/// the account has left.
class GitHubGraphQlCost {
  final int limit;
  final int cost;
  final int remaining;
  final int? nodeCount;
  final DateTime? resetAt;

  const GitHubGraphQlCost({
    required this.limit,
    required this.cost,
    required this.remaining,
    this.nodeCount,
    this.resetAt,
  });

  /// Reads a `rateLimit` object out of [data], wherever the caller aliased it.
  ///
  /// Returns null when the document did not ask for one, which is the ordinary
  /// case and not a failure — a caller that wants the budget requests the
  /// field.
  static GitHubGraphQlCost? fromData(Map<String, dynamic>? data) {
    final rate = data?['rateLimit'];
    if (rate is! Map<String, dynamic>) return null;
    final limit = rate['limit'];
    final cost = rate['cost'];
    final remaining = rate['remaining'];
    if (limit is! int || cost is! int || remaining is! int) return null;
    return GitHubGraphQlCost(
      limit: limit,
      cost: cost,
      remaining: remaining,
      nodeCount: rate['nodeCount'] as int?,
      resetAt: switch (rate['resetAt']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
    );
  }

  @override
  String toString() =>
      'GitHubGraphQlCost(cost $cost, $remaining/$limit points left)';
}

/// One GraphQL reply: what resolved, what failed, and what it cost.
///
/// Returned rather than reduced to `data`, because a field-scoped failure
/// leaves a **partial** result that is still worth having — §1's measurement
/// is that the siblings of a failed field resolve — and a caller cannot tell
/// a null field from an absent one without the errors beside it.
class GitHubGraphQlResponse {
  /// The decoded `data`, or null when nothing resolved — GitHub either omitted
  /// the key or answered it null, which are the same fact to a caller.
  final Map<String, dynamic>? data;

  /// Empty on a clean reply.
  final List<GitHubGraphQlError> errors;

  /// The `rateLimit` field, when the document asked for one.
  final GitHubGraphQlCost? cost;

  const GitHubGraphQlResponse({
    required this.data,
    required this.errors,
    required this.cost,
  });

  factory GitHubGraphQlResponse.fromJson(Map<String, dynamic> json) {
    // Absent and explicitly null are **both** "nothing resolved", and the
    // distinction is deliberately not preserved. A fatal query omits `data`
    // entirely; a document whose root field failed answers `"data": null`.
    // Neither leaves a caller anything to read, so carrying the difference
    // would be carrying a fact with no consumer — and an earlier draft of this
    // constructor kept a `containsKey` that could not have distinguished them
    // anyway, since both arrive here as a null map.
    final data = json['data'] as Map<String, dynamic>?;
    return GitHubGraphQlResponse(
      data: data,
      errors: [
        for (final error in (json['errors'] as List? ?? const []))
          if (error is Map<String, dynamic>)
            GitHubGraphQlError.fromJson(error),
      ],
      cost: GitHubGraphQlCost.fromData(data),
    );
  }

  bool get hasErrors => errors.isNotEmpty;

  /// Errors that killed one field and left the rest.
  Iterable<GitHubGraphQlError> get fieldErrors =>
      errors.where((e) => e.isFieldScoped);

  /// Errors that killed the whole document.
  Iterable<GitHubGraphQlError> get queryErrors =>
      errors.where((e) => !e.isFieldScoped);

  @override
  String toString() => 'GitHubGraphQlResponse('
      '${data == null ? 'no data' : '${data!.keys.length} field(s)'}, '
      '${errors.length} error(s))';
}
