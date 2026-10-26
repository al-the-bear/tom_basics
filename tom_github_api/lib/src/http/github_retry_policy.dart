import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../github_exception.dart';

/// How the HTTP layer waits out GitHub's rate limits and transient failures.
///
/// GitHub signals three distinct conditions that all look like "try again
/// later" but need different waits:
///
/// * **Primary rate limit** — `403`/`429` with `x-ratelimit-remaining: 0`. The
///   only safe wait is until `x-ratelimit-reset`; retrying sooner is guaranteed
///   to fail and burns nothing but time.
/// * **Secondary rate limit** — `403`/`429` with a non-zero remaining count.
///   GitHub *sometimes* states the wait in a `retry-after` header, in which
///   case that is the wait. When it does not, the **body message** is the only
///   signal there is: the headers are byte-for-byte an authorization failure,
///   because the primary quota is untouched. Missing that case is not a missed
///   optimisation — a burst of issue writes trips this limit routinely, and a
///   caller that treats it as a refusal (D11 §7.3 propagates refusals) fails a
///   flush that would have succeeded a minute later. Backoff starts at
///   [secondaryDelay], GitHub's own "wait at least one minute" guidance.
/// * **Transient server errors** — `5xx`. Nothing is advertised, so this is the
///   one case that gets exponential backoff.
///
/// A secondary-limit wait additionally gets **jitter** — see [jitterFraction].
///
/// [sleep] is injectable so tests can exercise the waits without spending the
/// wall-clock time they describe.
class GitHubRetryPolicy {
  /// Total attempts including the first. `1` disables retrying.
  final int maxAttempts;

  /// First backoff step for transient errors; doubles per attempt.
  final Duration baseDelay;

  /// First backoff step for a secondary rate limit GitHub did not put a
  /// `retry-after` on; doubles per attempt like [baseDelay].
  ///
  /// A minute rather than a second because GitHub says so — "wait at least one
  /// minute before retrying" — and because a secondary limit is a *rate*
  /// judgement, not a transient fault: retrying in a second re-earns it.
  final Duration secondaryDelay;

  /// Ceiling on any single wait. A rate-limit reset an hour out would
  /// otherwise stall a caller indefinitely — past this cap the error is
  /// raised instead, so the caller decides whether to keep waiting.
  final Duration maxDelay;

  /// Ceiling on a *secondary*-limit wait specifically.
  ///
  /// Higher than [maxDelay] because the two situations are not alike. A
  /// primary-quota reset an hour out, or a server that has been failing for
  /// minutes, is a condition the caller should be told about — it may have
  /// something better to do than wait. A secondary limit is GitHub saying
  /// "slower", it clears on its own, and there is nothing better to do: giving
  /// up turns a flush that would have finished into a refusal, which D11 §7.3
  /// propagates to the user as a failure. Measured against a real repository, a
  /// 50-section create-flush was still blocked after the 3 minutes the general
  /// ceiling allowed, and the block cleared shortly after.
  final Duration maxSecondaryDelay;

  /// How much random spread is added to a *secondary*-limit wait, as a
  /// fraction of it. `0` disables jitter.
  ///
  /// A secondary limit is the one failure several clients meet **at the same
  /// instant for the same reason** — it is earned by the account's aggregate
  /// request rate, so a fleet that trips it trips it together. Every one of
  /// them then computes the identical wait from the identical inputs and
  /// retries in lockstep, which re-earns the limit with the same burst that
  /// earned it. Spreading the retries is what breaks that cycle, and it costs
  /// only the spread.
  ///
  /// The primary limit is deliberately **not** jittered: its reset is a stated
  /// instant after which quota genuinely exists, so arriving together at it is
  /// harmless. Jitter is for a wait that is a guess about a shared resource,
  /// not for one that is a fact about a replenished one.
  ///
  /// Additive only — see [jittered].
  final double jitterFraction;

  /// Samples the spread, in `[0, 1)`. Injectable so a test can pin it.
  final double Function() jitter;

  final Future<void> Function(Duration) sleep;

