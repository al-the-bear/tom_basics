/// A git server in memory, reached through an `http.Client`: the smart HTTP
/// protocol, version 2 or version 0 for fetching and version 0 for pushing,
/// over a [GitRepository] — for suites that must not touch a network.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../object_id.dart';
import '../objects.dart';
import '../pack.dart';
import '../pkt_line.dart';
import '../repository.dart';

/// An in-memory git server.
class GitMemoryServer {
  GitMemoryServer({
    this.protocolV2 = true,
    this.defaultBranch = 'main',
    this.requiredPassword,
    Uri? url,
  }) : url = url ?? Uri.parse('https://git.memory.test/owner/repo.git');

  /// Whether fetching speaks protocol version 2 when the client asks.
  final bool protocolV2;

  /// What `HEAD` points at.
  final String defaultBranch;

  /// When set, every request must carry Basic credentials with this password.
  final String? requiredPassword;

  /// Where the repository is served; other paths answer 404.
  final Uri url;

  /// The hosted repository. Refs under `refs/heads/` are its branches.
  final GitRepository repository = GitRepository.memory();

  /// Requests answered, by kind — `ls-refs`, `fetch`, `push`.
  final Map<String, int> requests = {};

  /// Called before a push is applied: a test moves a branch here to lose a
  /// client's race deterministically.
  Future<void> Function()? beforePush;

  /// The client to give a `GitHttpRemote`.
  http.Client get client => MockClient(_handle);

  /// Makes a commit of [files] on [branch] directly on the server.
  Future<GitObjectId> seed(
    Map<String, List<int>> files, {
    String? branch,
    String message = 'seed',
  }) async {
    final ref = 'refs/heads/${branch ?? defaultBranch}';
    final parent = await repository.refs.read(ref);
    final base = parent == null
        ? null
        : (await repository.readCommit(parent)).tree;
    final tree = await repository.editTree(base, writes: files);
    final commit = await repository.commit(
      tree: tree,
      parents: [?parent],
      message: message,
      author: GitPerson(
        name: 'Server',
        email: 'server@test',
        seconds: 1700000000,
      ),
    );
    await repository.refs.write(ref, commit);
    return commit;
  }

  Future<http.Response> _handle(http.Request request) async {
    if (!request.url.path.startsWith(url.path)) {
      return http.Response('not found', 404);
    }
    final password = requiredPassword;
    if (password != null) {
      final header = request.headers['authorization'] ?? '';
      final expected =
          'Basic ${base64.encode(utf8.encode('x-access-token:$password'))}';
      final decoded = header.startsWith('Basic ')
          ? utf8.decode(base64.decode(header.substring(6)))
          : '';
      if (header != expected && !decoded.endsWith(':$password')) {
        return http.Response('unauthorized', 401);
      }
    }
    final rest = request.url.path.substring(url.path.length);
    final v2 =
        protocolV2 &&
        (request.headers['git-protocol'] ?? '').contains('version=2');
    switch ((request.method, rest)) {
      case ('GET', '/info/refs'):
        final service = request.url.queryParameters['service'];
        if (service == 'git-upload-pack') {
          return _advert(
            service!,
            v2 ? await _v2Caps() : await _v0Refs(uploadPack: true),
          );
        }
        if (service == 'git-receive-pack') {
          return _advert(service!, await _v0Refs(uploadPack: false));
        }
      case ('POST', '/git-upload-pack'):
        return _result(
          'git-upload-pack',
          v2
              ? await _v2Command(request.bodyBytes)
              : await _v0Fetch(request.bodyBytes),
        );
      case ('POST', '/git-receive-pack'):
        _count('push');
        return _result('git-receive-pack', await _receive(request.bodyBytes));
    }
    return http.Response('not found', 404);
  }

  void _count(String kind) => requests[kind] = (requests[kind] ?? 0) + 1;

  http.Response _advert(String service, Uint8List body) {
    final w = GitPktWriter()
      ..text('# service=$service')
      ..flush()
      ..raw(body);
    return http.Response.bytes(
      w.take(),
      200,
      headers: {'content-type': 'application/x-$service-advertisement'},
    );
  }

  http.Response _result(String service, Uint8List body) => http.Response.bytes(
    body,
    200,
    headers: {'content-type': 'application/x-$service-result'},
  );

  Future<Uint8List> _v2Caps() async {
    final w = GitPktWriter()
      ..text('version 2')
      ..text('agent=git/memory')
      ..text('ls-refs=unborn')
      ..text('fetch')
      ..text('object-format=sha1')
      ..flush();
    return w.take();
  }

  Future<Map<String, GitObjectId>> _branches() =>
      repository.refs.list('refs/heads/');

