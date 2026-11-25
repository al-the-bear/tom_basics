/// git helpers for the workspace clone's tests: fixture repositories built
/// under this package's `.dart_tool/`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs git in [dir] (local file transport allowed, as submodules need) and
/// returns its output; throws on a non-zero exit.
Future<String> git(String dir, List<String> args) async {
  final r = await Process.run('git', [
    '-c',
    'protocol.file.allow=always',
    ...args,
  ], workingDirectory: dir);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} in $dir: ${r.stderr}');
  }
  return r.stdout.toString();
}

/// A new repository at [dir] on `main` with `origin` set to [origin].
Future<void> initRepo(String dir, String origin) async {
  Directory(dir).createSync(recursive: true);
  await git(dir, ['init', '-q', '-b', 'main']);
  await git(dir, ['config', 'user.email', 'wc@example.com']);
  await git(dir, ['config', 'user.name', 'WC']);
  await git(dir, ['config', 'commit.gpgsign', 'false']);
  await git(dir, ['remote', 'add', 'origin', origin]);
}

/// Writes [file] in [dir] and commits it.
Future<void> commit(String dir, String file, String content) async {
  final f = File(p.join(dir, file))..parent.createSync(recursive: true);
  f.writeAsStringSync(content);
  await git(dir, ['add', file]);
  await git(dir, ['commit', '-q', '-m', file]);
}

/// The commit [dir] has checked out.
Future<String> head(String dir) async =>
    (await git(dir, ['rev-parse', 'HEAD'])).trim();
