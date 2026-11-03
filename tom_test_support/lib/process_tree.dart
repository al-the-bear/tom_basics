/// The process tree a test or a test runner started, so its cleanup reaches
/// that tree and nothing else.
///
/// Reaping the `flutter_tester` hosts a child `flutter test` leaves behind by
/// matching every `flutter_tester` on the machine by name — or every one that
/// appeared while the child ran — kills whichever test runs beside it, in a
/// parallel run or in another session. A cleanup is scoped to what was itself
/// spawned: the child's pid and every descendant of it, walked with
/// `pgrep -P`. A process is never matched by its name.
///
/// The walk is taken **while the tree is intact**. A child that is SIGKILLed
/// loses its children to the init process, so a descendant found after the
/// fact is no longer a descendant; the set taken before the signal is what a
/// later [aliveAmong] is asked about.
library;

import 'dart:io';

/// [root] and every process descended from it, at this moment.
///
/// POSIX only — `pgrep -P` lists a parent's children; the walk repeats it
/// per level. Throws [UnsupportedError] on Windows rather than answering with
/// an empty set a caller could mistake for "nothing to reap".
Set<int> processTreeOf(int root) {
  if (Platform.isWindows) {
    throw UnsupportedError('processTreeOf walks with pgrep -P (POSIX only)');
  }
  final tree = <int>{root};
  final frontier = [root];
  while (frontier.isNotEmpty) {
    final parent = frontier.removeLast();
    for (final child in _childrenOf(parent)) {
      if (tree.add(child)) frontier.add(child);
    }
  }
  return tree;
}

/// The members of [pids] that are still running, by `ps -p`.
Set<int> aliveAmong(Iterable<int> pids) {
  final asked = pids.toSet();
  if (asked.isEmpty) return const {};
  final r = Process.runSync('ps', ['-o', 'pid=', '-p', asked.join(',')]);
  return {
    for (final pid in _pids(r.stdout as String))
      if (asked.contains(pid)) pid,
  };
}

List<int> _childrenOf(int parent) {
  final r = Process.runSync('pgrep', ['-P', '$parent']);
  // pgrep exits 1 for "no match"; that is an empty list, not a failure.
  if (r.exitCode > 1) {
    throw ProcessException(
      'pgrep',
      ['-P', '$parent'],
      '${r.stderr}',
      r.exitCode,
    );
  }
  return _pids(r.stdout as String);
}

List<int> _pids(String text) => [
  for (final line in text.split('\n')) ?int.tryParse(line.trim()),
];
