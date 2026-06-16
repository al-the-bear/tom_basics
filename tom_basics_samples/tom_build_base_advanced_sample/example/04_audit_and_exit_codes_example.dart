// Failure, skips, and the exit code — a command that can say "no".
//
// `:audit` returns ItemResult.failure for any project that is not
// release-ready. A single failure flips `result.success` to false, which is
// what a real `main` turns into a non-zero exit code — so `:audit` is usable as
// a CI gate. The fixture's `draft` package (no version, no description) fails
// the default audit; raising the bar with `--min-desc=20` additionally fails
// `data_layer`, whose description is only 5 characters. The framework collects
// every failure into the `=== Errors ===` summary block.
//
// Run with: dart run example/04_audit_and_exit_codes_example.dart
import 'package:tom_build_base_advanced_sample/relkit.dart';

import 'fixture.dart';

Future<void> main() async {
  final workspace = await createFixtureWorkspace();
  final base = [
    '-R', workspace.path,
    '--scan', workspace.path,
    '-r',
  ];
  try {
    // Default audit: only `draft` (no version, no description) fails.
    final audit = StringBuffer();
    final r1 = await relkitRunner(output: audit).run([':audit', ...base]);
    print('--- :audit ---');
    print(audit.toString().trimRight());
    print(r1.renderRunSummary().trimRight());
    print('exit ${r1.success ? 0 : 1}');

    // Stricter audit: data_layer's 5-char description now fails too.
    final strict = StringBuffer();
    final r2 = await relkitRunner(output: strict)
        .run([':audit', '--min-desc=20', ...base]);
    print('--- :audit --min-desc=20 ---');
    print(strict.toString().trimRight());
    print(r2.renderRunSummary().trimRight());
    print('exit ${r2.success ? 0 : 1}');
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // --- :audit ---
  // >>> app/tool
  //   -> :audit release-ready
  // >>> data
  //   -> :audit release-ready
  // >>> draft
  //   -> :audit ERROR: no version, no description
  // >>> service
  //   -> :audit release-ready
  // >>> app
  //   -> :audit release-ready
  // === Errors ===
  //   draft_pkg :audit — no version, no description
  // 1 error(s) in 1 project(s).
  // exit 1
  // --- :audit --min-desc=20 ---
  // >>> app/tool
  //   -> :audit release-ready
  // >>> data
  //   -> :audit ERROR: description too short (5 < 20)
  // >>> draft
  //   -> :audit ERROR: no version, no description
  // >>> service
  //   -> :audit release-ready
  // >>> app
  //   -> :audit release-ready
  // === Errors ===
  //   data_layer :audit — description too short (5 < 20)
  //   draft_pkg :audit — no version, no description
  // 2 error(s) in 2 project(s).
  // exit 1
}
