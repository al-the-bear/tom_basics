// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

/// An operation of tom_pqc failed: an input the algorithm rejects (a public
/// key that fails the FIPS 203 modulus check, a secret key that fails its hash
/// check), the OS random generator, or memory.
final class TomPqcException implements Exception {
  const TomPqcException(this.message);

  final String message;

  @override
  String toString() => 'TomPqcException: $message';
}
