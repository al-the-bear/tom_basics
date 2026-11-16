/// `pub get` for `:pubget`, with one repair for a machine-local lock.
///
/// A library keeps its `pubspec.lock` untracked, so each host's lock is its
/// own, and a git dependency on a moving branch stays at the commit the host
/// resolved first (`pub get` keeps a locked resolved-ref). When the branch has
/// moved on and another dependency needs what the new commit brings, `pub get`
/// fails on version solving. [runPubGet] then retries once with
/// `pub upgrade <every git package of the lock>` and says so. A tracked lock
/// (an application's) is never upgraded: it follows the
/// pubspec-lock-last-changed rule, so its failure is reported as it is.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';
import 'package:yaml/yaml.dart';

/// The outcome of [runPubGet]: the exit code of the last command run, and the
/// git packages it upgraded (empty when `pub get` was enough or no retry was
/// made).
typedef PubGetOutcome = ({int exitCode, List<String> upgraded});

/// Runs `<executable> pub get` in [projectPath], printing its output, and
/// retries once with `<executable> pub upgrade <git packages>` when it failed
/// on version solving, the project's `pubspec.lock` is not tracked by git and
/// it pins git packages.
Future<PubGetOutcome> runPubGet(String projectPath, String executable) async {
  final get = await _pub(executable, ['pub', 'get'], projectPath);
  if (get.exitCode == 0) return (exitCode: 0, upgraded: const <String>[]);

  final failedOnSolving = '${get.stdout}\n${get.stderr}'.contains(
    'version solving failed',
  );
  final lockPath = p.join(projectPath, 'pubspec.lock');
  final gitPackages = failedOnSolving
      ? gitPackagesInLock(lockPath)
      : const <String>[];
  if (gitPackages.isEmpty || _isTracked(projectPath, 'pubspec.lock')) {
    return (exitCode: get.exitCode, upgraded: const <String>[]);
  }

  print(
    'Retrying with $executable pub upgrade ${gitPackages.join(' ')}: the '
    'untracked pubspec.lock pins git packages at the commits this host '
    'resolved first.',
  );
  final upgrade = await _pub(executable, [
    'pub',
    'upgrade',
    ...gitPackages,
  ], projectPath);
  return (exitCode: upgrade.exitCode, upgraded: gitPackages);
}

/// The packages of the lock at [lockPath] whose source is git, in the lock's
/// order; empty when the file is missing or unreadable.
List<String> gitPackagesInLock(String lockPath) {
  final file = File(lockPath);
  if (!file.existsSync()) return const [];
  final Object? doc;
  try {
    doc = loadYaml(file.readAsStringSync());
  } on YamlException {
    return const [];
  }
  if (doc is! YamlMap || doc['packages'] is! YamlMap) return const [];
  return [
    for (final MapEntry(:key, :value) in (doc['packages'] as YamlMap).entries)
      if (value is YamlMap && value['source'] == 'git') '$key',
  ];
}

/// Whether git tracks [file] in [dir]. Outside a git repository nothing is
/// tracked.
bool _isTracked(String dir, String file) {
  try {
    final r = Process.runSync('git', [
      'ls-files',
      '--error-unmatch',
      '--',
      file,
    ], workingDirectory: dir);
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<ProcessRunResult> _pub(
  String executable,
  List<String> args,
  String projectPath,
) async {
  // Printed, not streamed: under --jobs the projects run at once, and
  // ToolRunner keeps each project's printed output together.
  final run = await ProcessRunner.run(
    executable,
    args,
    workingDirectory: projectPath,
    runInShell: Platform.isWindows,
  );
  for (final text in [run.stdout, run.stderr]) {
    final trimmed = text.trimRight();
    if (trimmed.isNotEmpty) print(trimmed);
  }
  return run;
}
