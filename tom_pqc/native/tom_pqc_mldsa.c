/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The mldsa-native backend of tom_pqc's backend interface (tom_pqc.h): ML-DSA-65
 * (FIPS 204). A compilation unit of its own, so mldsa-native's internal names
 * and headers never meet mlkem-native's (tom_pqc.c); every mldsa-native
 * function is `static` (tom_pqc_mldsa_config.h).
 */
#define MLD_CONFIG_FILE "tom_pqc_mldsa_config.h"

#include "tom_pqc.h"

#include "mldsa-native/mldsa_native.c"
#include "mldsa-native/mldsa_native.h"

#if MLDSA65_PUBLICKEYBYTES != TOM_PQC_MLDSA65_PUBLICKEYBYTES || \
    MLDSA65_SECRETKEYBYTES != TOM_PQC_MLDSA65_SECRETKEYBYTES || \
    MLDSA65_BYTES != TOM_PQC_MLDSA65_SIGNATUREBYTES ||          \
    MLDSA_SEEDBYTES != TOM_PQC_MLDSA65_SEEDBYTES ||             \
    MLDSA_RNDBYTES != TOM_PQC_MLDSA65_RNDBYTES ||               \
    MLDSA_CRHBYTES != TOM_PQC_MLDSA65_MUBYTES
#error "tom_pqc: ML-DSA-65 sizes differ from the backend interface"
#endif

static int tom_pqc_mldsa_map_error(int rc)
{
  switch (rc)
  {
    case 0:
      return 0;
    case MLD_ERR_RNG_FAIL:
      return TOM_PQC_ERR_RANDOM;
    case MLD_ERR_OUT_OF_MEMORY:
      return TOM_PQC_ERR_OUT_OF_MEMORY;
    case MLD_ERR_INVALID_SIGNATURE:
      return TOM_PQC_ERR_INVALID_SIGNATURE;
    case MLD_ERR_INVALID_KEY:
      return TOM_PQC_ERR_INVALID_SECRET_KEY;
    case MLD_ERR_INVALID_ARG:
      return TOM_PQC_ERR_INVALID_ARGUMENT;
    default:
      return TOM_PQC_ERR_FAIL;
  }
}

TOM_PQC_EXPORT const char *tom_pqc_mldsa_backend_name(void)
{
  return "mldsa-native v2.0.0 (834a90d5e846ffa1e1611bd24e160bb2e9b86d35), "
         "portable C";
}

TOM_PQC_EXPORT int tom_pqc_mldsa65_keypair_derand(
    uint8_t pk[TOM_PQC_MLDSA65_PUBLICKEYBYTES],
    uint8_t sk[TOM_PQC_MLDSA65_SECRETKEYBYTES],
    const uint8_t seed[TOM_PQC_MLDSA65_SEEDBYTES])
{
  int rc = tom_pqc_mldsa_map_error(tom_pqc_mldn_keypair_internal(pk, sk, seed));
  if (rc != 0)
  {
    mld_zeroize(pk, TOM_PQC_MLDSA65_PUBLICKEYBYTES);
    mld_zeroize(sk, TOM_PQC_MLDSA65_SECRETKEYBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mldsa65_pk_from_sk(
    uint8_t pk[TOM_PQC_MLDSA65_PUBLICKEYBYTES],
    const uint8_t sk[TOM_PQC_MLDSA65_SECRETKEYBYTES])
{
  int rc = tom_pqc_mldsa_map_error(tom_pqc_mldn_pk_from_sk(pk, sk));
  if (rc != 0)
  {
    mld_zeroize(pk, TOM_PQC_MLDSA65_PUBLICKEYBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mldsa65_sign(
    uint8_t sig[TOM_PQC_MLDSA65_SIGNATUREBYTES], const uint8_t *m, size_t mlen,
    const uint8_t *ctx, size_t ctxlen,
    const uint8_t sk[TOM_PQC_MLDSA65_SECRETKEYBYTES])
{
  int rc;
  if (ctxlen > 255)
  {
    return TOM_PQC_ERR_INVALID_ARGUMENT;
  }
  rc = tom_pqc_mldsa_map_error(
      tom_pqc_mldn_signature(sig, m, mlen, ctx, ctxlen, sk));
  if (rc != 0)
  {
    mld_zeroize(sig, TOM_PQC_MLDSA65_SIGNATUREBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mldsa65_sign_internal(
    uint8_t sig[TOM_PQC_MLDSA65_SIGNATUREBYTES], const uint8_t *m, size_t mlen,
    const uint8_t *pre, size_t prelen,
    const uint8_t rnd[TOM_PQC_MLDSA65_RNDBYTES],
    const uint8_t sk[TOM_PQC_MLDSA65_SECRETKEYBYTES], int externalmu)
{
  int rc = tom_pqc_mldsa_map_error(tom_pqc_mldn_signature_internal(
      sig, m, mlen, pre, prelen, rnd, sk, externalmu));
  if (rc != 0)
  {
    mld_zeroize(sig, TOM_PQC_MLDSA65_SIGNATUREBYTES);
  }
  return rc;
}

TOM_PQC_EXPORT int tom_pqc_mldsa65_verify(
    const uint8_t sig[TOM_PQC_MLDSA65_SIGNATUREBYTES], const uint8_t *m,
    size_t mlen, const uint8_t *ctx, size_t ctxlen,
    const uint8_t pk[TOM_PQC_MLDSA65_PUBLICKEYBYTES])
{
  if (ctxlen > 255)
  {
    return TOM_PQC_ERR_INVALID_ARGUMENT;
  }
  return tom_pqc_mldsa_map_error(
      tom_pqc_mldn_verify(sig, m, mlen, ctx, ctxlen, pk));
}

TOM_PQC_EXPORT int tom_pqc_mldsa65_verify_internal(
    const uint8_t sig[TOM_PQC_MLDSA65_SIGNATUREBYTES], const uint8_t *m,
    size_t mlen, const uint8_t *pre, size_t prelen,
    const uint8_t pk[TOM_PQC_MLDSA65_PUBLICKEYBYTES], int externalmu)
{
  return tom_pqc_mldsa_map_error(tom_pqc_mldn_verify_internal(
      sig, m, mlen, pre, prelen, pk, externalmu));
}
