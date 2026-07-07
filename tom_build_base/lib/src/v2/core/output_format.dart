/// Canonical CLI output format and `<format>[:<file>]` specification, shared by
/// every tool built on tom_build_base.
///
/// testkit and issuekit historically each carried their own copy of this enum
/// and parser; this is the single source of truth they consolidate onto. See
/// `doc/cli_output_formats.md` for the cross-tool output contract.
library;

/// Supported CLI output formats.
enum OutputFormat {
  /// Plain text (the default). Accepts the alias `text`.
  plain,

  /// Comma-separated values.
  csv,

  /// JSON.
  json,

  /// Markdown. Accepts the alias `markdown`.
  md;

  /// Parses a format string (case-insensitive).
  ///
  /// Accepts the canonical names (`plain`, `csv`, `json`, `md`) plus the
  /// documented aliases `text` (→ [plain]) and `markdown` (→ [md]). Returns
  /// `null` for `null`, an empty string, or an unrecognized value.
  static OutputFormat? tryParse(String? value) {
    if (value == null) return null;
    return switch (value.toLowerCase()) {
      'plain' || 'text' => plain,
      'csv' => csv,
      'json' => json,
      'md' || 'markdown' => md,
      _ => null,
    };
  }
}

/// A parsed `--output <format>[:<file>]` specification.
///
/// Examples:
/// - `json` → [format] `json`, [filePath] `null` (stdout)
/// - `csv:results.csv` → [format] `csv`, [filePath] `results.csv`
/// - `md:` → [format] `md`, [filePath] `null` (a trailing empty file part is
///   treated as "no file")
class OutputSpec {
  /// Creates an output spec. A `null`/empty [filePath] means stdout.
  const OutputSpec({required this.format, this.filePath});

  /// The resolved output format.
  final OutputFormat format;

  /// Optional destination file path; `null` means write to stdout.
  final String? filePath;

  /// Whether output is directed to a (non-empty) file path.
  bool get hasFile => filePath != null && filePath!.isNotEmpty;

  /// The default spec: plain text to stdout.
  static const OutputSpec defaultSpec = OutputSpec(format: OutputFormat.plain);

  /// Parses a spec string of the form `<format>` or `<format>:<file>`.
  ///
  /// The string is split at the **first** colon, so file paths may themselves
  /// contain colons (e.g. `json:C:/out.json` → file `C:/out.json`). Returns
  /// `null` for `null`, an empty string, or an unrecognized format. A trailing
  /// empty file part (`csv:`) yields a spec with no [filePath].
  static OutputSpec? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;

    final colonIdx = value.indexOf(':');
    if (colonIdx == -1) {
      final format = OutputFormat.tryParse(value);
      if (format == null) return null;
      return OutputSpec(format: format);
    }

    final formatStr = value.substring(0, colonIdx);
    final filePath = value.substring(colonIdx + 1);
    final format = OutputFormat.tryParse(formatStr);
    if (format == null) return null;
    return OutputSpec(
      format: format,
      filePath: filePath.isEmpty ? null : filePath,
    );
  }
}
