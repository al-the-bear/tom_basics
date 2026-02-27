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
