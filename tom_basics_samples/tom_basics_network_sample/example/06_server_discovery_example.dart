// Finding a running service by scanning the local network.
//
// ServerDiscovery.discover() probes localhost, then each local IPv4, then (by
// default) the /24 subnet, asking every candidate for a JSON status document.
// The first host that answers 200 with a JSON object — and passes the optional
// statusValidator — is returned as a DiscoveredServer. Here we stand up a tiny
// status server on loopback and discover it; we set scanSubnet:false so the
// scan stays local and instant.
//
// Run with: dart run example/06_server_discovery_example.dart
import 'dart:io';

import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  // A minimal status endpoint, the shape ServerDiscovery looks for.
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"service":"orders-api","version":"2.3.0","port":${server.port}}');
    await req.response.close();
  });

  try {
    final found = await ServerDiscovery.discover(
      DiscoveryOptions(
        port: server.port,
        scanSubnet: false,
        statusPath: '/status',
        // Only accept the service we are actually looking for.
        statusValidator: (status) => status['service'] == 'orders-api',
      ),
    );

    if (found == null) {
      print('no server found');
    } else {
      print('service: ${found.service}');
      print('version: ${found.version}');
      print('reported port matches: ${found.port == server.port}');
      print('on loopback: ${found.serverUrl.startsWith('http://127.0.0.1:')}');
    }
  } finally {
    await server.close();
  }

  // expected output:
  // service: orders-api
  // version: 2.3.0
  // reported port matches: true
  // on loopback: true
}
