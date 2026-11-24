/// `buildkit :ws-repo-cleanup` on a tree of real repositories with bare
/// remotes, made by each test in a temporary folder (never the live
/// workspace): a root with repos.yaml, an entry, `_ai`, and surplus clones of
/// each kind — removable, dirty, unpushed, with a stash, one holding another
/// clone, one holding an entry — plus a clone under `_ai` that is never
/// touched.
///
/// Test IDs: BK-WSR-1..9.
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
import 'package:tom_build_kit/src/v2/ws/ws_messages.dart';
import 'package:tom_build_kit/src/v2/ws/ws_repo_cleanup.dart';

late Directory base;
late String root;
late Map<String, String> env;
final _now = DateTime(2026, 11, 24, 16, 2);
const _folder = 'ztmp/261124_ws_repo_cleanup';

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

void write(String path, String text) => File(path)
  ..parent.createSync(recursive: true)
  ..writeAsStringSync(text);

String at(String rel) => p.join(root, p.joinAll(rel.split('/')));
bool exists(String rel) => Directory(at(rel)).existsSync();

/// A bare remote with one commit, cloned at [rel] under the root.
void repo(String name, String rel) {
  final seed = p.join(base.path, 'seed', name);
  Directory(seed).createSync(recursive: true);
  git(seed, ['init', '-q', '-b', 'main']);
  write(p.join(seed, 'README.md'), '$name\n');
  git(seed, ['add', '-A']);
  git(seed, ['commit', '-qm', 'init $name']);
  final remote = p.join(base.path, 'remotes', '$name.git');
  Directory(p.dirname(remote)).createSync(recursive: true);
  git(base.path, ['clone', '-q', '--bare', seed, remote]);
  git(base.path, [
    'clone',
    '-q',
    'git@fixture:$name.git',
    rel.isEmpty ? root : at(rel),
  ]);
}

