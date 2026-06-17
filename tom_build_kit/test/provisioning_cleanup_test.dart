import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/test_workspace.dart';

/// Regression coverage for the `_build` provisioning lifecycle (cli_tools
/// quest, tool_run_analysis_todos.md #20).
///
/// The buildkit integration suite copies a `_build` project to the workspace
/// root for each test and removes it afterwards. Two invariants must hold so
/// the workspace tree stays clean across a run:
///
/// 1. The provisioned `<workspaceRoot>/_build` is gitignored, so provisioning
///    never produces `git status` churn (this is what eliminated the historic
///    `D _build/...` deletions — see §d.6 of the tool-run analysis).
/// 2. [TestWorkspace.deprovisionBuildProject] removes the provisioned copy, so
///    nothing lingers on disk after the suite finishes.
///
/// These tests deliberately do NOT call [TestWorkspace.requireCleanWorkspace];
/// they only touch the gitignored `_build` path, so they stay runnable even
/// when the outer repo carries an unrelated dirty gitlink (e.g. ` M tom_ai`).
void main() {
  late TestWorkspace ws;

  setUp(() {
    ws = TestWorkspace();
  });

  tearDown(() async {
    // Always leave the tree clean, even if an expectation failed mid-test.
    await ws.deprovisionBuildProject();
  });

  String provisionedBuildDir() => p.join(ws.workspaceRoot, '_build');

  Future<ProcessResult> gitCheckIgnore(String relativePath) {
    return Process.run(
      'git',
      ['check-ignore', relativePath],
      workingDirectory: ws.workspaceRoot,
    );
  }

  test('PROV_CLN01: provisioned _build is gitignored (no git-status churn)',
      () async {
    await ws.provisionBuildProject();
    expect(Directory(provisionedBuildDir()).existsSync(), isTrue,
        reason: 'provisionBuildProject should create <root>/_build');

    // git check-ignore exits 0 when the path is ignored.
    final ignored = await gitCheckIgnore('_build');
    expect(ignored.exitCode, 0,
        reason: 'The provisioned _build must be gitignored so it never shows '
            'up as workspace churn. Did /_build/ get dropped from .gitignore?');

    // And it must not appear in the integration suite's dirty-file scan.
    final dirty = await ws.hasUncommittedChanges();
    final buildEntries =
        dirty.where((line) => line.contains('_build')).toList();
    expect(buildEntries, isEmpty,
        reason: 'A provisioned _build must not surface in '
            'hasUncommittedChanges(); found: $buildEntries');
  });

  test('PROV_CLN02: deprovisionBuildProject removes the provisioned copy',
      () async {
    await ws.provisionBuildProject();
    expect(Directory(provisionedBuildDir()).existsSync(), isTrue);

    await ws.deprovisionBuildProject();
    expect(Directory(provisionedBuildDir()).existsSync(), isFalse,
        reason: 'deprovisionBuildProject must leave no _build directory behind');
  });

  test('PROV_CLN03: provision/deprovision cycle leaves no _build churn',
      () async {
    await ws.provisionBuildProject();
    await ws.deprovisionBuildProject();

    final dirty = await ws.hasUncommittedChanges();
    final buildEntries =
        dirty.where((line) => line.contains('_build')).toList();
    expect(buildEntries, isEmpty,
        reason: 'After a full provision/deprovision cycle no _build entry may '
            'remain in git status; found: $buildEntries');
  });
}
