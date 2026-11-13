/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The mldsa-native configuration of tom_pqc (selected by tom_pqc_mldsa.c
 * through MLD_CONFIG_FILE; it replaces the vendored mldsa_native_config.h,
 * which stays as upstream ships it). As for mlkem-native
 * (tom_pqc_mlkem_config.h): ML-DSA-65 only, one compilation unit with every
 * mldsa-native function `static`, portable C, randomness from
 * tom_pqc_randombytes.
 */
#ifndef TOM_PQC_MLDSA_CONFIG_H
#define TOM_PQC_MLDSA_CONFIG_H

#define MLD_CONFIG_PARAMETER_SET 65
#define MLD_CONFIG_NAMESPACE_PREFIX tom_pqc_mldn
#define MLD_CONFIG_INTERNAL_API_QUALIFIER static
#define MLD_CONFIG_EXTERNAL_API_QUALIFIER static

#if defined(MLD_BUILD_INTERNAL)
#define MLD_CONFIG_CUSTOM_RANDOMBYTES
#if !defined(__ASSEMBLER__)
#include <stddef.h>
#include <stdint.h>
#include "tom_pqc_random.h"
#include "mldsa-native/src/sys.h"
static MLD_INLINE int mld_randombytes(uint8_t *ptr, size_t len)
{
  return tom_pqc_randombytes(ptr, len);
}
#endif /* !__ASSEMBLER__ */
#endif /* MLD_BUILD_INTERNAL */

#endif /* !TOM_PQC_MLDSA_CONFIG_H */
