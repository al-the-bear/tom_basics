/// Secure password hashing using Argon2 for TomBase.
///
/// This library provides password hashing and verification using the Argon2
/// algorithm, which is the winner of the Password Hashing Competition and
/// recommended for secure password storage.
///
/// ## Features
///
/// - Argon2i, Argon2d, and Argon2id variants
/// - Configurable memory, iterations, and parallelism
/// - Automatic salt generation
/// - Hash specification storage for future algorithm changes
///
/// ## Usage
///
/// ```dart
/// // Hash a password
/// final (hash, spec) = TomPasswordHasher.hashPassword('user-password');
/// // Store both hash and spec in your database
///
/// // Verify a password
/// final isValid = TomPasswordHasher.verifyPassword(
///   'user-password',
///   hash,
///   spec,
/// );
/// ```
///
/// ## Storage Format
///
/// The hash is stored as `salt$hash` where both are hex-encoded.
/// The spec is stored as `Argon2;variant,version,iterations,memory,lanes,keyLength`.
library;

// =============================================================================
// Dart SDK Imports
// =============================================================================

import 'dart:math';
import 'dart:typed_data';

// =============================================================================
// Package Imports
// =============================================================================

import 'package:pointycastle/export.dart';

// =============================================================================
// Password Hasher
// =============================================================================

/// Secure password hashing and verification using Argon2.
///
/// [TomPasswordHasher] provides static methods for hashing passwords and
/// verifying them against stored hashes. It uses the Argon2 algorithm with
/// configurable parameters.
///
/// ## Security Considerations
///
/// - Always store both the hash and specification together
/// - The specification allows future algorithm upgrades
/// - Default parameters are tuned for security; adjust for your hardware
///
/// ## Default Configuration
///
/// The default configuration uses:
/// - Argon2i variant (data-independent, resistant to side-channel attacks)
/// - Version 1.3
/// - 4 iterations
/// - 64 MB memory
/// - 4 parallel lanes
/// - 128-byte output
///
/// ## Example
///
/// ```dart
/// // Hash a new password
/// final (hash, spec) = TomPasswordHasher.hashPassword('mySecurePassword123');
///
/// // Later, verify the password
/// if (TomPasswordHasher.verifyPassword('mySecurePassword123', hash, spec)) {
///   print('Password is correct!');
/// }
/// ```
class TomPasswordHasher {
  // ---------------------------------------------------------------------------
  // Global Settings
  // ---------------------------------------------------------------------------

  /// Default salt length in bytes.
  ///
  /// A 16-byte (128-bit) salt is recommended minimum for security.
  static int globalSettingDefaultSaltLength = 16;

  /// Default hash specification string.
  ///
  /// Format: `Argon2;variant,version,iterations,memory,lanes,keyLength`
  ///
  /// Default values:
  /// - Variant: 2i (Argon2i)
  /// - Version: 13 (v1.3)
  /// - Iterations: 4
  /// - Memory: 65536 KB (64 MB)
  /// - Lanes: 4 (parallelism)
  /// - Key Length: 128 bytes
  static String globalSettingDefaultHashSpec = "Argon2;2i,13,4,65536,4,128";

  // ---------------------------------------------------------------------------
  // Password Verification
  // ---------------------------------------------------------------------------

  /// Verifies a password against a stored hash.
  ///
  /// [password] is the plaintext password to verify.
  /// [dbHash] is the stored hash in format `salt$hash`.
  /// [dbHashSpec] is the hash specification used to create the hash.
  ///
  /// Returns true if the password matches, false otherwise.
  ///
  /// ## Example
  ///
  /// ```dart
  /// // Retrieve hash and spec from database
  /// final storedHash = user.passwordHash;
  /// final storedSpec = user.hashSpec;
  ///
  /// if (TomPasswordHasher.verifyPassword(inputPassword, storedHash, storedSpec)) {
  ///   // Password is correct
  /// }
  /// ```
  static bool verifyPassword(
    String password,
    String dbHash,
    String dbHashSpec,
  ) {
    var [salt, hash] = dbHash.split("\$");
    KeyDerivator derivator = buildKeyDerivator(dbHashSpec, salt);
    var hashedPasswordBytes = Uint8List(derivator.keySize);
    derivator.deriveKey(
      Uint8List.fromList(password.codeUnits),
      0,
      hashedPasswordBytes,
      0,
    );
    return hash == toHexString(hashedPasswordBytes);
  }

  // ---------------------------------------------------------------------------
  // Password Hashing
  // ---------------------------------------------------------------------------

  /// Hashes a password using the default configuration.
  ///
  /// [password] is the plaintext password to hash.
  ///
  /// Returns a tuple of (hash, specification):
  /// - `hash`: The salt and hash in format `salt$hash` (hex-encoded)
  /// - `specification`: The algorithm specification for verification
  ///
  /// Both values should be stored together in the database.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final (hash, spec) = TomPasswordHasher.hashPassword('userPassword123');
  /// // Store in database:
  /// // user.passwordHash = hash;
  /// // user.hashSpec = spec;
  /// ```
  static (String, String) hashPassword(String password) {
    String salt = generateSalt(globalSettingDefaultSaltLength);
    String spec = globalSettingDefaultHashSpec;
    KeyDerivator derivator = buildKeyDerivator(spec, salt);
    var hashedPasswordBytes = Uint8List(derivator.keySize);
    derivator.deriveKey(
      Uint8List.fromList(password.codeUnits),
      0,
      hashedPasswordBytes,
      0,
    );
    return ("$salt\$${toHexString(hashedPasswordBytes)}", spec);
  }

