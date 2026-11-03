/// The wait a live suite makes between a write and the read that depends on
/// it.
///
/// **Why a live suite has to wait at all.** A remote such as GitHub serves
/// reads from replicas and promises no read-after-write consistency — not to
/// the client that wrote, and least of all to a second one. A suite that writes
/// and then asks a *different* client what the remote holds can be answered
/// from a replica that has not seen the write yet. That window is not what a
/// live suite measures; what happens after it is. So the suite settles first —
/// it reads until the remote shows what was written, or a deadline passes —
/// and asserts after.
///
/// **One policy for every settle**, because "settled" is a property of the
/// remote and not of the caller: two suites disagreeing about how long the
/// remote may take would mean one of them is measuring the other's patience.
/// [tomLiveSettleTimeout] is far beyond anything observed, so reaching it is a
/// finding rather than a slow day.
///
/// **A settle is not a retry of an assertion.** The caller names what it
/// expects to become visible, the loop only reads, and a settle that times out
/// fails with the last value it saw. A suite that fails *after* a settle has
/// found a real defect.
///
/// Framework-free, like `pump_until.dart`: the timeout is this library's own
/// exception, so a pure-Dart and a Flutter suite use the same loop.
library;

/// How long a settle may take before it fails.
///
/// Thirty seconds: a GitHub ref replica normally catches up inside two (the
/// longest tail measured was under one, `TomGitHubStorage.refReplicaWindow`),
/// so this is a deadline for a remote that has not converged, not a budget.
const tomLiveSettleTimeout = Duration(seconds: 30);

/// Above this, a settle that **succeeded** says what it cost.
///
/// Settles are silent on success, so a run in which every one needed twelve
/// seconds and a run in which every one returned on the first read would look
/// identical — and a widening read-after-write window would show up first as a
/// [tomLiveSettleTimeout] failure, with no earlier sign it was creeping toward
/// it. Two seconds is above the ordinary case and far below the deadline. The
/// line is an observation, not a warning.
const tomLiveSettleSlowAfter = Duration(seconds: 2);

/// The settle's deadline passed before the remote showed what was expected.
class TomSettleTimeout implements Exception {
  /// What was waited for, as the caller named it.
  final String what;

  /// The last value read.
  final Object? last;

  /// How many reads, over how long — `"7 reads over 30.4 s"`.
  final String spent;

  /// The caller's account of the failure, when it gave one.
  final String? detail;

  TomSettleTimeout({
    required this.what,
    required this.last,
    required this.spent,
    this.detail,
  });

  /// The report, in one paragraph.
  String get message =>
      detail ??
      'The remote never showed $what.\n'
          '  last read: $last\n'
          '  after:     $spent';

  @override
  String toString() => 'TomSettleTimeout: $message';
}

/// Reads with [read] until [done] accepts the value, and returns it.
///
/// Backs off between reads — 200 ms first, growing by half up to two seconds —
/// so the common case, visible on the first or second read, costs almost
/// nothing and a lagging replica is not hammered for the whole deadline.
///
/// Throws [TomSettleTimeout] at [timeout], whose message is
/// [describeFailure]'s when given. On success, when the settle took longer than
/// [slowAfter], hands one line to [report] (`print` by default):
/// `live settle: <what> became visible after <n> reads over <s> s`.
Future<T> tomSettleUntil<T>({
  required String what,
  required Future<T> Function() read,
  required bool Function(T value) done,
  String Function(T last, String spent)? describeFailure,
  Duration timeout = tomLiveSettleTimeout,
  Duration slowAfter = tomLiveSettleSlowAfter,
  void Function(String line) report = print,
}) async {
  const first = Duration(milliseconds: 200);
  const cap = Duration(seconds: 2);
  final clock = Stopwatch()..start();
  var delay = first;
  var reads = 0;
  String spent() =>
      '$reads reads over '
      '${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s';
  while (true) {
    final value = await read();
    reads++;
    if (done(value)) {
      if (clock.elapsed > slowAfter) {
        report('live settle: $what became visible after ${spent()}');
      }
      return value;
    }
    if (clock.elapsed >= timeout) {
      throw TomSettleTimeout(
        what: what,
        last: value,
        spent: spent(),
        detail: describeFailure?.call(value, spent()),
      );
    }
    await Future<void>.delayed(delay);
    final next = delay * 1.5;
    delay = next > cap ? cap : next;
  }
}
