// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// The FFI binding of the native library's backend interface
/// (`native/tom_pqc.h`), built by `hook/build.dart`. Nothing but
/// [NativePqcBackend] uses these symbols.
@DefaultAsset('package:tom_pqc/src/native_backend.dart')
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart' show Utf8;

@Native<Pointer<Utf8> Function()>(symbol: 'tom_pqc_backend_name')
external Pointer<Utf8> tomPqcBackendName();

@Native<Int32 Function(Pointer<Uint8>, Size)>(symbol: 'tom_pqc_random_bytes')
external int tomPqcRandomBytes(Pointer<Uint8> out, int length);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'tom_pqc_mlkem768_keypair_derand',
)
external int tomPqcMlKem768KeypairDerand(
  Pointer<Uint8> publicKey,
  Pointer<Uint8> secretKey,
  Pointer<Uint8> seed,
);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'tom_pqc_mlkem768_keypair',
)
external int tomPqcMlKem768Keypair(
  Pointer<Uint8> publicKey,
  Pointer<Uint8> secretKey,
);

@Native<
  Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)
>(symbol: 'tom_pqc_mlkem768_enc_derand')
external int tomPqcMlKem768EncDerand(
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> publicKey,
  Pointer<Uint8> coins,
);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'tom_pqc_mlkem768_enc',
)
external int tomPqcMlKem768Enc(
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> publicKey,
);

@Native<Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'tom_pqc_mlkem768_dec',
)
external int tomPqcMlKem768Dec(
  Pointer<Uint8> sharedSecret,
  Pointer<Uint8> ciphertext,
  Pointer<Uint8> secretKey,
);

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'tom_pqc_mlkem768_check_pk')
external int tomPqcMlKem768CheckPk(Pointer<Uint8> publicKey);

@Native<Int32 Function(Pointer<Uint8>)>(symbol: 'tom_pqc_mlkem768_check_sk')
external int tomPqcMlKem768CheckSk(Pointer<Uint8> secretKey);

@Native<Pointer<Uint8> Function(Size)>(symbol: 'tom_pqc_secret_alloc')
external Pointer<Uint8> tomPqcSecretAlloc(int length);

@Native<Void Function(Pointer<Uint8>)>(symbol: 'tom_pqc_secret_free')
external void tomPqcSecretFree(Pointer<Uint8> secret);

/// The address of `tom_pqc_secret_free`, for the [NativeFinalizer] of a
/// secret buffer.
final Pointer<NativeFinalizerFunction> tomPqcSecretFreePointer =
    Native.addressOf<NativeFunction<Void Function(Pointer<Uint8>)>>(
      tomPqcSecretFree,
    ).cast();
