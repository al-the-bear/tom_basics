/// Rate limit information extracted from GitHub API response headers.
class GitHubRateLimit {
  final int limit;
  final int remaining;
  final DateTime resetAt;

  const GitHubRateLimit({
    required this.limit,
    required this.remaining,
    required this.resetAt,
  });

  /// Parse from HTTP response headers.
  factory GitHubRateLimit.fromHeaders(Map<String, String> headers) {
    return GitHubRateLimit(
      limit: int.parse(headers['x-ratelimit-limit'] ?? '5000'),
      remaining: int.parse(headers['x-ratelimit-remaining'] ?? '5000'),
      resetAt: DateTime.fromMillisecondsSinceEpoch(
        int.parse(headers['x-ratelimit-reset'] ?? '0') * 1000,
        isUtc: true,
      ),
    );
  }

  /// Whether the rate limit has been exceeded.
  bool get isExceeded => remaining <= 0;

  /// Duration until the rate limit resets.
  Duration get resetIn => resetAt.difference(DateTime.now().toUtc());

  @override
  String toString() =>
      'GitHubRateLimit($remaining/$limit, resets at $resetAt)';
}
