/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The randomness every randomized operation of tom_pqc uses: the operating
 * system's generator, never a user-space one.
 *
 * - macOS, iOS: SecRandomCopyBytes (Security framework).
 * - Windows: BCryptGenRandom with the system-preferred RNG (bcrypt.lib).
 * - Linux, Android: getrandom(2), retried on EINTR and on short reads.
 */
#include "tom_pqc_random.h"

#include <string.h>

#if defined(__APPLE__)
#include <Security/SecRandom.h>
#elif defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>
#elif defined(__linux__)
#include <errno.h>
#include <sys/random.h>
#else
#error "tom_pqc: no operating-system random generator for this platform"
#endif

int tom_pqc_randombytes(uint8_t *out, size_t len)
{
  if (len == 0)
  {
    return 0;
  }
  if (out == NULL)
  {
    return -1;
  }
#if defined(__APPLE__)
  if (SecRandomCopyBytes(kSecRandomDefault, len, out) != errSecSuccess)
  {
    memset(out, 0, len);
    return -1;
  }
  return 0;
#elif defined(_WIN32)
  uint8_t *start = out;
  size_t total = len;
  while (len > 0)
  {
    ULONG chunk = len > 0x7fffffffUL ? 0x7fffffffUL : (ULONG)len;
    if (!BCRYPT_SUCCESS(BCryptGenRandom(NULL, out, chunk,
                                        BCRYPT_USE_SYSTEM_PREFERRED_RNG)))
    {
      memset(start, 0, total);
      return -1;
    }
    out += chunk;
    len -= chunk;
  }
  return 0;
#else
  uint8_t *start = out;
  size_t total = len;
  while (len > 0)
  {
    ssize_t got = getrandom(out, len, 0);
    if (got < 0)
    {
      if (errno == EINTR)
      {
        continue;
      }
      memset(start, 0, total);
      return -1;
    }
    out += (size_t)got;
    len -= (size_t)got;
  }
  return 0;
#endif
}
