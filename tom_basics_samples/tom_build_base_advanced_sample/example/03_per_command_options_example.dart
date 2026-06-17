// Per-command options: flags and value options that belong to one command.
//
// Options written *after* a `:command` attach to that command, not globally.
// `:report --with-path` flips a flag the report command declared; `:bump
// --part=minor` passes a value option whose allowed values and default
// (`patch`) live in the bump command's definition. The framework parses both
// from the CommandDefinitions — the executors just read
// `args.commandArgs['<name>'].options`. `:bump` is a dry run: it computes the
// next version without touching any pubspec, and skips the version-less draft.
//
// Run with: dart run example/03_per_command_options_example.dart
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
    // A flag option on :report.
    final report = StringBuffer();
    await relkitRunner(output: report).run([':report', '--with-path', ...base]);
    print('--- :report --with-path ---');
    print(report.toString().trimRight());

    // A value option with allowed values + default on :bump.
    final bump = StringBuffer();
    await relkitRunner(output: bump).run([':bump', '--part=minor', ...base]);
    print('--- :bump --part=minor ---');
    print(bump.toString().trimRight());
  } finally {
    await disposeFixture(workspace);
  }

  // expected output:
  // --- :report --with-path ---
  // >>> app/tool
  //   -> :report app_tools v0.1.0 — 0 deps  [app/tool]
  // >>> data
  //   -> :report data_layer v1.0.0 — 0 deps  [data]
  // >>> draft
  //   -> :report draft_pkg (no version) — 0 deps  [draft]
  // >>> service
  //   -> :report service_layer v1.2.0 — 1 deps  [service]
  // >>> app
  //   -> :report app_runner v0.9.0 — 1 deps  [app]
  // --- :bump --part=minor ---
  // >>> app/tool
  //   -> :bump would bump 0.1.0 -> 0.2.0 (minor)
  // >>> data
  //   -> :bump would bump 1.0.0 -> 1.1.0 (minor)
  // >>> draft
  //   -> :bump no version to bump
  // >>> service
  //   -> :bump would bump 1.2.0 -> 1.3.0 (minor)
  // >>> app
  //   -> :bump would bump 0.9.0 -> 0.10.0 (minor)
}
