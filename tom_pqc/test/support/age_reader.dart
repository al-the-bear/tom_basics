/// A minimal age v1 reader for the age testkit's hybrid vectors: enough of
/// age (C2SP age.md) to decrypt a file to an `mlkem768x25519` or `X25519`
/// identity and classify a failure the way the testkit expects. Test-only:
/// it exists to show that tom_pqc's MLKEM768-X25519 is the KEM age uses.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:tom_pqc/tom_pqc.dart';

/// How decrypting a file ended, in the testkit's words.
enum AgeOutcome {
  success,
  noMatch,
  headerFailure,
  payloadFailure,
  armorFailure,
}

/// The outcome and, on success, the payload.
typedef AgeResult = ({AgeOutcome outcome, Uint8List? payload});

/// A testkit vector: its header fields (repeatable keys as lists) and the
/// age file after the blank line.
final class AgeVector {
  AgeVector(this.fields, this.file);

  factory AgeVector.read(File path) {
    final bytes = path.readAsBytesSync();
    final fields = <String, List<String>>{};
    var pos = 0;
    while (true) {
      final end = bytes.indexOf(0x0a, pos);
      final line = ascii.decode(bytes.sublist(pos, end));
      pos = end + 1;
      if (line.isEmpty) break;
      final colon = line.indexOf(': ');
      (fields[line.substring(0, colon)] ??= []).add(line.substring(colon + 2));
    }
    var file = Uint8List.sublistView(bytes, pos);
    if (fields['compressed']?.single == 'zlib') {
      file = Uint8List.fromList(zlib.decode(file));
    }
    return AgeVector(fields, file);
  }

  final Map<String, List<String>> fields;
  final Uint8List file;

  String get expect => fields['expect']!.single;
  bool get armored => fields['armored']?.single == 'yes';
  List<String> get identities => fields['identity'] ?? const [];
  String? get payloadHash => fields['payload']?.single;
}

final class _HeaderFailure implements Exception {
  _HeaderFailure(this.reason);
  final String reason;
  @override
  String toString() => 'header failure: $reason';
}

/// Decrypts [file] (armored when [armored]) with [identities] (Bech32 age
/// identities).
Future<AgeResult> decryptAge(
  Uint8List file,
  List<String> identities, {
  bool armored = false,
}) async {
  if (armored) {
    final dearmored = _dearmor(file);
    if (dearmored == null) {
      return (outcome: AgeOutcome.armorFailure, payload: null);
    }
    file = dearmored;
  }
  final _Header header;
  try {
    header = _Header.parse(file);
  } on _HeaderFailure {
    return (outcome: AgeOutcome.headerFailure, payload: null);
  }
  Uint8List? fileKey;
  try {
    for (final identity in identities) {
      fileKey = await _unwrap(header.stanzas, identity);
      if (fileKey != null) break;
    }
  } on _HeaderFailure {
    return (outcome: AgeOutcome.headerFailure, payload: null);
  }
  if (fileKey == null) return (outcome: AgeOutcome.noMatch, payload: null);
  final macKey = _hkdf(fileKey, Uint8List(0), utf8.encode('header'), 32);
  final mac = crypto.Hmac(crypto.sha256, macKey).convert(header.macInput).bytes;
  if (!_equal(Uint8List.fromList(mac), header.mac)) {
    return (outcome: AgeOutcome.headerFailure, payload: null);
  }
  return _payload(Uint8List.sublistView(file, header.length), fileKey);
}

/// One stanza: its arguments (the type first) and its body.
typedef _Stanza = ({List<String> args, Uint8List body});

final class _Header {
  _Header(this.stanzas, this.macInput, this.mac, this.length);

  final List<_Stanza> stanzas;
  final Uint8List macInput;
  final Uint8List mac;
  final int length;

  static _Header parse(Uint8List file) {
    var pos = 0;
    String line() {
      final end = file.indexOf(0x0a, pos);
      if (end < 0) throw _HeaderFailure('unterminated line');
      final text = file.sublist(pos, end);
      if (text.any((b) => b < 0x20 || b > 0x7e)) {
        throw _HeaderFailure('non-printable header byte');
      }
      pos = end + 1;
      return ascii.decode(text);
    }

    if (line() != 'age-encryption.org/v1') {
      throw _HeaderFailure('version line');
    }
    final stanzas = <_Stanza>[];
    while (true) {
      final start = pos;
      final l = line();
      if (l.startsWith('--- ')) {
        final macInput = Uint8List.sublistView(file, 0, start + 3);
        final mac = _canonicalBase64(l.substring(4));
        if (mac == null || mac.length != 32) throw _HeaderFailure('MAC');
        return _Header(stanzas, macInput, mac, pos);
      }
      if (!l.startsWith('-> ')) throw _HeaderFailure('stanza line');
      final args = l.substring(3).split(' ');
      if (args.any((a) => a.isEmpty)) throw _HeaderFailure('empty argument');
      final body = BytesBuilder();
      while (true) {
        final b = line();
        final bytes = _canonicalBase64(b);
        if (bytes == null || b.length > 64) throw _HeaderFailure('body');
        body.add(bytes);
        if (b.length < 64) break;
      }
      stanzas.add((args: args, body: body.toBytes()));
    }
  }
}

