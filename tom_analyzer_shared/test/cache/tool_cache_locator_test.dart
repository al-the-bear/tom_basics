import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  group('ToolCacheLocator.resolve', () {
    test('branch 1: honours TOM_BUILD_CACHE env override verbatim', () {
      final override = Directory.systemTemp.createTempSync('tcl_env_');
      addTearDown(() => override.deleteSync(recursive: true));

      final resolved = ToolCacheLocator.resolve(
        startDirectory: '/some/unrelated/start',
        environment: {ToolCacheLocator.envVariable: override.path},
        dartToolDirectory: '/should/not/be/used',
      );

      expect(resolved, equals(p.normalize(p.absolute(override.path))));
    });

    test('branch 1: trims and normalises the env override', () {
      final resolved = ToolCacheLocator.resolve(
        startDirectory: '/start',
        environment: {ToolCacheLocator.envVariable: '  /a/b/../c  '},
        dartToolDirectory: '/fallback',
      );

      expect(resolved, equals(p.normalize(p.absolute('/a/c'))));
    });

    test('branch 1: blank env override is ignored', () {
      final resolved = ToolCacheLocator.resolve(
        startDirectory: '/start',
        environment: {ToolCacheLocator.envVariable: '   '},
        dartToolDirectory: '/fallback',
      );

      expect(resolved, equals(p.join('/fallback', ToolCacheLocator.cacheDirName)));
    });

    test('branch 2: discovers .tom/tom_tool_cache in an ancestor', () {
      final root = Directory.systemTemp.createTempSync('tcl_ancestor_');
      addTearDown(() => root.deleteSync(recursive: true));

      final cacheDir = Directory(
        p.join(root.path, '.tom', ToolCacheLocator.cacheDirName),
      )..createSync(recursive: true);

      final deepStart = Directory(p.join(root.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);

      final resolved = ToolCacheLocator.resolve(
        startDirectory: deepStart.path,
        environment: const {},
        dartToolDirectory: '/should/not/be/used',
      );

      expect(resolved, equals(cacheDir.path));
    });

    test('branch 3: falls back to <dartToolDirectory>/tom_tool_cache', () {
      final start = Directory.systemTemp.createTempSync('tcl_fallback_');
      addTearDown(() => start.deleteSync(recursive: true));

      final resolved = ToolCacheLocator.resolve(
        startDirectory: start.path,
        environment: const {},
        dartToolDirectory: '/opt/dart-tool',
      );

      expect(
        resolved,
        equals(p.join('/opt/dart-tool', ToolCacheLocator.cacheDirName)),
      );
    });

    test('resolve never creates the cache directory', () {
      final start = Directory.systemTemp.createTempSync('tcl_nocreate_');
      addTearDown(() => start.deleteSync(recursive: true));
      final toolDir = p.join(start.path, 'dart-tool');

      final resolved = ToolCacheLocator.resolve(
        startDirectory: start.path,
        environment: const {},
        dartToolDirectory: toolDir,
      );

      expect(Directory(resolved).existsSync(), isFalse);
    });
  });

  group('ToolCacheLocator.defaultDartToolDirectory', () {
    test('Linux uses XDG_CONFIG_HOME when set', () {
      // Only assert the XDG branch on non-Windows/non-macOS hosts where it is
      // reachable; on other platforms the platform branch wins.
      if (Platform.isWindows || Platform.isMacOS) return;
      final dir = ToolCacheLocator.defaultDartToolDirectory(
        {'XDG_CONFIG_HOME': '/xdg/config'},
      );
      expect(dir, equals(p.join('/xdg/config', 'dart')));
    });

    test('Linux falls back to ~/.config/dart from HOME', () {
      if (Platform.isWindows || Platform.isMacOS) return;
      final dir = ToolCacheLocator.defaultDartToolDirectory({'HOME': '/home/u'});
      expect(dir, equals(p.join('/home/u', '.config', 'dart')));
    });
  });
}
