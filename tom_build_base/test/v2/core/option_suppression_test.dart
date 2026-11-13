import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Per-command option suppression (`:cmd -s-`) does not exist: a run's
/// commands share one traversal, so there is nothing to take an option away
/// from for one of them. The parser refuses the syntax instead of reading
/// `-s-` as `--scan -`, and ToolRunner stops before anything runs.
///
/// Test IDs: BB-SUPP-1..4.

const _tool = ToolDefinition(
  name: 'supptool',
  description: 'Tool for the suppression tests',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  features: NavigationFeatures.all,
  commands: [
    CommandDefinition(
      name: 'write',
      description: 'Records that it ran',
      requiresTraversal: false,
    ),
  ],
);

class _RecordingExecutor extends CommandExecutor {
  bool ran = false;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async =>
      ItemResult.success(path: context.path, name: context.name);

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    ran = true;
    return const ToolResult.success();
  }
}

void main() {
  CliArgs parse(List<String> args) =>
      CliArgParser(toolDefinition: _tool).parse(args);

  group('option suppression is refused', () {
    test('BB-SUPP-1: `:cmd -s-` is an argument error, not `--scan -` '
        '[2026-11-13]', () {
      final args = parse([':write', '-s-']);

      expect(args.argumentErrors, hasLength(1));
      expect(args.argumentErrors.single, contains('`-s-`'));
      expect(args.argumentErrors.single, contains('not supported'));
      expect(args.scan, isNull, reason: '`-` must not become the scan path');
      expect(args.scanExplicitlySet, isFalse);
    });

    test('BB-SUPP-2: every -X- and --name- form, before or after a command '
        '[2026-11-13]', () {
      for (final form in ['-v-', '-n-', '-r-', '--scan-', '--verbose-']) {
        expect(
          parse([':write', form]).argumentErrors,
          [contains('`$form`')],
          reason: '$form after a command',
        );
        expect(
          parse([form, ':write']).argumentErrors,
          [contains('`$form`')],
          reason: '$form before a command',
        );
      }
      expect(parse(['-s-', ':write', '-v-']).argumentErrors, hasLength(2));
    });

    test('BB-SUPP-3: values ending in a dash and a lone dash stay what they '
        'were [2026-11-13]', () {
      final attached = parse(['-sdir-', ':write']);
      expect(attached.argumentErrors, isEmpty);
      expect(attached.scan, 'dir-');

      final separate = parse(['--scan', 'dir-', ':write']);
      expect(separate.argumentErrors, isEmpty);
      expect(separate.scan, 'dir-');

      final equals = parse(['--scan=-', ':write']);
      expect(equals.argumentErrors, isEmpty);
      expect(equals.scan, '-');

      expect(parse([':write', '-']).argumentErrors, isEmpty);
      expect(parse(['-s', '.', '-v', ':write']).argumentErrors, isEmpty);
    });

    test('BB-SUPP-4: ToolRunner refuses the run before any command runs '
        '[2026-11-13]', () async {
      final ex = _RecordingExecutor();
      final out = StringBuffer();
      final result = await ToolRunner(
        tool: _tool,
        output: out,
        executors: {'write': ex},
      ).run(['-v', ':write', '-v-']);

      expect(result.success, isFalse);
      expect(ex.ran, isFalse);
      expect(out.toString(), contains('Error: `-v-`'));
      expect(out.toString(), contains('not supported'));
    });
  });
}
