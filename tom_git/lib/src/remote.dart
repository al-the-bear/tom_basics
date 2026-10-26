/// The smart HTTP transport: list refs, fetch a pack, push.
///
/// Fetching speaks protocol version 2 where the server offers it and falls
/// back to version 0; pushing is version 0, which is the only version
/// `git-receive-pack` has.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'object_id.dart';
import 'pkt_line.dart';

/// A username and password for HTTP Basic authentication — for a token, the
/// token is the password.
class GitCredentials {
  const GitCredentials(this.username, this.password);

  /// A token, under the username the major hosts accept for one.
  const GitCredentials.token(String token, {String username = 'x-access-token'})
    : this(username, token);

  final String username;
  final String password;

  String get _header =>
      'Basic ${base64.encode(utf8.encode('$username:$password'))}';

  @override
  String toString() => 'GitCredentials($username, <withheld>)';
}

/// Supplies credentials for a remote, or null for none.
typedef GitCredentialsProvider = Future<GitCredentials?> Function(Uri remote);

/// A transport failure.
class GitTransportException implements Exception {
  GitTransportException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message'
      '${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// The server refused the credentials, or there were none and it wanted some.
class GitAuthException extends GitTransportException {
  GitAuthException(super.message, {super.statusCode});
}

/// The server answered that there is no repository at the URL.
class GitRepositoryNotFoundException extends GitTransportException {
  GitRepositoryNotFoundException(super.message, {super.statusCode});
}

/// The server could not be reached at all.
class GitUnreachableException extends GitTransportException {
  GitUnreachableException(super.message, {super.cause});
}

/// The refs a remote advertises.
class GitRemoteRefs {
  const GitRemoteRefs({
    required this.refs,
    this.head,
    this.capabilities = const {},
    this.protocolVersion = 0,
  });

  /// Full ref names (`refs/heads/main`) to the ids they point at.
  final Map<String, GitObjectId> refs;

  /// The ref `HEAD` points at (`refs/heads/main`), when the server says.
  final String? head;

  final Set<String> capabilities;
  final int protocolVersion;

  /// The default branch's short name, when the server says.
  String? get defaultBranch => head != null && head!.startsWith('refs/heads/')
      ? head!.substring('refs/heads/'.length)
      : null;
}

/// One ref update of a push: from [oldId] to [newId]. A zero [oldId] creates
/// the ref; a zero [newId] deletes it.
class GitRefUpdate {
  const GitRefUpdate(this.ref, {required this.oldId, required this.newId});

  final String ref;
  final GitObjectId oldId;
  final GitObjectId newId;
}

/// What the server reported for a push.
class GitPushResult {
  const GitPushResult({
    this.unpackError,
    this.refErrors = const {},
    this.remoteMoved,
  });

  /// Why the server could not unpack the pack, or null when it could.
  final String? unpackError;

  /// Refs the server refused, each with its reason as the server words it —
  /// GitHub says `fetch first`, git's own receive-pack `failed to update
  /// ref`, others `non-fast-forward` or `stale info`.
  final Map<String, String> refErrors;

  /// Whether a listing made after the refusal found the ref somewhere other
  /// than where the push expected it — measured, so it does not depend on
  /// how a server words the refusal. Null when no listing was made.
  final bool? remoteMoved;

  bool get ok => unpackError == null && refErrors.isEmpty;

  /// Whether the refusal is a lost race — somebody else moved the ref first —
  /// which a fetch and retry can cure.
  ///
  /// Decided by [remoteMoved] when it was measured; otherwise by the reason,
  /// which only covers the wordings this library has met.
  bool get isRace {
    if (ok || unpackError != null) return false;
    final moved = remoteMoved;
    if (moved != null) return moved;
    return refErrors.values.every(
      (r) =>
          r.contains('non-fast-forward') ||
          r.contains('fetch first') ||
          r.contains('stale info'),
    );
  }

