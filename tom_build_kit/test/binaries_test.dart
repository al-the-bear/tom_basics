/// The release binaries (buildkit_ws_commands.md § 1.9):
/// `:skill-build-binaries`, `:skill-build-all-binaries`,
/// `:skill-push-binaries`, on a workspace and a tom_binaries clone made by
/// each test in a temporary folder (never the live workspace). The buildkit
/// subprocess and the self-compile are fakes that write what the real ones
/// write, so the declarations, the moves, the swap, the short names and the
/// ignored folder are checked in seconds; the real build is run by hand on
/// each platform.
///
/// Test IDs: BK-BIN-1..12.
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/binaries/binaries_build.dart';
import 'package:tom_build_kit/src/v2/binaries/binaries_executors.dart';
import 'package:tom_build_kit/src/v2/binaries/binaries_messages.dart';
import 'package:tom_build_kit/src/v2/binaries/release_set.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';

late Directory base;
late String ws;
late String bin;
final env = <String, String>{};
const plat = 'darwin-arm64';

void write(String path, String text) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(text);

ProcessResult git(String dir, List<String> args) {
  final r = Process.runSync(
    'git',
    args,
    workingDirectory: dir,
    environment: env,
  );
  if (r.exitCode != 0) throw StateError('git $args in $dir: ${r.stderr}');
  return r;
}

String out(String dir, List<String> args) => '${git(dir, args).stdout}'.trim();

void project(String rel, String yaml) =>
    write(p.join(ws, rel, 'buildkit.yaml'), yaml);

/// A workspace: a self-built project (buildkit), a project with a release and
/// a non-release executable, the generators, and a master list naming a
/// project's executable, an external, a bundled folder and short names.
void workspace() {
  project('tools/tom_build_kit', '''
compiler:
  skip-compile-with-buildkit: true
  executables:
    buildkit: {release: true}
    findproject: {release: true}
''');
  project('tools/tom_test_kit', '''
compiler:
  executables:
    testkit: {release: true}
    testkit_debug: {release: false}
''');
  project('gen/tom_d4rt_generator', 'compiler:\n  compiles: []\n');
  project('gen/tom_reflection_generator', '''
compiler:
  executables:
    reflectiongenerator: {release: true}
''');
  project('apps/tom_office_host', 'compiler:\n  compiles: []\n');
  project('tools/tom_test_kit/test/fixture', '''
compiler:
  executables:
    fixture_tool: {release: true}
''');
  write(p.join(ws, 'buildkit_master.yaml'), '''
binaries:
  - name: buildkit
    project: tom_build_kit
    short: [bk]
    windows-hard-link: true
  - name: testkit
    project: tools/tom_test_kit
    short: [tk]
  - name: d4rtgen
    project: tom_d4rt_generator
  - name: tom_office_host
    project: tom_office_host
    files: [libtom_office_host_lok.dylib]
    platforms: [darwin-arm64]
  - name: tomspecs
    built-by: the extension
  - name: pdfium
    bundled: true
    path: pdfium
  - name: suite
    built-by: another tool
    short:
      - {name: st, target: suite/bin/st}
''');
}

/// A tom_binaries clone with a bare remote; [ignoreAll] puts /all/ in its
/// .gitignore.
void binaries({bool ignoreAll = true}) {
  final remote = p.join(base.path, 'bin.git');
  git(base.path, ['init', '-q', '--bare', '-b', 'main', remote]);
  git(base.path, ['clone', '-q', remote, bin]);
  write(
    p.join(bin, '.gitignore'),
    '${ignoreAll ? '/all/\n' : ''}tom/*/*.old\ntom/*/*.old.*\ntom/*/*.new\n',
  );
  write(p.join(bin, 'tom', plat, 'buildkit'), 'old buildkit');
  write(p.join(bin, 'tom', plat, 'testkit'), 'old testkit');
  write(p.join(bin, 'pdfium', plat, 'libpdfium.dylib'), 'pdf');
  // From an earlier build: older than any run of the test.
  for (final f in ['buildkit', 'testkit']) {
    File(p.join(bin, 'tom', plat, f)).setLastModifiedSync(DateTime(2026, 1, 1));
  }
  git(bin, ['add', '-A']);
  git(bin, ['commit', '-qm', 'seed']);
  git(bin, ['push', '-q', 'origin', 'main']);
}

