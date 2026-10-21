/// A whole CI run: stages run in order, past any red, each step's full log
/// kept in one timestamped folder, and one summary line at the end.
///
/// What a stage *does* is the repository's — a callback handed to [CiRun] —
/// while the run, the logs, the lock, the summary and the interrupt handling
/// are the same for every repository that drives its CI by hand.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'ci_lock.dart';
import 'ci_process.dart';

/// One package a stage runs over.
class CiPackage {
  const CiPackage({
    required this.name,
    required this.directory,
    required this.isFlutter,
  });

  /// A package found under [directory]: its name relative to [root]
  /// (`/`-separated), and whether it is a Flutter package.
  factory CiPackage.at(String root, String directory) => CiPackage(
    name: p.relative(directory, from: root).replaceAll(r'\', '/'),
    directory: directory,
    isFlutter: ciIsFlutterPackage(directory),
  );

  /// The path relative to the repository root, `/`-separated (`pkg`,
  /// `pkg/example`). Also the name its log carries, with `/` replaced by `.`.
  final String name;

  /// Absolute directory of the package.
  final String directory;

  /// Whether the package depends on the Flutter SDK, so is analysed and
  /// tested with `flutter` rather than `dart`.
  final bool isFlutter;

  /// The file-name form of [name].
  String get logName => name.replaceAll('/', '.');

  @override
  String toString() => name;
}

/// Whether the package in [directory] declares a `flutter` SDK dependency.
bool ciIsFlutterPackage(String directory) {
  final file = File(p.join(directory, 'pubspec.yaml'));
  if (!file.existsSync()) return false;
  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return false;
  final dependencies = yaml['dependencies'];
  final flutter = dependencies is YamlMap ? dependencies['flutter'] : null;
  return flutter is YamlMap && flutter['sdk'] == 'flutter';
}

/// The tags among [candidates] that some test file under [directory]`/test`
/// declares in an `@Tags([...])` annotation, in [candidates]' order.
///
/// Read from the files, not from `dart_test.yaml`: a tag declared there and
/// used by no test would make a stage that selects it run an empty selection
/// and call it green. An annotation starts its line, so the same text inside
/// a string (a test of this very scan) is not one.
List<String> ciTestTagsOf(String directory, List<String> candidates) {
  final tests = Directory(p.join(directory, 'test'));
  if (!tests.existsSync()) return const [];
  final found = <String>{};
  final annotation = RegExp(r'^@Tags\(\s*\[([^\]]*)\]', multiLine: true);
  for (final file in tests.listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    for (final m in annotation.allMatches(file.readAsStringSync())) {
      for (final tag in candidates) {
        if (m.group(1)!.contains("'$tag'") || m.group(1)!.contains('"$tag"')) {
          found.add(tag);
        }
      }
    }
  }
  return [
    for (final tag in candidates)
      if (found.contains(tag)) tag,
  ];
}

/// Expands `all` into [stages], keeps the given order and drops repeats.
/// Unknown names throw.
///
/// [inAll] decides which stages `all` takes — every one by default; a stage
/// that can only run on some hosts is left out of `all` elsewhere and still
/// runs when named on its own.
List<String> resolveCiStages(
  Iterable<String> requested, {
  required List<String> stages,
  bool Function(String stage)? inAll,
}) {
  final out = <String>[];
  for (final name in requested) {
    if (name == 'all') {
      out.addAll(
        stages.where((s) => !out.contains(s) && (inAll?.call(s) ?? true)),
      );
    } else if (stages.contains(name)) {
      if (!out.contains(name)) out.add(name);
    } else {
      throw ArgumentError.value(name, 'stage', 'not a stage');
    }
  }
  return out;
}

/// The result of one step of one stage.
class CiOutcome {
  const CiOutcome({
    required this.stage,
    required this.subject,
    required this.ok,
    required this.logPath,
    this.detail = '',
    this.elapsed = Duration.zero,
    this.skipped = false,
  });

  final String stage;

  /// The package or step (`pkg`, `check_package_seams`).
  final String subject;
  final bool ok;
  final String logPath;
  final String detail;
  final Duration elapsed;

  /// Not run, for a reason in [detail] — counted apart from green and red.
  final bool skipped;

  String get label => subject == stage ? stage : '$stage $subject';
}

/// `14m02s`, `9s`.
String formatCiDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '${m}m${s.toString().padLeft(2, '0')}s' : '${s}s';
}

