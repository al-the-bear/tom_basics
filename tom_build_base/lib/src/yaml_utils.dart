import 'package:yaml/yaml.dart';

/// Recursively converts a [YamlMap] to a regular `Map<String, dynamic>`.
///
/// This utility is useful when YAML configuration needs to be passed to
/// code that expects plain Dart maps (e.g., `fromJson` factories).
///
/// Nested [YamlMap] and [YamlList] values are converted recursively.
///
/// ```dart
/// final yaml = loadYaml(content) as YamlMap;
/// final map = yamlToMap(yaml);
/// final config = MyConfig.fromJson(map);
/// ```
Map<String, dynamic> yamlToMap(YamlMap yaml) {
  final result = <String, dynamic>{};
  for (final entry in yaml.entries) {
    final key = entry.key.toString();
    final value = entry.value;
    if (value is YamlMap) {
      result[key] = yamlToMap(value);
    } else if (value is YamlList) {
      result[key] = yamlListToList(value);
    } else {
      result[key] = value;
    }
  }
  return result;
}

/// Recursively converts a [YamlList] to a regular `List<dynamic>`.
///
/// Nested [YamlMap] and [YamlList] values are converted recursively.
List<dynamic> yamlListToList(YamlList yaml) {
  return yaml.map((item) {
    if (item is YamlMap) {
      return yamlToMap(item);
    } else if (item is YamlList) {
      return yamlListToList(item);
    } else {
      return item;
    }
  }).toList();
}

/// Convert a dynamic value to a list of strings.
///
/// Handles null, single string, and list values.
/// Used for parsing YAML fields that can be either a single value or a list.
List<String> toStringList(dynamic value) {
  if (value == null) return [];
  if (value is String) return [value];
  if (value is List) return value.map((e) => e.toString()).toList();
  return [value.toString()];
}
