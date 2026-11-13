/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The mlkem-native configuration of tom_pqc (selected by tom_pqc.c through
 * MLK_CONFIG_FILE; it replaces the vendored mlkem_native_config.h, which
 * stays as upstream ships it).
 *
 * - ML-KEM-768 only.
 * - A single compilation unit: tom_pqc.c includes mlkem_native.c, and every
 *   mlkem-native function, internal and public, is `static`. The only
 *   exported symbols are tom_pqc.c's own, the backend interface of
 *   tom_pqc.h, so nothing of mlkem-native can collide with another copy of it
 *   (liboqs, AWS-LC) in the same process.
 * - Portable C: no native arithmetic or FIPS 202 backend, no assembly.
 * - Randomness from tom_pqc_randombytes (tom_pqc_random.c, the OS
 *   generator), not from a global `randombytes` symbol.
 */
#ifndef TOM_PQC_MLKEM_CONFIG_H
#define TOM_PQC_MLKEM_CONFIG_H

#define MLK_CONFIG_PARAMETER_SET 768
#define MLK_CONFIG_NAMESPACE_PREFIX tom_pqc_mlkn
#define MLK_CONFIG_INTERNAL_API_QUALIFIER static
#define MLK_CONFIG_EXTERNAL_API_QUALIFIER static

#if defined(MLK_BUILD_INTERNAL)
#define MLK_CONFIG_CUSTOM_RANDOMBYTES
#if !defined(__ASSEMBLER__)
#include <stddef.h>
#include <stdint.h>
#include "tom_pqc_random.h"
#include "mlkem-native/src/sys.h"
static MLK_INLINE int mlk_randombytes(uint8_t *ptr, size_t len)
{
  return tom_pqc_randombytes(ptr, len);
}
#endif /* !__ASSEMBLER__ */
#endif /* MLK_BUILD_INTERNAL */

#endif /* !TOM_PQC_MLKEM_CONFIG_H */
