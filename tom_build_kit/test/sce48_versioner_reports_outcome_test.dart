/// sce48: `:versioner` reports what it DID, not what it intended.
///
/// The installed buildkit binary printed
///
///     Version file generated: tom_d4rt_generator v1.37.0 build 20
///     Status: SUCCESS
///
/// over a `version.versioner.dart` that still read `0.0.1-STALE`. It advanced
/// `tom_build_state.json` and wrote nothing else. The consequence is worse
/// than a stale tool: `version_stamp_test.dart` fails with the remedy
/// "run `buildkit -v -p . :versioner`" — pointing the reader at the command
/// that silently does nothing, so following the instruction loops.
///
/// That message exists nowhere in current source — the binary was seven months
/// old and ran a code path since removed — so a rebuild is the repair. These
/// tests cover the CLASS of defect instead, which is what the todo's recorded
/// decision (B) asked for: a run must not be able to report success for a file
/// it did not write.
///
/// Two live paths were found and both are pinned here:
///
///   * a DRY RUN returned `true`, so the caller reported "version file
///     generated" having written nothing;
///   * a real run reported success on the strength of the write not throwing,
///     never reading back what landed on disk.
///
/// These tests do NOT use TestWorkspace — they drive the executor over a
/// throwaway project, so they run regardless of workspace cleanliness.
///
/// Test IDs: SCE48-1 – SCE48-4
@TestOn('!browser')
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/executors/versioner_executor.dart';

/// A minimal project with a `versioner:` block, which is what makes the
/// executor act rather than skip.
Directory writeProject({String version = '2.5.0'}) {
  final dir = Directory.systemTemp.createTempSync('sce48_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync(
    'name: zom_sce48\n'
    'version: $version\n'
    'environment:\n'
    "  sdk: '>=3.0.0 <4.0.0'\n",
  );
  File(p.join(dir.path, 'buildkit.yaml')).writeAsStringSync(
    'versioner:\n'
    '  variable-prefix: zomSce48\n',
  );
  return dir;
}

String stampPath(Directory project) =>
    p.join(project.path, 'lib', 'src', 'version.versioner.dart');

Future<ItemResult> runVersioner(Directory project, {bool dryRun = false}) =>
    VersionerExecutor().execute(
      CommandContext(
        fsFolder: FsFolder(path: project.path),
        natures: const [],
        executionRoot: project.path,
      ),
      CliArgs(dryRun: dryRun),
    );

void main() {
  late Directory project;

  setUp(() => project = writeProject());

  tearDown(() {
    try {
      project.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SCE48: the versioner reports its outcome', () {
    test('SCE48-1: a real run writes the stamp and says so', () async {
      final result = await runVersioner(project);

      expect(result.success, isTrue, reason: result.error ?? '');
      expect(result.message, 'version file generated');
      final stamp = File(stampPath(project));
      expect(
        stamp.existsSync(),
        isTrue,
        reason: 'success must mean the file is there',
      );
      expect(stamp.readAsStringSync(), contains("version = '2.5.0'"));
    });

    test(
      'SCE48-2: a DRY RUN writes nothing and does not claim it did',
      () async {
        // The defect this file is named for, one step smaller. Before sce48 the
        // dry-run path returned `true` and the caller reported "version file
        // generated" — a reader trusting the run summary believed a stamp had
        // been refreshed when nothing had been written.
        final result = await runVersioner(project, dryRun: true);

        expect(result.success, isTrue, reason: 'a dry run is not a failure');
        expect(
          result.message,
          'dry run — no version file written',
          reason:
              'the message is what a run summary prints; "version file '
              'generated" for a dry run is a tool reporting intent as fact',
        );
        expect(
          File(stampPath(project)).existsSync(),
          isFalse,
          reason: 'a dry run must leave the project untouched',
        );
      },
    );

    test('SCE48-3: a dry run does not advance the build number', () async {
      // The installed binary advanced `tom_build_state.json` on every run
      // while writing no stamp, which is how three consecutive runs looked
      // like progress. The build number is the one thing it DID move.
      await runVersioner(project, dryRun: true);
      expect(
        File(p.join(project.path, 'tom_build_state.json')).existsSync(),
        isFalse,
        reason:
            'nothing may be written by a dry run — least of all the counter '
            'that made the no-op look like work',
      );
    });

    test('SCE48-4: a stale stamp is REPLACED, not left in place', () async {
      // The reproduction, as a test. A stamp already on disk carrying the
      // wrong version is exactly the state the binary failed to repair while
      // reporting the correct version in its message.
      Directory(p.dirname(stampPath(project))).createSync(recursive: true);
      File(stampPath(project)).writeAsStringSync(
        '// stale\nclass ZomSce48Version {\n'
        "  static const String version = '0.0.1-STALE';\n}\n",
      );

      final result = await runVersioner(project);

      expect(result.success, isTrue, reason: result.error ?? '');
      final written = File(stampPath(project)).readAsStringSync();
      expect(written, contains("version = '2.5.0'"));
      expect(
        written,
        isNot(contains('0.0.1-STALE')),
        reason:
            'this is the measured failure: SUCCESS reported over a stamp that '
            'still read the old version',
      );
    });
  });
}
