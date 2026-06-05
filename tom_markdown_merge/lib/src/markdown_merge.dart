import 'package:tom_doc_specs/tom_doc_specs.dart'
    show InsertMarker, InsertMarkerParser, InsertMarkerProcessor;

/// Variable-name prefix marking a **managed** region — content the generator
/// may refresh on each run. A managed region is an insert-marker region whose
/// variable is `tom.managed.<key>`, e.g.:
///
/// ```markdown
/// <!--$insert:tom.managed.overview-->
/// ...generated prose the generator may refresh...
/// <!--$end-insert-->
/// ```
const String managedPrefix = 'tom.managed.';

/// Variable-name prefix marking an **override** region — author-owned content
/// that *replaces* the generated text and is never refreshed. When an override
/// region exists for a key, the generator also suppresses its own output for
/// that key (so a stray managed region for the same key is left as-is, not
/// refreshed).
const String overridePrefix = 'tom.override.';

/// Non-destructive Markdown region merge.
///
/// The merge is built on `tom_doc_specs`' [InsertMarkerProcessor]: the document
/// is tokenised into insert-marker regions, only *managed* regions the
/// generator currently owns are rewritten, and everything else — *override*
/// regions, foreign `$insert:` regions, and all free text before/between/after
/// regions — is preserved verbatim.
///
/// Marker keys must match the insert-marker variable grammar
/// (`[a-zA-Z0-9_.]`). Region content must not itself contain insert markers.
class MarkdownMerge {
  const MarkdownMerge();

  /// Returns [current] with every managed region refreshed from [generated]
  /// (a map of logical key → fresh prose).
  ///
  /// Rules (spec §6.2):
  /// - **Managed region** whose key is present in [generated] and is *not*
  ///   overridden → its content is replaced with the generated prose.
  /// - **Override region** → never touched; its key is removed from the set the
  ///   generator may refresh (override wins, managed not refreshed).
  /// - **Free text** outside any region and **foreign `$insert:` regions** →
  ///   preserved verbatim, in document order.
  /// - A managed key absent from [generated] → left as-is (the generator no
  ///   longer owns it).
  ///
  /// Throws [FormatException] (from the underlying parser) if the document has
  /// malformed markers (nested or unclosed).
  String merge(String current, Map<String, String> generated) {
    final processor = InsertMarkerProcessor();
    final markers = processor.parse(current);
    if (markers.isEmpty) return current;

    final overridden = _keysFor(markers, overridePrefix);
    final replacements = <String, String>{};
    for (final marker in markers) {
      final key = _suffix(marker.variable, managedPrefix);
      if (key == null) continue; // override region or foreign $insert: region
      if (overridden.contains(key)) continue; // override wins → do not refresh
      if (!generated.containsKey(key)) continue; // generator no longer owns it
      replacements[marker.variable] = generated[key]!;
    }
    return processor.process(current, replacements);
  }

  /// The logical keys of every managed region in [markdown].
  Set<String> managedKeys(String markdown) =>
      _keysFor(InsertMarkerParser().parse(markdown), managedPrefix);

  /// The logical keys of every override region in [markdown]. A generator
  /// should suppress its own output for these keys.
  Set<String> overrideKeys(String markdown) =>
      _keysFor(InsertMarkerParser().parse(markdown), overridePrefix);

  /// Builds a fresh managed region block for [key] wrapping [content].
  String managedBlock(String key, String content) =>
      _block('$managedPrefix$key', content);

  /// Builds a fresh override region block for [key] wrapping [content].
  String overrideBlock(String key, String content) =>
      _block('$overridePrefix$key', content);

  String _block(String variable, String content) {
    final body = content.isEmpty ? '' : '$content\n';
    return '<!--\$insert:$variable-->\n$body<!--\$end-insert-->';
  }

  static Set<String> _keysFor(List<InsertMarker> markers, String prefix) {
    final keys = <String>{};
    for (final marker in markers) {
      final key = _suffix(marker.variable, prefix);
      if (key != null) keys.add(key);
    }
    return keys;
  }

  static String? _suffix(String variable, String prefix) =>
      variable.startsWith(prefix) ? variable.substring(prefix.length) : null;
}
