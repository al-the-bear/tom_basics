import 'dart:io';

/// Platform-aware binary resolution and checking utilities.
///
/// All binary names in both code-level `defaultIncludes` and YAML
/// `nested_tools` are stored without platform extensions. The `.exe`
/// suffix is appended automatically on Windows at every resolution point.

/// Resolve a platform-specific binary name.
///
/// On Windows, appends `.exe` to the binary name.
/// On macOS/Linux, returns the name unchanged.
///
/// ```dart
/// resolveBinary('testkit');  // 'testkit' on macOS, 'testkit.exe' on Windows
/// ```
String resolveBinary(String binary) =>
    Platform.isWindows ? '$binary.exe' : binary;

/// Check if a binary is available on the system PATH.
///
/// Uses `which` on macOS/Linux and `where` on Windows to check
/// binary availability.
///
/// ```dart
/// if (isBinaryOnPath('testkit')) {
///   // Safe to call testkit
/// }
/// ```
bool isBinaryOnPath(String binary) {
  try {
    final cmd = Platform.isWindows ? 'where' : 'which';
    final result = Process.runSync(cmd, [binary]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// How to start the running program again, with arguments of its own: a
/// compiled binary is its [resolvedExecutable]; under the Dart VM (`dart
/// run`, `dart bin/x.dart`) or the AOT runtime it is that executable with
/// its [executableArguments] and the [script]. Null when the script is no
/// file (the caller then falls back to the tool's name on the PATH).
///
/// The defaults are this process's [Platform.resolvedExecutable],
/// [Platform.script] and [Platform.executableArguments]; tests hand others.
({String executable, List<String> leading})? selfInvocation({
  String? resolvedExecutable,
  Uri? script,
  List<String>? executableArguments,
}) {
  final executable = resolvedExecutable ?? Platform.resolvedExecutable;
  final name = executable
      .split(RegExp(r'[/\\]'))
      .last
      .toLowerCase()
      .replaceFirst(RegExp(r'\.exe$'), '');
  if (!const {'dart', 'dartvm', 'dartaotruntime'}.contains(name)) {
    return (executable: executable, leading: const []);
  }
  final uri = script ?? Platform.script;
  if (uri.scheme != 'file') return null;
  return (
    executable: executable,
    leading: [
      ...(executableArguments ?? Platform.executableArguments),
      uri.toFilePath(),
    ],
  );
}

/// Runs this program again with [args] in [workingDirectory]
/// ([selfInvocation]): the same binary or script, so a run it hands on
/// (a sub-workspace of `-w`, a delegated pipeline) has the same version and
/// needs nothing on the PATH. Falls back to [binary] on the PATH
/// ([runBinary]) when the program cannot name itself.
Future<ProcessResult> runSelf(
  String binary,
  List<String> args,
  String workingDirectory,
) {
  final self = selfInvocation();
  if (self == null) return runBinary(binary, args, workingDirectory);
  return Process.run(self.executable, [
    ...self.leading,
    ...args,
  ], workingDirectory: workingDirectory);
}

/// Run a binary with the given arguments in a working directory.
///
/// Returns an [ItemResult]-compatible result via the callback parameters.
/// The binary name is resolved to its platform-specific form before
/// execution.
///
/// On Windows, runs in a shell to support `.exe` resolution from PATH.
///
/// ```dart
/// final result = await runBinary('testkit', ['--dump-definitions'], '.');
/// if (result.exitCode == 0) {
///   print(result.stdout);
/// }
/// ```
Future<ProcessResult> runBinary(
  String binary,
  List<String> args,
  String workingDirectory,
) async {
  final resolved = resolveBinary(binary);
  return Process.run(
    resolved,
    args,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
}

/// Run a binary with streaming output directly to stdout/stderr.
///
/// Uses [ProcessStartMode.inheritStdio] to connect the child process's
/// stdin/stdout/stderr directly to the parent's, ensuring output appears
/// immediately without buffering.
///
/// Returns the exit code.
///
/// ```dart
/// final exitCode = await runBinaryStreaming('buildkit', [':pubupdate'], '.');
/// ```
Future<int> runBinaryStreaming(
  String binary,
  List<String> args,
  String workingDirectory,
) async {
  final resolved = resolveBinary(binary);
  final process = await Process.start(
    resolved,
    args,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}
