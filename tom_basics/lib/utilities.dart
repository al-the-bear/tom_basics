/// Small utilities with no platform dependency: cooperative cancellation, one
/// SHA-256, slugs, text decoding that keeps the encoding and BOM, globs and
/// `.gitignore` matching, protected-value copying with auto-clear, a bounded
/// output transcript, and YAML
/// writing — canonical emission, single-key
/// emission in hand-edited files' style, and surgical edits of existing text.
///
/// Reaches no `dart:io` and no HTTP client, so a web-linkable package can take
/// it without the rest of `tom_basics` (whose barrel reaches `http`).
library;

export 'src/utilities/cancellation.dart';
export 'src/utilities/content_hash.dart';
export 'src/utilities/glob.dart';
export 'src/utilities/output_transcript.dart';
export 'src/utilities/protected_clipboard.dart';
export 'src/utilities/slug.dart';
export 'src/utilities/text_codec.dart';
export 'src/utilities/yaml_config_writer.dart';
export 'src/utilities/yaml_emit.dart';
export 'src/utilities/yaml_lines.dart';
export 'src/utilities/yaml_order.dart';
export 'src/utilities/yaml_plain.dart';