  GitPushResult withRemoteMoved(bool moved) => GitPushResult(
    unpackError: unpackError,
    refErrors: refErrors,
    remoteMoved: moved,
  );

  @override
  String toString() => ok
      ? 'GitPushResult(ok)'
      : 'GitPushResult($unpackError $refErrors'
            '${remoteMoved == null ? '' : ', remote moved: $remoteMoved'})';
}

/// A remote repository reached over smart HTTP(S).
class GitHttpRemote {
  GitHttpRemote(
    Uri url, {
    http.Client? client,
    this.credentials,
    this.userAgent = 'git/tom_git-0.1',
  }) : url = _normalise(url),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  /// The repository URL, without a trailing slash.
  final Uri url;

  final GitCredentialsProvider? credentials;

  /// Sent as `User-Agent`. Servers decide some behaviour by a `git/` prefix.
  final String userAgent;

  final http.Client _client;
  final bool _ownsClient;

  static Uri _normalise(Uri url) {
    var path = url.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return url.replace(path: path);
  }

  Uri _endpoint(String suffix, [Map<String, String>? query]) =>
      url.replace(path: '${url.path}/$suffix', queryParameters: query);

  /// Lists the remote's refs for fetching, under [prefixes].
  Future<GitRemoteRefs> listRefs({
    List<String> prefixes = const ['refs/heads/'],
  }) async {
    final advert = await _advertisement('git-upload-pack', v2: true);
    if (advert.protocolVersion != 2) return advert;
    final w = GitPktWriter()
      ..text('command=ls-refs')
      ..text('agent=$userAgent')
      ..delimiter()
      ..text('symrefs');
    for (final p in [...prefixes, 'HEAD']) {
      w.text('ref-prefix $p');
    }
    w.flush();
    final body = await _post('git-upload-pack', w.take(), v2: true);
    final refs = <String, GitObjectId>{};
    String? head;
    for (final line in GitPktReader(body).untilFlush()) {
      final parts = line.text.split(' ');
      if (parts.length < 2) continue;
      final name = parts[1];
      for (final attr in parts.skip(2)) {
        if (attr.startsWith('symref-target:') && name == 'HEAD') {
          head = attr.substring('symref-target:'.length);
        }
      }
      if (parts[0] == 'unborn') continue;
      if (name == 'HEAD') continue;
      refs[name] = GitObjectId.fromHex(parts[0]);
    }
    return GitRemoteRefs(
      refs: refs,
      head: head,
      capabilities: advert.capabilities,
      protocolVersion: 2,
    );
  }

  /// A pack holding [wants] and everything they reach that [haves] do not.
  ///
  /// The pack is self-contained (not thin), so it can be read without the
  /// objects [haves] name.
  Future<Uint8List> fetchPack({
    required List<GitObjectId> wants,
    List<GitObjectId> haves = const [],
    void Function(String message)? progress,
  }) async {
    if (wants.isEmpty) throw ArgumentError('Nothing wanted');
    final advert = await _advertisement('git-upload-pack', v2: true);
    if (advert.protocolVersion == 2) {
      final w = GitPktWriter()
        ..text('command=fetch')
        ..text('agent=$userAgent')
        ..delimiter()
        ..text('ofs-delta');
      if (progress == null) w.text('no-progress');
      for (final id in wants) {
        w.text('want ${id.hex}');
      }
      for (final id in haves) {
        w.text('have ${id.hex}');
      }
      w
        ..text('done')
        ..flush();
      final body = await _post('git-upload-pack', w.take(), v2: true);
      final reader = GitPktReader(body);
      // Sections up to `packfile`; with `done` sent there are no
      // acknowledgments, but shallow-info or wanted-refs may come first.
      while (!reader.atEnd) {
        final header = reader.next();
        if (header.isData && header.text == 'packfile') {
          return GitSideBand.collect(reader.untilFlush(), progress: progress);
        }
        if (header.isData && header.text.startsWith('ERR ')) {
          throw GitRemoteError(header.text.substring(4));
        }
        if (header.isData) reader.untilFlush();
      }
      throw GitTransportException('The fetch response held no packfile');
    }

    // Protocol version 0.
    final caps = advert.capabilities;
    final requested = [
      if (caps.contains('side-band-64k')) 'side-band-64k',
      if (caps.contains('ofs-delta')) 'ofs-delta',
      if (progress == null && caps.contains('no-progress')) 'no-progress',
      'agent=$userAgent',
    ];
    final w = GitPktWriter()
      ..text('want ${wants.first.hex} ${requested.join(' ')}');
    for (final id in wants.skip(1)) {
      w.text('want ${id.hex}');
    }
    w.flush();
    for (final id in haves) {
      w.text('have ${id.hex}');
    }
    w.text('done');
    final body = await _post('git-upload-pack', w.take(), v2: false);
    final reader = GitPktReader(body);
    // ACK / NAK lines, then the pack.
    while (!reader.atEnd) {
      final line = reader.next();
      if (!line.isData) continue;
      final text = line.text;
      if (text.startsWith('NAK') || text.startsWith('ACK ')) {
        if (text.startsWith('NAK') || !text.contains(' continue')) break;
        continue;
      }
      if (text.startsWith('ERR ')) throw GitRemoteError(text.substring(4));
      throw GitTransportException('Unexpected line before the pack: $text');
    }
    if (caps.contains('side-band-64k')) {
      return GitSideBand.collect(_dataLines(reader), progress: progress);
    }
    return reader.rest;
  }

