import 'models/github_rate_limit.dart';

/// How GitHub's *secondary* rate limits are recognised.
///
/// They are recognisable by nothing but the response body. A secondary limit
/// leaves the primary quota untouched, so `x-ratelimit-remaining` still reads
/// in the thousands and the headers are byte-for-byte an authorization
/// failure. The retry policy and the exception mapping both classify through
/// this one type, so they cannot come to different conclusions about the same
/// response.
///
/// Matched on the raw body rather than a decoded `message` field: GitHub
/// answers some abuse-detection cases with an HTML page, and a JSON decode
/// that threw would turn the one recoverable 403 back into a refusal.
enum GitHubSecondaryLimitKind {
  /// Not a secondary limit at all.
  none,

  /// "You have exceeded a secondary rate limit. Please wait a few minutes."
  /// Measured to clear inside a minute or two — worth waiting out.
  throttled,

  /// "…and have been temporarily blocked from content creation." The
  /// abuse-detection block. How long it holds depends on what the client does
  /// next: still in force fifteen minutes after an unpaced burst that kept
  /// sending; cleared in 70–113 seconds, three runs out of three, for a client
  /// that stopped at the first refusal. Issue and comment writes meet it;
  /// git-data writes were measured to go through while it held.
  blocked;

  /// Classifies a raw response body.
  static GitHubSecondaryLimitKind of(String body) {
    if (body.isEmpty) return none;
    final lower = body.toLowerCase();
    final isSecondary = lower.contains('secondary rate limit') ||
        // The older wording, still served by some endpoints.
        lower.contains('abuse detection');
    if (!isSecondary) return none;
    return lower.contains('blocked from content creation')
        ? blocked
        : throttled;
  }
}

/// Base exception for all GitHub API errors.
class GitHubException implements Exception {
  final int statusCode;
  final String message;
  final String? documentationUrl;
  final Map<String, dynamic>? responseBody;

  const GitHubException({
    required this.statusCode,
    required this.message,
    this.documentationUrl,
    this.responseBody,
  });

  /// [rawBody] is the undecoded response body, when the caller still has it.
  /// A secondary rate limit is recognisable only from the body text, and
  /// GitHub answers some of them with an HTML page that never became [body].
  factory GitHubException.fromResponse(
    int statusCode,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    String? rawBody,
  }) {
    final message = body['message'] as String? ?? 'Unknown error';
    final docUrl = body['documentation_url'] as String?;

    // Distinguish 403 causes
    if (statusCode == 403 && headers != null) {
      final remaining = headers['x-ratelimit-remaining'];
      if (remaining == '0') {
        return GitHubRateLimitException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
          rateLimit: GitHubRateLimit.fromHeaders(headers),
        );
      }
    }

    if (statusCode == 403 || statusCode == 429) {
      final kind = GitHubSecondaryLimitKind.of(rawBody ?? message);
      if (kind != GitHubSecondaryLimitKind.none) {
        return GitHubSecondaryRateLimitException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
          kind: kind,
          retryAfter:
              GitHubSecondaryRateLimitException.retryAfterOf(headers),
        );
      }
    }

    return switch (statusCode) {
      401 => GitHubAuthException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
        ),
      403 => GitHubAuthException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
        ),
      404 => GitHubNotFoundException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
        ),
      422 => GitHubValidationException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
          errors: (body['errors'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>(),
        ),
      _ => GitHubException(
          statusCode: statusCode,
          message: message,
          documentationUrl: docUrl,
          responseBody: body,
        ),
    };
  }

  @override
  String toString() => 'GitHubException($statusCode): $message';
}

/// 404 Not Found.
/// A GraphQL document that resolved **nothing** (woneprpc78).
///
/// Raised only for the query-fatal class — GitHub omitted the `data` key
/// altogether, which `woneprpb22` measured for `INSUFFICIENT_SCOPES`. A
/// field-scoped failure is **not** this: its siblings resolved, so it comes
/// back inside a `GitHubGraphQlResponse` for the caller to read.
///
/// [statusCode] is `200` and that is not a placeholder. GraphQL reports every
/// error class over a successful HTTP response, so the field keeps meaning
/// "what GitHub answered" and the diagnosis lives in [errors].
class GitHubGraphQlException extends GitHubException {
  /// The `errors` array as it arrived, already parsed.
  ///
  /// Typed as `List<Object>` rather than as the model's own class so this file
  /// stays free of an import that would point from the exceptions back at the
  /// models; every element *is* a `GitHubGraphQlError`, and a caller that
  /// wants the fields casts one. The alternative — moving the exception in
  /// beside the model — would put one exception somewhere no reader looks for
  /// exceptions.
  final List<Object> errors;

