import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  group('PipelineOptionResolver', () {
    test('BB-PLX-1: command options override invocation and pipeline', () {
      final resolved = PipelineOptionResolver.resolveEffectiveOptions(
        pipelineOptions: const {'scan': '.', 'verbose': 'false'},
        invocationOptions: const {'verbose': 'true', 'root': '/tmp/ws'},
        commandOptions: const {'verbose': 'false', 'project': 'tom_build_base'},
      );

      expect(resolved['scan'], '.');
      expect(resolved['root'], '/tmp/ws');
      expect(resolved['project'], 'tom_build_base');
      expect(resolved['verbose'], 'false');
    });

    test('BB-PLX-2: disqualifying traversal options are detected', () {
      const args = CliArgs(root: '/tmp/ws', projectPatterns: ['tom_*']);
      expect(
        PipelineOptionResolver.hasDisqualifyingTraversalOptions(args),
        isTrue,
      );
    });

    test('BB-PLX-3: verbose and dry-run alone are not disqualifying', () {
      const args = CliArgs(verbose: true, dryRun: true);
      expect(
        PipelineOptionResolver.hasDisqualifyingTraversalOptions(args),
        isFalse,
      );
    });
  });
}
