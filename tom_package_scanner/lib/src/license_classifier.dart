/// Classifies a `LICENSE` / `license.md` file body into a canonical token
/// (spec §4.2.1 `license:`).
///
/// The vocabulary the website understands: a small set of SPDX identifiers for
/// the open-source licenses actually used in the tree, plus the two
/// non-SPDX tokens `proprietary` and `all-rights-reserved`. Anything the
/// classifier cannot place returns `null`, so the caller can flag it for a
/// human rather than guessing.
///
/// This is the single source of truth for license classification across the
/// website tooling; the website's `tool/seed/license_classifier.dart` re-exports
/// it.
library;

/// SPDX identifiers the classifier emits.
const Set<String> spdxLicenseTokens = {
  'BSD-3-Clause',
  'BSD-2-Clause',
  'MIT',
  'Apache-2.0',
  'AGPL-3.0',
  'AGPL-2.0',
  'GPL-3.0',
  'LGPL-3.0',
  'MPL-2.0',
  'ISC',
  'Unlicense',
};

/// The two non-SPDX tokens for closed licensing.
const Set<String> nonSpdxLicenseTokens = {
  'proprietary',
  'all-rights-reserved',
};

/// Every token a valid `license:` field may carry.
Set<String> get validLicenseTokens =>
    {...spdxLicenseTokens, ...nonSpdxLicenseTokens};

/// True if [token] is a recognised SPDX id or one of the closed-license tokens.
bool isValidLicenseToken(String token) => validLicenseTokens.contains(token);

/// Maps a license file's full text to a canonical token, or `null` when the
/// text is unrecognised or a placeholder (e.g. `TODO: Add your license here`).
///
/// Recognition is body-driven, not header-driven: a BSD/MIT body that opens
/// with `Copyright (c) … / All rights reserved.` (the Dart-SDK style) is still
/// classified by its grant clauses, so open-source licenses are checked
/// **before** the `all rights reserved` / proprietary fall-throughs. Order
/// therefore matters.
String? classifyLicense(String text) {
  final lower = text.toLowerCase();

  // Explicit non-license placeholders → unknown.
  if (lower.contains('todo') && lower.contains('license')) return null;

  // Open-source bodies (checked first; many open with "All rights reserved").
  if (lower.contains('apache license') && lower.contains('version 2.0')) {
    return 'Apache-2.0';
  }
  if (lower.contains('gnu affero general public license')) {
    return lower.contains('version 3') ? 'AGPL-3.0' : 'AGPL-2.0';
  }
  if (lower.contains('gnu lesser general public license')) return 'LGPL-3.0';
  if (lower.contains('gnu general public license')) return 'GPL-3.0';
  if (lower.contains('mozilla public license') && lower.contains('2.0')) {
    return 'MPL-2.0';
  }
  if (lower.contains('permission is hereby granted, free of charge') &&
      (lower.contains('mit license') ||
          !lower.contains('redistribution and use'))) {
    // MIT (also matches the ISC wording, distinguished below).
    if (lower.contains('mit license') || lower.contains('mit')) return 'MIT';
    return 'ISC';
  }
  if (lower.contains('redistribution and use in source and binary forms')) {
    // BSD family: 3-Clause carries the "Neither the name …" non-endorsement
    // clause; 2-Clause does not.
    return lower.contains('neither the name') ? 'BSD-3-Clause' : 'BSD-2-Clause';
  }
  if (lower.contains('this is free and unencumbered software released into '
      'the public domain')) {
    return 'Unlicense';
  }

  // Closed licensing fall-throughs.
  if (lower.contains('proprietary') || lower.contains('confidential')) {
    return 'proprietary';
  }
  if (lower.contains('all rights reserved')) return 'all-rights-reserved';

  return null;
}
