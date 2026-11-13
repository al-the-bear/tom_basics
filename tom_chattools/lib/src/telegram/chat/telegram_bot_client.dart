/// A minimal Telegram Bot API client over `dart:io`: JSON method calls,
/// multipart uploads and file downloads. No third-party dependency.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// The Bot API refused a call (`ok: false`) or answered with an HTTP error.
class TelegramApiException implements Exception {
  /// The Bot API method that was called, e.g. `sendMessage`.
  final String method;

  /// Telegram's `error_code` (usually the HTTP status), when it gave one.
  final int? errorCode;

  /// Telegram's `description`, or what went wrong.
  final String description;

  const TelegramApiException(this.method, this.description, {this.errorCode});

  @override
  String toString() =>
      'TelegramApiException($method'
      '${errorCode == null ? '' : ', $errorCode'}): $description';
}

/// Calls the Telegram Bot API for one bot token.
class TelegramBotClient {
  /// The bot token from @BotFather.
  final String token;

  /// The API root, `https://api.telegram.org` unless a test points it elsewhere.
  final String baseUrl;

  final HttpClient _http;
  final Random _random = Random();

  TelegramBotClient(
    this.token, {
    String baseUrl = 'https://api.telegram.org',
    HttpClient? httpClient,
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _http = httpClient ?? HttpClient();

  Uri _methodUri(String method) => Uri.parse('$baseUrl/bot$token/$method');

  /// Call [method] with JSON [params] (null values left out); answers the `result`.
  Future<Object?> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    final body = <String, Object?>{
      for (final e in params.entries)
        if (e.value != null) e.key: e.value,
    };
    final request = await _http.postUrl(_methodUri(method));
    request.headers.contentType = ContentType.json;
    request.add(utf8.encode(jsonEncode(body)));
    return _result(method, await request.close());
  }

  /// Call [method] uploading [file] as the multipart field [fileField], with
  /// the other [fields] (null values left out); answers the `result`.
  Future<Object?> upload(
    String method,
    Map<String, Object?> fields,
    String fileField,
    File file, {
    String? fileName,
  }) async {
    final boundary =
        'tomchattools${_random.nextInt(1 << 32)}${DateTime.now().microsecondsSinceEpoch}';
    final request = await _http.postUrl(_methodUri(method));
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    final name = fileName ?? file.uri.pathSegments.last;
    for (final e in fields.entries) {
      if (e.value == null) continue;
      request.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="${e.key}"\r\n\r\n'
          '${e.value}\r\n',
        ),
      );
    }
    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$fileField"; filename="${name.replaceAll('"', '')}"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ),
    );
    await request.addStream(file.openRead());
    request.add(utf8.encode('\r\n--$boundary--\r\n'));
    return _result(method, await request.close());
  }

  /// The bytes of a file Telegram holds, by the `file_path` getFile answered.
  Future<List<int>> download(String filePath) async {
    final request = await _http.getUrl(
      Uri.parse('$baseUrl/file/bot$token/$filePath'),
    );
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw TelegramApiException(
        'download',
        'HTTP ${response.statusCode}',
        errorCode: response.statusCode,
      );
    }
    return bytes;
  }

  /// Close the connections; a long poll in flight ends with an error.
  void close({bool force = true}) => _http.close(force: force);

  Future<Object?> _result(String method, HttpClientResponse response) async {
    final text = await utf8.decodeStream(response);
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw TelegramApiException(
        method,
        'HTTP ${response.statusCode}: not a Bot API answer',
        errorCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw TelegramApiException(
        method,
        'HTTP ${response.statusCode}: not a Bot API answer',
        errorCode: response.statusCode,
      );
    }
    if (decoded['ok'] != true) {
      throw TelegramApiException(
        method,
        decoded['description']?.toString() ?? 'HTTP ${response.statusCode}',
        errorCode: decoded['error_code'] is int
            ? decoded['error_code'] as int
            : response.statusCode,
      );
    }
    return decoded['result'];
  }
}
