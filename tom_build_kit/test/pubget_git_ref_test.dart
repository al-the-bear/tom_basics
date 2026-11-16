// BK-PUBGIT: a library keeps its pubspec.lock untracked, so a git dependency
// on a moving branch stays at the commit this host resolved first. When the
// branch has moved on and another dependency needs the new commit's
// dependencies, `pub get` fails on version solving. `buildkit :pubget` then
// retries once with `pub upgrade <the lock's git packages>` and says so. A
// tracked (application) lock is never upgraded: it follows the
// pubspec-lock-last-changed rule. Fixture packages and git repositories live
// under .dart_tool, with a PUB_CACHE of their own; the run is rooted there.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/pub_get_runner.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

void main() {
  late Directory root;
  late Map<String, String> env;

  void git(String dir, List<String> args) {
    final r = Process.runSync('git', [
      '-c',
      'user.email=t@t',
      '-c',
      'user.name=t',
      ...args,
    ], workingDirectory: dir);
    if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
  }

  void package(String name, String pubspec) {
    File(p.join(root.path, name, 'pubspec.yaml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(pubspec);
    File(p.join(root.path, name, 'lib', '$name.dart'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('// $name\n');
  }

  String dir(String name) => p.join(root.path, name);

  /// gitdep@main needs leaf v1 at commit one; `app` resolves it and keeps the
  /// lock. Then main moves to commit two (leaf v2) and app gets the path
  /// package mid, which needs leaf v2: the locked commit cannot be kept.
  void staleLockFixture() {
    package('leaf', 'name: leaf\nversion: 1.0.0\nenvironment: {sdk: ^3.0.0}\n');
    git(dir('leaf'), ['init', '-q', '-b', 'main']);
    git(dir('leaf'), ['add', '-A']);
    git(dir('leaf'), ['commit', '-qm', 'one']);
    git(dir('leaf'), ['tag', 'v1']);
    package('leaf', 'name: leaf\nversion: 2.0.0\nenvironment: {sdk: ^3.0.0}\n');
    git(dir('leaf'), ['commit', '-qam', 'two']);
    git(dir('leaf'), ['tag', 'v2']);

    String gitdepPubspec(String tag) =>
        'name: gitdep\nversion: 1.0.0\nenvironment: {sdk: ^3.0.0}\n'
        'dependencies:\n  leaf: {git: {url: ${dir('leaf')}, ref: $tag}}\n';
    package('gitdep', gitdepPubspec('v1'));
    git(dir('gitdep'), ['init', '-q', '-b', 'main']);
    git(dir('gitdep'), ['add', '-A']);
    git(dir('gitdep'), ['commit', '-qm', 'one']);

    final appPubspec =
        'name: app\nenvironment: {sdk: ^3.0.0}\ndependencies:\n'
        '  gitdep: {git: {url: ${dir('gitdep')}, ref: main}}\n';
    package('app', appPubspec);
    final first = Process.runSync(
      'dart',
      ['pub', 'get'],
      workingDirectory: dir('app'),
      environment: env,
    );
    expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');

    package('gitdep', gitdepPubspec('v2'));
    git(dir('gitdep'), ['commit', '-qam', 'two']);
    package(
      'mid',
      'name: mid\nenvironment: {sdk: ^3.0.0}\ndependencies:\n'
          '  leaf: {git: {url: ${dir('leaf')}, ref: v2}}\n',
    );
    package('app', '$appPubspec  mid: {path: ${dir('mid')}}\n');
  }

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = Directory(
      base.createTempSync('pubget_git_ref_test_').resolveSymbolicLinksSync(),
    );
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    env = {'PUB_CACHE': p.join(root.path, 'pub_cache')};
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> pubget() => Process.run(
    'dart',
    ['run', _buildkit, '-R', root.path, '-s', dir('app'), ':pubget'],
    workingDirectory: dir('app'),
    environment: env,
  );

  String lock() => File(p.join(dir('app'), 'pubspec.lock')).readAsStringSync();

  test('BK-PUBGIT-1: an untracked lock that pins a moved git branch is '
      'upgraded once, and the output says so [2026-11-16]', () async {
    staleLockFixture();
    final before = lock();
    final run = await pubget();
    final out = '${run.stdout}${run.stderr}';
    expect(run.exitCode, 0, reason: out);
    expect(out, contains('version solving failed'));
    expect(
      out,
      contains(
        'Retrying with dart pub upgrade gitdep leaf: the untracked '
        'pubspec.lock pins git packages at the commits this host resolved '
        'first',
      ),
    );
    expect(lock(), isNot(before));
    expect(lock(), contains('mid:'));
  });

  test('BK-PUBGIT-2: a tracked lock is not upgraded; pub get fails as it is '
      '[2026-11-16]', () async {
    staleLockFixture();
    git(dir('app'), ['init', '-q', '-b', 'main']);
    git(dir('app'), ['add', 'pubspec.lock']);
    git(dir('app'), ['commit', '-qm', 'lock']);
    final before = lock();
    final run = await pubget();
    final out = '${run.stdout}${run.stderr}';
    expect(run.exitCode, isNot(0), reason: out);
    expect(out, isNot(contains('Retrying with')));
    expect(lock(), before);
  });

  test(
    'BK-PUBGIT-3: the git packages of a lock, in its order [2026-11-16]',
    () {
      final lockFile = File(p.join(root.path, 'pubspec.lock'))
        ..writeAsStringSync('''
packages:
  gitdep:
    dependency: "direct main"
    description:
      path: "."
      ref: main
      resolved-ref: "0a2b7648"
      url: "https://example.com/gitdep.git"
    source: git
    version: "1.0.0"
  path:
    dependency: transitive
    description:
      name: path
      url: "https://pub.dev"
    source: hosted
    version: "1.9.0"
  leaf:
    dependency: transitive
    description:
      path: "."
      ref: v1
      resolved-ref: "370a29"
      url: "https://example.com/leaf.git"
    source: git
    version: "1.0.0"
sdks:
  dart: ">=3.0.0 <4.0.0"
''');
      expect(gitPackagesInLock(lockFile.path), ['gitdep', 'leaf']);
      expect(gitPackagesInLock(p.join(root.path, 'missing.lock')), isEmpty);
    },
  );
}
