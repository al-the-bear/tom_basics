/// `buildkit :skill-status`, `:skill-dirty-scan`, `:skill-reconcile-code`
/// against the fleet skills they take over (buildkit_ws_commands.md § 1.6).
///
/// Each test builds the skills' own fixture fleet
/// (`.claude/skills/_lib/fixtures/make_fixture_repos.sh`, two hosts sharing
/// bare remotes) in a temporary folder, never the live workspace. The
/// fixture's repos.yaml names its remotes by path; the schema wants `git@` or
/// `https://` URLs, so the test rewrites them to `git@fixture:<name>.git` and
/// maps that prefix onto the remotes with an `insteadOf` rule of its own git
/// configuration. Then:
///
/// - status and dirty scan: the command's rows are compared with what the
///   skill's script (`status_probe.sh`, `tom_dirty_work.sh --scan`) prints on
///   the same tree, and the fixture tests' expectations are checked on the
///   JSON;
/// - reconcile: the cases of `test_reconcile_code.sh`, with its expectations.
///
/// Without the skills (a tom_build_kit cloned on its own) the tests are
/// skipped.
///
/// Test IDs: BK-SKS-1..3, BK-SKD-1..3, BK-SKR-1..14.
@TestOn('vm')
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:tom_build_kit/src/v2/buildkit_executors.dart';
import 'package:tom_build_kit/src/v2/buildkit_tool.dart';
import 'package:tom_build_kit/src/v2/skill/skill_dirty_scan.dart';
import 'package:tom_build_kit/src/v2/skill/skill_messages.dart';
import 'package:tom_build_kit/src/v2/skill/skill_reconcile_code.dart';
import 'package:tom_build_kit/src/v2/skill/skill_status.dart';