/// The single line every run ends with. One line — a person reading the end
/// of a terminal and a script reading the last line of output get the same
/// answer: green or red, and for each red, the log that holds the finding.
String ciSummaryLine({
  required List<String> stages,
  required List<CiOutcome> outcomes,
  required Duration elapsed,
  required String runDir,
  required String relativeTo,
}) {
  String rel(String path) => p.relative(path, from: relativeTo);
  final red = [
    for (final o in outcomes)
      if (!o.ok) o,
  ];
  final time = formatCiDuration(elapsed);
  if (outcomes.isEmpty) {
    return 'CI RED: no step ran (${stages.join(' ')}) in $time';
  }
  final skipped = outcomes.where((o) => o.skipped).length;
  final skips = skipped == 0 ? '' : ', $skipped skipped';
  if (red.isEmpty) {
    final steps = outcomes.length == 1 ? '1 step' : '${outcomes.length} steps';
    return 'CI GREEN: ${stages.join(' ')} — $steps, 0 red'
        '$skips, in $time — logs ${rel(runDir)}';
  }
  final named = red.map((o) => '${o.label} (${rel(o.logPath)})').join('; ');
  return 'CI RED: ${red.length} of ${outcomes.length} steps red — $named — '
      'in $time';
}

/// What a stage does: given the run, it calls [CiRun.step], [CiRun.fail] and
/// [CiRun.skip] for each of its steps.
typedef CiStageRunner = Future<void> Function(CiRun run, String stage);

/// A whole run: the stages it was asked for, into one timestamped log folder.
class CiRun {
  CiRun({
    required this.toolName,
    required this.repositoryRoot,
    required this.lockPath,
    required this.stageDescriptions,
    required this.runStage,
    required this.console,
    String? logRoot,
    String? runDir,
    String? flutter,
    String? dart,
    String? Function() findFlutter = ciFlutterExecutable,
  }) : runDir =
           runDir ??
           p.join(
             logRoot ?? p.join(repositoryRoot, 'testlog'),
             ciTimestamp(DateTime.now()),
           ),
       dart = dart ?? ciDartExecutable(),
       flutter = flutter ?? findFlutter() {
    runner = CiProcessRunner(
      lock: CiLock(lockPath),
      pathPrefix: this.flutter == null ? null : p.dirname(this.flutter!),
      onLockWait: (waited) => console.write(
        '\n    waiting for $lockPath (${formatCiDuration(waited)}) — another '
        'session runs flutter',
      ),
    );
  }

  /// The tool's name, the first line of the console output.
  final String toolName;

  /// The repository the run verifies; paths are printed relative to it.
  final String repositoryRoot;

  /// The lock directory every child process runs under.
  final String lockPath;

  /// One line per stage, printed as each begins.
  final Map<String, String> stageDescriptions;

  /// What each stage does.
  final CiStageRunner runStage;

  final StringSink console;
  final String runDir;
  final String dart;

  /// The flutter executable: the one given, else what the constructor's
  /// `findFlutter` found (by default [ciFlutterExecutable]); null when there
  /// is none, and then a step that needs it is red without running.
  final String? flutter;

  late final CiProcessRunner runner;
  final List<CiOutcome> outcomes = [];

  /// [path] relative to [repositoryRoot], as the output prints it.
  String relative(String path) => p.relative(path, from: repositoryRoot);

  /// Runs [stages] in order, past any red, and returns the summary line.
  Future<String> run(List<String> stages) async {
    final watch = Stopwatch()..start();
    Directory(runDir).createSync(recursive: true);
    console.writeln('$toolName ${stages.map((s) => ':$s').join(' ')}');
    console.writeln('  logs    ${relative(runDir)}');
    console.writeln('  lock    $lockPath');
    console.writeln(
      '  flutter ${flutter ?? 'NOT FOUND (put it on PATH or set FLUTTER_ROOT)'}',
    );

    final subscriptions = <StreamSubscription<ProcessSignal>>[];
    void onSignal(ProcessSignal signal) {
      runner.interrupt();
      final line =
          'CI RED: interrupted by $signal after '
          '${formatCiDuration(watch.elapsed)} — logs so far ${relative(runDir)}';
      _appendSummary(line);
      stdout.writeln('\n$line');
      exit(130);
    }

    subscriptions.add(ProcessSignal.sigint.watch().listen(onSignal));
    if (!Platform.isWindows) {
      subscriptions.add(ProcessSignal.sigterm.watch().listen(onSignal));
    }
    try {
      for (final stage in stages) {
        console.writeln('== :$stage — ${stageDescriptions[stage] ?? ''}');
        await runStage(this, stage);
      }
    } finally {
      // A cancel takes effect when called; nothing waits on its future.
      for (final s in subscriptions) {
        unawaited(s.cancel());
      }
      runner.lock.release();
    }
    final line = ciSummaryLine(
      stages: stages,
      outcomes: outcomes,
      elapsed: watch.elapsed,
      runDir: runDir,
      relativeTo: repositoryRoot,
    );
    _appendSummary(line);
    return line;
  }

  void _appendSummary(String line) {
    final file = File(p.join(runDir, 'summary.txt'));
    final body = StringBuffer();
    for (final o in outcomes) {
      final state = o.skipped
          ? 'skip '
          : o.ok
          ? 'green'
          : 'RED  ';
      body.writeln(
        '$state  ${o.label}  ${formatCiDuration(o.elapsed)}  ${o.detail}  '
        '${relative(o.logPath)}',
      );
    }
    body.writeln(line);
    file.writeAsStringSync(body.toString());
  }

