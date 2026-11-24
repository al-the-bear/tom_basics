// BK-WSS: `wssetup` sets up the tree after a checkout from repos.yaml, on a
// fixture of bare local repositories (URLs `git@fixture:<name>.git`, mapped
// onto the bare repositories with git's insteadOf). The fixture tree has no
// `.tom`, no `_ai` and no extension configuration.
@TestOn('vm')
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';
import 'package:tom_build_kit/src/wssetup/wssetup.dart';
import 'package:tom_build_kit/src/wssetup/wssetup_tool.dart';

late Directory base;
late Map<String, String> gitEnv;

ProcessResult git(String dir, List<String> args) {
  final r = Process.runSync(
    'git',
    [
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      '-c',
      'init.defaultBranch=main',
      ...args,
    ],
    workingDirectory: dir,
    environment: gitEnv,
  );
  if (r.exitCode != 0) throw StateError('git $args in $dir: ${r.stderr}');
  return r;
}

String head(String dir) => '${git(dir, ['rev-parse', 'HEAD']).stdout}'.trim();

/// A bare repository `remotes/<name>.git` with one commit per entry of
/// [commits] (file name -> content); returns the SHAs, oldest first.
List<String> bare(
  String name,
  List<Map<String, String>> commits, {
  String branch = 'main',
}) {
  final work = Directory(p.join(base.path, 'work', name))
    ..createSync(recursive: true);
  git(work.path, ['init', '-q', '-b', branch]);
  final shas = <String>[];
  for (final files in commits) {
    files.forEach(
      (f, c) => File(p.join(work.path, f))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(c),
    );
    git(work.path, ['add', '-A']);
    git(work.path, ['commit', '-qm', 'c${shas.length}']);
    shas.add(head(work.path));
  }
  final remote = p.join(base.path, 'remotes', '$name.git');
  Directory(p.dirname(remote)).createSync(recursive: true);
  git(base.path, ['clone', '-q', '--bare', work.path, remote]);
  return shas;
}

const _manifest = '''
version: 1
root: {url: git@fixture:root.git, branch: main}
repos:
  - {path: ws, url: git@fixture:ws.git, kind: code, branch: main}
  - {path: ws/libs/lib, url: git@fixture:lib.git, kind: code, branch: dev}
  - {path: ws/up, url: git@fixture:up.git, kind: upstream, pin: PIN}
  - {path: ws/later, url: git@fixture:later.git, kind: code, branch: main, hosts: []}
  - {path: ws/elsewhere, url: git@fixture:elsewhere.git, kind: code, branch: main, hosts: [h2]}
  - {path: other, url: git@fixture:other.git, kind: code, branch: main}
  - {path: _ai, url: git@fixture:ai.git, kind: ai, branch: main}
links:
  - {path: ws/_ai, target: ../_ai}
''';

late String pin;

