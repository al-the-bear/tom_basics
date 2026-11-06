// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// A private copy of the workspace for the integration suites.
///
/// WHY. The integration suites install fixture `buildkit_master.yaml` files at
/// the workspace root, provision a `_build` project there, place skip files in
/// real folders, and revert with `git checkout -- .` after every test. Run in
/// the live workspace, that overwrites the manifest every other buildkit run
/// reads and can discard another session's uncommitted edits; a clean check at
/// the start proves nothing about the minutes after it. Run in a copy, nothing
/// a test does can reach the live tree.
///
/// WHAT THE COPY HOLDS. The live workspace's tracked tree (`git ls-files
/// --recurse-submodules`) as buildkit sees it, at the same relative paths, so
/// project discovery, natures, skip files and path dependencies resolve the
/// same way. tom_build_base's nature detection reads descriptor files, the
/// existence of folders (`bin`, `lib/src`, `test`, platform folders) and the
/// file names in `bin/`; so the copy holds every descriptor
/// ([descriptorFileNames]) with its content, every `bin/` file and one file of
/// every other directory, those created EMPTY. That is about 9k files and a
/// few megabytes instead of 73k files and 2.5 GB. The copy is one git
/// repository with everything committed, so the suites' `git checkout -- .`
/// revert works on it unchanged; nested repositories are not reproduced (no
/// suite uses git-mode traversal). [scratchMarkerFileName] marks it, and
/// `TestWorkspace` refuses to change a root that does not carry it.
///
/// WHERE. In the system temp directory, NOT under the workspace's `ztmp/`:
/// tom_build_base's `findTopRepo` returns the OUTERMOST git repository above a
/// path, so a copy nested in the workspace would resolve to the live
/// superproject. Each test file (one isolate) gets its own copy, deleted when
/// the isolate's suite finishes.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// File names whose content buildkit reads to find and describe a project.
const descriptorFileNames = {
  '.gitignore',
  'pubspec.yaml',
  'pubspec_overrides.yaml',
  'analysis_options.yaml',
  'build.yaml',
  'buildkit.yaml',
  'buildkit_master.yaml',
  'buildkit_skip.yaml',
  'tom_skip.yaml',
  'tom_project.yaml',
  'tom_repository.yaml',
  'testkit_master.yaml',
  'package.json',
  'tsconfig.json',
};

/// Committed at the root of every copy; nothing else creates it.
const scratchMarkerFileName = '.tom_build_kit_scratch_workspace';

/// Whether [root] is a copy made by [createScratchWorkspace].
bool isScratchWorkspace(String root) =>
    File(p.join(root, scratchMarkerFileName)).existsSync();

/// Create a copy of the git workspace at [liveRoot] in a new temp directory
/// and return its root.
Future<Directory> createScratchWorkspace(String liveRoot) async {
  final listed = await Process.run('git', [
    'ls-files',
    '--recurse-submodules',
    '-z',
  ], workingDirectory: liveRoot);
  if (listed.exitCode != 0) {
    throw StateError('git ls-files failed in $liveRoot: ${listed.stderr}');
  }
  final root = Directory.systemTemp.createTempSync('tom_build_kit_it_');
  final createdDirs = <String>{};
  final representedDirs = <String>{};
  void write(String rel, {required bool withContent}) {
    final dest = p.join(root.path, rel);
    final parent = p.dirname(dest);
    if (createdDirs.add(parent)) Directory(parent).createSync(recursive: true);
    final source = File(p.join(liveRoot, rel));
    if (withContent && source.existsSync()) {
      source.copySync(dest);
    } else {
      File(dest).createSync();
    }
    representedDirs.add(p.dirname(rel));
  }

  final tracked = (listed.stdout as String)
      .split('\x00')
      .where((rel) => rel.isNotEmpty)
      .toList();
  final placeholders = <String, String>{};
  for (final rel in tracked) {
    final name = p.basename(rel);
    final dir = p.dirname(rel);
    if (descriptorFileNames.contains(name)) {
      write(rel, withContent: true);
    } else if (p.basename(dir) == 'bin') {
      write(rel, withContent: false);
    } else {
      placeholders.putIfAbsent(dir, () => rel);
    }
  }
  for (final entry in placeholders.entries) {
    if (!representedDirs.contains(entry.key)) {
      write(entry.value, withContent: false);
    }
  }
  File(p.join(root.path, scratchMarkerFileName)).writeAsStringSync(
    'Scratch copy of $liveRoot for the tom_build_kit integration suites '
    '(test/helpers/scratch_workspace.dart). Deleted when the suite ends.\n',
  );
  Future<void> git(List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: root.path);
    if (r.exitCode != 0) {
      throw StateError(
        'git ${args.join(' ')} failed in ${root.path}: '
        '${r.stderr}',
      );
    }
  }

  await git(['init', '-q', '-b', 'main']);
  await git(['config', 'user.email', 'tom_build_kit-tests@localhost']);
  await git(['config', 'user.name', 'tom_build_kit tests']);
  await git(['config', 'commit.gpgsign', 'false']);
  await git(['add', '-A']);
  await git(['commit', '-q', '-m', 'scratch copy of $liveRoot']);
  return root;
}

/// Delete a copy made by [createScratchWorkspace]; refuses any other path.
void deleteScratchWorkspace(Directory root) {
  if (!root.existsSync()) return;
  if (!isScratchWorkspace(root.path)) {
    throw StateError('Refusing to delete ${root.path}: not a scratch copy');
  }
  root.deleteSync(recursive: true);
}