  /// The command that runs `dart` or `flutter` — whichever [pkg] needs — with
  /// [args] in its directory.
  CiCommand tool(
    CiPackage pkg,
    List<String> args, {
    Map<String, String> env = const {},
  }) => CiCommand(
    pkg.isFlutter ? (flutter ?? 'flutter') : dart,
    args,
    workingDirectory: pkg.directory,
    environment: env,
  );

  /// Runs [commands] as one step into the log [logName], recording its
  /// outcome. [counts] reads the test counts of the last progress line into
  /// the detail; [produces] is a file the step must leave behind, so an exit
  /// code of 0 with nothing built is red.
  Future<void> step(
    String stage,
    String subject,
    String logName,
    List<CiCommand> commands, {
    bool needsFlutter = false,
    bool counts = false,
    String? produces,
  }) async {
    final logPath = p.join(runDir, logName);
    final label = subject == stage ? '[$stage]' : '[$stage] $subject';
    console.write('$label …');
    if (needsFlutter && flutter == null) {
      console.writeln();
      fail(
        stage,
        subject,
        logName,
        'flutter not found — put it on PATH or set FLUTTER_ROOT',
      );
      return;
    }
    final result = await runner.run(commands, logPath: logPath);
    var ok = result.ok;
    var detail = '';
    if (counts) {
      final c = parseCiTestCounts(result.tail);
      detail = c?.toString() ?? 'no test progress line';
    }
    if (ok && produces != null && !File(produces).existsSync()) {
      ok = false;
      detail = 'exit 0 but no ${relative(produces)}';
    }
    if (!ok && detail.isEmpty) detail = 'exit ${result.exitCode}';
    if (!ok && counts && result.exitCode != 0) {
      detail = '$detail, exit ${result.exitCode}';
    }
    _record(stage, subject, logPath, ok, detail, result.elapsed);
    console.writeln(
      ' ${ok ? 'green' : 'RED'} $detail '
      '(${formatCiDuration(result.elapsed)})'
      '${ok ? '' : ' -> ${relative(logPath)}'}',
    );
  }

  /// A step that is red without running anything; the reason is its log.
  void fail(String stage, String subject, String logName, String reason) {
    final logPath = p.join(runDir, logName);
    File(logPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('$reason\n');
    _record(stage, subject, logPath, false, reason);
    final label = subject == stage ? '[$stage]' : '[$stage] $subject';
    console.writeln('$label RED $reason -> ${relative(logPath)}');
  }

  /// A step deliberately not run; the reason is its log. Counted apart from
  /// green and red.
  void skip(String stage, String subject, String logName, String reason) {
    final logPath = p.join(runDir, logName);
    File(logPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('skipped: $reason\n');
    outcomes.add(
      CiOutcome(
        stage: stage,
        subject: subject,
        ok: true,
        logPath: logPath,
        detail: 'skipped — $reason',
        skipped: true,
      ),
    );
    final label = subject == stage ? '[$stage]' : '[$stage] $subject';
    console.writeln('$label skipped — $reason');
  }

  void _record(
    String stage,
    String subject,
    String log,
    bool ok,
    String detail, [
    Duration elapsed = Duration.zero,
  ]) {
    outcomes.add(
      CiOutcome(
        stage: stage,
        subject: subject,
        ok: ok,
        logPath: log,
        detail: detail,
        elapsed: elapsed,
      ),
    );
  }
}

/// `YYYYMMDD-HHMMSS`, the name of a run's log folder.
String ciTimestamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
}

/// The Dart running this tool when it is a `dart` VM (it is, under `dart run`),
/// else `dart` from PATH.
String ciDartExecutable() {
  final exe = Platform.resolvedExecutable;
  return p.basenameWithoutExtension(exe) == 'dart' ? exe : 'dart';
}

/// `FLUTTER_ROOT`'s flutter, else the SDK this Dart belongs to, else `PATH`,
/// else null.
String? ciFlutterExecutable({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final root = env['FLUTTER_ROOT'];
  if (root != null && File(p.join(root, 'bin', name)).existsSync()) {
    return p.join(root, 'bin', name);
  }
  // <flutter>/bin/cache/dart-sdk/bin/dart
  final dartBin = p.dirname(Platform.resolvedExecutable);
  final fromDart = p.normalize(p.join(dartBin, '..', '..', '..', name));
  if (File(fromDart).existsSync()) return fromDart;
  for (final dir in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (dir.isEmpty) continue;
    final candidate = p.join(dir, name);
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// The workspace flutter lock: [override] when set (`TOM_FLUTTER_LOCK`), else
/// `<workspace>/ztmp/flutter.lock`, else — a repository checked out on its
/// own — `<repository>/ztmp/flutter.lock`.
String ciFlutterLockPath({
  required String repositoryRoot,
  String? workspaceRoot,
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final override = env['TOM_FLUTTER_LOCK'];
  if (override != null && override.isNotEmpty) return override;
  return p.join(workspaceRoot ?? repositoryRoot, 'ztmp', 'flutter.lock');
}