/// The file key one of [stanzas] yields for [identity], or null when none
/// does; a stanza of the identity's type that breaks the rules is a header
/// failure.
Future<Uint8List?> _unwrap(List<_Stanza> stanzas, String identity) async {
  final upper = identity.toUpperCase();
  if (upper.startsWith('AGE-SECRET-KEY-PQ-1')) {
    final seed = _bech32('age-secret-key-pq-', identity);
    for (final s in stanzas.where((s) => s.args.first == 'mlkem768x25519')) {
      if (s.args.length != 2) throw _HeaderFailure('mlkem768x25519 arguments');
      final enc = _canonicalBase64(s.args[1]);
      if (enc == null || enc.length != MlKem768X25519.ciphertextLength) {
        throw _HeaderFailure('mlkem768x25519 enc');
      }
      if (s.body.length != 32) throw _HeaderFailure('mlkem768x25519 body');
      final Uint8List? key;
      try {
        key = await hpkeOpenMlKem768X25519(
          enc,
          s.body,
          seed,
          ascii.encode('age-encryption.org/mlkem768x25519'),
        );
      } on TomPqcException catch (e) {
        throw _HeaderFailure(e.message);
      }
      if (key != null) return key;
    }
    return null;
  }
  if (upper.startsWith('AGE-SECRET-KEY-1')) {
    final secret = _bech32('age-secret-key-', identity);
    for (final s in stanzas.where((s) => s.args.first == 'X25519')) {
      if (s.args.length != 2) throw _HeaderFailure('X25519 arguments');
      final share = _canonicalBase64(s.args[1]);
      if (share == null || share.length != 32) {
        throw _HeaderFailure('X25519 share');
      }
      if (s.body.length != 32) throw _HeaderFailure('X25519 body');
      final key = await _x25519Open(share, s.body, secret);
      if (key != null) return key;
    }
    return null;
  }
  throw ArgumentError('not an age identity: $identity');
}

/// HPKE OpenBase (RFC 9180) with KEM MLKEM768-X25519 (0x647a), HKDF-SHA256
/// and ChaCha20Poly1305: the plaintext of [sealed] (sequence number 0) for
/// the 32-byte [seed], or null when it does not authenticate. age uses it
/// with info "age-encryption.org/mlkem768x25519". A low-order X25519 share
/// throws TomPqcException.
Future<Uint8List?> hpkeOpenMlKem768X25519(
  Uint8List enc,
  Uint8List sealed,
  Uint8List seed,
  List<int> info,
) async {
  final sk = SecretBytes.fromBytes(seed);
  final SecretBytes shared;
  try {
    shared = await MlKem768X25519.decapsulate(enc, sk);
  } finally {
    sk.dispose();
  }
  final ss = shared.extractBytes();
  shared.dispose();
  final suite = Uint8List.fromList([
    ...ascii.encode('HPKE'),
    0x64, 0x7a, 0x00, 0x01, 0x00, 0x03, //
  ]);
  Uint8List extract(List<int> salt, String label, List<int> ikm) => _extract(
    salt,
    [...ascii.encode('HPKE-v1'), ...suite, ...ascii.encode(label), ...ikm],
  );
  Uint8List expand(List<int> prk, String label, List<int> info, int length) =>
      _expand(prk, [
        length >> 8,
        length % 256,
        ...ascii.encode('HPKE-v1'),
        ...suite,
        ...ascii.encode(label),
        ...info,
      ], length);
  final context = [
    0,
    ...extract(const [], 'psk_id_hash', const []),
    ...extract(const [], 'info_hash', info),
  ];
  final secret = extract(ss, 'secret', const []);
  final key = expand(secret, 'key', context, 32);
  final nonce = expand(secret, 'base_nonce', context, 12);
  return _chachaOpen(key, nonce, sealed);
}

/// age's X25519 recipient: X25519 with the share, HKDF-SHA256 with salt
/// share || recipient, ChaCha20Poly1305 with a zero nonce.
Future<Uint8List?> _x25519Open(
  Uint8List share,
  Uint8List body,
  Uint8List secret,
) async {
  final x = X25519();
  final pair = await x.newKeyPairFromSeed(secret);
  final recipient = (await pair.extractPublicKey()).bytes;
  final shared = await (await x.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: SimplePublicKey(share, type: KeyPairType.x25519),
  )).extractBytes();
  if (shared.every((b) => b == 0)) throw _HeaderFailure('X25519 low order');
  final key = _hkdf(
    Uint8List.fromList(shared),
    Uint8List.fromList([...share, ...recipient]),
    utf8.encode('age-encryption.org/v1/X25519'),
    32,
  );
  return _chachaOpen(key, Uint8List(12), body);
}

