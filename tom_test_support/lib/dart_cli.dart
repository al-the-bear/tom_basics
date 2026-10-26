/// The Dart CLI a test may spawn — located, never assumed.
///
/// `Platform.resolvedExecutable` is the *runner's* binary. Under `dart test`
/// that is the Dart CLI; under `flutter test` it is `flutter_tester`, which is
/// not a Dart CLI at all. It fails in two ways depending on what it is asked:
/// told to `compile js` it prints engine errors, starts a VM service and
/// **never exits**; used as a stand-in executable it answers at once but
/// wrongly, so a suite fails fast with a diagnosis about the wrong thing. Both
/// are the same assumption, and both end the same way here: a test gets
/// something named `dart`, or a failure that names the runner as the cause.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The Dart CLI given the runner's own binary [running] and a PATH lookup, or
/// null. Split from its inputs so both branches are testable on a machine
/// that, by running a Dart test at all, always has a Dart CLI.
///
/// Cheapest first: when the runner **is** the Dart CLI nothing is spawned.
/// What it never does is hand back a runner that is not one.
String? tomDartFrom(String running, String? Function() lookupOnPath) {
  if (p.basenameWithoutExtension(running) == 'dart') return running;
  final found = lookupOnPath();
  return (found == null || found.isEmpty) ? null : found;
}

/// `dart` as the PATH resolves it, or null.
String? tomDartOnPath() {
  final found = Process.runSync(Platform.isWindows ? 'where' : 'which', const [
    'dart',
  ], runInShell: false);
  if (found.exitCode != 0) return null;
  final first = (found.stdout as String).trim().split('\n').first.trim();
  return first.isEmpty ? null : first;
}

/// The Dart CLI for this process, or null when none is on offer.
String? tomDartCli() => tomDartFrom(Platform.resolvedExecutable, tomDartOnPath);

/// Why no Dart CLI could be found, for a test that needs one to [purpose].
///
/// A sentence rather than a flag because it is the deliverable: it replaces a
/// hang, or a failure blamed on something else, with one that says what to do.
String tomMissingDartReason(String purpose) =>
    'No Dart CLI found, and this test needs one to $purpose. Run it with '
    '`dart test`, or put `dart` on PATH. The runner here is '
    '"${Platform.resolvedExecutable}", which is not a Dart CLI — under '
    '`flutter test` it is `flutter_tester`, and a test that spawns it gets '
    'either a process that never exits or a failure about the wrong thing.';

/// The Dart CLI, or a [StateError] carrying [tomMissingDartReason].
String requireTomDartCli(String purpose) =>
    tomDartCli() ?? (throw StateError(tomMissingDartReason(purpose)));
