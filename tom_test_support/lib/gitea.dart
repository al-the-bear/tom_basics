/// A disposable Gitea server in Docker for live suites: one admin user, a
/// token and an initialised repository, removed when the suite ends.
///
/// Docker is test infrastructure here, as GitHub is for the GitHub suites;
/// the code under test talks to the server over HTTP and nothing else.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One running Gitea container.
class TomGiteaServer {
  TomGiteaServer._(this.container, this.base, this.user, this.token);

  static const image = 'gitea/gitea:1.22.6';

  final String container;
  final Uri base;
  final String user;
  final String token;

  /// Whether `docker` answers at all — the suite skips without it.
  static Future<bool> available() async {
    try {
      final r = await Process.run('docker', ['info', '--format', '{{.ID}}']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  static Future<TomGiteaServer> start() async {
    final name = 'tom-git-gitea-${DateTime.now().millisecondsSinceEpoch}';
    await _run('docker', [
      'run',
      '-d',
      '--rm',
      '--name',
      name,
      '-p',
      '127.0.0.1::3000',
      '-e',
      'GITEA__security__INSTALL_LOCK=true',
      '-e',
      'GITEA__database__DB_TYPE=sqlite3',
      '-e',
      'GITEA__server__ROOT_URL=http://localhost:3000/',
      '-e',
      'GITEA__repository__DEFAULT_BRANCH=main',
      image,
    ]);
    try {
      final port = (await _run('docker', [
        'port',
        name,
        '3000',
      ])).trim().split('\n').first.split(':').last;
      final base = Uri.parse('http://127.0.0.1:$port');
      final deadline = DateTime.now().add(const Duration(seconds: 90));
      while (true) {
        try {
          final r = await http.get(base.replace(path: '/api/healthz'));
          if (r.statusCode == 200) break;
        } on Object {
          // Not up yet.
        }
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Gitea did not come up within 90 s');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      const user = 'tom';
      await _run('docker', [
        'exec',
        '-u',
        'git',
        name,
        'gitea',
        'admin',
        'user',
        'create',
        '--username',
        user,
        '--password',
        'tom-git-live-1',
        '--email',
        'tom@example.invalid',
        '--admin',
        '--must-change-password=false',
      ]);
      final token = (await _run('docker', [
        'exec',
        '-u',
        'git',
        name,
        'gitea',
        'admin',
        'user',
        'generate-access-token',
        '--username',
        user,
        '--token-name',
        'live',
        '--scopes',
        'all',
        '--raw',
      ])).trim();
      final created = await http.post(
        base.replace(path: '/api/v1/user/repos'),
        headers: {
          'Authorization': 'token $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': 'scratch',
          'auto_init': true,
          'default_branch': 'main',
          'readme': 'Default',
        }),
      );
      if (created.statusCode != 201) {
        throw StateError(
          'Creating the repository failed: '
          '${created.statusCode} ${created.body}',
        );
      }
      return TomGiteaServer._(name, base, user, token);
    } catch (_) {
      await Process.run('docker', ['rm', '-f', name]);
      rethrow;
    }
  }

  Uri get repositoryUrl => base.replace(path: '/$user/scratch.git');

  Future<void> stop() async {
    await Process.run('docker', ['rm', '-f', container]);
  }

  static Future<String> _run(String exe, List<String> args) async {
    final r = await Process.run(exe, args);
    if (r.exitCode != 0) {
      throw StateError('$exe ${args.take(3).join(' ')} failed: ${r.stderr}');
    }
    return r.stdout as String;
  }
}