Future<AgeResult> _payload(Uint8List rest, Uint8List fileKey) async {
  if (rest.length < 16) {
    return (outcome: AgeOutcome.payloadFailure, payload: null);
  }
  final key = _hkdf(
    fileKey,
    Uint8List.sublistView(rest, 0, 16),
    utf8.encode('payload'),
    32,
  );
  final out = BytesBuilder();
  const chunk = 64 * 1024 + 16;
  var pos = 16;
  var counter = 0;
  while (true) {
    final end = (pos + chunk <= rest.length) ? pos + chunk : rest.length;
    final last = end == rest.length;
    final nonce = Uint8List(12);
    var c = counter;
    for (var i = 10; i >= 0; i--) {
      nonce[i] = c % 256;
      c = c ~/ 256;
    }
    if (last) nonce[11] = 1;
    final plain = await _chachaOpen(
      key,
      nonce,
      Uint8List.sublistView(rest, pos, end),
    );
    if (plain == null || (plain.isEmpty && counter > 0)) {
      return (outcome: AgeOutcome.payloadFailure, payload: out.toBytes());
    }
    out.add(plain);
    if (last) break;
    pos = end;
    counter++;
  }
  return (outcome: AgeOutcome.success, payload: out.toBytes());
}

Future<Uint8List?> _chachaOpen(
  Uint8List key,
  Uint8List nonce,
  Uint8List sealed,
) async {
  if (sealed.length < 16) return null;
  try {
    final plain = await Chacha20.poly1305Aead().decrypt(
      SecretBox(
        sealed.sublist(0, sealed.length - 16),
        nonce: nonce,
        mac: Mac(sealed.sublist(sealed.length - 16)),
      ),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    return null;
  }
}

Uint8List _extract(List<int> salt, List<int> ikm) => Uint8List.fromList(
  crypto.Hmac(
    crypto.sha256,
    salt.isEmpty ? List<int>.filled(32, 0) : salt,
  ).convert(ikm).bytes,
);

Uint8List _expand(List<int> prk, List<int> info, int length) {
  final out = BytesBuilder();
  var t = <int>[];
  for (var i = 1; out.length < length; i++) {
    t = crypto.Hmac(crypto.sha256, prk).convert([...t, ...info, i]).bytes;
    out.add(t);
  }
  return Uint8List.sublistView(out.toBytes(), 0, length);
}

Uint8List _hkdf(Uint8List ikm, Uint8List salt, List<int> info, int length) =>
    _expand(_extract(salt, ikm), info, length);

/// Standard base64 without padding, refused unless canonical.
Uint8List? _canonicalBase64(String text) {
  if (text.contains('=')) return null;
  try {
    final padded = text.padRight((text.length + 3) ~/ 4 * 4, '=');
    final bytes = base64.decode(padded);
    final again = base64.encode(bytes).replaceAll('=', '');
    return again == text ? bytes : null;
  } on FormatException {
    return null;
  }
}

Uint8List? _dearmor(Uint8List file) {
  final text = ascii.decode(file, allowInvalid: true).trim();
  final lines = text.split(RegExp(r'\r?\n'));
  if (lines.length < 3 ||
      lines.first != '-----BEGIN AGE ENCRYPTED FILE-----' ||
      lines.last != '-----END AGE ENCRYPTED FILE-----') {
    return null;
  }
  final body = lines.sublist(1, lines.length - 1);
  for (final (i, l) in body.indexed) {
    if (l.length > 64 || (i < body.length - 1 && l.length != 64)) return null;
  }
  try {
    return base64.decode(body.join());
  } on FormatException {
    return null;
  }
}

/// The data of the Bech32 string [text] with human-readable part [hrp]
/// (lowercase), checksum checked.
Uint8List _bech32(String hrp, String text) {
  const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final lower = text.toLowerCase();
  if (lower != text && text.toUpperCase() != text) {
    throw ArgumentError('mixed-case Bech32');
  }
  final sep = lower.lastIndexOf('1');
  if (lower.substring(0, sep) != hrp) {
    throw ArgumentError('Bech32 HRP ${lower.substring(0, sep)}');
  }
  final values = [
    for (final c in lower.substring(sep + 1).split('')) charset.indexOf(c),
  ];
  if (values.any((v) => v < 0)) throw ArgumentError('Bech32 character');
  int polymod(List<int> v) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final x in v) {
      final top = chk >> 25;
      chk = ((chk % 0x2000000) << 5) ^ x;
      for (var i = 0; i < 5; i++) {
        if ((top >> i).isOdd) chk ^= gen[i];
      }
    }
    return chk;
  }

  final h = lower.substring(0, sep).codeUnits;
  final expanded = [for (final c in h) c >> 5, 0, for (final c in h) c % 32];
  if (polymod([...expanded, ...values]) != 1) {
    throw ArgumentError('Bech32 checksum');
  }
  final data = values.sublist(0, values.length - 6);
  final out = <int>[];
  var acc = 0;
  var bits = 0;
  for (final v in data) {
    acc = (acc << 5) | v;
    bits += 5;
    while (bits >= 8) {
      bits -= 8;
      out.add((acc >> bits) % 256);
    }
  }
  return Uint8List.fromList(out);
}

bool _equal(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// The SHA-256 of [bytes] in lowercase hex, as the testkit writes it.
String sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();
