/// A cleanup reaches the tree it spawned and no process that merely shares a
/// name with one.
///
/// Two trees are started side by side: one is "ours" (a shell with two
/// children), the other a foreign stand-in for another session's
/// `flutter_tester` — it is the same executable as our children, which is
/// the point: name alone must not put it in the kill set.
///
/// **Deadline.** The children are bounded by their own `sleep`; the harness
/// bound is twice the longest wait stated here (seam TEST-DEADLINE).
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'package:tom_test_support/process_tree.dart';

/// The longest this file waits for a process it started to go.
const _exitDeadline = Duration(seconds: 10);

void main() {
  late Process ours;
  late Process foreign;

  setUp(() async {
    // A root with two children, held open by `wait`.
    ours = await Process.start('sh', ['-c', 'sleep 30 & sleep 30 & wait']);
    foreign = await Process.start('sleep', ['30']);
    // Let the shell fork its children before the tree is read.
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });

  tearDown(() async {
    for (final p in [ours, foreign]) {
      for (final pid in processTreeOf(p.pid)) {
        Process.killPid(pid, ProcessSignal.sigkill);
      }
      await p.exitCode.timeout(_exitDeadline);
    }
  });

  test('WONEQR24-F1: the tree of our root is the root and its descendants; a '
      'foreign process of the same name is not in it [1005]', () {
    final tree = processTreeOf(ours.pid);
    expect(tree, contains(ours.pid));
    expect(tree, hasLength(3), reason: 'the shell and its two sleeps');
    expect(
      tree,
      isNot(contains(foreign.pid)),
      reason: 'the stand-in is a `sleep` too, and is left alone',
    );
    expect(processTreeOf(foreign.pid), {foreign.pid});
  }, skip: Platform.isWindows ? 'pgrep/ps' : null);

  test(
    'WONEQR24-F2: aliveAmong answers for the tree it was given — a killed '
    'member drops out, the foreign process is never asked about [1005]',
    () async {
      final tree = processTreeOf(ours.pid);
      expect(aliveAmong(tree), tree);
      final leaf = tree.difference({ours.pid}).first;
      Process.killPid(leaf, ProcessSignal.sigkill);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(aliveAmong(tree), tree.difference({leaf}));
      expect(aliveAmong(tree), isNot(contains(foreign.pid)));
      expect(aliveAmong({foreign.pid}), {
        foreign.pid,
      }, reason: 'still running, untouched');
    },
    skip: Platform.isWindows ? 'pgrep/ps' : null,
  );

  test('WONEQR24-F3: a root killed after the tree was read keeps the walk '
      'honest — its orphans are still named by the earlier set and are alive '
      'until that set is reaped [1005]', () async {
    final before = processTreeOf(ours.pid);
    Process.killPid(ours.pid, ProcessSignal.sigkill);
    await ours.exitCode.timeout(_exitDeadline);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // Orphaned: the children now hang off init, so a fresh walk from the
    // dead root finds nothing — the set taken before the signal is the one
    // that still names them.
    expect(processTreeOf(ours.pid), {ours.pid});
    final leaked = aliveAmong(before);
    expect(leaked, before.difference({ours.pid}));
    for (final pid in leaked) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(aliveAmong(before), isEmpty);
    expect(aliveAmong({foreign.pid}), {foreign.pid});
  }, skip: Platform.isWindows ? 'pgrep/ps' : null);
}
