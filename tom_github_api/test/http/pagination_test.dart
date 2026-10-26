import 'package:test/test.dart';

import 'package:tom_github_api/src/http/github_http_client.dart';

void main() {
  group('HTTP Utilities', () {
    test('GH-PAG-1: parseLinkHeader extracts next and last URLs [2026-02-13 10:00]', () {
      final header =
          '<https://api.github.com/repos/o/r/issues?page=2&per_page=100>; rel="next", '
          '<https://api.github.com/repos/o/r/issues?page=5&per_page=100>; rel="last"';

      final links = parseLinkHeader(header);

      expect(links['next'], contains('page=2'));
      expect(links['last'], contains('page=5'));
    });

    test('GH-PAG-2: parseLinkHeader returns empty map for null header [2026-02-13 10:00]', () {
      final links = parseLinkHeader(null);
      expect(links, isEmpty);
    });

    test('GH-PAG-3: parseLinkHeader returns empty map for empty string [2026-02-13 10:00]', () {
      final links = parseLinkHeader('');
      expect(links, isEmpty);
    });

    test('GH-PAG-4: parseLinkHeader handles single link [2026-02-13 10:00]', () {
      final header =
          '<https://api.github.com/repos/o/r/issues?page=1&per_page=100>; rel="prev"';

      final links = parseLinkHeader(header);

      expect(links, hasLength(1));
      expect(links['prev'], contains('page=1'));
    });
  });
}
