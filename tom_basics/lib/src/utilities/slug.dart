/// Human-readable names that stay stable: a slug and a short id.
library;

/// Lowercase ASCII slug of [text]: runs of anything but `a-z0-9` become one
/// `-`, with none leading or trailing. An empty result becomes [fallback].
String tomSlugify(String text, {String fallback = 'section'}) {
  final slug = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return slug.isEmpty ? fallback : slug;
}

/// The first 8 hex characters of a canonical UUID (`7f3c9e21-…` → `7f3c9e21`).
String tomShortId(String uuid) => uuid.replaceAll('-', '').substring(0, 8);
