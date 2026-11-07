// The stamp beside a summary records what wrote it: a summary is kept only
// while its stamp is the one the running toolchain would write.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('summary_stamp_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('SST-1: the current stamp is the running toolchain; it round-trips '
      'through its text, which names no path', () {
    final stamp = SummaryStamp.current(embedderYamlPath: '/f/_embedder.yaml');
    expect(stamp.toolchain, currentToolchainKey());
    expect(stamp.dartUi, isTrue);
    expect(stamp.encode(), isNot(contains('/f/')));
    expect(SummaryStamp.decode(stamp.encode()), stamp);
    expect(
      SummaryStamp.decode(const SummaryStamp(toolchain: 'x').encode()),
      const SummaryStamp(toolchain: 'x'),
    );
    expect(SummaryStamp.decode('not a stamp'), isNull);
  });

  test('SST-2: a summary is current only with the stamp the toolchain would '
      'write — another analyzer data version, another embedder or no stamp '
      'is stale', () {
    final summary = p.join(dir.path, 'sdk_summary.sum');
    File(summary).writeAsBytesSync([1, 2, 3]);
    final now = SummaryStamp.current();

    expect(now.isCurrentFor(summary), isFalse, reason: 'no stamp yet');

    now.writeFor(summary);
    expect(now.isCurrentFor(summary), isTrue);

    // Written by analyzer 14.5.0 (data version 739) on the same SDK.
    SummaryStamp(
      toolchain: currentToolchainKey(dataVersion: analyzerDataVersion - 1),
    ).writeFor(summary);
    expect(now.isCurrentFor(summary), isFalse);

    now.writeFor(summary);
    expect(
      SummaryStamp.current(
        embedderYamlPath: '/f/_embedder.yaml',
      ).isCurrentFor(summary),
      isFalse,
      reason: 'built without dart:ui',
    );

    File(summary).deleteSync();
    expect(now.isCurrentFor(summary), isFalse, reason: 'no summary');
  });
}