/// What the buildkit subprocess was asked, and a fake that writes every
/// executable the projects compile into `TOM_BINARY_PATH/<platform>`.
final calls = <List<String>>[];
final outputs = {
  'tom_d4rt_generator': ['d4rtgen'],
  'tom_reflection_generator': ['reflectiongenerator'],
  'tom_test_kit': ['testkit', 'testkit_debug'],
  'tom_office_host': ['tom_office_host', 'libtom_office_host_lok.dylib'],
  'other_app': ['other_tool'],
};
Set<String> skip = {};
var failStep = -1;

Future<BinStepResult> fakeBuildkit(
  List<String> args, {
  required Map<String, String> environment,
  required String workingDirectory,
}) async {
  calls.add(args);
  final named = [
    for (var i = 0; i < args.length - 1; i++)
      if (args[i] == '-p') args[i + 1],
  ];
  final dir = p.join(environment['TOM_BINARY_PATH']!, plat);
  for (final e in outputs.entries) {
    if (named.isNotEmpty && !named.contains(e.key)) continue;
    for (final f in e.value) {
      if (skip.contains(f)) continue;
      write(p.join(dir, f), 'new $f');
      if (!f.startsWith('lib')) write(p.join(dir, '$f.buildkit.json'), '{}');
    }
  }
  if (calls.length - 1 == failStep) {
    return (exitCode: 1, output: 'boom\nerror: it broke');
  }
  return (exitCode: 0, output: 'ok');
}

final selfBuilt = <String>[];
Future<BinStepResult> fakeSelf(
  String projectDir,
  String dartFile,
  String output,
) async {
  selfBuilt.add('${p.basename(projectDir)}:$dartFile');
  write(output, 'new ${p.basenameWithoutExtension(dartFile)}');
  return (exitCode: 0, output: '');
}

Future<({int exit, String text, Map<String, dynamic>? json})> bk(
  String command,
  List<String> args, {
  bool json = true,
  String platform = plat,
}) async {
  final buffer = StringBuffer();
  final previous = Directory.current;
  Directory.current = ws;
  try {
    final result =
        await ToolRunner(
          tool: buildkitTool,
          executors: {
            ...createBuildkitExecutors(),
            'skill-build-binaries': SkillBuildBinariesExecutor(
              all: false,
              out: buffer,
              buildkit: fakeBuildkit,
              compileSelf: fakeSelf,
              progress: StringBuffer(),
              platform: platform,
            ),
            'skill-build-all-binaries': SkillBuildBinariesExecutor(
              all: true,
              out: buffer,
              buildkit: fakeBuildkit,
              compileSelf: fakeSelf,
              progress: StringBuffer(),
              platform: platform,
            ),
            'skill-push-binaries': SkillPushBinariesExecutor(
              out: buffer,
              gitEnvironment: env,
            ),
          },
          output: StringBuffer(),
        ).run([
          '-R',
          ws,
          ':$command',
          if (json) '--json',
          '--binaries',
          bin,
          ...args,
        ]);
    final text = '$buffer';
    Map<String, dynamic>? doc;
    if (json) {
      final start = text.indexOf('{');
      doc = start < 0
          ? null
          : jsonDecode(text.substring(start)) as Map<String, dynamic>;
    }
    return (exit: result.exitCode, text: text, json: doc);
  } finally {
    Directory.current = previous;
  }
}

List<Map<String, dynamic>> messages(Map<String, dynamic>? json, String code) =>
    [
      for (final m in (json!['messages'] as List).cast<Map<String, dynamic>>())
        if (m['code'] == code) m,
    ];

Map<String, List<String>> doneOf(Map<String, dynamic>? json) => {
  for (final d in (json!['done'] as List).cast<Map>())
    d['repository'] as String: [for (final a in d['actions'] as List) '$a'],
};

List<String> codes(Map<String, dynamic>? json) => [
  for (final m in (json!['messages'] as List).cast<Map>()) m['code'] as String,
];

String tom(String f) => p.join(bin, 'tom', plat, f);
String allDir(String f) => p.join(bin, 'all', plat, f);

