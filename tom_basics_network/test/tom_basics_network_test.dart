import 'dart:async';

import 'package:tom_basics_network/tom_basics_network.dart';
import 'package:test/test.dart';

void main() {
  group('RetryConfig', () {
    test('default config has correct delays', () {
      const config = RetryConfig.defaultConfig;
      expect(config.retryDelaysMs, equals(kDefaultRetryDelaysMs));
    });

    test('custom config accepts custom delays', () {
      const config = RetryConfig(retryDelaysMs: [100, 200, 300]);
      expect(config.retryDelaysMs, equals([100, 200, 300]));
    });
  });

  group('RetryExhaustedException', () {
    test('toString includes attempts', () {
      final exception = RetryExhaustedException(
        lastError: Exception('test'),
        attempts: 3,
      );
      expect(exception.toString(), contains('3 attempts'));
    });
  });

  group('withRetry', () {
    test('succeeds on first attempt', () async {
      var attempts = 0;
      final result = await withRetry(() async {
        attempts++;
        return 'success';
      });
      expect(result, equals('success'));
      expect(attempts, equals(1));
    });

    test('retries on retryable errors', () async {
      var attempts = 0;
      final result = await withRetry(
        () async {
          attempts++;
          if (attempts < 2) {
            throw TimeoutException('test');
          }
          return 'success';
        },
        config: const RetryConfig(retryDelaysMs: [10]),
      );
      expect(result, equals('success'));
      expect(attempts, equals(2));
    });

    test('throws RetryExhaustedException when all retries fail', () async {
      expect(
        () => withRetry(
          () async => throw TimeoutException('test'),
          config: const RetryConfig(retryDelaysMs: [10, 20]),
        ),
        throwsA(isA<RetryExhaustedException>()),
      );
    });
  });

  group('ServerDiscovery', () {
    test('getLocalIpAddresses returns list', () async {
      final ips = await ServerDiscovery.getLocalIpAddresses();
      expect(ips, isA<List<String>>());
    });

    test('getSubnetAddresses returns 253 addresses', () {
      final addresses = ServerDiscovery.getSubnetAddresses('192.168.1.100');
      // 254 - 1 (skip own IP) = 253 addresses
      expect(addresses.length, equals(253));
      expect(addresses, isNot(contains('192.168.1.100')));
      expect(addresses, contains('192.168.1.1'));
      expect(addresses, contains('192.168.1.254'));
    });

    test('DiscoveryOptions has sensible defaults', () {
      const options = DiscoveryOptions();
      expect(options.port, equals(19880));
      expect(options.timeout, equals(const Duration(milliseconds: 500)));
      expect(options.scanSubnet, isTrue);
      expect(options.statusPath, equals('/status'));
    });

    test('DiscoveryOptions copyWith works', () {
      const options = DiscoveryOptions(port: 8080);
      final copied = options.copyWith(port: 9090, scanSubnet: false);
      expect(copied.port, equals(9090));
      expect(copied.scanSubnet, isFalse);
      expect(copied.timeout, equals(options.timeout));
    });

    test('DiscoveredServer properties work', () {
      const server = DiscoveredServer(
        serverUrl: 'http://localhost:8080',
        status: {'service': 'test', 'version': '1.0', 'port': 8080},
      );
      expect(server.service, equals('test'));
      expect(server.version, equals('1.0'));
      expect(server.port, equals(8080));
      expect(server.toString(), contains('http://localhost:8080'));
    });

    test('DiscoveryFailedException message', () {
      final exception = DiscoveryFailedException('test message');
      expect(exception.toString(), contains('test message'));
    });
  });
}
