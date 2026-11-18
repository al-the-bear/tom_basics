import 'dart:io';

import 'package:path/path.dart' as p;

/// A fixture tool compiled once with `dart compile exe`, for the tests that
/// run a tool as a process.
///
/// Why: `dart run <script>` compiles the script on every call, which takes
/// seconds on an idle machine and minutes on a loaded one, so the tests timed
/// out without anything being wrong. A compiled tool starts in milliseconds,
/// and running it also checks that the AOT build of the tool works, as the
/// shipped binaries are AOT builds.
class CompiledTool {
  CompiledTool._(this.path, this._dir);

  /// The executable.
  final String path;
  final Directory _dir;

  /// Compiles [script] (relative to the package root, the tests' working
  /// directory) into a temporary folder as [name] (default: the script's
  /// name). Call it in `setUpAll` and [delete] in `tearDownAll`.
  static Future<CompiledTool> compile(String script, {String? name}) async {
    final dir = Directory.systemTemp.createTempSync('bb_compiled_tool_');
    final exe = p.join(
      dir.path,
      (name ?? p.basenameWithoutExtension(script)) +
          (Platform.isWindows ? '.exe' : ''),
    );
    final result = await Process.run('dart', [
      'compile',
      'exe',
      '--verbosity=error',
      '-o',
      exe,
      script,
    ]);
    if (result.exitCode != 0) {
      dir.deleteSync(recursive: true);
      throw StateError(
        'dart compile exe $script failed (${result.exitCode}):\n'
        '${result.stdout}${result.stderr}',
      );
    }
    return CompiledTool._(exe, dir);
  }

  /// Removes the compiled tool and its folder.
  void delete() {
    if (_dir.existsSync()) _dir.deleteSync(recursive: true);
  }
}
