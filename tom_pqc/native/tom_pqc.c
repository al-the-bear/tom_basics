/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The mlkem-native backend of tom_pqc's backend interface (tom_pqc.h).
 *
 * mlkem-native is built here as one compilation unit with every one of its
 * functions `static` (tom_pqc_mlkem_config.h), so the functions below are
 * the library's whole exported surface. They map mlkem-native's error codes
 * onto TOM_PQC_ERR_* and zero every output on failure.
 */
/* Selected here rather than on the command line, so every toolchain (clang,
 * gcc, MSVC) gets the same configuration without quoting a define. */
#define MLK_CONFIG_FILE "tom_pqc_mlkem_config.h"

#include "tom_pqc.h"

#include <stdlib.h>
#include <string.h>

#include "mlkem-native/mlkem_native.c"
#include "mlkem-native/mlkem_native.h"
#include "tom_pqc_random.h"

#if MLKEM768_PUBLICKEYBYTES != TOM_PQC_MLKEM768_PUBLICKEYBYTES ||   \
    MLKEM768_SECRETKEYBYTES != TOM_PQC_MLKEM768_SECRETKEYBYTES ||   \
    MLKEM768_CIPHERTEXTBYTES != TOM_PQC_MLKEM768_CIPHERTEXTBYTES || \
    MLKEM_BYTES != TOM_PQC_MLKEM768_SHAREDSECRETBYTES
#error "tom_pqc: ML-KEM-768 sizes differ from the backend interface"
#endif

/* The vendored code and its pinned commit; THIRD_PARTY.md and the
 * CHANGELOG name the same. */
#define TOM_PQC_BACKEND_NAME \
  "mlkem-native v2.0.0 (d1b2fe782888bdb761a50336012923180be7f502), portable C"

static int tom_pqc_map_error(int rc)
{
  switch (rc)
  {
    case 0:
      return 0;
    case MLK_ERR_INVALID_PK:
      return TOM_PQC_ERR_INVALID_PUBLIC_KEY;
    case MLK_ERR_INVALID_SK:
      return TOM_PQC_ERR_INVALID_SECRET_KEY;
    case MLK_ERR_RNG_FAIL:
      return TOM_PQC_ERR_RANDOM;
    case MLK_ERR_OUT_OF_MEMORY:
      return TOM_PQC_ERR_OUT_OF_MEMORY;
    default:
      return TOM_PQC_ERR_FAIL;
  }
}

TOM_PQC_EXPORT const char *tom_pqc_backend_name(void)
{
  return TOM_PQC_BACKEND_NAME;
}

TOM_PQC_EXPORT int tom_pqc_random_bytes(uint8_t *out, size_t len)
{
  return tom_pqc_randombytes(out, len) == 0 ? 0 : TOM_PQC_ERR_RANDOM;
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_keypair_derand(
    uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES],
    uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES],
    const uint8_t seed[TOM_PQC_MLKEM768_SEEDBYTES])
{
  int rc = tom_pqc_map_error(tom_pqc_mlkn_keypair_derand(pk, sk, seed));
  if (rc != 0)
  {
    mlk_zeroize(pk, TOM_PQC_MLKEM768_PUBLICKEYBYTES);
    mlk_zeroize(sk, TOM_PQC_MLKEM768_SECRETKEYBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_keypair(
    uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES],
    uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES])
{
  int rc = tom_pqc_map_error(tom_pqc_mlkn_keypair(pk, sk));
  if (rc != 0)
  {
    mlk_zeroize(pk, TOM_PQC_MLKEM768_PUBLICKEYBYTES);
    mlk_zeroize(sk, TOM_PQC_MLKEM768_SECRETKEYBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_enc_derand(
    uint8_t ct[TOM_PQC_MLKEM768_CIPHERTEXTBYTES],
    uint8_t ss[TOM_PQC_MLKEM768_SHAREDSECRETBYTES],
    const uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES],
    const uint8_t coins[TOM_PQC_MLKEM768_ENCAPSCOINBYTES])
{
  int rc = tom_pqc_map_error(tom_pqc_mlkn_enc_derand(ct, ss, pk, coins));
  if (rc != 0)
  {
    mlk_zeroize(ct, TOM_PQC_MLKEM768_CIPHERTEXTBYTES);
    mlk_zeroize(ss, TOM_PQC_MLKEM768_SHAREDSECRETBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_enc(
    uint8_t ct[TOM_PQC_MLKEM768_CIPHERTEXTBYTES],
    uint8_t ss[TOM_PQC_MLKEM768_SHAREDSECRETBYTES],
    const uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES])
{
  int rc = tom_pqc_map_error(tom_pqc_mlkn_enc(ct, ss, pk));
  if (rc != 0)
  {
    mlk_zeroize(ct, TOM_PQC_MLKEM768_CIPHERTEXTBYTES);
    mlk_zeroize(ss, TOM_PQC_MLKEM768_SHAREDSECRETBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_dec(
    uint8_t ss[TOM_PQC_MLKEM768_SHAREDSECRETBYTES],
    const uint8_t ct[TOM_PQC_MLKEM768_CIPHERTEXTBYTES],
    const uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES])
{
  int rc = tom_pqc_map_error(tom_pqc_mlkn_dec(ss, ct, sk));
  if (rc != 0)
  {
    mlk_zeroize(ss, TOM_PQC_MLKEM768_SHAREDSECRETBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_check_pk(
    const uint8_t pk[TOM_PQC_MLKEM768_PUBLICKEYBYTES])
{
  return tom_pqc_map_error(tom_pqc_mlkn_check_pk(pk));
}

TOM_PQC_EXPORT int tom_pqc_mlkem768_check_sk(
    const uint8_t sk[TOM_PQC_MLKEM768_SECRETKEYBYTES])
{
  return tom_pqc_map_error(tom_pqc_mlkn_check_sk(sk));
}

/* A secret buffer is preceded by its length, so the finalizer, which gets
 * only the pointer, knows how much to overwrite. */
typedef struct
{
  size_t len;
  /* Keeps the data that follows aligned for any type. */
  union
  {
    long double ld;
    void *p;
    uint64_t u;
  } align;
} tom_pqc_secret_header;

TOM_PQC_EXPORT uint8_t *tom_pqc_secret_alloc(size_t len)
{
  tom_pqc_secret_header *header;
  if (len > SIZE_MAX - sizeof(tom_pqc_secret_header))
  {
    return NULL;
  }
  header = (tom_pqc_secret_header *)calloc(1, sizeof(tom_pqc_secret_header) + len);
  if (header == NULL)
  {
    return NULL;
  }
  header->len = len;
  return (uint8_t *)(header + 1);
}

TOM_PQC_EXPORT void tom_pqc_secret_free(uint8_t *secret)
{
  tom_pqc_secret_header *header;
  if (secret == NULL)
  {
    return;
  }
  header = ((tom_pqc_secret_header *)secret) - 1;
  mlk_zeroize(secret, header->len);
  mlk_zeroize(header, sizeof(tom_pqc_secret_header));
  free(header);
}
