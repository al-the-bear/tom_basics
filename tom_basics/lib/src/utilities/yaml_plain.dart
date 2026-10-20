/// Reading YAML back as plain Dart values.
library;

import 'package:yaml/yaml.dart' as yaml;

/// Converts a value `package:yaml` produced into plain Dart: every
/// `YamlMap` becomes a `Map<String, Object?>` (keys by their `toString`),
/// every `YamlList` a `List<Object?>`, recursively; scalars pass through.
///
/// Plain maps and lists are converted too, so a value that is partly parsed
/// YAML and partly built in code comes back in one shape. A caller compares,
/// copies and casts the result without meeting a `YamlMap`, whose
/// `UnmodifiableMapView` and node spans are a parser's business.
Object? tomYamlToPlain(Object? node) {
  if (node is yaml.YamlMap || node is Map) {
    return <String, Object?>{
      for (final entry in (node as Map).entries)
        entry.key.toString(): tomYamlToPlain(entry.value),
    };
  }
  if (node is yaml.YamlList || node is List) {
    return [for (final item in node as List) tomYamlToPlain(item)];
  }
  return node;
}
