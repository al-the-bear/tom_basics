/// Non-destructive Markdown region merge.
///
/// A generator can refresh designated *managed* regions of a Markdown file
/// while leaving author-owned *override* regions and all free text untouched.
/// Built on `tom_doc_specs`' insert-marker engine
/// (`InsertMarkerParser`/`InsertMarkerProcessor`) rather than a hand-written
/// parser.
///
/// See the package README for the marker vocabulary and merge rules.
library;

export 'src/markdown_merge.dart';