  const GitHubRetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    this.secondaryDelay = const Duration(seconds: 60),
    this.maxDelay = const Duration(minutes: 2),
    this.maxSecondaryDelay = const Duration(minutes: 5),
    this.jitterFraction = 0.25,
    this.jitter = _defaultJitter,
    this.sleep = _realSleep,
  });

  /// Never retries — the right choice inside an outer loop that owns its own
  /// recovery (a compare-and-swap retry, say).
  static const none = GitHubRetryPolicy(maxAttempts: 1);

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  static final _random = math.Random();

  static double _defaultJitter() => _random.nextDouble();

  /// [base] spread by up to `fraction` of itself, using [sample] from `[0, 1)`.
  ///
  /// **Additive only.** Jitter never shortens a wait, because the waits it is
  /// applied to are floors: a `Retry-After` is GitHub's own instruction, and
  /// the fallback backoff is already the shortest wait believed to clear the
  /// limit. Subtracting from either turns de-synchronisation into a retry that
  /// arrives before the limit has lifted — which re-earns it, for every client
  /// the jitter moved earlier.
  ///
  /// Public and static because the sync loop's own deferral needs the same
  /// spread for the same reason, and two implementations of "additive jitter,
  /// clamped" would be two chances to get the sign wrong.
  static Duration jittered(
    Duration base, {
    required double fraction,
    required double sample,
    Duration? ceiling,
  }) {
    if (fraction <= 0 || sample <= 0) return base;
    final extra = (base.inMilliseconds * fraction * sample).round();
    final total = base + Duration(milliseconds: extra);
    // Clamped rather than refused: the ceiling has already been consulted
    // about `base`, so a spread that overshoots it means "wait the maximum",
    // never "give up on a wait that was acceptable a line ago".
    if (ceiling != null && total > ceiling) return ceiling;
    return total;
  }

  /// The wait before re-issuing [response], or `null` when it must not be
  /// retried. [attempt] is 1-based.
  Duration? delayFor(http.Response response, int attempt) {
    if (attempt >= maxAttempts) return null;
    final status = response.statusCode;
    final headers = response.headers;

    if (status == 403 || status == 429) {
      final remaining = int.tryParse(headers['x-ratelimit-remaining'] ?? '');
      if (remaining != null && remaining <= 0) {
        final reset = int.tryParse(headers['x-ratelimit-reset'] ?? '');
        if (reset == null) return null;
        final resetAt =
            DateTime.fromMillisecondsSinceEpoch(reset * 1000, isUtc: true);
        return _cap(resetAt.difference(DateTime.now().toUtc()));
      }
      final kind = GitHubSecondaryLimitKind.of(response.body);
      // The abuse-detection block is not a wait, it is a refusal wearing a
      // wait's clothing. Measured still in force fifteen minutes after an
      // unpaced burst earned it, so spending the secondary budget on it only
      // delays the failure the caller is going to see anyway — and D11 §7.3
      // journals the work rather than losing it.
      if (kind == GitHubSecondaryLimitKind.blocked) return null;
      final retryAfter =
          GitHubSecondaryRateLimitException.retryAfterOf(headers);
      if (retryAfter != null) {
        return _spread(_cap(retryAfter), ceiling: maxDelay);
      }
      if (kind == GitHubSecondaryLimitKind.throttled) {
        return _spread(
          _cap(secondaryDelay * math.pow(2, attempt - 1).toInt(),
              ceiling: maxSecondaryDelay),
          ceiling: maxSecondaryDelay,
        );
      }
      // A 403 with quota left and no secondary signal is an authorization
      // failure, not a wait.
      return null;
    }

    if (status >= 500) {
      return _cap(baseDelay * math.pow(2, attempt - 1).toInt());
    }
    return null;
  }

  /// [jittered] over an already-capped wait, passing `null` through — a wait
  /// the ceiling refused stays refused.
  Duration? _spread(Duration? capped, {required Duration ceiling}) =>
      capped == null
          ? null
          : jittered(capped,
              fraction: jitterFraction, sample: jitter(), ceiling: ceiling);

  /// Clamps to `[1s, ceiling]`, or `null` when the wait exceeds the ceiling.
  /// A zero/negative wait means the window has already passed — retry at once,
  /// but never in a tight spin.
  Duration? _cap(Duration d, {Duration? ceiling}) {
    if (d > (ceiling ?? maxDelay)) return null;
    return d.isNegative || d.inMilliseconds < 1000
        ? const Duration(seconds: 1)
        : d;
  }
}
