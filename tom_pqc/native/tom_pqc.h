/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The backend interface of tom_pqc: the only symbols the native library
 * exports, and the only ones the Dart side binds (lib/src/native_backend.dart).
 * Another C implementation (liboqs, PQClean) replaces mlkem-native by
 * implementing these functions; the Dart API does not change, and the same
 * known-answer vectors decide whether it may.
 *
 * Every function returns 0 on success and a negative TOM_PQC_ERR_* code on
 * failure; on failure every output buffer is zeroed.
 */
#ifndef TOM_PQC_H
#define TOM_PQC_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#define TOM_PQC_EXPORT __declspec(dllexport)
#else
#define TOM_PQC_EXPORT __attribute__((visibility("default")))
#endif

#define TOM_PQC_ERR_FAIL -1
#define TOM_PQC_ERR_INVALID_PUBLIC_KEY -2
#define TOM_PQC_ERR_INVALID_SECRET_KEY -3
#define TOM_PQC_ERR_RANDOM -4
#define TOM_PQC_ERR_OUT_OF_MEMORY -5

/* ML-KEM-768 (FIPS 203) sizes in bytes. */
#define TOM_PQC_MLKEM768_PUBLICKEYBYTES 1184
#define TOM_PQC_MLKEM768_SECRETKEYBYTES 2400
#define TOM_PQC_MLKEM768_CIPHERTEXTBYTES 1088
#define TOM_PQC_MLKEM768_SHAREDSECRETBYTES 32
#define TOM_PQC_MLKEM768_SEEDBYTES 64
#define TOM_PQC_MLKEM768_ENCAPSCOINBYTES 32

/* The backend: its name, the vendored code and the commit it is pinned to. */
TOM_PQC_EXPORT const char *tom_pqc_backend_name(void);

/* The operating system's generator (tom_pqc_random.c). */
TOM_PQC_EXPORT int tom_pqc_random_bytes(uint8_t *out, size_t len);

/* ML-KEM.KeyGen_internal(d, z) with seed = d || z (FIPS 203, Algorithm 16),
 * the 64-byte seed form `age` stores. */
TOM_PQC_EXPORT int tom_pqc_mlkem768_keypair_derand(
    uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES],
    uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES],
    const uint8_t seed[TOM_PQC_MLKEM768_SEEDBYTES]);

/* ML-KEM.KeyGen (Algorithm 19), seeded from the OS generator. */
TOM_PQC_EXPORT int tom_pqc_mlkem768_keypair(
    uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES],
    uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES]);

/* ML-KEM.Encaps_internal(ek, m) (Algorithm 17), with the input check of
 * Section 7.2. For known-answer tests; callers use tom_pqc_mlkem768_enc. */
TOM_PQC_EXPORT int tom_pqc_mlkem768_enc_derand(
    uint8_t ct[TOM_PQC_MLKEM768_CIPHERTEXTBYTES],
    uint8_t ss[TOM_PQC_MLKEM768_SHAREDSECRETBYTES],
    const uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES],
    const uint8_t coins[TOM_PQC_MLKEM768_ENCAPSCOINBYTES]);

/* ML-KEM.Encaps (Algorithm 20). */
TOM_PQC_EXPORT int tom_pqc_mlkem768_enc(
    uint8_t ct[TOM_PQC_MLKEM768_CIPHERTEXTBYTES],
    uint8_t ss[TOM_PQC_MLKEM768_SHAREDSECRETBYTES],
    const uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES]);

/* ML-KEM.Decaps (Algorithm 21), with the input check of Section 7.3. A
 * ciphertext that does not decrypt yields the implicit-rejection secret, not
 * an error. */
TOM_PQC_EXPORT int tom_pqc_mlkem768_dec(
    uint8_t ss[TOM_PQC_MLKEM768_SHAREDSECRETBYTES],
    const uint8_t ct[TOM_PQC_MLKEM768_CIPHERTEXTBYTES],
    const uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES]);

/* The encapsulation-key check (Section 7.2, modulus check). */
TOM_PQC_EXPORT int tom_pqc_mlkem768_check_pk(
    const uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES]);

/* The decapsulation-key check (Section 7.3, hash check). */
TOM_PQC_EXPORT int tom_pqc_mlkem768_check_sk(
    const uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES]);

/* Secret buffers: native memory the Dart side keeps keys and shared secrets
 * in. tom_pqc_secret_free overwrites the buffer before releasing it, and is
 * what the Dart NativeFinalizer calls, so a secret never outlives its owner
 * in readable memory. */
TOM_PQC_EXPORT uint8_t *tom_pqc_secret_alloc(size_t len);
TOM_PQC_EXPORT void tom_pqc_secret_free(uint8_t *secret);

#endif /* !TOM_PQC_H */
