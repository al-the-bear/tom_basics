// BK-FP: the shared step records in the binaries layer
// (`$TOM_BINARY_PATH/<platform>/.buildkit/steps/`). A build in one clone
// records each step's fingerprint there; another clone (another host, after
// it pulled the code and the binaries) with the same inputs skips the
// compile, the versioner and the generators, reporting `up to date
// (fingerprint)`, and writes no new build number. The fixture workspace is a
// git repository under .dart_tool, cloned once more beside it; both clones
// share one TOM_BINARY_PATH. Each compile appends a line to runs.log in its
// clone (not one of the project's inputs).
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/platform_utils.dart';
import 'package:tom_build_kit/src/v2/incremental/step_inputs.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

const _gitEnv = {
  'GIT_AUTHOR_NAME': 'Test',
  'GIT_AUTHOR_EMAIL': 'test@example.com',
  'GIT_COMMITTER_NAME': 'Test',
  'GIT_COMMITTER_EMAIL': 'test@example.com',
};

/// A fake generator wired as `:d4rtgen` (buildkit_master.yaml's
/// `nested_tools:` names it in place of the real one): it writes `lib/generated.dart` into
/// the project (from `lib/source.dart`, so a changed source changes it) and
/// appends the project to `gen.log` in the clone.
const _fakegen = r'''#!/bin/sh
if [ "$1" = "--dump-definitions" ]; then
cat <<YAML
name: d4rtgen
version: 1.0.0
description: A fake generator
mode: single_command
features:
  project_traversal: true
works_with_natures: [DartProjectFolder]
YAML
exit 0
fi
if [ "$1" = "--version" ]; then echo "d4rtgen 1.0.0 (fake)"; exit 0; fi
echo "$(basename "$PWD")" >> ../gen.log
{ echo "// generated"; cat lib/source.dart; } > lib/generated.dart
''';