  const GitHubGraphQlException({
    required super.statusCode,
    required super.message,
    required this.errors,
    super.responseBody,
  });
}

class GitHubNotFoundException extends GitHubException {
  const GitHubNotFoundException({
    required super.statusCode,
    required super.message,
    super.documentationUrl,
    super.responseBody,
  });

  @override
  String toString() => 'GitHubNotFoundException($statusCode): $message';
}

/// 401 Unauthorized / 403 Forbidden (not rate limit).
class GitHubAuthException extends GitHubException {
  const GitHubAuthException({
    required super.statusCode,
    required super.message,
    super.documentationUrl,
    super.responseBody,
  });

  @override
  String toString() => 'GitHubAuthException($statusCode): $message';
}

/// 422 Unprocessable Entity — validation errors.
class GitHubValidationException extends GitHubException {
  final List<Map<String, dynamic>>? errors;

  const GitHubValidationException({
    required super.statusCode,
    required super.message,
    super.documentationUrl,
    super.responseBody,
    this.errors,
  });

  @override
  String toString() => 'GitHubValidationException($statusCode): $message';
}

/// 403/429 caused by a *secondary* rate limit — "you are going too fast",
/// not "you may not do this".
///
/// Separate from [GitHubRateLimitException] because the primary quota is
/// untouched: the wait is stated differently when it is stated at all, and the
/// recovery is different. Separate from [GitHubAuthException] because a caller
/// told its token was refused will go and check the token, which is the one
/// thing that is not wrong here.
class GitHubSecondaryRateLimitException extends GitHubException {
  final GitHubSecondaryLimitKind kind;

  /// The wait GitHub asked for in `Retry-After`, or null when it asked for
  /// none.
  ///
  /// Null is a real answer and not a missing one: GitHub states this header on
  /// some secondary refusals and omits it on others, and the difference matters
  /// to a caller. A stated wait is the backend's own instruction and is obeyed;
  /// an absent one leaves the caller to choose a wait of its own, which it may
  /// then describe as its own choice rather than as GitHub's. Nothing is
  /// invented here to spare callers that distinction — a fabricated instruction
  /// is indistinguishable from a real one exactly where it does the most harm.
  final Duration? retryAfter;

  const GitHubSecondaryRateLimitException({
    required super.statusCode,
    required super.message,
    super.documentationUrl,
    super.responseBody,
    required this.kind,
    this.retryAfter,
  });

  /// The `Retry-After` wait in [headers], or null when there is none.
  ///
  /// Seconds only. RFC 9110 also permits an HTTP-date, but GitHub sends
  /// seconds, and a date misread as a second count would produce a wait of
  /// absurd length from a response that looked ordinary. Treating an
  /// unrecognised value as absent falls back to the caller's own conservative
  /// wait, which is wrong by minutes rather than by years.
  ///
  /// Shared by [GitHubException.fromResponse] and [GitHubRetryPolicy] so the
  /// in-request retry and the exception a caller finally sees cannot disagree
  /// about how long GitHub asked them to wait.
  static Duration? retryAfterOf(Map<String, String>? headers) {
    final seconds = int.tryParse(headers?['retry-after'] ?? '');
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }

  /// Whether GitHub's abuse detection has blocked content creation outright,
  /// rather than merely throttling it. Measured: the throttle clears in about
  /// a minute; the block was still in force fifteen minutes on. A caller that
  /// sees this should stop and journal the work, not keep retrying.
  bool get blockedFromContentCreation =>
      kind == GitHubSecondaryLimitKind.blocked;

  @override
  String toString() => 'GitHubSecondaryRateLimitException($statusCode): '
      '$message'
      '${retryAfter == null ? '' : ' [retry after ${retryAfter!.inSeconds}s]'}'
      '${blockedFromContentCreation ? ' [content creation blocked]' : ''}';
}

/// 403 Rate Limit Exceeded.
class GitHubRateLimitException extends GitHubException {
  final GitHubRateLimit rateLimit;

  const GitHubRateLimitException({
    required super.statusCode,
    required super.message,
    super.documentationUrl,
    super.responseBody,
    required this.rateLimit,
  });

  @override
  String toString() =>
      'GitHubRateLimitException: $message (resets at ${rateLimit.resetAt})';
}
