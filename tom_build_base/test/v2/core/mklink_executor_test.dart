import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('MkLinkExecutor', () {
    late Directory tempDir;
    late MkLinkExecutor executor;
    late bool canCreateSymlink;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('mklink_executor_test_');
      executor = MkLinkExecutor();
      canCreateSymlink = _probeSymlinkSupport(tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('creates symbolic link with target and link positional args', () async {
      final target = File('${tempDir.path}/target.txt')..writeAsStringSync('x');
      final linkPath = '${tempDir.path}/alias.txt';

      final result = await executor.executeWithoutTraversal(
        CliArgs(positionalArgs: [target.path, linkPath]),
      );

      if (!canCreateSymlink) {
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Failed to create symbolic link'));
        return;
      }

      expect(result.success, isTrue);
      final link = Link(linkPath);
      expect(link.existsSync(), isTrue);
      expect(link.targetSync(), equals(target.path));
    });

    test('replaces existing destination when --force is set', () async {
      final target = File('${tempDir.path}/target.txt')..writeAsStringSync('x');
      final linkPath = '${tempDir.path}/alias.txt';
      File(linkPath).writeAsStringSync('old-content');

      final result = await executor.executeWithoutTraversal(
        CliArgs(positionalArgs: [target.path, linkPath], force: true),
      );

      if (!canCreateSymlink) {
        expect(result.success, isFalse);
        expect(result.errorMessage, contains('Failed to create symbolic link'));
        return;
      }

      expect(result.success, isTrue);
      final link = Link(linkPath);
      expect(link.existsSync(), isTrue);
      expect(link.targetSync(), equals(target.path));
    });

    test('fails when destination exists and --force is not set', () async {
      final target = File('${tempDir.path}/target.txt')..writeAsStringSync('x');
      final linkPath = '${tempDir.path}/alias.txt';
      File(linkPath).writeAsStringSync('old-content');

      final result = await executor.executeWithoutTraversal(
        CliArgs(positionalArgs: [target.path, linkPath]),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Destination already exists'));
    });
  });
}

bool _probeSymlinkSupport(String rootPath) {
  final target = File('$rootPath/probe_target.txt')..writeAsStringSync('x');
  final link = Link('$rootPath/probe_link.txt');

  try {
    link.createSync(target.path);
    return link.existsSync();
  } catch (_) {
    return false;
  } finally {
    if (link.existsSync()) {
      link.deleteSync();
    }
    if (target.existsSync()) {
      target.deleteSync();
    }
  }
}