Future<({int exit, String text, Map<String, dynamic>? json})> cleanup(
  List<String> args, {
  bool json = true,
}) async {
  final buffer = StringBuffer();
  final previous = Directory.current;
  Directory.current = root;
  try {
    final result = await ToolRunner(
      tool: buildkitTool,
      executors: {
        ...createBuildkitExecutors(),
        'ws-repo-cleanup': WsRepoCleanupExecutor(
          out: buffer,
          now: _now,
          gitEnvironment: env,
        ),
      },
      output: StringBuffer(),
    ).run(['-R', root, ':ws-repo-cleanup', if (json) '--json', ...args]);
    final text = "$buffer";
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

Map<String, dynamic> message(
  Map<String, dynamic>? json,
  String code,
  String repo,
) {
  final found = messages(
    json,
    code,
  ).where((m) => m['repository']?['path'] == repo);
  expect(
    found,
    hasLength(1),
    reason: '$code $repo in ${jsonEncode(json!['messages'])}',
  );
  return found.single;
}

List<String> optionsOf(Map<String, dynamic> m) => [
  for (final o in (m['options'] as List).cast<Map>()) o['option'] as String,
];

String commandLineOf(Map<String, dynamic> m, String flag) =>
    (m['options'] as List).cast<Map>().firstWhere(
          (o) => (o['option'] as String).startsWith(flag),
        )['commandLine']
        as String;

Map<String, List<String>> doneOf(Map<String, dynamic>? json) {
  final out = <String, List<String>>{};
  for (final d in (json!['done'] as List).cast<Map>()) {
    out.putIfAbsent(d['repository'] as String, () => []).addAll([
      for (final a in d['actions'] as List) '$a',
    ]);
  }
  return out;
}

/// Every repository the report names.
Set<String> named(Map<String, dynamic>? json) => {
  for (final m in (json!['messages'] as List).cast<Map>())
    if (m['repository'] != null) (m['repository'] as Map)['path'] as String,
  ...doneOf(json).keys,
};

void main() {
  setUp(() {
    base = Directory(
      Directory.systemTemp.createTempSync('bk_wsr_').resolveSymbolicLinksSync(),
    );
    root = p.join(base.path, 'tree');
    final config = File(p.join(base.path, 'gitconfig'))
      ..writeAsStringSync('''
[user]
\tname = t
\temail = t@t
[init]
\tdefaultBranch = main
[url "${base.path}/remotes/"]
\tinsteadOf = git@fixture:
''');
    env = {'GIT_CONFIG_GLOBAL': config.path, 'GIT_CONFIG_NOSYSTEM': '1'};
    repo('root', '');
    repo('ai', '_ai');
    repo('core', 'tom_ai/core');
    // Surplus clones.
    repo('clean', 'old/clean');
    git(at('old/clean'), ['branch', 'extra']);
    repo('dirty', 'old/dirty');
    write(p.join(at('old/dirty'), 'wip.txt'), 'wip\n');
    repo('unpushed', 'old/unpushed');
    write(p.join(at('old/unpushed'), 'x.txt'), 'x\n');
    git(at('old/unpushed'), ['add', '-A']);
    git(at('old/unpushed'), ['commit', '-qm', 'local only']);
    repo('stashed', 'old/stashed');
    write(p.join(at('old/stashed'), 'README.md'), 'changed\n');
    git(at('old/stashed'), ['stash', '-q']);
    repo('nest', 'nest');
    repo('inner', 'nest/inner');
    repo('outer', 'outer');
    repo('entry', 'outer/entry');
    repo('aiclone', '_ai/scratch/aiclone');
    write(p.join(root, 'repos.yaml'), '''
version: 1
root: {url: git@fixture:root.git, branch: main}
repos:
  - {path: tom_ai/core, url: git@fixture:core.git, kind: code, branch: main}
  - {path: outer/entry, url: git@fixture:entry.git, kind: code, branch: main}
  - {path: _ai, url: git@fixture:ai.git, kind: ai, branch: main}
''');
    write(
      p.join(root, '.gitignore'),
      '/_ai/\n/tom_ai/\n/old/\n/nest/\n/outer/\n/ztmp/\n',
    );
    git(root, ['add', '-A']);
    git(root, ['commit', '-qm', 'manifest']);
  });
  tearDown(() => base.deleteSync(recursive: true));

  test(
    'BK-WSR-1: the report names every surplus clone with its state and '
    'options; nothing changes; nothing under _ai is named [2026-11-24]',
    () async {
      final r = await cleanup([]);
      expect(r.exit, 1, reason: r.text);
      expect(named(r.json), {
        'old/clean',
        'old/dirty',
        'old/unpushed',
        'old/stashed',
        'nest',
        'nest/inner',
        'outer',
      });

      final clean = message(r.json, 'ws-surplus', 'old/clean');
      expect(clean['evidence']['origin'], ['git@fixture:clean.git']);
      expect(clean['evidence']['branch'], ['main']);
      expect(clean['evidence']['branches'], [
        'extra',
      ], reason: 'a branch without upstream');
      expect(optionsOf(clean), ['--apply', '--delete']);
      expect(
        commandLineOf(clean, '--apply'),
        'buildkit :ws-repo-cleanup --apply',
      );
      expect(
        commandLineOf(clean, '--delete'),
        'buildkit :ws-repo-cleanup --delete',
      );
      expect(
        (clean['options'] as List).cast<Map>().first['explanation'],
        contains('$_folder/old/clean'),
      );

      final dirty = message(r.json, 'ws-not-removable', 'old/dirty');
      expect(dirty['evidence']['files'], ['?? wip.txt']);
      expect(dirty['finding'], contains('1 uncommitted file(s)'));
      expect(optionsOf(dirty), ['--force-remove dirty', '--skip dirty']);
      expect(
        commandLineOf(dirty, '--force-remove'),
        'buildkit :ws-repo-cleanup --force-remove dirty',
      );
      expect(
        (dirty['options'] as List).cast<Map>().first['explanation'],
        contains('buildkit :ws-push --include-unknown dirty'),
      );

      final unpushed = message(r.json, 'ws-not-removable', 'old/unpushed');
      expect(unpushed['evidence']['commits'].single, contains('local only'));
      final stashed = message(r.json, 'ws-not-removable', 'old/stashed');
      expect(stashed['evidence']['stashes'].single, contains('stash@{0}'));

      final nest = message(r.json, 'ws-not-removable', 'nest');
      expect(nest['evidence']['inside'], ['nest/inner']);
      expect(nest['finding'], contains('never moved as a whole'));
      expect(optionsOf(nest), [
        '--skip nest',
      ], reason: 'no --force-remove for a nest');
      expect(
        message(r.json, 'ws-not-removable', 'outer')['evidence']['inside'],
        ['outer/entry'],
      );
      message(r.json, 'ws-surplus', 'nest/inner');

      expect(r.json!['done'], isEmpty);
      for (final rel in [
        'old/clean',
        'old/dirty',
        'nest',
        'outer',
        '_ai/scratch/aiclone',
      ]) {
        expect(exists(rel), isTrue, reason: rel);
      }
      expect(exists('ztmp'), isFalse);
    },
  );

  test('BK-WSR-2: a tree whose surplus clones are all removable reports '
      'warnings only: exit 0 [2026-11-24]', () async {
    for (final rel in [
      'old/dirty',
      'old/unpushed',
      'old/stashed',
      'nest',
      'outer',
    ]) {
      Directory(at(rel)).deleteSync(recursive: true);
    }
    final r = await cleanup([]);
    expect(r.exit, 0, reason: r.text);
    expect(messages(r.json, 'ws-surplus'), hasLength(1));
  });

  test(
    'BK-WSR-3: --apply moves only the removable clones to '
    'ztmp/<yymmdd>_ws_repo_cleanup/<path>; _ai untouched [2026-11-24]',
    () async {
      final r = await cleanup(['--apply']);
      expect(r.exit, 1, reason: r.text);
      expect(exists('old/clean'), isFalse);
      expect(exists('$_folder/old/clean'), isTrue);
      expect(
        File(p.join(at('$_folder/old/clean'), 'README.md')).existsSync(),
        isTrue,
      );
      expect(exists('nest/inner'), isFalse);
      expect(exists('$_folder/nest/inner'), isTrue);
      for (final rel in [
        'old/dirty',
        'old/unpushed',
        'old/stashed',
        'nest',
        'outer',
        'outer/entry',
        '_ai/scratch/aiclone',
      ]) {
        expect(exists(rel), isTrue, reason: '$rel stays');
      }
      expect(doneOf(r.json)['old/clean'], ['moved to $_folder/old/clean']);
      expect(messages(r.json, 'ws-not-removable'), hasLength(5));

      // A second run never looks into ztmp/; nest, empty of repositories
      // now and clean, is moved (beside the nest/inner already there).
      final again = await cleanup(['--apply']);
      expect(doneOf(again.json), {
        'nest': ['moved to $_folder/nest-2'],
      });
      expect(exists('$_folder/nest/inner'), isTrue);
      expect(exists('outer'), isTrue, reason: 'still holds its entry');
    },
  );

  test('BK-WSR-4: --apply --delete and --delete delete only the removable '
      'clones [2026-11-24]', () async {
    var r = await cleanup(['--apply', '--delete']);
    expect(r.exit, 1, reason: r.text);
    expect(exists('old/clean'), isFalse);
    expect(exists('nest/inner'), isFalse);
    expect(exists('ztmp'), isFalse, reason: 'deleted, not moved');
    expect(doneOf(r.json)['old/clean'], ['deleted']);
    for (final rel in [
      'old/dirty',
      'old/unpushed',
      'old/stashed',
      'nest',
      'outer',
      '_ai/scratch/aiclone',
    ]) {
      expect(exists(rel), isTrue, reason: '$rel stays');
    }

    repo('clean2', 'old/clean2');
    r = await cleanup(['--delete']);
    expect(exists('old/clean2'), isFalse);
    expect(doneOf(r.json)['old/clean2'], ['deleted']);
  });

  test(
    'BK-WSR-5: --force-remove moves a dirty clone with its work, also '
    'with --delete; never a clone with repositories inside [2026-11-24]',
    () async {
      final r = await cleanup([
        '--apply',
        '--delete',
        '--force-remove',
        'dirty,unpushed,nest',
      ]);
      expect(exists('old/dirty'), isFalse);
      expect(
        File(p.join(at('$_folder/old/dirty'), 'wip.txt')).readAsStringSync(),
        'wip\n',
      );
      expect(exists('$_folder/old/unpushed'), isTrue);
      expect(doneOf(r.json)['old/dirty'], [
        'moved to $_folder/old/dirty with its work (--force-remove)',
      ]);
      expect(exists('nest'), isTrue, reason: 'never moved as a whole');
      message(r.json, 'ws-not-removable', 'nest');
      expect(exists('old/stashed'), isTrue, reason: 'not named');
    },
  );

  test(
    'BK-WSR-6: -n shows the plan and changes nothing [2026-11-24]',
    () async {
      final r = await cleanup(['--apply', '-n', '--force-remove', 'dirty']);
      expect(doneOf(r.json)['old/clean'], ['would move to $_folder/old/clean']);
      expect(doneOf(r.json)['old/dirty'], [
        'would move to $_folder/old/dirty with its work (--force-remove)',
      ]);
      expect(exists('old/clean'), isTrue);
      expect(exists('old/dirty'), isTrue);
      expect(exists('ztmp'), isFalse);
    },
  );

  test(
    'BK-WSR-7: a target already taken gets a free name [2026-11-24]',
    () async {
      Directory(at('$_folder/old/clean')).createSync(recursive: true);
      final r = await cleanup(['--apply']);
      expect(doneOf(r.json)['old/clean'], ['moved to $_folder/old/clean-2']);
      expect(exists('$_folder/old/clean-2'), isTrue);
    },
  );

  test(
    'BK-WSR-8: --skip leaves a clone out (exit 1); an unknown name is a '
    'usage error (exit 2); no repos.yaml is ws-manifest [2026-11-24]',
    () async {
      for (final rel in [
        'old/dirty',
        'old/unpushed',
        'old/stashed',
        'nest',
        'outer',
      ]) {
        Directory(at(rel)).deleteSync(recursive: true);
      }
      var r = await cleanup(['--apply', '--skip', 'clean']);
      expect(r.exit, 1);
      expect(exists('old/clean'), isTrue);

      r = await cleanup(['--skip', 'nosuch'], json: false);
      expect(r.exit, 2);
      expect(r.text, contains('nosuch'));

      File(p.join(root, 'repos.yaml')).deleteSync();
      r = await cleanup([]);
      expect(r.exit, 2);
      expect(messages(r.json, 'ws-manifest'), hasLength(1));
    },
  );

  test('BK-WSR-9: the help page lists every option, the steps and the exit '
      'codes; every message has its topic [2026-11-24]', () async {
    final help = HelpGenerator.generateCommandHelp(
      wsrepocleanupCommand,
      tool: buildkitTool,
    );
    for (final o in wsrepocleanupOptions) {
      expect(help, contains('--${o.name}'), reason: o.name);
    }
    expect(help, contains('**Exit Codes**'));
    expect(help, contains('ztmp/<yymmdd>_ws_repo_cleanup'));
    for (final d in wsRepoCleanupMessages.definitions) {
      expect(
        buildkitTool.helpTopics.where((t) => t.name == d.code),
        hasLength(1),
      );
    }
    final text = await cleanup([], json: false);
    expect(text.text, contains('[ws-not-removable]'));
    expect(text.text, contains('[ws-surplus]'));
  });
}
