// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:ffi';
import 'dart:typed_data';

import 'native_backend.dart';
import 'pqc_exception.dart';

/// Secret bytes kept in native memory: a secret key or a shared secret.
///
/// The bytes never live on the Dart heap unless [extractBytes] copies them
/// there. [dispose] overwrites the native buffer and releases it; a
/// [NativeFinalizer] does the same if the object is collected undisposed, so
/// a secret does not outlive its owner in readable memory. Dispose as soon as
/// the secret is no longer needed: the finalizer runs at the garbage
/// collector's discretion.
final class SecretBytes implements Finalizable {
  SecretBytes._(this._pointer, this.length) {
    _finalizer.attach(
      this,
      _pointer.cast(),
      detach: this,
      externalSize: length,
    );
  }

  /// A buffer of [length] zero bytes in native memory.
  factory SecretBytes.allocate(int length) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'must be positive');
    }
    final pointer = tomPqcSecretAlloc(length);
    if (pointer == nullptr) {
      throw const TomPqcException('out of memory for a secret buffer');
    }
    return SecretBytes._(pointer, length);
  }

  /// A copy of [bytes] in native memory. The caller still owns [bytes] and
  /// should overwrite it (`bytes.fillRange(0, bytes.length, 0)`) once copied.
  factory SecretBytes.fromBytes(Uint8List bytes) {
    final secret = SecretBytes.allocate(bytes.length);
    secret._pointer.asTypedList(bytes.length).setAll(0, bytes);
    return secret;
  }

  static final _finalizer = NativeFinalizer(tomPqcSecretFreePointer);

  final Pointer<Uint8> _pointer;

  /// The number of bytes.
  final int length;

  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// The native buffer, for the backend. Throws once disposed.
  Pointer<Uint8> get pointer {
    if (_disposed) throw StateError('SecretBytes used after dispose()');
    return _pointer;
  }

  /// A copy of the secret on the Dart heap. The copy is the caller's to
  /// overwrite; prefer handing [SecretBytes] on to keeping a copy.
  Uint8List extractBytes() => Uint8List.fromList(pointer.asTypedList(length));

  /// Overwrites and releases the native buffer. Safe to call more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(this);
    tomPqcSecretFree(_pointer);
  }
}