void main() {
  late Directory base;
  late Directory clone1;
  late Directory clone2;
  late Directory binaries;
  final platform = PlatformUtils.getCurrentPlatform();

  void write(Directory root, String rel, String text) =>
      File(p.join(root.path, rel))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);

  List<String> lines(Directory root, String name) {
    final log = File(p.join(root.path, name));
    return log.existsSync()
        ? log.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList()
        : [];
  }

  File stamp(Directory root) =>
      File(p.join(root.path, 'alpha', 'lib', 'src', 'version.versioner.dart'));

  setUp(() {
    final dartTool = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    base = dartTool.createTempSync('binary_fingerprint_test_');
    clone1 = Directory(p.join(base.path, 'one'))..createSync();
    binaries = Directory(p.join(base.path, 'binaries'))..createSync();
    write(
      clone1,
      'buildkit_master.yaml',
      'required-environment:\n  binaryPath: \$TOM_BINARY_PATH\n'
          'nested_tools:\n  d4rtgen:\n'
          '    binary: d4rtgen\n'
          '    mode: standalone\n',
    );
    write(clone1, '.gitignore', '*.log\n.dart_tool/\npubspec.lock\n');
    write(
      clone1,
      'alpha/pubspec.yaml',
      'name: alpha\nenvironment:\n  sdk: ^3.0.0\n',
    );
    write(clone1, 'alpha/bin/main.dart', 'void main() {}\n');
    write(clone1, 'alpha/lib/source.dart', 'const answer = 1;\n');
    write(
      clone1,
      'alpha/buildkit.yaml',
      'versioner:\n  variable-prefix: alpha\n'
          'd4rtgen:\n  generate: true\n'
          'compiler:\n  compiles:\n    - commandline:\n'
          '        - shell echo alpha >> ../runs.log\n'
          '        - shell mkdir -p \$TOM_BINARY_PATH/$platform\n'
          '        - shell dart compile kernel %{file} -o '
          '\$TOM_BINARY_PATH/$platform/alpha.dill\n'
          '      files:\n        - bin/main.dart\n',
    );
    final fakegen = File(p.join(base.path, 'fakebin', 'd4rtgen'))
      ..parent.createSync()
      ..writeAsStringSync(_fakegen);
    Process.runSync('chmod', ['+x', fakegen.path]);
    _git(clone1.path, ['init', '-q', '-b', 'main']);
    _git(clone1.path, ['add', '-A']);
    _git(clone1.path, ['commit', '-q', '-m', 'fixture']);
  });
  tearDown(() => base.deleteSync(recursive: true));

  /// Runs buildkit in [root] with the shared binaries path (or none).
  Future<String> buildkit(
    Directory root,
    List<String> args, {
    bool withBinaries = true,
  }) async {
    final env = Map.of(Platform.environment);
    // The fake generator comes first on the PATH, before a real d4rtgen.
    env['PATH'] =
        '${p.join(base.path, 'fakebin')}${Platform.isWindows ? ';' : ':'}'
        '${env['PATH'] ?? ''}';
    if (withBinaries) {
      env['TOM_BINARY_PATH'] = binaries.path;
    } else {
      env.remove('TOM_BINARY_PATH');
    }
    final r = await Process.run(
      'dart',
      ['run', _buildkit, '-R', root.path, '-s', root.path, '-r', ...args],
      workingDirectory: root.path,
      environment: env,
      includeParentEnvironment: false,
    );
    final out = '${r.stdout}${r.stderr}';
    expect(r.exitCode, 0, reason: out);
    return out;
  }

  /// The build of build_binaries.sh: stamp, generate, compile.
  Future<String> build(Directory root, [List<String> extra = const []]) =>
      buildkit(root, [':versioner', ':d4rtgen', ':compiler', ...extra]);

  /// Clone 1's build result as another host gets it: the code as committed
  /// after the build (tom_push_code) in a second clone; the binaries and the
  /// shared records come along (tom_pull_binaries), in a folder at another
  /// place.
  void cloneAfterBuild() {
    _git(clone1.path, ['add', '-A']);
    _git(clone1.path, ['commit', '-q', '-m', 'build']);
    clone2 = Directory(p.join(base.path, 'two'));
    _git(base.path, ['clone', '-q', clone1.path, clone2.path]);
    binaries = binaries.renameSync(p.join(base.path, 'pulled_binaries'));
  }

  test('BK-FP-1: another clone with the same inputs skips the compile, the '
      'generator and the versioner by the shared records, and writes no '
      'new build number [2026-11-23]', () async {
    await build(clone1);
    expect(lines(clone1, 'runs.log'), ['alpha']);
    expect(lines(clone1, 'gen.log'), ['alpha']);
    Map<String, dynamic> record(List<String> dir) =>
        jsonDecode(
              File(
                p.joinAll([
                  binaries.path,
                  ...dir,
                  '.buildkit',
                  'steps',
                  'alpha.json',
                ]),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    // The compile is the platform's; the stamp and the generated code are
    // every platform's.
    final perPlatform = record([platform]);
    expect(perPlatform.keys, ['compiler']);
    expect(record([]).keys, unorderedEquals(['versioner', 'd4rtgen']));
    // The binary is recorded relative to TOM_BINARY_PATH: no host path.
    expect((perPlatform['compiler'] as Map)['outputs'], [
      '$platform/alpha.dill',
    ]);

    cloneAfterBuild();
    final stamped = stamp(clone2).readAsStringSync();
    final out = await build(clone2);
    expect(lines(clone2, 'runs.log'), isEmpty, reason: out);
    expect(lines(clone2, 'gen.log'), isEmpty, reason: out);
    expect(stamp(clone2).readAsStringSync(), stamped);
    expect(out, contains('alpha: :compiler up to date (fingerprint)'));
    expect(out, contains('alpha: :d4rtgen up to date (fingerprint)'));
    expect(out, contains('alpha: :versioner up to date (fingerprint)'));

    // The project's own state is filled from them: the next run there skips
    // by its own record.
    final again = await build(clone2);
    expect(again, contains('alpha: :compiler up to date (inputs unchanged'));
    expect(lines(clone2, 'runs.log'), isEmpty);
  });

  test('BK-FP-2: a changed input rebuilds: a new build number, the generator '
      'and the compile run [2026-11-23]', () async {
    await build(clone1);
    cloneAfterBuild();
    final stamped = stamp(clone2).readAsStringSync();
    write(clone2, 'alpha/lib/source.dart', 'const answer = 2;\n');
    final out = await build(clone2);
    expect(lines(clone2, 'runs.log'), ['alpha'], reason: out);
    expect(lines(clone2, 'gen.log'), ['alpha'], reason: out);
    expect(stamp(clone2).readAsStringSync(), isNot(stamped));
    // The versioner is recorded with the project as the run left it (after
    // the generator rewrote lib/generated.dart): the next run skips it.
    final again = await build(clone2);
    expect(again, contains('alpha: :versioner up to date'));
    expect(lines(clone2, 'runs.log'), ['alpha'], reason: again);
  });

  test('BK-FP-3: --force runs every step although the shared records '
      'match [2026-11-23]', () async {
    await build(clone1);
    cloneAfterBuild();
    final stamped = stamp(clone2).readAsStringSync();
    await build(clone2, ['--force']);
    expect(lines(clone2, 'runs.log'), ['alpha']);
    expect(lines(clone2, 'gen.log'), ['alpha']);
    expect(stamp(clone2).readAsStringSync(), isNot(stamped));
  });

  test(
    'BK-FP-4: without TOM_BINARY_PATH only the project\'s own record is '
    'used: another clone builds, a second run there skips [2026-11-23]',
    () async {
      await buildkit(clone1, [':versioner', ':d4rtgen'], withBinaries: false);
      expect(
        Directory(p.join(binaries.path, platform, '.buildkit')).existsSync(),
        isFalse,
      );
      cloneAfterBuild();
      await buildkit(clone2, [':versioner', ':d4rtgen'], withBinaries: false);
      expect(lines(clone2, 'gen.log'), ['alpha']);
      final out = await buildkit(clone2, [
        ':versioner',
        ':d4rtgen',
      ], withBinaries: false);
      expect(out, contains('alpha: :d4rtgen up to date (inputs unchanged'));
      expect(lines(clone2, 'gen.log'), ['alpha']);
    },
  );

  test('BK-FP-5: outputs are recorded relative to their folder and found '
      'there again [2026-11-23]', () {
    final root = p.join(base.path, 'binaries');
    final output = p.join(root, platform, 'alpha.dill');
    final elsewhere = p.join(base.path, 'out', 'alpha.dill');
    final recorded = recordedOutputs([output, elsewhere], root);
    expect(recorded, ['$platform/alpha.dill', elsewhere]);
    expect(resolveOutputs(recorded, root), [output, elsewhere]);
    expect(
      sharedProjectLabel(p.join(clone1.path, 'alpha'), root: clone1.path),
      'alpha',
    );
  });

  test('BK-FP-6: only a workspace that names a binaries layer shares records, '
      'and never for a project in a scratch folder [2026-11-23]', () {
    final ws = Directory(p.join(base.path, 'ws'))..createSync();
    final alpha = p.join(ws.path, 'alpha');
    write(ws, 'buildkit_master.yaml', 'navigation: {}\n');
    expect(
      SharedStepRecords.forProject(alpha, platformSpecific: false),
      isNull,
    );
    final layer = p.join(base.path, 'layer');
    write(
      ws,
      'buildkit_master.yaml',
      'required-environment:\n  binaryPath: $layer\n',
    );
    expect(
      SharedStepRecords.forProject(alpha, platformSpecific: true)!.dir,
      p.join(layer, platform, '.buildkit', 'steps'),
    );
    expect(
      SharedStepRecords.forProject(alpha, platformSpecific: false)!.dir,
      p.join(layer, '.buildkit', 'steps'),
    );
    expect(binariesLayer(ws.path), layer);
    expect(
      SharedStepRecords.forProject(
        p.join(ws.path, '.dart_tool', 'fixture'),
        platformSpecific: false,
      ),
      isNull,
    );
    expect(
      SharedStepRecords.forProject(
        p.join(ws.path, 'ztmp', 'x'),
        platformSpecific: false,
      ),
      isNull,
    );
  });
}

void _git(String dir, List<String> args) {
  final r = Process.runSync(
    'git',
    args,
    workingDirectory: dir,
    environment: _gitEnv,
  );
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')}: ${r.stderr}');
  }
}
