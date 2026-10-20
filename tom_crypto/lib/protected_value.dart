/// A secret held in memory behind one explicit accessor:
/// [TomProtectedValue].
///
/// An entry point of its own, because it needs only `tom_basics`: a package
/// that holds secrets in memory takes this without linking the JWT and RSA
/// libraries the `tom_crypto.dart` barrel brings.
library;

export 'src/protected_value.dart';
