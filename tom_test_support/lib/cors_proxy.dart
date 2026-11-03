/// A reverse proxy that adds the CORS headers a web page needs, for browser
/// suites against servers that send none.
///
/// A page may read a response from another origin only when the response
/// allows it, and a request with an `Authorization` header is preceded by a
/// preflight `OPTIONS` the server must answer. Gitea's own `[cors]` setting
/// covers its `/api` routes and not git's smart-HTTP endpoints (measured on
/// 1.22), so a git server a page can reach is one behind a proxy that adds
/// the headers — the way a deployment would put nginx in front of it. This is
/// that proxy, in-process, for the length of a suite.
library;

import 'dart:io';

/// A running proxy in front of [target].
class TomCorsProxy {
  TomCorsProxy._(this._server, this.target);

  final HttpServer _server;

  /// The server requests are forwarded to.
  final Uri target;

  final HttpClient _client = HttpClient();

  /// The proxy's address: [target] with its scheme, host and port replaced.
  Uri get url => target.replace(
    scheme: 'http',
    host: _server.address.address,
    port: _server.port,
  );

  /// Starts a proxy on a free loopback port in front of [target].
  static Future<TomCorsProxy> start(Uri target) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = TomCorsProxy._(server, target);
    server.listen(proxy._handle);
    return proxy;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, POST, OPTIONS')
      ..set(
        'Access-Control-Allow-Headers',
        request.headers.value('access-control-request-headers') ??
            'authorization, content-type, git-protocol',
      )
      ..set('Access-Control-Max-Age', '600');
    if (request.method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }
    try {
      final forward = await _client.openUrl(
        request.method,
        target.replace(path: request.uri.path, query: request.uri.query),
      );
      forward.followRedirects = false;
      request.headers.forEach((name, values) {
        if (name == 'host' || name == 'origin' || name == 'referer') return;
        for (final value in values) {
          forward.headers.add(name, value);
        }
      });
      await forward.addStream(request);
      final answer = await forward.close();
      response.statusCode = answer.statusCode;
      answer.headers.forEach((name, values) {
        if (name == 'transfer-encoding' || name == 'content-length') return;
        for (final value in values) {
          response.headers.add(name, value);
        }
      });
      await response.addStream(answer);
    } on Object catch (e) {
      response.statusCode = HttpStatus.badGateway;
      response.write('proxy: $e');
    }
    await response.close();
  }

  /// Stops the proxy.
  Future<void> stop() async {
    _client.close(force: true);
    await _server.close(force: true);
  }
}
