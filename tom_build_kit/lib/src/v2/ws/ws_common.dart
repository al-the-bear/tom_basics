/// What the `:ws-*` commands share: running git in a repository, reading
/// its status, and the checks every command makes before it changes a
/// repository (an operation in progress, unregistered merge drivers).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs git in one folder, with an optional environment (tests).
class WsGit {
  WsGit(this.dir, [this.environment]);

  final String dir;
  final Map<String, String>? environment;

  Future<ProcessResult> run(List<String> args) => Process.run(
    'git',
    args,
    workingDirectory: dir,
    environment: environment,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  Future<String> out(List<String> args) async =>
      '${(await run(args)).stdout}'.trim();

  Future<bool> ok(List<String> args) async => (await run(args)).exitCode == 0;

  /// The first lines of what git wrote, for a report.
  static String text(ProcessResult r) => '${r.stderr}\n${r.stdout}'
      .trim()
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(4)
      .join(' | ');

  /// The origin URL as configured (`remote.origin.url`), not as an
  /// `insteadOf` rule rewrites it: what repos.yaml is compared with.
  Future<String> originUrl() => out(['config', '--get', 'remote.origin.url']);

  Future<bool> hasRef(String ref) => ok(['rev-parse', '--verify', '-q', ref]);

  /// Whether [ancestor] is contained in [of].
  Future<bool> contains(String ancestor, String of) =>
      ok(['merge-base', '--is-ancestor', ancestor, of]);

  /// `git log --oneline` of [range] (space-separated revision arguments),
  /// at most [max] lines.
  Future<List<String>> log(String range, {int max = 10}) async {
    final out = await this.out([
      'log',
      '--oneline',
      '-n',
      '$max',
      ...range.split(' '),
    ]);
    return out.isEmpty ? const [] : out.split('\n');
  }

  /// The uncommitted changes (`git status --porcelain=v1 -z -uall`).
  Future<List<WsChange>> changes() async => wsParseStatus(
    '${(await run(['status', '--porcelain=v1', '-z', '-uall'])).stdout}',
  );
}

/// One uncommitted change (`git status --porcelain`).
class WsChange {
  const WsChange(this.code, this.path);
  final String code;
  final String path;
  bool get deleted => code.contains('D');
  bool get conflicted => code.contains('U') || code == 'AA' || code == 'DD';
}

/// Parses `git status --porcelain=v1 -z` output.
List<WsChange> wsParseStatus(String z) {
  final out = <WsChange>[];
  final parts = z.split('\x00');
  for (var i = 0; i < parts.length; i++) {
    final e = parts[i];
    if (e.length < 4) continue;
    final code = e.substring(0, 2);
    out.add(WsChange(code, e.substring(3)));
    if (code.startsWith('R') || code.startsWith('C')) i++;
  }
  return out;
}

/// The operation a repository is in the middle of (`a merge`, `a rebase`,
/// `a cherry-pick`, `a revert`), or null.
Future<String?> wsOperationInProgress(WsGit g) async {
  for (final (marker, what) in const [
    ('MERGE_HEAD', 'a merge'),
    ('rebase-merge', 'a rebase'),
    ('rebase-apply', 'a rebase'),
    ('CHERRY_PICK_HEAD', 'a cherry-pick'),
    ('REVERT_HEAD', 'a revert'),
  ]) {
    final at = await g.out(['rev-parse', '--git-path', marker]);
    final full = p.isAbsolute(at) ? at : p.join(g.dir, at);
    if (FileSystemEntity.typeSync(full) != FileSystemEntityType.notFound) {
      return what;
    }
  }
  return null;
}

/// The merge drivers the repository's `.gitattributes` files name
/// (`merge=<name>`, not the built-in text / binary / union) that have no
/// `merge.<name>.driver` in the git configuration.
Future<List<({String driver, String file})>> wsMissingDrivers(WsGit g) async {
  final listed = (await g.out([
    'ls-files',
    '-z',
    '--',
    '.gitattributes',
    '*/.gitattributes',
  ])).split('\x00').where((f) => f.isNotEmpty).toSet();
  if (File(p.join(g.dir, '.gitattributes')).existsSync()) {
    listed.add('.gitattributes');
  }
  final drivers = <String, String>{};
  for (final rel in listed) {
    final file = File(p.join(g.dir, rel));
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      if (line.trimLeft().startsWith('#')) continue;
      for (final m in RegExp(r'(?:^|\s)merge=([^\s]+)').allMatches(line)) {
        final name = m.group(1)!;
        if (const {'text', 'binary', 'union'}.contains(name)) continue;
        drivers.putIfAbsent(name, () => rel);
      }
    }
  }
  return [
    for (final e in drivers.entries)
      if (!await g.ok(['config', '--get', 'merge.${e.key}.driver']))
        (driver: e.key, file: e.value),
  ];
}

/// `ws-push/<host>/<yymmdd-hhmm>`: the branch rescued commits go to.
String wsRescueBranch(String host, DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'ws-push/$host/${two(now.year % 100)}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}';
}

/// `2026-11-24T16:02`.
String wsIsoMinute(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}';
}

/// Whether two remote URLs name the same repository (`.git` and a trailing
/// slash aside).
bool wsSameUrl(String a, String b) {
  String norm(String u) =>
      u.trim().replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'\.git$'), '');
  return norm(a) == norm(b);
}

/// Runs [job] for [items], eight at a time.
Future<void> wsPool<T>(List<T> items, Future<void> Function(T) job) async {
  for (var i = 0; i < items.length; i += 8) {
    await Future.wait([for (final x in items.skip(i).take(8)) job(x)]);
  }
}