  Future<Uint8List> _v0Refs({required bool uploadPack}) async {
    final branches = await _branches();
    final caps = uploadPack
        ? 'side-band-64k ofs-delta no-progress agent=git/memory '
              'symref=HEAD:refs/heads/$defaultBranch'
        : 'report-status side-band-64k delete-refs quiet agent=git/memory';
    final w = GitPktWriter();
    final lines = <String>[];
    final head = branches['refs/heads/$defaultBranch'];
    if (uploadPack && head != null) lines.add('${head.hex} HEAD');
    for (final e
        in (branches.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))) {
      lines.add('${e.value.hex} ${e.key}');
    }
    if (lines.isEmpty) lines.add('${GitObjectId.zero.hex} capabilities^{}');
    for (var i = 0; i < lines.length; i++) {
      if (i == 0) {
        w.bytes([...utf8.encode(lines[i]), 0, ...utf8.encode(caps), 10]);
      } else {
        w.text(lines[i]);
      }
    }
    w.flush();
    return w.take();
  }

  Future<Uint8List> _v2Command(Uint8List body) async {
    final reader = GitPktReader(body);
    final head = reader.untilFlush(); // command and capabilities
    final command = head.first.text;
    final args = reader.untilFlush().map((l) => l.text).toList();
    if (command == 'command=ls-refs') {
      _count('ls-refs');
      final prefixes = [
        for (final a in args)
          if (a.startsWith('ref-prefix ')) a.substring(11),
      ];
      bool wanted(String name) =>
          prefixes.isEmpty || prefixes.any(name.startsWith);
      final w = GitPktWriter();
      final branches = await _branches();
      final head = branches['refs/heads/$defaultBranch'];
      if (wanted('HEAD')) {
        w.text(
          head == null
              ? 'unborn HEAD symref-target:refs/heads/$defaultBranch'
              : '${head.hex} HEAD symref-target:refs/heads/$defaultBranch',
        );
      }
      for (final e in branches.entries) {
        if (wanted(e.key)) w.text('${e.value.hex} ${e.key}');
      }
      w.flush();
      return w.take();
    }
    if (command == 'command=fetch') {
      _count('fetch');
      final pack = await _pack(args);
      final w = GitPktWriter()..text('packfile');
      _sideBand(w, pack);
      w.flush();
      return w.take();
    }
    throw StateError('Unsupported command $command');
  }

  Future<Uint8List> _v0Fetch(Uint8List body) async {
    _count('fetch');
    final reader = GitPktReader(body);
    final args = <String>[];
    while (!reader.atEnd) {
      final line = reader.next();
      if (line.isData) args.add(line.text.split(' ').take(2).join(' '));
    }
    final pack = await _pack(args);
    final w = GitPktWriter()..text('NAK');
    _sideBand(w, pack);
    w.flush();
    return w.take();
  }

  Future<Uint8List> _pack(List<String> args) async {
    final wants = <GitObjectId>[];
    final haves = <GitObjectId>[];
    for (final a in args) {
      if (a.startsWith('want ')) {
        wants.add(GitObjectId.fromHex(a.substring(5, 45)));
      } else if (a.startsWith('have ')) {
        final id = GitObjectId.fromHex(a.substring(5, 45));
        if (await repository.objects.contains(id)) haves.add(id);
      }
    }
    return gitWritePack(await repository.objectsToSend(wants, excluded: haves));
  }

  void _sideBand(GitPktWriter w, Uint8List data) {
    for (var i = 0; i < data.length; i += 8000) {
      final end = i + 8000 < data.length ? i + 8000 : data.length;
      w.bytes([1, ...data.sublist(i, end)]);
    }
  }

  Future<Uint8List> _receive(Uint8List body) async {
    final reader = GitPktReader(body);
    final commands = <(GitObjectId, GitObjectId, String)>[];
    for (final line in reader.untilFlush()) {
      var bytes = line.bytes!;
      final nul = bytes.indexOf(0);
      if (nul >= 0) bytes = Uint8List.sublistView(bytes, 0, nul);
      final parts = utf8.decode(bytes).trim().split(' ');
      commands.add((
        GitObjectId.fromHex(parts[0]),
        GitObjectId.fromHex(parts[1]),
        parts[2],
      ));
    }
    final report = GitPktWriter();
    final pack = reader.rest;
    try {
      if (pack.isNotEmpty) await repository.objects.writePack(pack);
      report.text('unpack ok');
    } on Object catch (e) {
      report.text('unpack $e');
    }
    await beforePush?.call();
    for (final (oldId, newId, ref) in commands) {
      final current = await repository.refs.read(ref);
      final matches = oldId.isZero ? current == null : current == oldId;
      if (!matches) {
        report.text('ng $ref fetch first');
        continue;
      }
      if (newId.isZero) {
        await repository.refs.delete(ref);
      } else if (!await repository.objects.contains(newId)) {
        report.text('ng $ref missing objects');
        continue;
      } else {
        await repository.refs.write(ref, newId);
      }
      report.text('ok $ref');
    }
    report.flush();
    final w = GitPktWriter();
    _sideBand(w, report.take());
    w.flush();
    return w.take();
  }
}
