/// A whole run: stages in order past any red, one log per step, the summary
/// line and `summary.txt`; the summary line on its own; stage resolution;
/// test tags read from annotations; the lock path; and the tool runner that
/// puts the stages on the command line.
///
/// The run spawns Dart children that exit at once; the bound is for a child
/// that hangs.
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/ci.dart';

import 'support_scratch.dart';

void main() {
  group('CI-SUMMARY the summary line', () {
    CiOutcome o(
      String stage,
      String subject,
      bool ok, {
      bool skipped = false,
    }) => CiOutcome(
      stage: stage,
      subject: subject,
      ok: ok,
      logPath: p.join('/r', 'build', 'testlog', 't', '$subject.log'),
      skipped: skipped,
    );

    test('CI-SUMMARY-1: green names the stages, the steps and the logs', () {
      final line = ciSummaryLine(
        stages: ['analyze', 'test'],
        outcomes: [o('analyze', 'a', true), o('test', 'a', true)],
        elapsed: const Duration(minutes: 14, seconds: 2),
        runDir: p.join('/r', 'build', 'testlog', 't'),
        relativeTo: '/r',
      );
      expect(line, startsWith('CI GREEN: analyze test — 2 steps, 0 red'));
      expect(line, contains('14m02s'));
      expect(line, contains(p.join('build', 'testlog', 't')));
      expect(line, isNot(contains('\n')));
    });

    test('CI-SUMMARY-2: red names every red step and its log, on one line', () {
      final line = ciSummaryLine(
        stages: ['test', 'web'],
        outcomes: [
          o('test', 'pkg_a', false),
          o('test', 'pkg_b', true),
          o('web', 'web', false),
        ],
        elapsed: const Duration(seconds: 9),
        runDir: '/r/x',
        relativeTo: '/r',
      );
      expect(line, startsWith('CI RED: 2 of 3 steps red'));
      expect(
        line,
        contains(
          'test pkg_a (${p.join('build', 'testlog', 't', 'pkg_a.log')})',
        ),
      );
      expect(line, contains('web ('));
      expect(line, isNot(contains('pkg_b')));
      expect(line, isNot(contains('\n')));
    });

    test('CI-SUMMARY-3: a run in which nothing ran is red', () {
      expect(
        ciSummaryLine(
          stages: ['test'],
          outcomes: const [],
          elapsed: Duration.zero,
          runDir: '/r/x',
          relativeTo: '/r',
        ),
        startsWith('CI RED'),
      );
    });

    test('CI-SUMMARY-4: a skipped step is green, and the summary counts it '
        'apart', () {
      final line = ciSummaryLine(
        stages: ['test', 'ui'],
        outcomes: [o('test', 'a', true), o('ui', 'ui', true, skipped: true)],
        elapsed: const Duration(seconds: 3),
        runDir: '/r/x',
        relativeTo: '/r',
      );
      expect(line, startsWith('CI GREEN: test ui — 2 steps, 0 red, 1 skipped'));
      expect(formatCiDuration(const Duration(seconds: 9)), '9s');
    });
  });

  group('CI-STAGES resolving and finding', () {
    const stages = ['analyze', 'test', 'ui', 'web'];

    test('CI-STAGES-1: all expands in the stage order, the given order is '
        'kept, repeats dropped, an unknown name throws', () {
      expect(resolveCiStages(['all'], stages: stages), stages);
      expect(resolveCiStages(['web', 'test', 'web'], stages: stages), [
        'web',
        'test',
      ]);
      expect(resolveCiStages(['test', 'all'], stages: stages), [
        'test',
        'analyze',
        'ui',
        'web',
      ]);
      expect(
        () => resolveCiStages(['nope'], stages: stages),
        throwsArgumentError,
      );
    });

    test('CI-STAGES-2: all leaves out what inAll excludes, which still runs '
        'when named', () {
      bool notUi(String s) => s != 'ui';
      expect(
        resolveCiStages(['all'], stages: stages, inAll: notUi),
        isNot(contains('ui')),
      );
      expect(resolveCiStages(['ui'], stages: stages, inAll: notUi), ['ui']);
    });

    test('CI-STAGES-3: a tag counts only when a test file annotates with it — '
        'a declaration in dart_test.yaml or the text in a string does not', () {
      final pkg = scratchDir('tags');
      writeFile(pkg, 'dart_test.yaml', 'tags:\n  golden: {}\n');
      final testFile = File(p.join(pkg.path, 'test', 'a_test.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('void main() {}\n');
      const tags = ['golden', 'ui-flow'];
      expect(ciTestTagsOf(pkg.path, tags), isEmpty);
      testFile.writeAsStringSync("@Tags(['ui-flow'])\nlibrary;\n");
      expect(ciTestTagsOf(pkg.path, tags), ['ui-flow']);
      testFile.writeAsStringSync(
        "void main() { print(\"@Tags(['golden'])\"); }\n",
      );
      expect(ciTestTagsOf(pkg.path, tags), isEmpty);
    });

    test('CI-STAGES-4: a package is named relative to the root and knows '
        'whether it is a Flutter package', () {
      final root = scratchDir('pkgs');
      writeFile(root, 'a/pubspec.yaml', 'name: a\n');
      writeFile(
        root,
        'b/ex/pubspec.yaml',
        'name: ex\ndependencies:\n  flutter:\n    sdk: flutter\n',
      );
      final a = CiPackage.at(root.path, p.join(root.path, 'a'));
      final ex = CiPackage.at(root.path, p.join(root.path, 'b', 'ex'));
      expect(a.name, 'a');
      expect(a.isFlutter, isFalse);
      expect(ex.name, 'b/ex');
      expect(ex.logName, 'b.ex');
      expect(ex.isFlutter, isTrue);
    });

    test('CI-STAGES-5: the lock path: override, workspace ztmp, repository '
        'ztmp', () {
      expect(
        ciFlutterLockPath(
          repositoryRoot: '/r',
          workspaceRoot: '/w',
          environment: {'TOM_FLUTTER_LOCK': '/x/l'},
        ),
        '/x/l',
      );
      expect(
        ciFlutterLockPath(
          repositoryRoot: '/r',
          workspaceRoot: '/w',
          environment: {},
        ),
        p.join('/w', 'ztmp', 'flutter.lock'),
      );
      expect(
        ciFlutterLockPath(repositoryRoot: '/r', environment: {}),
        p.join('/r', 'ztmp', 'flutter.lock'),
      );
    });
  });

  group('CI-RUN a whole run', () {
    test('CI-RUN-1: stages run in order past a red, each step has its log, '
        'and the summary line and summary.txt name the red', () async {
      final root = scratchDir('run');
      writeFile(root, 'ok.dart', "void main() { print('fine'); }\n");
      writeFile(
        root,
        'red.dart',
        "import 'dart:io';\nvoid main() { exitCode = 2; }\n",
      );
      final console = StringBuffer();
      final order = <String>[];
      final run = CiRun(
        toolName: 'fixture_ci',
        repositoryRoot: root.path,
        lockPath: p.join(root.path, 'lock'),
        stageDescriptions: const {'one': 'first', 'two': 'second'},
        console: console,
        runDir: p.join(root.path, 'testlog', 'run'),
        runStage: (run, stage) async {
          order.add(stage);
          final pkg = CiPackage(
            name: 'pkg',
            directory: root.path,
            isFlutter: false,
          );
          if (stage == 'one') {
            await run.step(stage, 'red', 'red.log', [
              run.tool(pkg, ['red.dart']),
            ]);
            run.skip(stage, 'later', 'later.log', 'not on this host');
          } else {
            await run.step(stage, stage, 'ok.log', [
              run.tool(pkg, ['ok.dart']),
            ]);
            run.fail(stage, 'gone', 'gone.log', 'the test is gone');
          }
        },
        dart: Platform.resolvedExecutable,
      );
      final line = await run.run(['one', 'two']);
      expect(order, ['one', 'two'], reason: 'a red does not stop the run');
      expect(line, startsWith('CI RED: 2 of 4 steps red'));
      expect(line, contains('one red'));
      expect(line, contains('two gone'));
      expect(
        File(p.join(run.runDir, 'ok.log')).readAsStringSync(),
        contains('fine'),
      );
      expect(
        File(p.join(run.runDir, 'gone.log')).readAsStringSync(),
        contains('the test is gone'),
      );
      final summary = File(
        p.join(run.runDir, 'summary.txt'),
      ).readAsStringSync();
      expect(summary, contains('skip '));
      expect(summary.trimRight(), endsWith(line));
      expect(console.toString(), contains('fixture_ci :one :two'));
      expect(console.toString(), contains('== :one — first'));
    });

    test('CI-RUN-2: a step that needs flutter where there is none is red '
        'without running', () async {
      final root = scratchDir('run_noflutter');
      final run = CiRun(
        toolName: 'fixture_ci',
        repositoryRoot: root.path,
        lockPath: p.join(root.path, 'lock'),
        stageDescriptions: const {},
        console: StringBuffer(),
        runDir: p.join(root.path, 'testlog', 'run'),
        findFlutter: () => null,
        runStage: (run, stage) =>
            run.step(stage, stage, 'x.log', const [], needsFlutter: true),
      );
      expect(run.flutter, isNull);
      final line = await run.run(['s']);
      expect(line, startsWith('CI RED'));
      expect(line, contains('x.log'));
      expect(run.outcomes.single.detail, contains('flutter not found'));
    });

    test('CI-RUN-3: a step that exits 0 without what it must produce is '
        'red', () async {
      final root = scratchDir('run_produces');
      writeFile(root, 'ok.dart', 'void main() {}\n');
      final run = CiRun(
        toolName: 'fixture_ci',
        repositoryRoot: root.path,
        lockPath: p.join(root.path, 'lock'),
        stageDescriptions: const {},
        console: StringBuffer(),
        runDir: p.join(root.path, 'testlog', 'run'),
        dart: Platform.resolvedExecutable,
        runStage: (run, stage) => run.step(stage, stage, 'build.log', [
          CiCommand(Platform.resolvedExecutable, [
            'ok.dart',
          ], workingDirectory: root.path),
        ], produces: p.join(root.path, 'build', 'out.js')),
      );
      final line = await run.run(['build']);
      expect(line, startsWith('CI RED'));
      expect(run.outcomes.single.detail, contains('exit 0 but no'));
    });
  });

  group('CI-TOOL the command line', () {
    test('CI-TOOL-1: every stage and all are commands with their '
        'description; the stages named run once, in order', () async {
      final tool = ciToolDefinition(
        name: 'fixture_ci',
        description: 'A fixture.',
        version: '1.0.0',
        stages: const ['analyze', 'test'],
        descriptions: const {
          'analyze': 'analyze it',
          'test': 'test it',
          'all': 'both',
        },
      );
      expect(tool.commands.map((c) => c.name), ['analyze', 'test', 'all']);
      expect(tool.findCommand('test')!.description, 'test it');
      final calls = <List<String>>[];
      final out = StringBuffer();
      final runner = ciToolRunner(
        tool: tool,
        console: out,
        runStages: (stages, console) async {
          calls.add(stages);
          return 'CI GREEN: ${stages.join(' ')}';
        },
      );
      final result = await runner.run([':test', ':analyze']);
      expect(calls, [
        ['test', 'analyze'],
      ]);
      expect(result.success, isTrue);
      expect(out.toString(), contains('CI GREEN: test analyze'));
    });

    test('CI-TOOL-2: a red summary is a failed result', () async {
      final tool = ciToolDefinition(
        name: 'fixture_ci',
        description: 'A fixture.',
        version: '1.0.0',
        stages: const ['test'],
        descriptions: const {'test': 't', 'all': 'a'},
      );
      final runner = ciToolRunner(
        tool: tool,
        console: StringBuffer(),
        runStages: (stages, console) async => 'CI RED: 1 of 1 steps red',
      );
      final result = await runner.run([':test']);
      expect(result.success, isFalse);
    });
  });
}
