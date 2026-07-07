import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  group('ToolCacheLocator.resolve', () {
    test('branch 1: honours TOM_TOOL_CACHE env override verbatim', () {
      final override = Directory.systemTemp.createTempSync('tcl_env_');
      addTearDown(() => override.deleteSync(recursive: true));

      final resolved = ToolCacheLocator.resolve(
        startDirectory: '/some/unrelated/start',
        environment: {ToolCacheLocator.envVariable: override.path},
      );

      expect(resolved, equals(p.normalize(p.absolute(override.path))));
    });

    test('branch 1: trims and normalises the env override', () {
      final resolved = ToolCacheLocator.resolve(
        startDirectory: '/start',
        environment: {ToolCacheLocator.envVariable: '  /a/b/../c  '},
      );

      expect(resolved, equals(p.normalize(p.absolute('/a/c'))));
    });

    test('branch 1: blank env override falls through to the workspace cache', () {
      // With a blank override and no workspace root, resolution uses the
      // workspace-local fallback `<start>/.tom` — never a machine-global dir.
      final start = Directory.systemTemp.createTempSync('tcl_blank_');
      addTearDown(() => start.deleteSync(recursive: true));

      final resolved = ToolCacheLocator.resolve(
        startDirectory: start.path,
        environment: {ToolCacheLocator.envVariable: '   '},
      );

      expect(
        resolved,
        equals(p.join(
          p.normalize(p.absolute(start.path)),
          ToolCacheLocator.workspaceCacheDirName,
        )),
      );
    });

    test('branch 2: resolves the workspace-root .tom via tom_workspace.yaml', () {
      final root = Directory.systemTemp.createTempSync('tcl_ws_');
      addTearDown(() => root.deleteSync(recursive: true));

      File(p.join(root.path, 'tom_workspace.yaml')).writeAsStringSync('name: ws');

      final deepStart = Directory(p.join(root.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);

      final resolved = ToolCacheLocator.resolve(
        startDirectory: deepStart.path,
        environment: const {},
      );

      // The cache root is the workspace root's `.tom`, so SummaryCacheManager
      // writes summaries to `<workspace>/.tom/analyzer-cache/<major>/`.
      expect(
        resolved,
        equals(p.join(
          p.normalize(p.absolute(root.path)),
          ToolCacheLocator.workspaceCacheDirName,
        )),
      );
    });

    test('branch 2: also recognises .tom_metadata/tom_master.yaml', () {
      final root = Directory.systemTemp.createTempSync('tcl_meta_');
      addTearDown(() => root.deleteSync(recursive: true));

      File(p.join(root.path, '.tom_metadata', 'tom_master.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('projects: []');

      final deepStart = Directory(p.join(root.path, 'x', 'y'))
        ..createSync(recursive: true);

      final resolved = ToolCacheLocator.resolve(
        startDirectory: deepStart.path,
        environment: const {},
      );

      expect(
        resolved,
        equals(p.join(
          p.normalize(p.absolute(root.path)),
          ToolCacheLocator.workspaceCacheDirName,
        )),
      );
    });

    test('branch 2: a nested project .tom does NOT shadow the workspace root',
        () {
      // A nested project that has its own `.tom` (but no workspace marker) must
      // not capture the cache — resolution keeps walking up to the workspace.
      final root = Directory.systemTemp.createTempSync('tcl_nested_');
      addTearDown(() => root.deleteSync(recursive: true));

      File(p.join(root.path, 'tom_workspace.yaml')).writeAsStringSync('name: ws');

      final nested = Directory(p.join(root.path, 'proj'))..createSync();
      Directory(p.join(nested.path, ToolCacheLocator.workspaceCacheDirName))
          .createSync(); // nested project-level .tom, no marker

      final resolved = ToolCacheLocator.resolve(
        startDirectory: nested.path,
        environment: const {},
      );

      expect(
        resolved,
        equals(p.join(
          p.normalize(p.absolute(root.path)),
          ToolCacheLocator.workspaceCacheDirName,
        )),
      );
    });

    test(
        'branch 3: falls back to <start>/.tom, never a machine-global directory',
        () {
      final start = Directory.systemTemp.createTempSync('tcl_fallback_');
      addTearDown(() => start.deleteSync(recursive: true));

      final resolved = ToolCacheLocator.resolve(
        startDirectory: start.path,
        environment: const {},
      );

      expect(
        resolved,
        equals(p.join(
          p.normalize(p.absolute(start.path)),
          ToolCacheLocator.workspaceCacheDirName,
        )),
      );
      // Guard: the resolved path is inside the workspace, not under a global
      // Dart tool / config directory.
      expect(resolved, isNot(contains('.config')));
      expect(resolved, isNot(contains('Application Support')));
    });

    test('resolve never creates the cache directory', () {
      final start = Directory.systemTemp.createTempSync('tcl_nocreate_');
      addTearDown(() => start.deleteSync(recursive: true));

      final resolved = ToolCacheLocator.resolve(
        startDirectory: start.path,
        environment: const {},
      );

      expect(Directory(resolved).existsSync(), isFalse);
    });
  });
}