/// `.claude/skills` above this package, or null.
final String? skills = () {
  var dir = Directory.current.absolute.path;
  while (true) {
    final candidate = p.join(dir, '.claude', 'skills');
    if (File(
      p.join(candidate, '_lib', 'fixtures', 'make_fixture_repos.sh'),
    ).existsSync()) {
      return candidate;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}();

final _skip = skills == null
    ? 'the fleet skills (.claude/skills) are not above this package'
    : null;

late Directory base;
late String remotes;
late String h1;
late String h2;
late String upPin;
late Map<String, String> env;
const forkBranch = 'tom/1.0-patches';

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
String head(String dir) => out(dir, ['rev-parse', 'HEAD']);
String originHead(String name, String branch) => out(base.path, [
  '--git-dir',
  p.join(remotes, '$name.git'),
  'rev-parse',
  'refs/heads/$branch',
]);

void write(String path, String text) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsStringSync('$text\n');

void commitFile(String repo, String file, String text, String msg) {
  write(p.join(repo, file), text);
  git(repo, ['add', '--', file]);
  git(repo, ['commit', '-q', '-m', msg]);
}

void pushFrom(String repo, String branch) =>
    git(repo, ['push', '-q', 'origin', 'HEAD:refs/heads/$branch']);

/// Builds the fixture fleet with its URLs rewritten.
void buildFleet() {
  base = Directory(
    Directory.systemTemp.createTempSync('bk_skill_').resolveSymbolicLinksSync(),
  );
  final dest = p.join(base.path, 'fleet');
  remotes = p.join(dest, 'remotes');
  final config = File(p.join(base.path, 'gitconfig'))
    ..writeAsStringSync('''
[user]
\tname = fixture
\temail = fixture@local
[init]
\tdefaultBranch = main
[protocol "file"]
\tallow = always
[url "$remotes/"]
\tinsteadOf = git@fixture:
[merge "generated-newer-wins"]
\tdriver = true
[merge "pubspec-lock-last-changed"]
\tdriver = true
''');
  env = {
    'GIT_CONFIG_GLOBAL': config.path,
    'GIT_CONFIG_NOSYSTEM': '1',
    'TOM_FIXTURE_HERMETIC_GITCONFIG': config.path,
  };
  final built = Process.runSync('bash', [
    p.join(skills!, '_lib', 'fixtures', 'make_fixture_repos.sh'),
    dest,
    '--hosts',
    '2',
  ], environment: env);
  if (built.exitCode != 0) throw StateError('fixture: ${built.stderr}');
  h1 = p.join(dest, 'hosts', 'host1');
  h2 = p.join(dest, 'hosts', 'host2');
  final yaml = File(p.join(h1, 'repos.yaml'));
  yaml.writeAsStringSync(
    yaml.readAsStringSync().replaceAllMapped(
      RegExp('"${RegExp.escape(remotes)}/([a-z0-9]+)\\.git"'),
      (m) => 'git@fixture:${m[1]}.git',
    ),
  );
  upPin = RegExp(
    r'path: up/up, .*pin: ([0-9a-f]{40})',
  ).firstMatch(yaml.readAsStringSync())![1]!;
  git(h1, ['commit', '-q', '-am', 'fixture urls']);
  pushFrom(h1, 'main');
  git(h2, ['pull', '-q', 'origin', 'main']);
}

Future<({int exit, String text, Map<String, dynamic>? json})> bk(
  String host,
  String command,
  List<String> args, {
  bool json = true,
}) async {
  final buffer = StringBuffer();
  final previous = Directory.current;
  Directory.current = host;
  try {
    final result = await ToolRunner(
      tool: buildkitTool,
      executors: {
        ...createBuildkitExecutors(),
        'skill-status': SkillStatusExecutor(out: buffer, gitEnvironment: env),
        'skill-dirty-scan': SkillDirtyScanExecutor(
          out: buffer,
          gitEnvironment: env,
        ),
        'skill-reconcile-code': SkillReconcileExecutor(
          out: buffer,
          gitEnvironment: env,
        ),
      },
      output: StringBuffer(),
    ).run(['-R', host, ':$command', if (json) '--json', ...args]);
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

bool hasMessage(Map<String, dynamic>? json, String code, [String? repo]) =>
    messages(
      json,
      code,
    ).any((m) => repo == null || m['repository']?['path'] == repo);

Map<String, List<String>> doneOf(Map<String, dynamic>? json) {
  final o = <String, List<String>>{};
  for (final d in (json!['done'] as List).cast<Map>()) {
    o.putIfAbsent(d['repository'] as String, () => []).addAll([
      for (final a in d['actions'] as List) '$a',
    ]);
  }
  return o;
}

/// The skill's rows of a script run in [host].
String skillRun(String host, List<String> command, {String? stdin}) {
  final r = Process.runSync(
    'bash',
    command,
    workingDirectory: host,
    environment: {...env, 'TOM_WS_ROOT': host},
  );
  return '${r.stdout}'.trim();
}

/// What `tom_fleet_status` sends to a host: status_probe.sh on stdin with the
/// host's entries.
Future<String> skillProbe(String host) async {
  final entries = Process.runSync('python3', [
    p.join(skills!, '_lib', 'repos.py'),
    p.join(host, 'repos.yaml'),
    '--host',
    'host1',
  ], environment: env);
  final lines = [
    '.|root|main|-',
    for (final l in '${entries.stdout}'.trim().split('\n'))
      if (l.isNotEmpty)
        [
          for (final i in [1, 2, 3, 4]) l.split('\t')[i],
        ].join('|'),
  ];
  String q(String s) => "'${s.replaceAll("'", r"'\''")}'";
  final proc = await Process.start('bash', ['-s'], environment: env);
  proc.stdin.write('TFS_ROOT=${q(host)}\nTFS_ENTRIES=${q(lines.join('\n'))}\n');
  proc.stdin.write(
    File(p.join(skills!, '_lib', 'status_probe.sh')).readAsStringSync(),
  );
  await proc.stdin.close();
  final o = await proc.stdout.transform(utf8.decoder).join();
  await proc.exitCode;
  return o.trim();
}

/// Scan rows with the ages (seconds since a change: they move between two
/// runs) replaced by `A` where a file exists.
String maskAges(String rows) => [
  for (final l in rows.split('\n'))
    if (l.startsWith('DIRTY\t') || l.startsWith('GROUP\t'))
      () {
        final f = l.split('\t');
        if (f[5] != '-1') f[5] = 'A';
        return f.join('\t');
      }()
    else
      l,
].join('\n');

void main() {
  setUp(() {
    if (skills != null) buildFleet();
  });
  tearDown(() {
    if (skills != null) base.deleteSync(recursive: true);
  });

  group('skill-status', skip: _skip, () {
    test('BK-SKS-1: the rows equal status_probe.sh on a tree with a stale, a '
        'behind, an ahead, an off-pin, a missing clone, run branches and an '
        'old tree [2026-11-25]', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      void pushBackdated(String name, String branch, int secs, String f) {
        final w = p.join(base.path, 'push_$name');
        if (!Directory(w).existsSync()) {
          git(base.path, [
            'clone',
            '-q',
            '--branch',
            branch,
            p.join(remotes, '$name.git'),
            w,
          ]);
        }
        write(p.join(w, f), f);
        git(w, ['add', f]);
        final when = '@${now - secs} +0000';
        Process.runSync(
          'git',
          ['commit', '-q', '-m', f],
          workingDirectory: w,
          environment: {
            ...env,
            'GIT_AUTHOR_DATE': when,
            'GIT_COMMITTER_DATE': when,
          },
        );
        git(w, ['push', '-q', 'origin', branch]);
      }

      pushBackdated('lib', 'main', 60 * 86400, 'sixty_days_ago.txt');
      pushBackdated('app', 'main', 600, 'ten_minutes_ago.txt');
      File(
        p.join(h1, 'libs/lib/README.md'),
      ).writeAsStringSync('edit\n', mode: FileMode.append);
      File(
        p.join(h1, 'code/app/inner/README.md'),
      ).writeAsStringSync('wip\n', mode: FileMode.append);
      write(p.join(h1, 'forks/fork/local.txt'), 'local');
      git(p.join(h1, 'forks/fork'), ['add', 'local.txt']);
      git(p.join(h1, 'forks/fork'), ['commit', '-q', '-m', 'never pushed']);
      git(p.join(h1, 'up/up'), [
        'commit',
        '-q',
        '--allow-empty',
        '-m',
        'off the pin',
      ]);
      Directory(p.join(h1, 'bin/tom_binaries')).deleteSync(recursive: true);
      git(p.join(h1, 'code/app'), [
        'worktree',
        'add',
        '-q',
        p.join(h1, '.worktrees/run1/code/app'),
        '-b',
        'run1',
      ]);
      commitFile(
        p.join(h1, '.worktrees/run1/code/app'),
        'run.txt',
        'run',
        'run work',
      );
      git(p.join(h1, 'code/app/inner'), [
        'worktree',
        'add',
        '-q',
        p.join(h1, '.worktrees/run2/code/app/inner'),
        '-b',
        'run2',
      ]);
      write(p.join('${h1}_old', 'sub', 'file'), 'old');

      final probe = await skillProbe(h1);
      final rows = await bk(h1, 'skill-status', ['--rows'], json: false);
      expect(rows.exit, 0);
      expect(
        rows.text.trim(),
        probe,
        reason: 'the same rows as status_probe.sh',
      );

      final r = await bk(h1, 'skill-status', []);
      expect(r.exit, 0, reason: r.text);
      final repos = {
        for (final x in (r.json!['status']['repositories'] as List).cast<Map>())
          x['path']: x,
      };
      expect(repos.keys.first, '.', reason: 'the root first');
      expect(repos['libs/lib']!['behind'], 1);
      expect(repos['libs/lib']!['lagAt'], now - 60 * 86400);
      expect(repos['libs/lib']!['dirty'], 1);
      expect(repos['code/app']!['behind'], 1);
      expect(repos['forks/fork']!['ahead'], 1);
      expect(repos['code/app/inner']!['behind'], 0);
      expect(repos['code/app/inner']!['dirty'], 1);
      expect(repos['up/up']!['state'], 'offpin');
      expect(repos['bin/tom_binaries']!['state'], 'missing');
      expect(repos['.']!['kind'], 'root');
      expect(repos['code/app']!['syncAt'], isA<int>());
      expect(r.json!['status']['probed'], 8);
      final runs = (r.json!['status']['runBranches'] as List).cast<Map>();
      expect(
        runs.single['branch'],
        'run1',
        reason: 'run2 has nothing of its own',
      );
      expect(runs.single['commits'], 1);
      expect(
        (r.json!['status']['oldTrees'] as List).single['sizeKiB'],
        isA<int>(),
      );
      expect(hasMessage(r.json, 'skill-off-pin', 'up/up'), isTrue);
      expect(hasMessage(r.json, 'skill-missing', 'bin/tom_binaries'), isTrue);
      expect(hasMessage(r.json, 'skill-run-branch', 'code/app'), isTrue);
      expect(hasMessage(r.json, 'skill-old-tree'), isTrue);
    });

    test('BK-SKS-2: a branch origin does not have is nobranch, as the probe '
        'says [2026-11-25]', () async {
      final yaml = File(p.join(h1, 'repos.yaml'));
      yaml.writeAsStringSync(
        yaml.readAsStringSync().replaceFirst(
          'path: libs/lib, url: git@fixture:lib.git, kind: code, branch: main',
          'path: libs/lib, url: git@fixture:lib.git, kind: code, branch: nosuch',
        ),
      );
      final rows = await bk(h1, 'skill-status', ['--rows'], json: false);
      expect(rows.text.trim(), await skillProbe(h1));
      final r = await bk(h1, 'skill-status', []);
      expect(hasMessage(r.json, 'skill-no-branch', 'libs/lib'), isTrue);
    });

    test('BK-SKS-3: -n fetches nothing [2026-11-25]', () async {
      commitFile(p.join(h2, 'libs/lib'), 'r.txt', 'r', 'host2');
      pushFrom(p.join(h2, 'libs/lib'), 'main');
      final r = await bk(h1, 'skill-status', ['-n']);
      final lib = (r.json!['status']['repositories'] as List)
          .cast<Map>()
          .firstWhere((x) => x['path'] == 'libs/lib');
      expect(lib['behind'], 0, reason: 'origin/main not fetched');
      final f = await bk(h1, 'skill-status', []);
      expect(
        (f.json!['status']['repositories'] as List).cast<Map>().firstWhere(
          (x) => x['path'] == 'libs/lib',
        )['behind'],
        1,
      );
    });
  });

  group('skill-dirty-scan', skip: _skip, () {
    void dirty() {
      File(p.join(h1, 'libs/lib/README.md')).writeAsStringSync('changed\n');
      write(p.join(h1, 'libs/lib/added.txt'), 'new');
      write(
        p.join(h1, 'code/app/lib/app.versioner.dart'),
        'const buildNumber = 9;',
      );
      write(p.join(h1, 'code/app/.env'), 'SECRET=1');
      File(
        p.join(h1, 'code/app/inner/README.md'),
      ).writeAsStringSync('inner edit\n');
      File(p.join(h1, 'up/up/README.md')).writeAsStringSync('upstream edit\n');
      write(p.join(h1, 'note.md'), 'root note');
      write(p.join(h1, 'state/_ai/x.md'), 'ai');
      write(p.join(h1, 'bin/tom_binaries/x.txt'), 'bin');
      git(p.join(h1, 'code/app'), [
        'worktree',
        'add',
        '-q',
        p.join(h1, '.worktrees/run1/code/app'),
        '-b',
        'run1',
      ]);
      File(
        p.join(h1, '.worktrees/run1/code/app/lib/app.versioner.dart'),
      ).writeAsStringSync('x\n');
      write(p.join(h1, '.worktrees/run1/code/app/run.txt'), 'r');
      Directory(p.join(h1, 'stray/repo')).createSync(recursive: true);
      git(p.join(h1, 'stray/repo'), ['init', '-q']);
      write(p.join(h1, 'stray/repo/f.txt'), 'f');
    }

    test('BK-SKD-1: the rows equal tom_dirty_work --scan: groups, '
        'fingerprints, run worktrees, unknown, SCANNED [2026-11-25]', () async {
      dirty();
      final skill = skillRun(h1, [
        p.join(skills!, 'tom_dirty_work', 'tom_dirty_work.sh'),
        '--scan',
      ]);
      final rows = await bk(h1, 'skill-dirty-scan', ['--rows'], json: false);
      expect(rows.exit, 0);
      expect(
        maskAges(rows.text.trim()),
        maskAges(skill),
        reason: 'the same rows (ages aside)',
      );

      final r = await bk(h1, 'skill-dirty-scan', []);
      expect(r.exit, 0, reason: r.text);
      final scan = r.json!['scan'] as Map;
      expect(
        scan['scanned'],
        7,
        reason: '5 clones of code/fork/upstream + the run tree + the root',
      );
      Map<String, List<String>> files(String repo) => {
        for (final g
            in ((scan['repositories'] as List).cast<Map>().firstWhere(
                      (x) => x['path'] == repo,
                    )['groups']
                    as List)
                .cast<Map>())
          g['group'] as String: [
            for (final f in (g['files'] as List).cast<Map>())
              f['path'] as String,
          ],
      };
      expect(files('libs/lib'), {
        'modified': ['README.md'],
        'new': ['added.txt'],
      });
      expect(files('code/app'), {
        'secret': ['.env'],
        'generated': ['lib/app.versioner.dart'],
      });
      expect(files('code/app/inner'), {
        'modified': ['README.md'],
      });
      expect(files('up/up'), {
        'modified': ['README.md'],
      });
      expect(files('host1'), {
        'new': ['note.md'],
      }, reason: "the root's own file, none of its clones");
      expect(files('.worktrees/run1/code/app'), {
        'generated': ['lib/app.versioner.dart'],
        'new': ['run.txt'],
      });
      final paths = [
        for (final x in (scan['repositories'] as List).cast<Map>()) x['path'],
      ];
      expect(paths, isNot(contains('state/_ai')));
      expect(paths, isNot(contains('bin/tom_binaries')));
      expect(scan['unknown'], ['stray/repo']);
      expect(hasMessage(r.json, 'skill-uncommitted', 'libs/lib'), isTrue);
      expect(hasMessage(r.json, 'skill-unknown-seen'), isTrue);
    });

    test('BK-SKD-2: a fingerprint moves only with its own group '
        '[2026-11-25]', () async {
      dirty();
      String fp(Map<String, dynamic>? j, String group) =>
          (((j!['scan']['repositories'] as List).cast<Map>().firstWhere(
                        (x) => x['path'] == 'libs/lib',
                      )['groups']
                      as List)
                  .cast<Map>()
                  .firstWhere((g) => g['group'] == group))['fingerprint']
              as String;
      final a = (await bk(h1, 'skill-dirty-scan', [])).json;
      write(p.join(h1, 'libs/lib/added2.txt'), 'more');
      final b = (await bk(h1, 'skill-dirty-scan', [])).json;
      expect(fp(a, 'modified'), fp(b, 'modified'));
      expect(fp(a, 'new'), isNot(fp(b, 'new')));
    });

    test('BK-SKD-3: --baseline records what tom_dirty_work --baseline '
        'records [2026-11-25]', () async {
      dirty();
      skillRun(h1, [
        p.join(skills!, 'tom_dirty_work', 'tom_dirty_work.sh'),
        '--baseline',
        p.join(h1, 'ztmp', 'skill.tsv'),
      ]);
      final r = await bk(h1, 'skill-dirty-scan', [
        '--baseline',
        'ztmp/bk.tsv',
      ], json: false);
      expect(r.exit, 0, reason: r.text);
      Set<String> lines(String f) => File(
        p.join(h1, 'ztmp', f),
      ).readAsLinesSync().where((l) => l.isNotEmpty).toSet();
      expect(lines('bk.tsv'), lines('skill.tsv'));
    });
  });

  group('skill-reconcile-code', skip: _skip, () {
    Future<({int exit, String text, Map<String, dynamic>? json})> recon(
      String host, [
      List<String> args = const [],
    ]) => bk(host, 'skill-reconcile-code', args);

    test('BK-SKR-1: converge: a local and a remote commit end up on origin '
        'and on both hosts [2026-11-25]', () async {
      commitFile(
        p.join(h2, 'libs/lib'),
        'remote.txt',
        'from host2',
        'host2 change',
      );
      pushFrom(p.join(h2, 'libs/lib'), 'main');
      commitFile(
        p.join(h1, 'libs/lib'),
        'local.txt',
        'from host1',
        'host1 change',
      );
      var r = await recon(h1);
      expect(r.exit, 0, reason: r.text);
      final log = out(base.path, [
        '--git-dir',
        p.join(remotes, 'lib.git'),
        'log',
        '--format=%s',
        'main',
      ]);
      expect(log, allOf(contains('host1 change'), contains('host2 change')));
      expect(head(p.join(h1, 'libs/lib')), originHead('lib', 'main'));
      final done = doneOf(r.json);
      expect(
        done.keys,
        contains('libs/lib'),
        reason: 'the changed repository is named',
      );
      expect(
        done.keys,
        isNot(contains('code/app')),
        reason: 'the level ones are not',
      );
      expect(done['libs/lib'], [
        'took in 1 commit(s) from origin/main',
        'pushed 2 commit(s)',
      ]);
      r = await recon(h2);
      expect(r.exit, 0, reason: r.text);
      expect(head(p.join(h2, 'libs/lib')), originHead('lib', 'main'));
    });

    test('BK-SKR-2: ask: a lone run with uncommitted work exits 3 and '
        'changes nothing [2026-11-25]', () async {
      commitFile(
        p.join(h2, 'libs/lib'),
        'README.md',
        'remote readme',
        'host2 readme',
      );
      pushFrom(p.join(h2, 'libs/lib'), 'main');
      final before = head(p.join(h1, 'libs/lib'));
      File(p.join(h1, 'libs/lib/README.md')).writeAsStringSync('local edit\n');
      final r = await recon(h1);
      expect(r.exit, 3, reason: r.text);
      final m = messages(r.json, 'skill-decision').single;
      expect(m['evidence']['libs/lib'], [startsWith('modified: 1 (')]);
      expect(
        (m['options'] as List).single['commandLine'],
        'buildkit :skill-reconcile-code --dirty=hold',
      );
      expect(head(p.join(h1, 'libs/lib')), before);
      expect(
        File(p.join(h1, 'libs/lib/README.md')).readAsStringSync(),
        'local edit\n',
      );
    });

    test('BK-SKR-3: hold: the repository the merge would overwrite is held, '
        'the others reconciled; exit 0 [2026-11-25]', () async {
      commitFile(
        p.join(h2, 'libs/lib'),
        'README.md',
        'remote readme',
        'host2 readme',
      );
      pushFrom(p.join(h2, 'libs/lib'), 'main');
      commitFile(p.join(h2, 'code/app'), 'other.txt', 'x', 'host2 app');
      pushFrom(p.join(h2, 'code/app'), 'main');
      final before = head(p.join(h1, 'libs/lib'));
      File(p.join(h1, 'libs/lib/README.md')).writeAsStringSync('local edit\n');
      final r = await recon(h1, ['--dirty=hold']);
      expect(r.exit, 0, reason: r.text);
      expect(head(p.join(h1, 'libs/lib')), before);
      expect(
        messages(r.json, 'skill-held')
            .where((m) => m['repository']['path'] == 'libs/lib')
            .map((m) => m['finding']),
        contains(
          contains('the incoming 1 commit(s) would overwrite - not merged'),
        ),
      );
      expect(
        File(p.join(h1, 'libs/lib/README.md')).readAsStringSync(),
        'local edit\n',
      );
      expect(
        out(base.path, [
          '--git-dir',
          p.join(remotes, 'lib.git'),
          'log',
          '--format=%B',
          'main',
        ]),
        isNot(contains('local edit')),
      );
      expect(head(p.join(h1, 'code/app')), originHead('app', 'main'));
    });

    test('BK-SKR-4: staged: a file another session staged is not swept into '
        'a commit [2026-11-25]', () async {
      commitFile(
        p.join(h1, 'libs/lib'),
        'mine.txt',
        'mine',
        'host1 own commit',
      );
      write(p.join(h1, 'libs/lib/theirs.txt'), 'other session');
      git(p.join(h1, 'libs/lib'), ['add', 'theirs.txt']);
      final r = await recon(h1, ['--dirty=hold']);
      expect(r.exit, 0, reason: r.text);
      expect(head(p.join(h1, 'libs/lib')), originHead('lib', 'main'));
      expect(
        out(p.join(h1, 'libs/lib'), ['diff', '--cached', '--name-only']),
        'theirs.txt',
      );
      expect(
        Process.runSync('git', [
          '--git-dir',
          p.join(remotes, 'lib.git'),
          'cat-file',
          '-e',
          'main:theirs.txt',
        ], environment: env).exitCode,
        isNot(0),
      );
    });

    test('BK-SKR-5: own_since: a file written after the baseline is '
        'committed and pushed, one from before is not [2026-11-25]', () async {
      write(p.join(h1, 'libs/lib/before.txt'), 'before');
      final b = await bk(h1, 'skill-dirty-scan', [
        '--baseline',
        'ztmp/base.tsv',
      ], json: false);
      expect(b.exit, 0, reason: b.text);
      write(p.join(h1, 'libs/lib/built.txt'), 'built');
      final r = await recon(h1, ['--dirty=hold', '--own-since=ztmp/base.tsv']);
      expect(r.exit, 0, reason: r.text);
      bool onOrigin(String f) =>
          Process.runSync('git', [
            '--git-dir',
            p.join(remotes, 'lib.git'),
            'cat-file',
            '-e',
            'main:$f',
          ], environment: env).exitCode ==
          0;
      expect(onOrigin('built.txt'), isTrue);
      expect(onOrigin('before.txt'), isFalse);
      expect(
        out(p.join(h1, 'libs/lib'), ['status', '--porcelain', 'before.txt']),
        '?? before.txt',
      );
      expect(
        doneOf(r.json)['libs/lib'],
        contains(
          'committed 1 path(s) this run wrote (since the --own-since baseline)',
        ),
      );
    });

    test('BK-SKR-6: fork: fast-forwarded when behind; diverged is reported '
        '(exit 1) and not merged [2026-11-25]', () async {
      final fork1 = p.join(h1, 'forks/fork'), fork2 = p.join(h2, 'forks/fork');
      commitFile(fork2, 'patch2.txt', 'p2', 'host2 patch');
      pushFrom(fork2, forkBranch);
      var r = await recon(h1);
      expect(r.exit, 0, reason: r.text);
      expect(head(fork1), originHead('fork', forkBranch));
      commitFile(fork2, 'patch3.txt', 'p3', 'host2 patch 3');
      pushFrom(fork2, forkBranch);
      commitFile(fork1, 'local.txt', 'l', 'host1 diverging patch');
      final before = head(fork1);
      r = await recon(h1);
      expect(r.exit, 1, reason: r.text);
      expect(
        messages(r.json, 'skill-failed').single['finding'],
        startsWith('fork has diverged'),
      );
      expect(
        messages(r.json, 'skill-failed').single['repository']['path'],
        'forks/fork',
      );
      expect(head(fork1), before);
      expect(out(fork1, ['rev-list', '--merges', 'HEAD']), isEmpty);
    });

    test(
      'BK-SKR-7: an upstream off its pin is put back [2026-11-25]',
      () async {
        commitFile(p.join(h1, 'up/up'), 'x.txt', 'x', 'off-pin');
        final r = await recon(h1);
        expect(r.exit, 0, reason: r.text);
        expect(head(p.join(h1, 'up/up')), upPin);
        expect(doneOf(r.json)['up/up'], [
          'moved to its pin ${upPin.substring(0, 12)}',
        ]);
      },
    );

    test(
      'BK-SKR-8: a missing entry is cloned and reported [2026-11-25]',
      () async {
        Directory(p.join(h1, 'libs/lib')).deleteSync(recursive: true);
        final r = await recon(h1);
        expect(r.exit, 0, reason: r.text);
        expect(Directory(p.join(h1, 'libs/lib/.git')).existsSync(), isTrue);
        expect(doneOf(r.json)['libs/lib'], ['cloned (it was missing)']);
      },
    );

    test('BK-SKR-9: an unknown repository stops the run (exit 1) before '
        'anything is touched [2026-11-25]', () async {
      commitFile(p.join(h2, 'libs/lib'), 'remote.txt', 'r', 'host2 change');
      pushFrom(p.join(h2, 'libs/lib'), 'main');
      final before = head(p.join(h1, 'libs/lib'));
      git(h1, ['init', '-q', p.join(h1, 'libs/stray')]);
      final r = await recon(h1);
      expect(r.exit, 1, reason: r.text);
      expect(messages(r.json, 'skill-unknown').single['evidence']['paths'], [
        'libs/stray',
      ]);
      expect(head(p.join(h1, 'libs/lib')), before);
    });

    test(
      'BK-SKR-10: -n takes nothing in and pushes nothing [2026-11-25]',
      () async {
        commitFile(p.join(h2, 'libs/lib'), 'remote.txt', 'r', 'host2 change');
        pushFrom(p.join(h2, 'libs/lib'), 'main');
        git(p.join(h1, 'libs/lib'), ['fetch', '-q']);
        commitFile(p.join(h1, 'code/app'), 'local.txt', 'l', 'host1 change');
        final lib = head(p.join(h1, 'libs/lib')),
            app = originHead('app', 'main');
        final r = await recon(h1, ['-n']);
        expect(r.exit, 0, reason: r.text);
        expect(head(p.join(h1, 'libs/lib')), lib);
        expect(originHead('app', 'main'), app);
        expect(doneOf(r.json)['libs/lib'], ['would take in 1 commit(s)']);
        expect(doneOf(r.json)['code/app'], ['would push 1 commit(s)']);
      },
    );

    test('BK-SKR-11: quiet: a level host changes nothing, exit 0 '
        '[2026-11-25]', () async {
      var r = await recon(h1);
      expect(r.exit, 0, reason: r.text);
      r = await recon(h1);
      expect(r.exit, 0);
      expect(r.json!['done'], isEmpty);
      expect(
        r.json!['reconcile']['repositories'],
        6,
        reason: '5 code/fork/upstream entries + the root',
      );
    });

    test('BK-SKR-12: unregistered merge drivers stop the run (exit 1) '
        '[2026-11-25]', () async {
      final config = File(env['GIT_CONFIG_GLOBAL']!);
      config.writeAsStringSync(
        config.readAsStringSync().replaceAll(
          '[merge "pubspec-lock-last-changed"]\n\tdriver = true\n',
          '',
        ),
      );
      final r = await recon(h1, ['--dirty=hold']);
      expect(r.exit, 1, reason: r.text);
      expect(messages(r.json, 'skill-driver').single['evidence']['drivers'], [
        'pubspec-lock-last-changed',
      ]);
    });

    test('BK-SKR-13: a conflicting merge is aborted and fails (exit 1); a '
        'usage error is exit 2 [2026-11-25]', () async {
      commitFile(p.join(h2, 'libs/lib'), 'README.md', 'theirs', 'host2 readme');
      pushFrom(p.join(h2, 'libs/lib'), 'main');
      commitFile(p.join(h1, 'libs/lib'), 'README.md', 'ours', 'host1 readme');
      var r = await recon(h1);
      expect(r.exit, 1, reason: r.text);
      expect(
        messages(r.json, 'skill-failed').single['finding'],
        contains('conflicts (README.md) - aborted'),
      );
      expect(
        File(p.join(h1, 'libs/lib/.git/MERGE_HEAD')).existsSync(),
        isFalse,
      );
      r = await recon(h1, ['--dirty=maybe']);
      expect(r.exit, 2);
      r = await recon(h1, ['--own-since=ztmp/none.tsv']);
      expect(r.exit, 2);
    });

    test('BK-SKR-14: the help pages list every option and the exit codes; '
        'every message and skill-json are topics [2026-11-25]', () {
      for (final (cmd, opts) in [
        (skillreconcileCommand, skillreconcileOptions),
        (skillstatusCommand, skillstatusOptions),
        (skilldirtyscanCommand, skilldirtyscanOptions),
      ]) {
        final help = HelpGenerator.generateCommandHelp(cmd, tool: buildkitTool);
        for (final o in opts) {
          expect(
            help,
            contains('--${o.name}'),
            reason: '${cmd.name} --${o.name}',
          );
        }
        expect(help, contains('**Exit Codes**'));
      }
      final topics = buildkitTool.helpTopics.map((t) => t.name).toList();
      for (final d in skillAllMessages.definitions) {
        expect(topics.where((t) => t == d.code), hasLength(1), reason: d.code);
      }
      expect(topics, contains('skill-json'));
      expect(
        HelpGenerator.generateCommandHelp(
          skillreconcileCommand,
          tool: buildkitTool,
        ),
        contains('3'),
      );
    });
  });
}