void main() {
  setUp(() {
    base = Directory(
      Directory.systemTemp.createTempSync('bk_wss_').resolveSymbolicLinksSync(),
    );
    gitEnv = {
      'GIT_CONFIG_COUNT': '1',
      'GIT_CONFIG_KEY_0': 'url.${p.join(base.path, 'remotes')}/.insteadOf',
      'GIT_CONFIG_VALUE_0': 'git@fixture:',
    };
    bare('ws', [
      {'README.md': 'ws\n', '.gitignore': '# kept\n*.log\n'},
    ]);
    bare('lib', [
      {'lib.txt': 'lib\n'},
    ], branch: 'dev');
    final ups = bare('up', [
      {'v.txt': '1\n'},
      {'v.txt': '2\n'},
    ]);
    pin = ups.first;
    for (final name in ['later', 'elsewhere', 'other', 'ai']) {
      bare(name, [
        {'$name.txt': '$name\n'},
      ]);
    }
    bare('root', [
      {
        'repos.yaml': _manifest.replaceAll('PIN', pin),
        '.gitignore': '/ztmp/\n',
      },
    ]);
  });
  tearDown(() => base.deleteSync(recursive: true));

  /// A checkout of the root repository at `<base>/<name>`.
  String rootCheckout([String name = 'tree']) {
    final dir = p.join(base.path, name);
    git(base.path, ['clone', '-q', 'git@fixture:root.git', dir]);
    return dir;
  }

  Future<WssetupResult> run(
    String cwd, {
    String? folder,
    List<String> only = const [],
    bool check = false,
    bool dryRun = false,
  }) => runWssetup(
    WssetupRequest(
      workingDirectory: cwd,
      folder: folder,
      host: 'h1',
      only: only,
      check: check,
      dryRun: dryRun,
      gitEnvironment: gitEnv,
    ),
  );

  List<String> paths(WssetupResult r, String status) => [
    for (final i in r.items)
      if (i.status == status) i.path,
  ];

  test('BK-WSS-1: from a root checkout it sets up the whole tree: every '
      'entry for this host on its branch, the upstream at its pin, the '
      'parents\' ignore blocks [2026-11-18]', () async {
    final tree = rootCheckout();
    final r = await run(tree);
    expect(r.hasFailures, isFalse, reason: r.render());
    expect(r.scope, '');
    expect(paths(r, 'cloned'), ['other', 'ws', 'ws/libs/lib', 'ws/up']);
    expect(
      '${git(p.join(tree, 'ws/libs/lib'), ['symbolic-ref', '--short', 'HEAD']).stdout}'
          .trim(),
      'dev',
    );
    expect(head(p.join(tree, 'ws/up')), pin);
    expect(
      paths(r, 'skipped'),
      containsAll(['_ai', 'ws/later', 'ws/elsewhere']),
    );
    expect(
      Directory(p.join(tree, '_ai')).existsSync(),
      isFalse,
      reason: 'the AI state is the fleet skill\'s',
    );

    expect(
      File(p.join(tree, '.gitignore')).readAsStringSync(),
      '/ztmp/\n\n$wssetupBlockBegin\n/_ai/\n/other/\n/ws/\n$wssetupBlockEnd\n',
    );
    expect(
      File(p.join(tree, 'ws/.gitignore')).readAsStringSync(),
      '# kept\n*.log\n\n$wssetupBlockBegin\n/_ai\n/elsewhere/\n/later/\n/libs/lib/\n/up/\n$wssetupBlockEnd\n',
    );
  });

  test(
    'BK-WSS-2: a second run clones and writes nothing [2026-11-18]',
    () async {
      final tree = rootCheckout();
      await run(tree);
      final before = File(p.join(tree, 'ws/.gitignore')).readAsStringSync();
      final again = await run(tree);
      expect(paths(again, 'cloned'), isEmpty);
      expect(paths(again, 'block written'), isEmpty);
      expect(paths(again, 'exists'), ['other', 'ws', 'ws/libs/lib', 'ws/up']);
      expect(File(p.join(tree, 'ws/.gitignore')).readAsStringSync(), before);
    },
  );

  test('BK-WSS-3: run in a workspace folder it sets up only that folder\'s '
      'repositories [2026-11-18]', () async {
    final tree = rootCheckout();
    git(tree, ['clone', '-q', 'git@fixture:ws.git', 'ws']);
    final r = await run(p.join(tree, 'ws'));
    expect(r.scope, 'ws');
    expect(paths(r, 'cloned'), ['ws/libs/lib', 'ws/up']);
    expect(Directory(p.join(tree, 'other')).existsSync(), isFalse);
    expect(
      File(p.join(tree, '.gitignore')).readAsStringSync(),
      '/ztmp/\n',
      reason: 'the root is no parent inside the folder',
    );
    expect(paths(r, 'block written'), ['ws/.gitignore']);
    // --folder from the root does the same.
    final again = await run(tree, folder: 'ws');
    expect(paths(again, 'cloned'), isEmpty);
  });

  test('BK-WSS-4: --dry-run lists the plan and changes nothing; --check '
      'reports a block instead of writing it [2026-11-18]', () async {
    final tree = rootCheckout();
    final dry = await run(tree, dryRun: true);
    expect(paths(dry, 'would clone'), ['other', 'ws', 'ws/libs/lib', 'ws/up']);
    expect(paths(dry, 'would write block'), ['./.gitignore']);
    expect(Directory(p.join(tree, 'ws')).existsSync(), isFalse);
    expect(File(p.join(tree, '.gitignore')).readAsStringSync(), '/ztmp/\n');

    final checked = await run(tree, check: true);
    expect(paths(checked, 'cloned'), ['other', 'ws', 'ws/libs/lib', 'ws/up']);
    expect(paths(checked, 'block differs'), ['./.gitignore', 'ws/.gitignore']);
    expect(File(p.join(tree, '.gitignore')).readAsStringSync(), '/ztmp/\n');
  });

  test('BK-WSS-5: --only clones an on-demand entry and another host\'s; an '
      'unknown path fails [2026-11-18]', () async {
    final tree = rootCheckout();
    final r = await run(tree, only: ['ws', 'ws/later', 'ws/elsewhere']);
    expect(paths(r, 'cloned'), ['ws', 'ws/elsewhere', 'ws/later']);
    final bad = await run(tree, only: ['ws/nope']);
    expect(paths(bad, 'failed'), ['ws/nope']);
  });

  test('BK-WSS-6: an existing repository is compared, never changed: wrong '
      'branch, wrong origin, upstream off its pin [2026-11-18]', () async {
    final tree = rootCheckout();
    await run(tree);
    git(p.join(tree, 'ws'), ['checkout', '-q', '-b', 'topic']);
    git(p.join(tree, 'other'), [
      'remote',
      'set-url',
      'origin',
      'git@fixture:moved.git',
    ]);
    git(p.join(tree, 'ws/up'), ['checkout', '-q', 'main']);
    final r = await run(tree);
    final differs = {
      for (final i in r.items)
        if (i.status == 'differs') i.path: i.detail,
    };
    expect(differs.keys, unorderedEquals(['ws', 'other', 'ws/up']));
    expect(differs['ws'], contains('on topic, not main'));
    expect(differs['other'], contains('git@fixture:moved.git'));
    expect(differs['ws/up'], contains('not the pin'));
    expect(
      '${git(p.join(tree, 'ws'), ['symbolic-ref', '--short', 'HEAD']).stdout}'
          .trim(),
      'topic',
    );
    expect(r.hasFailures, isFalse);
  });

  test('BK-WSS-7: reduced mode (root .gitmodules): no ignore block is '
      'written [2026-11-18]', () async {
    final tree = rootCheckout();
    File(p.join(tree, '.gitmodules')).writeAsStringSync('');
    final r = await run(tree);
    expect(r.reduced, isTrue);
    expect(paths(r, 'block written'), isEmpty);
    expect(File(p.join(tree, '.gitignore')).readAsStringSync(), '/ztmp/\n');
  });

  test('BK-WSS-8: no repos.yaml is a usage error; an invalid one names its '
      'problems [2026-11-18]', () async {
    await expectLater(
      runWssetup(
        WssetupRequest(workingDirectory: base.path, gitEnvironment: gitEnv),
      ),
      throwsA(isA<WssetupUsageException>()),
    );
    expect(
      () => ReposManifest.parse('''
version: 1
root: {url: git@x:r.git, branch: main}
repos:
  - {path: a, url: git@x:a.git, kind: upstream, branch: main}
  - {path: a, url: nope, kind: code}
  - {path: ../b, url: git@x:b.git, kind: thing, branch: main}
  - {path: a, url: git@x:a2.git, kind: code, branch: main}
'''),
      throwsA(
        isA<ReposManifestException>().having(
          (e) => e.problems.join('\n'),
          'problems',
          allOf(
            contains('pin'),
            contains('`url` is not valid'),
            contains('`branch` missing'),
            contains('unknown kind `thing`'),
            contains('`path` is not valid'),
            contains('a: listed twice'),
          ),
        ),
      ),
    );
  });

  test('BK-WSS-9: the ignore block as tom_repos writes it [2026-11-18]', () {
    expect(
      blockWritten('', ['/a/']),
      '$wssetupBlockBegin\n/a/\n$wssetupBlockEnd\n',
    );
    expect(
      blockWritten('x\n\n\n', ['/a/']),
      'x\n\n$wssetupBlockBegin\n/a/\n$wssetupBlockEnd\n',
    );
    final withBlock = 'x\n\n$wssetupBlockBegin\n/old/\n$wssetupBlockEnd\ny\n';
    expect(
      blockWritten(withBlock, ['/a/', '/b']),
      'x\n\n$wssetupBlockBegin\n/a/\n/b\n$wssetupBlockEnd\n\ny\n',
    );
    expect(
      blockWritten(withBlock, []),
      'x\n\ny\n',
      reason: 'no children: the block goes',
    );
    expect(blockWritten('$wssetupBlockBegin\n/a/\n$wssetupBlockEnd\n', []), '');
  });

  test('BK-WSS-10: wssetup and buildkit :wssetup run the same, with their '
      'options; the run needs no build environment [2026-11-18]', () async {
    final tree = rootCheckout();
    // A failing required-environment check would stop buildkit; :wssetup
    // needs none.
    File(p.join(tree, 'buildkit_master.yaml')).writeAsStringSync('''
required-environment:
  env-variables:
    - name: BK_WSS_SURELY_NOT_SET
      error: not set
''');
    final previous = Directory.current;
    Directory.current = tree;
    try {
      final out = StringBuffer();
      final viaTool = await ToolRunner(
        tool: wssetupTool,
        executors: {'default': WssetupExecutor(out: out)},
        output: StringBuffer(),
      ).run(['-n', '--host', 'h1', '--only', 'ws']);
      expect(viaTool.success, isTrue, reason: '$out');
      expect('$out', contains('would clone'));
      expect('$out', contains('ws'));

      final viaBuildkit = await ToolRunner(
        tool: buildkitTool,
        executors: createBuildkitExecutors(),
        output: StringBuffer(),
      ).run([':wssetup', '-n', '--host', 'h1', '--folder', 'ws']);
      expect(viaBuildkit.success, isTrue, reason: viaBuildkit.errorMessage);
    } finally {
      Directory.current = previous;
    }
  });

  test('BK-WSS-11: --manifest reaches wssetup in both tools, also where the '
      'git traversal options have their own --manifest [2026-11-24]', () async {
    final tree = rootCheckout();
    final kept = Directory(p.join(base.path, 'kept'))..createSync();
    final manifest = File(p.join(kept.path, 'repos.yaml'))
      ..writeAsStringSync(
        File(p.join(tree, 'repos.yaml')).readAsStringSync().replaceFirst(
          'kind: code, branch: main}',
          'kind: code, branch: main} # kept',
        ),
      );
    File(p.join(tree, 'repos.yaml')).deleteSync();
    final previous = Directory.current;
    Directory.current = tree;
    try {
      for (final args in [
        ['-n', '--host', 'h1', '--manifest', manifest.path, '--only', 'ws'],
        ['--manifest', manifest.path, '-n', '--host', 'h1', '--only', 'ws'],
      ]) {
        final out = StringBuffer();
        final viaTool = await ToolRunner(
          tool: wssetupTool,
          executors: {'default': WssetupExecutor(out: out)},
          output: StringBuffer(),
        ).run(args);
        expect(viaTool.success, isTrue, reason: '$args\n$out');
        expect('$out', contains('would clone'), reason: '$args');
      }
      for (final args in [
        [':wssetup', '-n', '--host', 'h1', '--manifest', manifest.path],
        ['--manifest', manifest.path, ':wssetup', '-n', '--host', 'h1'],
      ]) {
        final viaBuildkit = await ToolRunner(
          tool: buildkitTool,
          executors: createBuildkitExecutors(),
          output: StringBuffer(),
        ).run(args);
        expect(
          viaBuildkit.success,
          isTrue,
          reason: '$args ${viaBuildkit.errorMessage}',
        );
      }
    } finally {
      Directory.current = previous;
    }
  });
}
