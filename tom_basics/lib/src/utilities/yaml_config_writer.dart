import 'package:yaml_edit/yaml_edit.dart';

/// The single sanctioned path for *mutating* YAML config text while
/// preserving its on-disk layout.
///
/// Reading config goes through `package:yaml`; writing it goes
/// through this writer. It is a thin wrapper over `package:yaml_edit`'s
/// [YamlEditor], which performs **surgical** edits: a [set] or [remove]
/// rewrites only the bytes of the targeted node and leaves every comment,
/// key order, and whitespace of the surrounding document untouched.
///
/// This is exactly the property a naive `load → mutate map → re-serialize`
/// round-trip destroys — `package:yaml`'s emitter drops comments, re-orders
/// keys, and re-flows formatting. Any code that needs to change a value in a
/// human-maintained config file must use this writer rather than rewriting
/// the whole document.
///
/// The writer is **string in, string out** and imports no `dart:io`, so it
/// is safe wherever `dart:io` is not available, the web included. Callers
/// read the file, thread the source through a writer, and write the [source] back:
///
/// ```dart
/// final writer = TomYamlConfigWriter(await file.readAsString());
/// writer.set(['substrate', 'model'], 'gemma-4-26b-new');
/// writer.remove(['substrate', 'legacyField']);
/// await file.writeAsString(writer.source);
/// ```
///
/// **Path argument.** Every mutation takes a `path` — the sequence of map
/// keys and list indices locating the node (e.g.
/// `['substrate', 'providers', 0, 'weight']`). String elements address map
/// keys; int elements address list positions.
final class TomYamlConfigWriter {
  final YamlEditor _editor;

  /// Wraps [source] — the current YAML document text — for surgical editing.
  TomYamlConfigWriter(String source) : _editor = YamlEditor(source);

  /// Sets the node at [path] to [value], adding the key if it is absent.
  ///
  /// Only the targeted node is rewritten; comments, key order, and the
  /// formatting of every other node are preserved. [value] is encoded as
  /// YAML by `yaml_edit` (scalars inline, collections block-style).
  ///
  /// Throws an [ArgumentError] (from `yaml_edit`) when an intermediate
  /// segment of [path] does not exist or is not a collection.
  void set(List<Object?> path, Object? value) => _editor.update(path, value);

  /// Removes the node at [path] (a map key or a list element), leaving its
  /// neighbours, their comments, and the surrounding formatting intact.
  ///
  /// Throws an [ArgumentError] (from `yaml_edit`) when [path] does not
  /// resolve to an existing node.
  void remove(List<Object?> path) => _editor.remove(path);

  /// The current edited YAML document text.
  String get source => _editor.toString();

  @override
  String toString() => _editor.toString();
}
