/// One child process, its whole output kept.
///
/// Two hazards decide the shape:
///
/// * **Nothing is buffered until exit.** A suite piped through `tail` showed
///   nothing for minutes and then lost everything but three lines when it
///   failed. Here each line is written to the log as it arrives, so the log
///   can be followed while it grows (`tail -f`) and survives a kill.
/// * **Every log is kept.** A red that a rerun did not reproduce was lost three
///   times because no run kept its output. The log *is* the finding; the
///   summary names it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ci_lock.dart';

/// What a test run reported in its last progress line: `+passed ~skipped
/// -failed`.
class CiTestCounts {
  const CiTestCounts(this.passed, this.skipped, this.failed);

  final int passed;
  final int skipped;
  final int failed;

  @override
  String toString() =>
      '+$passed${skipped > 0 ? ' ~$skipped' : ''}${failed > 0 ? ' -$failed' : ''}';
}

final _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
final _progress = RegExp(r'\d\d:\d\d \+(\d+)(?: ~(\d+))?(?: -(\d+))?:');

/// The counts of the last `dart test` / `flutter test` progress line among
/// [lines], or null when there is none (the run died before testing).
CiTestCounts? parseCiTestCounts(Iterable<String> lines) {
  CiTestCounts? last;
  for (final raw in lines) {
    // A compact reporter rewrites one line with carriage returns; the last
    // segment is the current state.
    for (final segment in raw.replaceAll(_ansi, '').split('\r')) {
      final m = _progress.firstMatch(segment);
      if (m == null) continue;
      last = CiTestCounts(
        int.parse(m.group(1)!),
        int.parse(m.group(2) ?? '0'),
        int.parse(m.group(3) ?? '0'),
      );
    }
  }
  return last;
}

/// One command to run.
class CiCommand {
  const CiCommand(
    this.executable,
    this.arguments, {
    required this.workingDirectory,
    this.environment = const {},
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  /// Added to the inherited environment.
  final Map<String, String> environment;

  @override
  String toString() => [executable, ...arguments].join(' ');
}

/// How a run of one or more commands into one log ended.
class CiStepResult {
  const CiStepResult({
    required this.exitCode,
    required this.logPath,
    required this.elapsed,
    required this.tail,
  });

  /// The first non-zero exit code, or 0.
  final int exitCode;
  final String logPath;
  final Duration elapsed;

  /// The last lines written, for counts and a one-line reason.
  final List<String> tail;

  bool get ok => exitCode == 0;
}

/// Runs commands one at a time under the workspace lock, each line of their
/// output to a log file as it arrives.
class CiProcessRunner {
  CiProcessRunner({required this.lock, this.pathPrefix, this.onLockWait});

  final CiLock lock;

  /// A directory put first on every child's `PATH` — the Flutter SDK's `bin`,
  /// so a tool the child itself spawns (`package_app.dart` runs `flutter`)
  /// finds the same SDK this run uses.
  final String? pathPrefix;

  /// Told when the lock is held by somebody else, and how long we have waited.
  final void Function(Duration waited)? onLockWait;

  Process? _current;

  /// Kills the running child, if any, and releases the lock. For Ctrl-C.
  void interrupt() {
    _current?.kill();
    lock.release();
  }

  /// Runs [commands] in order into the log at [logPath] (created, or appended
  /// to when [append]), stopping at the first that fails.
  Future<CiStepResult> run(
    List<CiCommand> commands, {
    required String logPath,
    bool append = false,
  }) async {
    final watch = Stopwatch()..start();
    final logFile = File(logPath)..parent.createSync(recursive: true);
    final log = logFile.openSync(
      mode: append ? FileMode.append : FileMode.write,
    );
    final tail = <String>[];
    void write(String line) {
      log.writeStringSync('$line\n');
      log.flushSync();
      tail.add(line);
      if (tail.length > 40) tail.removeAt(0);
    }

    var exit = 0;
    try {
      for (final command in commands) {
        write('\$ $command');
        write(
          '  (in ${command.workingDirectory}, ${DateTime.now().toIso8601String()})',
        );
        await lock.acquire(onWait: onLockWait);
        try {
          exit = await _runOne(command, write);
        } finally {
          lock.release();
        }
        write('[exit $exit]');
        if (exit != 0) break;
      }
    } on ProcessException catch (e) {
      write('could not start: ${e.message} (${e.executable})');
      exit = 127;
    } finally {
      log.closeSync();
    }
    return CiStepResult(
      exitCode: exit,
      logPath: logPath,
      elapsed: watch.elapsed,
      tail: tail,
    );
  }

  Future<int> _runOne(CiCommand command, void Function(String) write) async {
    final env = <String, String>{...command.environment};
    if (pathPrefix != null) {
      final current = Platform.environment['PATH'] ?? '';
      env['PATH'] = '$pathPrefix${Platform.isWindows ? ';' : ':'}$current';
    }
    final process = await Process.start(
      command.executable,
      command.arguments,
      workingDirectory: command.workingDirectory,
      environment: env,
      // `flutter` on Windows is `flutter.bat`, which only a shell starts.
      runInShell: Platform.isWindows,
    );
    _current = process;
    await process.stdin.close();
    Stream<String> lines(Stream<List<int>> s) => s
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
    final done = Future.wait([
      lines(process.stdout).forEach(write),
      lines(process.stderr).forEach(write),
    ]);
    final code = await process.exitCode;
    // A grandchild that inherited the pipes (a daemon, a browser) can hold
    // them open after the child exits; the exit code is the answer, so the
    // drain gets a bounded wait rather than an unbounded one.
    await done.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        write('[output still open 30 s after exit; stopped reading]');
        return const [];
      },
    );
    _current = null;
    return code;
  }
}
