/// The versioner's emitted template must be `dart format` clean.
///
/// WHY THIS TEST EXISTS. `:versioner` writes `version.versioner.dart` into
/// packages that hold themselves to a formatting gate. A template the formatter
/// would rewrite makes such a gate unaddable: the tree is clean until the next
/// version bump and red immediately after it, for a file nobody edited — which
/// trains a reader to run `dart format` without looking at what it changed.
///
/// Observed 2026-09-08 in `tom_specs_model`, whose `version.versioner.dart` is
/// gitignored and regenerated on every run: two getter lines ran past the page
/// width, so the tall formatter wrapped them after `=>` and the gate reported
/// exactly that one file after every bump.
///
/// The check runs the REAL `dart format` rather than comparing against a
/// recorded string, for the reason `check_format.dart` shells out too: a pinned
/// expectation and the SDK's own formatter drift apart at every SDK bump, and
/// the question here is what the installed formatter does.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/versioner_executor.dart';

void main() {
  group('versioner template formatting', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('versioner_fmt'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// `dart format`'s verdict on [source], or null when no formatter is
    /// reachable.
    String? formatted(String source) {
      final f = File('${tmp.path}/version.versioner.dart')
        ..writeAsStringSync(source);
      try {
        final r = Process.runSync('dart', [
          'format',
          '--output=show',
          '--summary=none',
          f.path,
        ]);
        if (r.exitCode != 0) return null;
        return r.stdout as String;
      } on ProcessException {
        return null;
      }
    }

    test('a fully populated version file needs no reformatting', () {
      final source = VersionerExecutor.generateVersionFileContent(
        packageName: 'tom_specs_model',
        version: '1.3.1',
        buildTime: '2026-09-09T18:34:46.256979Z',
        gitCommit: 'aefd83dd',
        buildNumber: 9,
        dartSdkVersion: '3.12.2',
        className: 'TomSpecsModelVersionInfo',
      );
      final result = formatted(source);
      if (result == null) {
        markTestSkipped('no `dart format` on PATH');
        return;
      }
      expect(
        result,
        source,
        reason:
            'the emitted template must already be formatted — a generated file '
            'the formatter would rewrite makes a formatting gate red after '
            'every version bump, for something nobody did',
      );
    });

    test('the sparse form — no commit, no build number, no SDK — too', () {
      // The three optional fields take a different branch each, and an empty
      // string is shorter than a real value, so the populated case alone does
      // not cover them.
      final source = VersionerExecutor.generateVersionFileContent(
        packageName: 'p',
        version: '0.0.1',
        buildTime: '2026-01-01T00:00:00.000Z',
      );
      final result = formatted(source);
      if (result == null) {
        markTestSkipped('no `dart format` on PATH');
        return;
      }
      expect(result, source);
    });
  });
}
