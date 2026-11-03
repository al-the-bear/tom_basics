import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_test_support/tom_test_support.dart';

void main() {
  late HttpServer origin;
  late TomCorsProxy proxy;
  late HttpClient client;

  setUp(() async {
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      final body = await utf8.decodeStream(request);
      request.response
        ..headers.set(
          'X-Seen-Auth',
          request.headers.value('authorization') ?? '',
        )
        ..write('${request.method} ${request.uri} $body');
      await request.response.close();
    });
    proxy = await TomCorsProxy.start(
      Uri.parse('http://127.0.0.1:${origin.port}/repo.git'),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await proxy.stop();
    await origin.close(force: true);
  });

  test('CORS-1: a request is forwarded with its headers, and the answer '
      'carries the CORS headers', () async {
    final request = await client.postUrl(
      proxy.url.replace(path: '/repo.git/git-upload-pack', query: 'x=1'),
    );
    request.headers.set('Authorization', 'Basic abc');
    request.headers.set('Origin', 'http://localhost:9999');
    request.write('want');
    final response = await request.close();
    expect(
      await utf8.decodeStream(response),
      'POST /repo.git/git-upload-pack?x=1 want',
    );
    expect(response.headers.value('x-seen-auth'), 'Basic abc');
    expect(response.headers.value('access-control-allow-origin'), '*');
  });

  test('CORS-2: a preflight is answered by the proxy, allowing the headers '
      'the page asked for', () async {
    final request = await client.openUrl('OPTIONS', proxy.url);
    request.headers.set('Origin', 'http://localhost:9999');
    request.headers.set('Access-Control-Request-Method', 'POST');
    request.headers.set(
      'Access-Control-Request-Headers',
      'authorization,git-protocol',
    );
    final response = await request.close();
    await response.drain<void>();
    expect(response.statusCode, HttpStatus.noContent);
    expect(
      response.headers.value('access-control-allow-headers'),
      'authorization,git-protocol',
    );
    expect(
      response.headers.value('access-control-allow-methods'),
      contains('POST'),
    );
  });
}
