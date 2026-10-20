/// One SHA-256, so that two callers keying on a hash get the same key.
///
/// Anything that names content by its hash — an asset's identity, a source
/// cache, a prompt record — must compute it the same way everywhere; a hash
/// computed in two places is two hashes the day one of them changes its
/// encoding.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The lowercase hex SHA-256 of [bytes] — 64 characters.
String tomSha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// [tomSha256Hex] over the UTF-8 encoding of [text].
String tomSha256OfText(String text) => tomSha256Hex(utf8.encode(text));