  // ---------------------------------------------------------------------------
  // Salt Generation
  // ---------------------------------------------------------------------------

  /// Generates a cryptographically secure random salt.
  ///
  /// [length] is the number of random bytes to generate.
  ///
  /// Returns a hex-encoded string of the salt.
  ///
  /// Uses [Random.secure] for cryptographically strong randomness.
  static String generateSalt(int length) {
    var secureRandom = Random.secure();
    var salt = Uint8List(length);
    for (int i = 0; i < salt.length; i++) {
      salt[i] = secureRandom.nextInt(255);
    }
    return toHexString(salt);
  }

  // ---------------------------------------------------------------------------
  // Key Derivation
  // ---------------------------------------------------------------------------

  /// Builds a key derivator from a specification string.
  ///
  /// [specs] is the algorithm specification (e.g., "Argon2;2i,13,4,65536,4,128").
  /// [salt] is the hex-encoded salt to use (generates new salt if null).
  ///
  /// Returns an initialized [KeyDerivator] ready for password hashing.
  ///
  /// Throws [Exception] if the specification is invalid or unsupported.
  static KeyDerivator buildKeyDerivator([String? specs, String? salt]) {
    String specification = specs ?? globalSettingDefaultHashSpec;
    String saltHexString = salt ?? generateSalt(globalSettingDefaultSaltLength);
    var specParts = specification.split(";");
    if (specParts[0] == "Argon2") {
      var params = makeArgon2Params(specParts[1], saltHexString);
      KeyDerivator result = Argon2BytesGenerator();
      result.init(params);
      return result;
    }
    throw Exception("Invalid key derivator spec $specification");
  }

  /// Creates Argon2 parameters from a specification string.
  ///
  /// [specification] is the parameter string in format:
  /// `variant,version,iterations,memory,lanes,keyLength`
  ///
  /// [saltHexString] is the hex-encoded salt.
  ///
  /// Supported variants:
  /// - `2i`: Argon2i (data-independent, recommended for password hashing)
  /// - `2d`: Argon2d (data-dependent, faster but less secure)
  /// - `2id`: Argon2id (hybrid, recommended for key derivation)
  ///
  /// Supported versions:
  /// - `13`: Version 1.3 (current)
  /// - `10`: Version 1.0 (legacy)
  static Argon2Parameters makeArgon2Params(
    String specification,
    String saltHexString,
  ) {
    var saltBytes = toUint8List(saltHexString);

    var parts = specification.split(",");

    var algoType = 0;
    var algoVersion = 0;
    var iterations = 0;
    var memory = 0;
    var lanes = 0;
    var keyLength = 0;

    if (parts[0] == "2i") {
      algoType = Argon2Parameters.ARGON2_i;
    } else if (parts[0] == "2d") {
      algoType = Argon2Parameters.ARGON2_d;
    } else if (parts[0] == "2id") {
      algoType = Argon2Parameters.ARGON2_id;
    }

    if (parts[1] == "13") {
      algoVersion = Argon2Parameters.ARGON2_VERSION_13;
    } else if (parts[1] == "10") {
      algoVersion = Argon2Parameters.ARGON2_VERSION_10;
    }

    iterations = int.parse(parts[2]);
    memory = int.parse(parts[3]);
    lanes = int.parse(parts[4]);
    keyLength = int.parse(parts[5]);

    return Argon2Parameters(
      algoType,
      saltBytes,
      version: algoVersion,
      iterations: iterations,
      memory: memory,
      lanes: lanes,
      desiredKeyLength: keyLength,
    );
  }

  /// Converts Argon2 parameters back to a specification string.
  ///
  /// [params] is the Argon2Parameters object to convert.
  ///
  /// Returns a tuple of (specification, salt) both as strings.
  ///
  /// This is useful for storing the parameters alongside the hash
  /// for future verification.
  static (String, String) parameterString(Argon2Parameters params) {
    String result = "";
    if (params.type == Argon2Parameters.ARGON2_i) {
      result += "2i";
    }
    if (params.version == Argon2Parameters.ARGON2_VERSION_13) {
      result += ",13";
    }
    result += ",${params.iterations}";
    result += ",${params.memory}";
    result += ",${params.lanes}";
    result += ",${params.desiredKeyLength}";
    String result2 = toHexString(params.salt);
    return (result, result2);
  }

  // ---------------------------------------------------------------------------
  // Hex Encoding Utilities
  // ---------------------------------------------------------------------------

  /// Converts a byte list to a hex-encoded string.
  ///
  /// [list] is the byte array to convert.
  ///
  /// Returns a lowercase hex string (e.g., "0a1b2c3d").
  static String toHexString(Uint8List list) {
    StringBuffer b = StringBuffer();
    for (var byte in list) {
      if (byte < 16) {
        b.write("0${byte.toRadixString(16)}");
      } else {
        b.write(byte.toRadixString(16));
      }
    }
    var result = b.toString();
    return result;
  }

  /// Converts a hex-encoded string to a byte list.
  ///
  /// [hexString] is the hex string to convert (must have even length).
  ///
  /// Returns a [Uint8List] of the decoded bytes.
  static Uint8List toUint8List(String hexString) {
    var result = Uint8List(hexString.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hexString.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
