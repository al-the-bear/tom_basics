/*
 * Copyright (c) 2026 Peter Nicolai Alexis Kyaw
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * The randomness every randomized operation of tom_pqc uses: the operating
 * system's generator, never a user-space one.
 *
 * - macOS, iOS: SecRandomCopyBytes (Security framework).
 * - Windows: BCryptGenRandom with the system-preferred RNG (bcrypt.lib).
 * - Linux: getrandom(2), retried on EINTR and on short reads.
 * - Android: the getrandom system call through syscall(2), since bionic
 *   declares getrandom() only from API 28 and an app's minimum is lower;
 *   on a kernel without it (ENOSYS, before Linux 3.17) /dev/urandom.
 */
#include "tom_pqc_random.h"

#include <string.h>

#if defined(__APPLE__)
#include <Security/SecRandom.h>
#elif defined(_WIN32)
#include <windows.h>
#include <bcrypt.h>
#elif defined(__ANDROID__)
#include <errno.h>
#include <fcntl.h>
#include <sys/syscall.h>
#include <unistd.h>
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
#elif defined(__ANDROID__)
  uint8_t *start = out;
  size_t total = len;
  int fd = -1;
  while (len > 0)
  {
    ssize_t got;
    if (fd < 0)
    {
      got = (ssize_t)syscall(SYS_getrandom, out, len, 0);
      if (got < 0 && errno == ENOSYS)
      {
        fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
        if (fd < 0)
        {
          memset(start, 0, total);
          return -1;
        }
        continue;
      }
    }
    else
    {
      got = read(fd, out, len);
    }
    if (got < 0)
    {
      if (errno == EINTR)
      {
        continue;
      }
      if (fd >= 0)
      {
        close(fd);
      }
      memset(start, 0, total);
      return -1;
    }
    if (got == 0)
    {
      /* /dev/urandom never ends; a zero read is a failure. */
      if (fd >= 0)
      {
        close(fd);
      }
      memset(start, 0, total);
      return -1;
    }
    out += (size_t)got;
    len -= (size_t)got;
  }
  if (fd >= 0)
  {
    close(fd);
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
