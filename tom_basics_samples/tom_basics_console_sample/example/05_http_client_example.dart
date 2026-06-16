// The IO HTTP client, exercised against a local server (runs offline).
//
// httpClient() returns a package:http Client backed by dart:io's HttpClient.
// Its one non-default behaviour is a convenience: invalid TLS certificates are
// accepted *only* for localhost / 127.0.0.1 / 0.0.0.0, so a self-signed dev
// server just works while remote calls stay strict. To keep this example
// hermetic we stand up a tiny local HTTP server and call it.
//
// Run with: dart run example/05_http_client_example.dart
import 'dart:io';

import 'package:tom_basics_console/tom_basics_console.dart';

Future<void> main() async {
  // A throwaway local server so the example needs no network.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = 200
      ..write('{"status":"ok"}');
    await req.response.close();
  });

  final client = TomStandalonePlatformUtils().httpClient();
  try {
    final res = await client.get(
      Uri.parse('http://localhost:${server.port}/health'),
    );
    print('status: ${res.statusCode}');
    print('body:   ${res.body}');
  } finally {
    client.close();
    await server.close();
  }

  // expected output:
  // status: 200
  // body:   {"status":"ok"}
}
