import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:test/test.dart';
import 'package:tom_github_api/tom_github_api.dart';

/// A client that answers `github.com` device-flow endpoints from a script.
///
/// The device flow does not go through [GitHubHttpClient] — it talks to
/// `github.com`, not `api.github.com`, and it is unauthenticated by
/// definition — so it needs its own harness rather than the API mock.
http.Client _deviceClient(Map<String, List<Map<String, dynamic>>> script) {
  final calls = <String, int>{};
  return http_testing.MockClient((request) async {
    final path = request.url.path;
    final responses = script[path]!;
    final index = calls[path] ?? 0;
    calls[path] = index + 1;
    return http.Response(
      jsonEncode(responses[index.clamp(0, responses.length - 1)]),
      200,
      headers: const {'content-type': 'application/json'},
    );
  });
}

void main() {
  group('requestCode', () {
    test('returns what the user must be shown', () async {
      final flow = GitHubDeviceFlow(
        clientId: 'Iv1.test',
        httpClient: _deviceClient({
          '/login/device/code': [
            {
              'device_code': 'dev-1',
              'user_code': 'ABCD-1234',
              'verification_uri': 'https://github.com/login/device',
              'expires_in': 900,
              'interval': 5,
            },
          ],
        }),
      );
      addTearDown(flow.close);

      final code = await flow.requestCode();

      expect(code.userCode, 'ABCD-1234');
      expect(code.verificationUri, 'https://github.com/login/device');
      expect(code.deviceCode, 'dev-1');
      expect(code.expiresIn, const Duration(minutes: 15));
      expect(code.interval, const Duration(seconds: 5));
    });

    test('surfaces a rejected client id', () async {
      final flow = GitHubDeviceFlow(
        clientId: 'bogus',
        httpClient: _deviceClient({
          '/login/device/code': [
            {'error': 'unauthorized_client'},
          ],
        }),
      );
      addTearDown(flow.close);

      expect(flow.requestCode, throwsA(isA<GitHubDeviceFlowException>()));
    });
  });

  group('pollForToken', () {
    const code = GitHubDeviceCode(
      userCode: 'ABCD-1234',
      verificationUri: 'https://github.com/login/device',
      deviceCode: 'dev-1',
      expiresIn: Duration(minutes: 15),
      interval: Duration(seconds: 5),
    );

    test('polls past authorization_pending until the user authorizes',
        () async {
      final slept = <Duration>[];
      final flow = GitHubDeviceFlow(
        clientId: 'Iv1.test',
        sleep: (d) async => slept.add(d),
        httpClient: _deviceClient({
          '/login/oauth/access_token': [
            {'error': 'authorization_pending'},
            {'error': 'authorization_pending'},
            {'access_token': 'ghu_token'},
          ],
        }),
      );
      addTearDown(flow.close);

      expect(await flow.pollForToken(code), 'ghu_token');
      expect(slept, List.filled(3, const Duration(seconds: 5)));
    });

    test('widens the interval on slow_down — ignoring it gets us blocked',
        () async {
      final slept = <Duration>[];
      final flow = GitHubDeviceFlow(
        clientId: 'Iv1.test',
        sleep: (d) async => slept.add(d),
        httpClient: _deviceClient({
          '/login/oauth/access_token': [
            {'error': 'slow_down', 'interval': 10},
            {'access_token': 'ghu_token'},
          ],
        }),
      );
      addTearDown(flow.close);

      expect(await flow.pollForToken(code), 'ghu_token');
      expect(slept, [const Duration(seconds: 5), const Duration(seconds: 15)]);
    });

    test('stops when the user declines', () async {
      final flow = GitHubDeviceFlow(
        clientId: 'Iv1.test',
        sleep: (_) async {},
        httpClient: _deviceClient({
          '/login/oauth/access_token': [
            {'error': 'access_denied', 'error_description': 'user declined'},
          ],
        }),
      );
      addTearDown(flow.close);

      expect(
        () => flow.pollForToken(code),
        throwsA(isA<GitHubDeviceFlowException>()
            .having((e) => e.error, 'error', 'access_denied')),
      );
    });

    test('gives up when the code has already expired', () async {
      final flow = GitHubDeviceFlow(
        clientId: 'Iv1.test',
        sleep: (_) async {},
        httpClient: _deviceClient({
          '/login/oauth/access_token': [
            {'error': 'authorization_pending'},
          ],
        }),
      );
      addTearDown(flow.close);

      expect(
        () => flow.pollForToken(const GitHubDeviceCode(
          userCode: 'ABCD-1234',
          verificationUri: 'https://github.com/login/device',
          deviceCode: 'dev-1',
          expiresIn: Duration.zero,
          interval: Duration(seconds: 5),
        )),
        throwsA(isA<GitHubDeviceFlowException>()
            .having((e) => e.error, 'error', 'expired_token')),
      );
    });
  });

  test('authorize hands the code to the caller before polling', () async {
    GitHubDeviceCode? shown;
    final flow = GitHubDeviceFlow(
      clientId: 'Iv1.test',
      sleep: (_) async {},
      httpClient: _deviceClient({
        '/login/device/code': [
          {
            'device_code': 'dev-1',
            'user_code': 'ABCD-1234',
            'verification_uri': 'https://github.com/login/device',
            'expires_in': 900,
            'interval': 5,
          },
        ],
        '/login/oauth/access_token': [
          {'access_token': 'ghu_token'},
        ],
      }),
    );
    addTearDown(flow.close);

    final token = await flow.authorize(onUserCode: (c) => shown = c);

    expect(shown?.userCode, 'ABCD-1234');
    expect(token, 'ghu_token');
  });
}
