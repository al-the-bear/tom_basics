// BK-ISO: the integration suites work in a private copy of the workspace, so
// nothing they do can reach the live tree where other sessions are working.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'helpers/scratch_workspace.dart';
import 'helpers/test_workspace.dart';

List<String> _tracked(String root, bool Function(String) keep) {
  final r = Process.runSync('git', [
    'ls-files',
    '--recurse-submodules',
    '-z',
  ], workingDirectory: root);
  return (r.stdout as String)
      .split('\x00')
      .where((f) => f.isNotEmpty && keep(f))
      .toList()
    ..sort();
}

void main() {
  String? deletedLater;

  group('an isolated workspace', () {
    late TestWorkspace ws;

    setUpAll(() async {
      ws = await TestWorkspace.isolated();
      deletedLater = ws.workspaceRoot;
    });

    tearDownAll(() => ws.dispose());

    test('BK-ISO-1: is a scratch copy outside the live workspace and outside '
        'any git repository above it [2026-11-06]', () {
      expect(isScratchWorkspace(ws.workspaceRoot), isTrue);
      expect(ws.liveRoot, isNotNull);
      expect(p.isWithin(ws.liveRoot!, ws.workspaceRoot), isFalse);
      expect(ws.workspaceRoot, isNot(ws.liveRoot));
      // tom_build_base's findTopRepo takes the OUTERMOST repository above a
      // path: no ancestor of the copy may be one.
      var dir = p.dirname(ws.workspaceRoot);
      while (p.dirname(dir) != dir) {
        expect(
          FileSystemEntity.typeSync(p.join(dir, '.git')),
          FileSystemEntityType.notFound,
          reason: '$dir is a git repository above the copy',
        );
        dir = p.dirname(dir);
      }
    });

    test('BK-ISO-2: holds every project of the live workspace with its '
        'descriptor content [2026-11-06]', () {
      bool descriptor(String f) => descriptorFileNames.contains(p.basename(f));
      final live = _tracked(ws.liveRoot!, descriptor);
      expect(live.where((f) => f.endsWith('pubspec.yaml')), isNotEmpty);
      for (final rel in live) {
        final copy = File(p.join(ws.workspaceRoot, rel));
        expect(copy.existsSync(), isTrue, reason: '$rel missing in the copy');
        expect(
          copy.readAsStringSync(),
          File(p.join(ws.liveRoot!, rel)).readAsStringSync(),
          reason: '$rel differs from the live file',
        );
      }
      // Every directory of the live tree exists, and every bin/ file.
      for (final rel in _tracked(ws.liveRoot!, (_) => true)) {
        expect(
          Directory(p.join(ws.workspaceRoot, p.dirname(rel))).existsSync(),
          isTrue,
          reason: '${p.dirname(rel)} missing in the copy',
        );
        if (p.basename(p.dirname(rel)) == 'bin') {
          expect(File(p.join(ws.workspaceRoot, rel)).existsSync(), isTrue);
        }
      }
    });

    test('BK-ISO-3: is clean, with its buildkit snapshot excluded '
        '[2026-11-06]', () async {
      expect(await uncommittedChangesIn(ws.workspaceRoot), isEmpty);
    });

    test('BK-ISO-4: fixtures, skip files and reverts stay in the copy '
        '[2026-11-06]', () async {
      final liveMaster = File(p.join(ws.liveRoot!, 'buildkit_master.yaml'));
      final before = liveMaster.readAsStringSync();

      await ws.installFixture('versioner');
      final skip = ws.placeSkipFile('tom_ai/core');
      expect(p.isWithin(ws.workspaceRoot, skip), isTrue);
      expect(
        File(ws.masterConfigPath).readAsStringSync(),
        isNot(before),
        reason: 'the fixture master was installed in the copy',
      );
      expect(liveMaster.readAsStringSync(), before);
      expect(
        File(
          p.join(ws.liveRoot!, 'tom_ai', 'core', TestWorkspace.skipFileName),
        ).existsSync(),
        isFalse,
      );

      ws.removeSkipFile('tom_ai/core');
      await ws.revertAll();
      await ws.deprovisionBuildProject();
      expect(liveMaster.readAsStringSync(), before);
      expect(await uncommittedChangesIn(ws.workspaceRoot), isEmpty);
    });

    test('BK-ISO-5: refuses to run buildkit outside the copy [2026-11-06]', () {
      expect(
        () =>
            ws.runTool('versioner', ['--list'], workingDirectory: ws.liveRoot),
        throwsStateError,
      );
    });
  });

  test('BK-ISO-6: dispose() deletes the copy [2026-11-06]', () {
    expect(deletedLater, isNotNull);
    expect(Directory(deletedLater!).existsSync(), isFalse);
  });

  test('BK-ISO-8: every suite that makes a copy disposes of it last in '
      'tearDownAll [2026-11-06]', () {
    final offenders = <String>[];
    for (final file in Directory('test').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('_test.dart')) continue;
      final source = file.readAsStringSync();
      if (!source.contains('TestWorkspace.isolated()')) continue;
      final tearDown = RegExp(
        r'tearDownAll\(\(\) (?:async )?(?:=>|\{)[\s\S]*?ws\.dispose\(\)',
      );
      if (!tearDown.hasMatch(source)) offenders.add(file.path);
    }
    expect(
      offenders,
      isEmpty,
      reason: 'these suites never delete their scratch copy',
    );
  });

  group('a workspace that is not a scratch copy', () {
    late Directory other;
    late TestWorkspace ws;

    setUp(() async {
      other = Directory.systemTemp.createTempSync('bk_iso_other_');
      await Process.run('git', ['init', '-q'], workingDirectory: other.path);
      File(
        p.join(other.path, 'buildkit_master.yaml'),
      ).writeAsStringSync('navigation: {}\n');
      ws = TestWorkspace.forRoot(other.path);
    });

    tearDown(() => other.deleteSync(recursive: true));

    test('BK-ISO-7: refuses every change [2026-11-06]', () async {
      await expectLater(ws.installFixture('versioner'), throwsStateError);
      await expectLater(ws.revertAll(), throwsStateError);
      await expectLater(ws.provisionBuildProject(), throwsStateError);
      expect(() => ws.placeSkipFile('.'), throwsStateError);
      await expectLater(ws.runTool('versioner', ['--list']), throwsStateError);
      expect(
        () => deleteScratchWorkspace(other),
        throwsStateError,
        reason: 'only a scratch copy may be deleted',
      );
      expect(
        File(p.join(other.path, 'buildkit_master.yaml')).readAsStringSync(),
        'navigation: {}\n',
      );
    });
  });
}
