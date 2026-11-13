/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 */
#ifndef TOM_PQC_RANDOM_H
#define TOM_PQC_RANDOM_H

#include <stddef.h>
#include <stdint.h>

/* Fills out[0..len) from the operating system's generator. Returns 0 on
 * success, non-zero on failure (and then out is zeroed). */
int tom_pqc_randombytes(uint8_t *out, size_t len);

#endif /* !TOM_PQC_RANDOM_H */