  Iterable<GitPktLine> _dataLines(GitPktReader reader) sync* {
    while (!reader.atEnd) {
      final line = reader.next();
      if (!line.isData) return;
      yield line;
    }
  }

  /// Lists the remote's refs for pushing.
  Future<GitRemoteRefs> listPushRefs() =>
      _advertisement('git-receive-pack', v2: false);

  /// Applies [updates] on the remote, sending [pack] (the objects the remote
  /// needs; null when every update is a delete).
  Future<GitPushResult> push(
    List<GitRefUpdate> updates,
    Uint8List? pack, {
    void Function(String message)? progress,
  }) async {
    if (updates.isEmpty) return const GitPushResult();
    final advert = await listPushRefs();
    final caps = advert.capabilities;
    final requested = [
      'report-status',
      if (caps.contains('side-band-64k')) 'side-band-64k',
      if (caps.contains('delete-refs')) 'delete-refs',
      if (progress == null && caps.contains('quiet')) 'quiet',
      'agent=$userAgent',
    ];
    final w = GitPktWriter();
    for (var i = 0; i < updates.length; i++) {
      final u = updates[i];
      final line = '${u.oldId.hex} ${u.newId.hex} ${u.ref}';
      if (i == 0) {
        w.bytes([
          ...utf8.encode(line),
          0,
          ...utf8.encode(requested.join(' ')),
          10,
        ]);
      } else {
        w.text(line);
      }
    }
    w.flush();
    if (pack != null) w.raw(pack);
    final body = await _post('git-receive-pack', w.take(), v2: false);
    final reader = GitPktReader(body);
    final reportBytes = caps.contains('side-band-64k')
        ? GitSideBand.collect(_dataLines(reader), progress: progress)
        : body;
    String? unpackError;
    final refErrors = <String, String>{};
    for (final line in GitPktReader(reportBytes).untilFlush()) {
      final text = line.text;
      if (text.startsWith('unpack ')) {
        final status = text.substring(7);
        if (status != 'ok') unpackError = status;
      } else if (text.startsWith('ng ')) {
        final rest = text.substring(3);
        final space = rest.indexOf(' ');
        refErrors[space < 0 ? rest : rest.substring(0, space)] = space < 0
            ? 'refused'
            : rest.substring(space + 1);
      }
    }
    return GitPushResult(unpackError: unpackError, refErrors: refErrors);
  }

