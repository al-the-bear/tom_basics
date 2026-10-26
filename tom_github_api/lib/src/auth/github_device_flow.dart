import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The first leg of the OAuth device flow: what to show the user.
class GitHubDeviceCode {
  /// The short code the user types into [verificationUri].
  final String userCode;

  /// Where the user goes to enter [userCode].
  final String verificationUri;

  /// Opaque handle this client polls with. Never shown to the user.
  final String deviceCode;

  /// How long [userCode] stays valid.
  final Duration expiresIn;

  /// The minimum poll interval GitHub will tolerate.
  final Duration interval;

  const GitHubDeviceCode({
    required this.userCode,
    required this.verificationUri,
    required this.deviceCode,
    required this.expiresIn,
    required this.interval,
  });

  factory GitHubDeviceCode.fromJson(Map<String, dynamic> json) =>
      GitHubDeviceCode(
        userCode: json['user_code'] as String,
        verificationUri: json['verification_uri'] as String,
        deviceCode: json['device_code'] as String,
        expiresIn: Duration(seconds: (json['expires_in'] as num).toInt()),
        interval: Duration(seconds: (json['interval'] as num?)?.toInt() ?? 5),
      );
}

/// A device-flow authorization that did not produce a token.
class GitHubDeviceFlowException implements Exception {
  /// GitHub's error code — `access_denied`, `expired_token`, … .
  final String error;
  final String? description;

  const GitHubDeviceFlowException(this.error, [this.description]);

  @override
  String toString() =>
      'GitHubDeviceFlowException($error)${description == null ? '' : ': $description'}';
}

/// OAuth **device flow** — browserless authorization for a client that cannot
/// keep a secret.
///
/// The device flow exists precisely because a desktop or mobile app has no
/// safe place to store a client secret; only the public client id is needed.
/// The user authorizes on another device and this client polls until they do.
class GitHubDeviceFlow {
  static const _deviceCodeUrl = 'https://github.com/login/device/code';
  static const _tokenUrl = 'https://github.com/login/oauth/access_token';

  /// The OAuth app's public client id.
  final String clientId;

  final http.Client _http;
  final bool _ownsClient;
  final Future<void> Function(Duration) _sleep;

  GitHubDeviceFlow({
    required this.clientId,
    http.Client? httpClient,
    Future<void> Function(Duration)? sleep,
  })  : _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _sleep = sleep ?? _realSleep;

  static Future<void> _realSleep(Duration d) => Future<void>.delayed(d);

  /// Requests a device code. Show [GitHubDeviceCode.userCode] and
  /// [GitHubDeviceCode.verificationUri] to the user, then call [pollForToken].
  ///
  /// [scopes] for repository storage is typically `['repo']`; a fine-grained
  /// PAT is the alternative when the user prefers per-repository scoping.
  Future<GitHubDeviceCode> requestCode({
    List<String> scopes = const ['repo'],
  }) async {
    final response = await _http.post(
      Uri.parse(_deviceCodeUrl),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'client_id': clientId, 'scope': scopes.join(' ')}),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json['error'] != null) {
      throw GitHubDeviceFlowException(
        json['error'] as String,
        json['error_description'] as String?,
      );
    }
    return GitHubDeviceCode.fromJson(json);
  }

  /// Polls until the user authorizes, returning the access token.
  ///
  /// Honours GitHub's `slow_down` by widening the interval — ignoring it gets
  /// the client rate limited, which turns a slow authorization into a failed
  /// one. Gives up when the code expires or the user declines.
  Future<String> pollForToken(GitHubDeviceCode code) async {
    var interval = code.interval;
    final deadline = DateTime.now().add(code.expiresIn);

    while (DateTime.now().isBefore(deadline)) {
      await _sleep(interval);
      final response = await _http.post(
        Uri.parse(_tokenUrl),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'client_id': clientId,
          'device_code': code.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        }),
      );
      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final token = json['access_token'] as String?;
      if (token != null) return token;

      switch (json['error'] as String?) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += Duration(
            seconds: (json['interval'] as num?)?.toInt() ?? 5,
          );
          continue;
        case final String error:
          throw GitHubDeviceFlowException(
            error,
            json['error_description'] as String?,
          );
        case null:
          throw const GitHubDeviceFlowException(
            'unexpected_response',
            'The token endpoint returned neither a token nor an error.',
          );
      }
    }
    throw const GitHubDeviceFlowException(
      'expired_token',
      'The user did not authorize before the device code expired.',
    );
  }

  /// [requestCode] then [pollForToken]; [onUserCode] is where the app shows
  /// the code and opens the verification page.
  Future<String> authorize({
    List<String> scopes = const ['repo'],
    required FutureOr<void> Function(GitHubDeviceCode) onUserCode,
  }) async {
    final code = await requestCode(scopes: scopes);
    await onUserCode(code);
    return pollForToken(code);
  }

  void close() {
    if (_ownsClient) _http.close();
  }
}
