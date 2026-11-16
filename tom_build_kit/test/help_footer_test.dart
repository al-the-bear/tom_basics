/// buildkit's help footer says where pipelines are defined: the top-level
/// `pipelines:` of buildkit_master.yaml. A project's buildkit.yaml holds none
/// (the pipeline loader reads only the master file, and the project file's
/// schema refuses the key).
///
/// Test IDs: BK-HELPFOOT-1.
library;

import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';

void main() {
  test('BK-HELPFOOT-1: pipelines are named as buildkit_master.yaml\'s only '
      '[2026-11-16]', () {
    final footer = buildkitTool.helpFooter!;
    expect(footer, contains('Pipelines are defined in buildkit_master.yaml'));
    expect(footer, isNot(contains('buildkit.yaml under buildkit.pipelines')));
    expect(footer, isNot(contains('or buildkit.yaml')));
  });
}
