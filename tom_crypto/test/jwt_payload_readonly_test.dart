/// Guards that a decoded token's payload cannot be edited through the getter
/// every consumer reaches it by.
///
/// A JWT's public section is plain base64, so its claims are whatever the
/// holder last wrote there. On the server the answer to that is checking the
/// signature — nothing here replaces it. What this covers is the narrower
/// property that made the exposure so cheap to exploit: `payload` handed back
/// the decoded map itself, so editing a claim was a single statement and the
/// token afterwards had no way to tell what it had decoded from what somebody
/// assigned.
library;

import 'package:tom_crypto/tom_crypto.dart';
import 'package:test/test.dart';

TomClientJwtToken _token([
  Map<String, dynamic> claims = const {'userId': 'u'},
]) => TomClientJwtToken(
  TomServerJwtToken(Map<String, dynamic>.from(claims)).getJWT('issuer'),
  decrypt: false,
);

void main() {
  group('TomClientJwtToken.payload is unmodifiable', () {
    test('assigning to an existing claim throws', () {
      final payload = _token({'userId': 'u', 'role': 'user'}).payload!;
      expect(payload['role'], 'user');
      expect(() => payload['role'] = 'admin', throwsUnsupportedError);
    });

    test('adding a claim throws', () {
      final payload = _token().payload!;
      expect(
        () => payload['twoFactorEnrolmentSkippable'] = true,
        throwsUnsupportedError,
      );
    });

    test('removing a claim throws', () {
      final payload = _token().payload!;
      expect(() => payload.remove('userId'), throwsUnsupportedError);
    });

    test('clearing throws', () {
      final payload = _token().payload!;
      expect(payload.clear, throwsUnsupportedError);
    });
  });

  group('the view still reads', () {
    test('every claim the token was issued with is present', () {
      final payload = _token({'userId': 'u', 'role': 'user'}).payload!;
      expect(payload['userId'], 'u');
      expect(payload['role'], 'user');
    });

    test('a refused edit leaves the token unchanged', () {
      // The point of the guarantee: the second read has to agree with the
      // first, which is what a caller downstream of a signature check relies
      // on. A copy that were merely *a* copy would satisfy the throw above and
      // still let the next reader see something different.
      final token = _token({'userId': 'u', 'role': 'user'});
      try {
        token.payload!['role'] = 'admin';
      } on UnsupportedError {
        // expected
      }
      expect(token.payload!['role'], 'user');
    });
  });
}
