/// Whether a file is text, judged by its first bytes — the one question a
/// file's content answers when its name does not.
library;

/// The text test over a file's first bytes: a UTF-16 byte-order mark,
/// or no NUL byte in the first 8 KiB and a valid UTF-8 prefix.
bool tomLooksLikeText(List<int> head) {
  if (head.length >= 2 &&
      ((head[0] == 0xFF && head[1] == 0xFE) ||
          (head[0] == 0xFE && head[1] == 0xFF))) {
    return true;
  }
  final prefix = head.length > 8192 ? head.sublist(0, 8192) : head;
  if (prefix.contains(0)) return false;
  return _validUtf8Prefix(prefix);
}

/// Whether [bytes] are valid UTF-8, allowing a sequence cut off at the end
/// (a prefix may end inside a character).
bool _validUtf8Prefix(List<int> bytes) {
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    final int extra;
    if (b < 0x80) {
      extra = 0;
    } else if (b >= 0xC2 && b <= 0xDF) {
      extra = 1;
    } else if (b >= 0xE0 && b <= 0xEF) {
      extra = 2;
    } else if (b >= 0xF0 && b <= 0xF4) {
      extra = 3;
    } else {
      return false;
    }
    for (var k = 1; k <= extra; k++) {
      if (i + k >= bytes.length) return true;
      if (bytes[i + k] & 0xC0 != 0x80) return false;
    }
    i += extra + 1;
  }
  return true;
}
