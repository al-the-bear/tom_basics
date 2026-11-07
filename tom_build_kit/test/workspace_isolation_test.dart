// BK-ISO: the integration suites work in the machine's workspace clone
// (tom_test_support TomWorkspaceClone), so nothing they do can reach the live
// tree where other sessions are working. The clone itself — created on first
// use, updated, reset — is tested in tom_test_support (WC-1..13); this file
// holds what TestWorkspace adds on top.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/workspace_clone.dart';

import 'helpers/test_workspace.dart';

void main() {
  group('an isolated workspace', () {
    late TestWorkspace ws;

    setUpAll(() async {
      ws = await TestWorkspace.isolated();
    });

    tearDownAll(() => ws.dispose());

    test('BK-ISO-1: is the workspace clone, outside the live workspace '
        '[2026-11-07]', () {
      expect(tomIsWorkspaceClone(Directory(ws.workspaceRoot)), isTrue);
      expect(ws.liveRoot, isNotNull);
      expect(ws.workspaceRoot, isNot(ws.liveRoot));
      expect(p.isWithin(ws.liveRoot!, ws.workspaceRoot), isFalse);
      expect(p.isWithin(ws.workspaceRoot, ws.liveRoot!), isFalse);
      expect(
        p.isWithin(ws.workspaceRoot, ws.buildkitRoot),
        isFalse,
        reason: 'the package under test runs from the live tree',
      );
    });

    test('BK-ISO-2: fixtures, skip files and reverts stay in the clone '
        '[2026-11-07]', () async {
      final liveMaster = File(p.join(ws.liveRoot!, 'buildkit_master.yaml'));
      final before = liveMaster.readAsStringSync();

      await ws.installFixture('versioner');
      final skip = ws.placeSkipFile('tom_ai/core');
      expect(p.isWithin(ws.workspaceRoot, skip), isTrue);
      expect(
        File(ws.masterConfigPath).readAsStringSync(),
        isNot(before),
        reason: 'the fixture master was installed in the clone',
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

    test(
      'BK-ISO-3: refuses to run buildkit outside the clone [2026-11-07]',
      () {
        expect(
          () => ws.runTool('versioner', [
            '--list',
          ], workingDirectory: ws.liveRoot),
          throwsStateError,
        );
      },
    );
  });

  group('a workspace that is not a clone', () {
    late Directory other;
    late TestWorkspace ws;

    setUp(() async {
      final base = Directory(p.join(Directory.current.path, '.dart_tool'))
        ..createSync();
      other = base.createTempSync('bk_iso_other_');
      await Process.run('git', ['init', '-q'], workingDirectory: other.path);
      File(
        p.join(other.path, 'buildkit_master.yaml'),
      ).writeAsStringSync('navigation: {}\n');
      ws = TestWorkspace.forRoot(other.path);
    });

    tearDown(() => other.deleteSync(recursive: true));

    test('BK-ISO-4: refuses every change [2026-11-07]', () async {
      await expectLater(ws.installFixture('versioner'), throwsStateError);
      await expectLater(ws.revertAll(), throwsStateError);
      await expectLater(ws.provisionBuildProject(), throwsStateError);
      expect(() => ws.placeSkipFile('.'), throwsStateError);
      await expectLater(ws.runTool('versioner', ['--list']), throwsStateError);
      await expectLater(ws.dispose(), throwsStateError);
      expect(
        File(p.join(other.path, 'buildkit_master.yaml')).readAsStringSync(),
        'navigation: {}\n',
      );
    });
  });

  test('BK-ISO-5: every suite that holds the clone gives it back last in '
      'tearDownAll [2026-11-07]', () {
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
      reason: 'these suites never give the clone back',
    );
  });
}
