/// The `dart:io` half of the Node search: the machine as `llmDiscoverNode`
/// sees it.
///
/// Behind `package:tom_llm/io.dart`: the search itself is
/// platform-neutral and lives in the default entry point; the
/// `PATH` read, the `stat`s and the `--version` run are not, and a library
/// that imports `dart:io` does not link under dart2js at all.
library;

import 'dart:async';
import 'dart:io';

import 'node_discovery.dart';

/// The running process's own view of the machine: its `PATH`, its home
/// directory, its filesystem, and a `--version` run with no shell.
class LlmProcessNodeHost implements LlmNodeHost {
  /// How long one candidate is given to answer `--version` before it is
  /// recorded as not runnable. A real Node answers in milliseconds; a wrapper
  /// that waits on something is not a Node this search should pick.
  static const _versionTimeout = Duration(seconds: 10);

  const LlmProcessNodeHost();

  @override
  List<String> get pathEntries {
    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) return const [];
    return path.split(Platform.isWindows ? ';' : ':');
  }

  @override
  String? get homeDirectory =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

  @override
  bool get isWindows => Platform.isWindows;

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  List<String> directoryEntries(String directory) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return const [];
    try {
      return [
        for (final entity in dir.listSync(followLinks: true))
          entity.path.split(Platform.pathSeparator).last,
      ];
    } on FileSystemException {
      return const [];
    }
  }

  @override
  Future<String?> versionOf(String executable) async {
    final Process process;
    try {
      process = await Process.start(executable, const [
        '--version',
      ], runInShell: false);
    } on ProcessException {
      return null;
    }
    unawaited(process.stdin.close());
    final output = StringBuffer();
    final drained = Future.wait([
      process.stdout.forEach(
        (bytes) => output.write(String.fromCharCodes(bytes)),
      ),
      process.stderr.forEach(
        (bytes) => output.write(String.fromCharCodes(bytes)),
      ),
    ]);
    final int code;
    try {
      code = await process.exitCode.timeout(_versionTimeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return null;
    }
    await drained;
    if (code != 0) return null;
    final line = output
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .firstOrNull;
    return line;
  }
}

/// The resolver a desktop root hands its standalone transport: a search of
/// this machine, or the one executable `ai.nodePath` names.
///
/// A resolver rather than a resolution because the settings are read after
/// the transports are built, and because a search that found nothing has to
/// be able to run again after the user installs Node and presses Retry.
LlmNodeResolver llmNodeResolverFor({
  String? nodePath,
  LlmNodeHost host = const LlmProcessNodeHost(),
  int floor = llmRequiredNodeMajorVersion,
}) =>
    () => llmDiscoverNode(host: host, nodePath: nodePath, floor: floor);