void main() {
  setUp(() {
    base = Directory(
      Directory.systemTemp.createTempSync('bk_bin_').resolveSymbolicLinksSync(),
    );
    ws = p.join(base.path, 'ws');
    bin = p.join(ws, 'tom_binaries');
    final config = File(p.join(base.path, 'gitconfig'))
      ..writeAsStringSync(
        '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n',
      );
    env
      ..clear()
      ..addAll({'GIT_CONFIG_GLOBAL': config.path, 'GIT_CONFIG_NOSYSTEM': '1'});
    calls.clear();
    selfBuilt.clear();
    skip = {};
    failStep = -1;
    workspace();
  });
  tearDown(() => base.deleteSync(recursive: true));

  test('BK-BIN-1: the set is the sum of both declarations; an entry in both '
      'is one, declared in both [2026-11-25]', () {
    final set = ReleaseSet.load(ws);
    expect(set.problems, isEmpty);
    final byName = {for (final b in set.binaries) b.name: b};
    expect(
      byName.keys,
      containsAll([
        'buildkit',
        'findproject',
        'testkit',
        'reflectiongenerator',
        'd4rtgen',
        'tom_office_host',
        'tomspecs',
        'pdfium',
        'suite',
      ]),
    );
    expect(
      byName.keys,
      isNot(contains('testkit_debug')),
      reason: 'release: false',
    );
    expect(
      byName.keys,
      isNot(contains('fixture_tool')),
      reason: 'test/ fixtures are no projects',
    );
    expect(byName['buildkit']!.declaredIn, [
      'tools/tom_build_kit/buildkit.yaml',
      'buildkit_master.yaml',
    ]);
    expect(byName['buildkit']!.selfBuilt, isTrue);
    expect(byName['buildkit']!.shortNames.single.name, 'bk');
    expect(byName['d4rtgen']!.declaredIn, ['buildkit_master.yaml']);
    expect(byName['d4rtgen']!.project, 'gen/tom_d4rt_generator');
    expect(
      byName['testkit']!.project,
      'tools/tom_test_kit',
      reason: 'a project named by its path',
    );
    expect(byName['tomspecs']!.kind, ReleaseKind.external);
    expect(byName['pdfium']!.kind, ReleaseKind.bundled);
    expect(byName['suite']!.shortNames.single.target, 'suite/bin/st');
    expect(
      set.forPlatform('linux-x64').map((b) => b.name),
      isNot(contains('tom_office_host')),
    );
  });

  test(
    'BK-BIN-2: an entry naming no project, or saying nothing of how it is '
    'built, is a problem; --list shows it, the build refuses [2026-11-25]',
    () async {
      File(p.join(ws, 'buildkit_master.yaml')).writeAsStringSync(
        '${File(p.join(ws, 'buildkit_master.yaml')).readAsStringSync()}'
        '  - name: ghost\n    project: tom_nowhere\n  - name: lonely\n',
      );
      final set = ReleaseSet.load(ws);
      expect(set.problems, hasLength(2));
      binaries();
      var r = await bk('skill-build-binaries', ['--list'], json: false);
      expect(r.exit, 2);
      expect(r.text, contains('no project tom_nowhere'));
      r = await bk('skill-build-binaries', []);
      expect(r.exit, 2);
      expect(codes(r.json), ['bin-set']);
      expect(calls, isEmpty);
    },
  );

  test('BK-BIN-3: --list prints every entry with where it is declared '
      '[2026-11-25]', () async {
    binaries();
    final r = await bk('skill-build-binaries', ['--list']);
    expect(r.exit, 0, reason: r.text);
    final list = {
      for (final b in (r.json!['binaries'] as List).cast<Map>()) b['name']: b,
    };
    expect(list['buildkit']!['declaredIn'], [
      'tools/tom_build_kit/buildkit.yaml',
      'buildkit_master.yaml',
    ]);
    expect(list['tomspecs']!['builtBy'], 'the extension');
    final text = await bk('skill-build-binaries', ['--list'], json: false);
    expect(text.text, contains('compiled by tools/tom_build_kit (swapped in)'));
    expect(text.text, contains('short: bk (hard link on Windows)'));
  });

  test(
    'BK-BIN-4: :skill-build-binaries: the generators first, then only the '
    'release projects; release files into tom/<platform>/, the rest stays '
    'in the ignored all/; git status shows only release files [2026-11-25]',
    () async {
      binaries();
      // Untracked, from before the run: left where it is.
      write(tom('legacy_tool'), 'legacy');
      File(tom('legacy_tool')).setLastModifiedSync(DateTime(2026, 1, 1));
      final r = await bk('skill-build-binaries', []);
      expect(r.exit, 0, reason: r.text);
      expect(File(tom('legacy_tool')).existsSync(), isTrue);
      expect(
        File(allDir('testkit_debug.buildkit.json')).existsSync(),
        isTrue,
        reason: 'its stamp goes with it',
      );
      expect(calls.first, [
        '-p',
        'tom_d4rt_generator',
        '-p',
        'tom_reflection_generator',
        ':versioner',
        ':pubget',
        ':compiler',
      ]);
      expect(calls[1], [
        '-p',
        'tom_office_host',
        '-p',
        'tom_test_kit',
        ...binBuildCommands,
      ]);
      expect(File(tom('testkit')).readAsStringSync(), 'new testkit');
      expect(
        File(tom('testkit.buildkit.json')).existsSync(),
        isTrue,
        reason: 'its stamp moves with it',
      );
      expect(File(tom('d4rtgen')).readAsStringSync(), 'new d4rtgen');
      expect(File(tom('reflectiongenerator')).existsSync(), isTrue);
      expect(
        File(tom('libtom_office_host_lok.dylib')).existsSync(),
        isTrue,
        reason: 'an entry\'s other files',
      );
      expect(File(tom('testkit_debug')).existsSync(), isFalse);
      expect(
        File(allDir('testkit_debug')).existsSync(),
        isTrue,
        reason: 'the non-release binary stays in all/',
      );
      expect(selfBuilt, [
        'tom_build_kit:bin/buildkit.dart',
        'tom_build_kit:bin/findproject.dart',
      ]);
      expect(calls[2], [
        '-p',
        'tom_build_kit',
        ':versioner',
        ':pubget',
      ], reason: 'buildkit gets its version stamp before it is compiled');
      expect(
        r.json!['summary']['repositories'],
        6,
        reason: 'the compiled release binaries',
      );
      expect(File(tom('buildkit')).readAsStringSync(), 'new buildkit');
      expect(
        File(tom('buildkit.old')).readAsStringSync(),
        'old buildkit',
        reason: 'set aside, not overwritten',
      );
      expect(Link(tom('bk')).targetSync(), 'buildkit');
      expect(Link(tom('tk')).targetSync(), 'testkit');
      final status = '${git(bin, ['status', '--porcelain', '-uall']).stdout}'
          .split('\n')
          .where((l) => l.isNotEmpty)
          .map((l) => l.substring(3))
          .toSet();
      expect(
        status.every((f) => f.startsWith('tom/$plat/')),
        isTrue,
        reason: '$status',
      );
      expect(
        status,
        containsAll([
          'tom/$plat/testkit',
          'tom/$plat/buildkit',
          'tom/$plat/bk',
          'tom/$plat/d4rtgen',
        ]),
      );
      expect(status, isNot(contains('tom/$plat/testkit_debug')));
      expect(
        status,
        isNot(contains('tom/$plat/buildkit.old')),
        reason: 'ignored',
      );
      expect(codes(r.json), ['bin-not-built']);
      final notBuilt =
          (r.json!['messages'] as List).single['evidence']['binaries'] as List;
      expect(
        notBuilt,
        containsAll([
          'tomspecs: built by the extension (missing on $plat)',
          'pdfium: bundled',
          'suite: built by another tool (missing on $plat)',
        ]),
      );
    },
  );

  test('BK-BIN-5: the next run deletes the .old files [2026-11-25]', () async {
    binaries();
    await bk('skill-build-binaries', []);
    expect(File(tom('buildkit.old')).existsSync(), isTrue);
    final r = await bk('skill-build-binaries', []);
    expect(r.exit, 0, reason: r.text);
    expect(
      File(tom('testkit.old')).existsSync(),
      isFalse,
      reason: 'only buildkit\'s own binaries are swapped',
    );
    expect(
      File(tom('buildkit.old')).readAsStringSync(),
      'new buildkit',
      reason: 'the previous run\'s old one is gone',
    );
  });

  test(
    'BK-BIN-6: the self-swap replaces a RUNNING executable; the running '
    'process goes on; the next run deletes what was set aside [2026-11-25]',
    () async {
      final dir = p.join(base.path, 'swap');
      Directory(dir).createSync();
      final target = p.join(dir, Platform.isWindows ? 'tool.exe' : 'tool');
      final Process running;
      if (Platform.isWindows) {
        // A copy of the Dart VM, running: Windows refuses to overwrite or
        // delete a running executable, but lets it be renamed.
        File(Platform.resolvedExecutable).copySync(target);
        final script = p.join(dir, 'sleep.dart');
        write(
          script,
          'import "dart:io"; void main() => sleep(const Duration(seconds: 20));',
        );
        running = await Process.start(target, [script]);
      } else {
        write(target, '#!/bin/sh\nsleep 20\n');
        Process.runSync('chmod', ['+x', target]);
        running = await Process.start(target, const []);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      write('$target.new', 'replacement');
      binSwapIn('$target.new', target);
      expect(File(target).readAsStringSync(), 'replacement');
      expect(File('$target.old').existsSync(), isTrue);
      expect(File('$target.new').existsSync(), isFalse);
      // Set aside a second time while the first is still in use.
      write('$target.new', 'second');
      binSwapIn('$target.new', target);
      expect(File(target).readAsStringSync(), 'second');
      running.kill();
      await running.exitCode;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(binDeleteOld(dir), greaterThanOrEqualTo(1));
      expect(
        Directory(
          dir,
        ).listSync().map((f) => p.basename(f.path)).where(binIsOld),
        isEmpty,
      );
      expect(binIsOld('buildkit.exe.old'), isTrue);
      expect(binIsOld('buildkit.exe.old.1732'), isTrue);
      expect(binIsOld('buildkit.exe'), isFalse);
    },
  );

  test(
    'BK-BIN-7: :skill-build-all-binaries builds every project; only release '
    'binaries reach tom/, the others are in the ignored all/ [2026-11-25]',
    () async {
      binaries();
      final r = await bk('skill-build-all-binaries', []);
      expect(r.exit, 0, reason: r.text);
      expect(calls[1], binBuildCommands, reason: 'no -p: every project');
      expect(File(allDir('other_tool')).existsSync(), isTrue);
      expect(File(tom('other_tool')).existsSync(), isFalse);
      expect(
        Process.runSync('git', [
          'check-ignore',
          '-q',
          'all/$plat/other_tool',
        ], workingDirectory: bin).exitCode,
        0,
      );
      final status = out(bin, ['status', '--porcelain', '-uall']);
      expect(status, isNot(contains('all/')));
      expect(status, isNot(contains('other_tool')));
      final done = {
        for (final d in (r.json!['done'] as List).cast<Map>())
          d['repository']: d['actions'],
      };
      expect(
        done['all/$plat']!.single,
        contains('other binaries (no release binary; ignored by git)'),
      );
    },
  );

  test('BK-BIN-8: refused without an ignored all/ and without a clone; '
      'nothing is built [2026-11-25]', () async {
    var r = await bk('skill-build-binaries', []);
    expect(r.exit, 2);
    expect(codes(r.json), ['bin-no-clone']);
    binaries(ignoreAll: false);
    r = await bk('skill-build-all-binaries', []);
    expect(r.exit, 2);
    expect(codes(r.json), ['bin-not-ignored']);
    expect(calls, isEmpty);
  });

  test('BK-BIN-9: a failing step and a release binary not written: exit 1, '
      'the rest in place [2026-11-25]', () async {
    binaries();
    skip = {'d4rtgen', 'testkit'};
    failStep = 1;
    final r = await bk('skill-build-binaries', []);
    expect(r.exit, 1, reason: r.text);
    expect(codes(r.json), containsAll(['bin-build-failed', 'bin-missing']));
    expect(
      messages(r.json, 'bin-missing').single['finding'],
      startsWith('d4rtgen (gen/tom_d4rt_generator) was not written'),
    );
    expect(
      File(tom('testkit')).readAsStringSync(),
      'old testkit',
      reason: 'kept: not built this time, still there',
    );
    expect(doneOf(r.json)['tom/$plat/testkit'], [
      'up to date (tools/tom_test_kit: its :compiler had nothing to do)',
    ]);
    expect(File(tom('reflectiongenerator')).existsSync(), isTrue);
  });

  test('BK-BIN-10: on Windows the binaries are .exe and a short name is a Git '
      'Bash script and a .cmd [2026-11-25]', () async {
    binaries();
    outputs['tom_test_kit'] = ['testkit.exe', 'testkit_debug.exe'];
    try {
      final win = p.join(bin, 'tom', 'win32-x64');
      Directory(win).createSync(recursive: true);
      Future<BinStepResult> winBuildkit(
        List<String> args, {
        required Map<String, String> environment,
        required String workingDirectory,
      }) async {
        final dir = p.join(environment['TOM_BINARY_PATH']!, 'win32-x64');
        for (final f in [
          'd4rtgen.exe',
          'reflectiongenerator.exe',
          'testkit.exe',
        ]) {
          write(p.join(dir, f), 'new $f');
        }
        return (exitCode: 0, output: '');
      }

      final run = SkillBinariesBuild(
        set: ReleaseSet.load(ws),
        binaries: bin,
        all: false,
        platform: 'win32-x64',
        buildkit: winBuildkit,
        compileSelf: fakeSelf,
        progress: StringBuffer(),
      );
      await run.run();
      expect(File(p.join(win, 'testkit.exe')).existsSync(), isTrue);
      expect(
        File(p.join(win, 'buildkit.exe')).readAsStringSync(),
        'new buildkit',
      );
      expect(
        File(p.join(win, 'tk')).readAsStringSync(),
        contains('exec "\$(dirname "\$0")/testkit.exe" "\$@"'),
      );
      expect(
        File(p.join(win, 'tk.cmd')).readAsStringSync(),
        '@"%~dp0testkit.exe" %*\r\n',
      );
      expect(
        File(p.join(win, 'bk.cmd')).readAsStringSync(),
        '@"%~dp0buildkit.exe" %*\r\n',
      );
    } finally {
      outputs['tom_test_kit'] = ['testkit', 'testkit_debug'];
    }
  });

  test('BK-BIN-11: :skill-push-binaries commits by platform, rebases onto the '
      'other platforms, this build wins a path both changed; never forced; '
      'an unrelated history is refused [2026-11-25]', () async {
    binaries();
    final other = p.join(base.path, 'other');
    git(base.path, ['clone', '-q', p.join(base.path, 'bin.git'), other]);
    write(p.join(other, 'tom', 'linux-x64', 'testkit'), 'linux build');
    write(p.join(other, 'tom', plat, 'testkit'), 'mac built elsewhere');
    git(other, ['add', '-A']);
    git(other, ['commit', '-qm', 'linux']);
    git(other, ['push', '-q', 'origin', 'main']);

    write(tom('testkit'), 'mac built here');
    var r = await bk('skill-push-binaries', ['-n']);
    expect(r.json!['push']['outcome'], 'would push');
    r = await bk('skill-push-binaries', []);
    expect(r.exit, 0, reason: r.text);
    expect(r.json!['push']['outcome'], 'pushed');
    final remote = p.join(base.path, 'bin.git');
    expect(
      out(base.path, ['--git-dir', remote, 'log', '-1', '--format=%s', 'main']),
      matches(
        RegExp(
          r'^chore: refresh binaries \(darwin-arm64\) at \d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$',
        ),
      ),
    );
    expect(
      out(base.path, ['--git-dir', remote, 'show', 'main:tom/$plat/testkit']),
      'mac built here',
    );
    expect(
      out(base.path, [
        '--git-dir',
        remote,
        'show',
        'main:tom/linux-x64/testkit',
      ]),
      'linux build',
    );

    r = await bk('skill-push-binaries', []);
    expect(r.json!['push']['outcome'], 'no-op');

    final fresh = p.join(base.path, 'fresh');
    git(base.path, ['init', '-q', '-b', 'main', fresh]);
    write(p.join(fresh, 'x'), 'x');
    git(fresh, ['add', '-A']);
    git(fresh, ['commit', '-qm', 'new history']);
    git(fresh, ['push', '-q', '--force', remote, 'main']);
    write(tom('testkit'), 'again');
    r = await bk('skill-push-binaries', []);
    expect(r.exit, 1);
    expect(codes(r.json), ['bin-unrelated']);
    expect(
      out(base.path, ['--git-dir', remote, 'log', '--format=%s', 'main']),
      'new history',
    );
  });

  test('BK-BIN-12: -n plans and changes nothing; the help pages; every '
      'message a topic [2026-11-25]', () async {
    binaries();
    final r = await bk('skill-build-binaries', ['-n'], json: false);
    expect(r.exit, 0, reason: r.text);
    expect(calls, isEmpty);
    expect(
      r.text,
      contains(
        'buildkit -p tom_d4rt_generator -p tom_reflection_generator :versioner :pubget :compiler',
      ),
    );
    expect(r.text, contains('dart compile exe bin/buildkit.dart'));
    expect(File(tom('buildkit')).readAsStringSync(), 'old buildkit');
    for (final c in [
      skillbuildbinariesCommand,
      skillbuildallbinariesCommand,
      skillpushbinariesCommand,
    ]) {
      final help = HelpGenerator.generateCommandHelp(c, tool: buildkitTool);
      for (final o in c.options) {
        expect(help, contains('--${o.name}'));
      }
      expect(help, contains('**Exit Codes**'));
    }
    final topics = buildkitTool.helpTopics.map((t) => t.name).toList();
    for (final d in binAllMessages.definitions) {
      expect(topics.where((t) => t == d.code), hasLength(1), reason: d.code);
    }
  });
}