  /// The `info/refs` advertisement for [service].
  Future<GitRemoteRefs> _advertisement(
    String service, {
    required bool v2,
  }) async {
    final response = await _send(
      http.Request('GET', _endpoint('info/refs', {'service': service}))
        ..headers.addAll({if (v2) 'Git-Protocol': 'version=2'}),
    );
    final type = response.headers['content-type'] ?? '';
    if (!type.startsWith('application/x-$service-advertisement')) {
      throw GitTransportException(
        '${url.host} does not speak the smart HTTP '
        'protocol (content type "$type")',
      );
    }
    final reader = GitPktReader(response.bodyBytes);
    var first = reader.next();
    if (first.isData && first.text.startsWith('# service=')) {
      reader.untilFlush();
      first = reader.next();
    }
    if (first.isData && first.text == 'version 2') {
      final capabilities = <String>{};
      for (final line in reader.untilFlush()) {
        capabilities.add(line.text);
      }
      return GitRemoteRefs(
        refs: const {},
        capabilities: capabilities,
        protocolVersion: 2,
      );
    }
    // Version 0: the first ref line carries the capabilities after a NUL.
    final refs = <String, GitObjectId>{};
    final capabilities = <String>{};
    String? head;
    var line = first;
    var isFirst = true;
    while (line.isData) {
      final bytes = line.bytes!;
      var refPart = bytes;
      if (isFirst) {
        final nul = bytes.indexOf(0);
        if (nul >= 0) {
          refPart = Uint8List.sublistView(bytes, 0, nul);
          final capText = utf8
              .decode(Uint8List.sublistView(bytes, nul + 1))
              .trim();
          for (final cap in capText.split(' ')) {
            if (cap.isEmpty) continue;
            capabilities.add(cap);
            if (cap.startsWith('symref=HEAD:')) {
              head = cap.substring('symref=HEAD:'.length);
            }
          }
        }
        isFirst = false;
      }
      final text = utf8.decode(refPart).trim();
      final space = text.indexOf(' ');
      if (space > 0) {
        final name = text.substring(space + 1);
        if (name != 'capabilities^{}' &&
            name != 'HEAD' &&
            !name.endsWith('^{}')) {
          refs[name] = GitObjectId.fromHex(text.substring(0, space));
        }
      }
      if (reader.atEnd) break;
      line = reader.next();
    }
    return GitRemoteRefs(
      refs: refs,
      head: head,
      capabilities: capabilities,
      protocolVersion: 0,
    );
  }

  Future<Uint8List> _post(
    String service,
    Uint8List body, {
    required bool v2,
  }) async {
    final response = await _send(
      http.Request('POST', _endpoint(service))
        ..headers.addAll({
          'Content-Type': 'application/x-$service-request',
          'Accept': 'application/x-$service-result',
          if (v2) 'Git-Protocol': 'version=2',
        })
        ..bodyBytes = body,
    );
    return response.bodyBytes;
  }

  Future<http.Response> _send(http.Request request) async {
    request.headers['User-Agent'] = userAgent;
    final creds = await credentials?.call(url);
    if (creds != null) request.headers['Authorization'] = creds._header;
    http.Response response;
    try {
      response = await http.Response.fromStream(await _client.send(request));
    } on http.ClientException catch (e) {
      throw GitUnreachableException(
        '${url.host} could not be reached: '
        '${e.message}',
        cause: e,
      );
    }
    final status = response.statusCode;
    if (status == 401 || status == 403) {
      throw GitAuthException(
        creds == null
            ? '${url.host} wants credentials for $url'
            : '${url.host} refused the credentials for $url',
        statusCode: status,
      );
    }
    if (status == 404) {
      throw GitRepositoryNotFoundException(
        'No repository at $url',
        statusCode: status,
      );
    }
    if (status != 200) {
      throw GitTransportException(
        '${request.method} ${request.url.path} '
        'failed',
        statusCode: status,
      );
    }
    return response;
  }

  /// Closes the HTTP client when this remote made it.
  void close() {
    if (_ownsClient) _client.close();
  }
}
