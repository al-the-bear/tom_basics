import 'dart:io';

/// Kills the process [pid] and every process it started, children before
/// parents, with SIGKILL (`taskkill /T /F` on Windows).
///
/// Killing only the parent leaves what it spawned running: `dart test` starts
/// test VMs of its own, and a hung one keeps its database connection or port.
/// The descendants are found with `pgrep -P` (macOS and Linux) before any is
/// killed, so a child that the parent's death would orphan is still reached.
/// A process that is already gone is not an error.
Future<void> killProcessTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/T', '/F', '/PID', '$pid']);
    return;
  }
  final all = <int>[];
  Future<void> collect(int parent) async {
    final result = await Process.run('pgrep', ['-P', '$parent']);
    for (final line in '${result.stdout}'.split('\n')) {
      final child = int.tryParse(line.trim());
      if (child == null) continue;
      await collect(child);
      all.add(child);
    }
  }

  await collect(pid);
  for (final p in [...all, pid]) {
    Process.killPid(p, ProcessSignal.sigkill);
  }
}
