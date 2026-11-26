/// `buildkit :textresources`: an application's text resource files, one per
/// language, assembled from the `lib/resources/<package>_<language>.json`
/// files of the packages it uses, each package's block placed under the
/// scope the application mounts it with (the workspace guideline
/// `_agent_guidelines/i18n.md`, section 8).
///
/// The application's `buildkit.yaml` says what to assemble:
///
/// ```yaml
/// text-resources:
///   languages: [en, de]          # the first is the reference language
///   output: assets/resources/{app}_{language}.json   # the default
///   dart: lib/generated/{app}_texts.g.dart           # optional
///   overrides: lib/resources/overrides_{language}.json # optional
///   mounts:
///     - scope: app
///       package: my_app
///     - scope: workbench.explorer
///       package: rename_demo
/// ```
///
/// The packages' files are found through the application's package
/// configuration (`.dart_tool/package_config.json`). The output has the
/// mounts' scopes at its top level, the mounts in their order and each block
/// in its file's order, so an unchanged input gives an unchanged file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The key of the section in a project's `buildkit.yaml`.
const String textResourcesKey = 'text-resources';

/// The default output path; `{app}` is the pubspec name, `{language}` the
/// language code.
const String defaultTextResourcesOutput =
    'assets/resources/{app}_{language}.json';

/// The top-level sections of an overrides file that may add entries the
/// packages do not have: Tom Core's global captions (`TomFormLabels`,
/// `TomFileLabels`).
const Set<String> tomCoreGlobalSections = {'form', 'file'};

/// Something that stops the assembly; the message names the package, the
/// scope and the entry.
class TextResourcesException implements Exception {
  TextResourcesException(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => message;
}

/// One package mounted under a scope.
class TextMount {
  const TextMount({required this.scope, required this.package});

  /// The scope path (`workbench.explorer`).
  final String scope;

  /// The package whose block is placed there.
  final String package;

  @override
  String toString() => '$package at "$scope"';
}

/// The `text-resources:` section of a project's `buildkit.yaml`.
class TextResourcesConfig {
  const TextResourcesConfig({
    required this.languages,
    required this.mounts,
    this.output = defaultTextResourcesOutput,
    this.dart,
    this.overrides,
  });

  /// The languages, the reference language first.
  final List<String> languages;

  /// The packages and their scopes, in order.
  final List<TextMount> mounts;

  /// Where each language's JSON file is written (`{app}`, `{language}`).
  final String output;

  /// Where the Dart source with every language's map is written (for a
  /// headless program that cannot read a file at start), or null.
  final String? dart;

  /// The overrides file per language (`{language}`), or null.
  final String? overrides;

  /// The reference language: the first.
  String get referenceLanguage => languages.first;

  /// The section of the `buildkit.yaml` in [projectDir], or null when it
  /// has none. Throws a [TextResourcesException] for a section that is not
  /// well formed.
  static TextResourcesConfig? load(String projectDir) {
    final file = File(p.join(projectDir, 'buildkit.yaml'));
    if (!file.existsSync()) return null;
    final Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      throw TextResourcesException('${file.path}: ${e.message}');
    }
    if (yaml is! YamlMap || !yaml.containsKey(textResourcesKey)) return null;
    return parse(yaml[textResourcesKey], where: file.path);
  }

  /// [section] read as a `text-resources:` section ([where] names it in
  /// messages).
  static TextResourcesConfig parse(
    Object? section, {
    String where = textResourcesKey,
  }) {
    TextResourcesException bad(String message) =>
        TextResourcesException('$where: $textResourcesKey: $message');
    if (section is! Map) throw bad('must be a map');
    for (final key in section.keys) {
      if (!const {
        'languages',
        'output',
        'dart',
        'overrides',
        'mounts',
      }.contains(key)) {
        throw bad('unknown key "$key"');
      }
    }
    final languagesValue = section['languages'] ?? const ['en'];
    if (languagesValue is! List || languagesValue.isEmpty) {
      throw bad('languages must be a non-empty list, the reference first');
    }
    final languages = [for (final l in languagesValue) '$l'];
    for (final language in languages) {
      if (!RegExp(r'^[a-z]{2,3}(_[A-Za-z0-9]+)?$').hasMatch(language)) {
        throw bad('"$language" is no language code (en, de, pt_BR)');
      }
    }
    final mountsValue = section['mounts'];
    if (mountsValue is! List || mountsValue.isEmpty) {
      throw bad('mounts must be a non-empty list of scope + package');
    }
    final mounts = <TextMount>[];
    for (final entry in mountsValue) {
      if (entry is! Map ||
          entry['scope'] is! String ||
          entry['package'] is! String) {
        throw bad('each mount needs a scope and a package (found $entry)');
      }
      final scope = entry['scope'] as String;
      final package = entry['package'] as String;
      final problem = scopeProblem(scope);
      if (problem != null) {
        throw bad('the scope "$scope" of the mount of $package $problem');
      }
      mounts.add(TextMount(scope: scope, package: package));
    }
    String? path(String key) {
      final value = section[key];
      if (value == null) return null;
      if (value is! String || value.isEmpty) throw bad('$key must be a path');
      return value;
    }

    return TextResourcesConfig(
      languages: languages,
      mounts: mounts,
      output: path('output') ?? defaultTextResourcesOutput,
      dart: path('dart'),
      overrides: path('overrides'),
    );
  }
}

/// Why [scope] cannot be a scope path, or null: Tom Core's scopes refuse an
/// empty id and an id holding `.` (the separator), so every segment of the
/// path must be non-empty; and a segment must be a JSON-safe identifier.
String? scopeProblem(String scope) {
  if (scope.isEmpty) return 'is empty';
  for (final segment in scope.split('.')) {
    if (segment.isEmpty) {
      return 'has an empty segment (Tom Core refuses an empty scope id)';
    }
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(segment)) {
      return 'has the segment "$segment", which is no identifier '
          '(letters, digits, _)';
    }
  }
  return null;
}

/// The resource files of the packages an application uses, found through
/// its package configuration.
class TextResourceSources {
  TextResourceSources(this.packageRoots);

  /// Reads `.dart_tool/package_config.json` of [projectDir].
  factory TextResourceSources.ofProject(String projectDir) {
    final file = File(p.join(projectDir, '.dart_tool', 'package_config.json'));
    if (!file.existsSync()) {
      throw TextResourcesException(
        '${file.path} is missing: run pub get first',
      );
    }
    final json = jsonDecode(file.readAsStringSync());
    final roots = <String, String>{};
    for (final package in (json as Map)['packages'] as List) {
      final entry = package as Map;
      final rootUri = Uri.parse(entry['rootUri'] as String);
      final root = rootUri.hasScheme
          ? rootUri.toFilePath()
          : p.normalize(p.join(p.dirname(file.path), rootUri.toFilePath()));
      roots[entry['name'] as String] = root;
    }
    return TextResourceSources(roots);
  }

  /// Each package's root folder, by name.
  final Map<String, String> packageRoots;

  /// The path of [package]'s file for [language].
  String fileOf(String package, String language) {
    final root = packageRoots[package];
    if (root == null) {
      throw TextResourcesException(
        'the package $package is mounted but not among the application\'s '
        'dependencies (its package configuration)',
      );
    }
    return p.join(root, 'lib', 'resources', '${package}_$language.json');
  }

  /// [package]'s block for [language] (the map under its name), or null when
  /// it has no such file.
  Map<String, Object?>? blockOf(String package, String language) {
    final path = fileOf(package, language);
    final file = File(path);
    if (!file.existsSync()) return null;
    final Object? json;
    try {
      json = jsonDecode(file.readAsStringSync());
    } on FormatException catch (e) {
      throw TextResourcesException('$path is not JSON: ${e.message}');
    }
    if (json is! Map<String, Object?> ||
        json.length != 1 ||
        json[package] is! Map<String, Object?>) {
      throw TextResourcesException(
        '$path: its top level must be the one key "$package" holding an '
        'object',
      );
    }
    return json[package] as Map<String, Object?>;
  }
}

/// The result of an assembly: each language's map, and the warnings.
class TextResourcesResult {
  TextResourcesResult(this.byLanguage, this.warnings);

  /// The assembled map per language, in the configured order.
  final Map<String, Map<String, Object?>> byLanguage;

  /// What was filled from the reference language, and the like.
  final List<String> warnings;
}

/// Assembles every language of [config] from [sources].
///
/// Throws a [TextResourcesException] naming package, scope and entry for: a
/// mounted package without a file for the reference language; two mounts
/// whose blocks would overwrite each other (an entry both place, or a scope
/// that is an entry of a package mounted before it); an override for an
/// entry that does not exist. A language a package lacks is filled from the
/// reference language, entry by entry, with a warning. [readOverrides]
/// answers the overrides map of a language (null: none).
TextResourcesResult assembleTextResources(
  TextResourcesConfig config,
  TextResourceSources sources, {
  Map<String, Object?>? Function(String language)? readOverrides,
}) {
  final warnings = <String>[];
  final references = <String, Map<String, Object?>>{};
  for (final mount in config.mounts) {
    final block =
        references[mount.package] ??
        sources.blockOf(mount.package, config.referenceLanguage);
    if (block == null) {
      throw TextResourcesException(
        'the package ${mount.package} (mounted at "${mount.scope}") has no '
        '${p.basename(sources.fileOf(mount.package, config.referenceLanguage))} '
        '(${sources.fileOf(mount.package, config.referenceLanguage)})',
      );
    }
    references[mount.package] = block;
  }
  final byLanguage = <String, Map<String, Object?>>{};
  for (final language in config.languages) {
    final result = <String, Object?>{};
    final owners = <String, TextMount>{};
    for (final mount in config.mounts) {
      final reference = references[mount.package]!;
      Map<String, Object?> block;
      if (language == config.referenceLanguage) {
        block = reference;
      } else {
        final own = sources.blockOf(mount.package, language);
        if (own == null) {
          warnings.add(
            '${mount.package} has no ${mount.package}_$language.json: its '
            '${config.referenceLanguage} texts are used for $language',
          );
          block = reference;
        } else {
          final filled = <String>[];
          block = _fill(own, reference, '', filled);
          if (filled.isNotEmpty) {
            warnings.add(
              '${mount.package}_$language.json lacks ${filled.length} '
              'entr${filled.length == 1 ? 'y' : 'ies'} its '
              '${config.referenceLanguage} file has, filled from it: '
              '${filled.take(5).join(', ')}${filled.length > 5 ? ', ...' : ''}',
            );
          }
        }
      }
      _place(result, owners, mount, block);
    }
    final overrides = readOverrides?.call(language);
    if (overrides != null) _override(result, overrides, '', language);
    byLanguage[language] = result;
  }
  return TextResourcesResult(byLanguage, warnings);
}

/// [own] with every entry of [reference] it lacks added (in [reference]'s
/// order, then [own]'s extra entries); the dotted paths added go to
/// [filled].
Map<String, Object?> _fill(
  Map<String, Object?> own,
  Map<String, Object?> reference,
  String path,
  List<String> filled,
) {
  final out = <String, Object?>{};
  for (final entry in reference.entries) {
    final at = path.isEmpty ? entry.key : '$path.${entry.key}';
    final mine = own[entry.key];
    if (mine == null) {
      out[entry.key] = entry.value;
      filled.add(at);
    } else if (mine is Map<String, Object?> &&
        entry.value is Map<String, Object?>) {
      out[entry.key] = _fill(
        mine,
        entry.value as Map<String, Object?>,
        at,
        filled,
      );
    } else {
      out[entry.key] = mine;
    }
  }
  for (final entry in own.entries) {
    out.putIfAbsent(entry.key, () => entry.value);
  }
  return out;
}

/// Places [block] under [mount]'s scope in [result]. [owners] records the
/// mount that placed each entry (dotted path), so a collision names both.
void _place(
  Map<String, Object?> result,
  Map<String, TextMount> owners,
  TextMount mount,
  Map<String, Object?> block,
) {
  final segments = mount.scope.split('.');
  var node = result;
  var path = '';
  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    path = path.isEmpty ? segment : '$path.$segment';
    final last = i == segments.length - 1;
    final existing = node[segment];
    final owner = owners[path];
    if (last && existing != null && owner != null) {
      throw TextResourcesException(
        'the mount of ${mount.package} at "${mount.scope}" would overwrite '
        '${owner.scope == mount.scope ? 'the mount of ${owner.package} at the same scope' : 'the entry "$path" of ${owner.package} (mounted at "${owner.scope}")'}',
      );
    }
    if (existing == null) {
      final created = <String, Object?>{};
      node[segment] = created;
      node = created;
    } else if (existing is Map<String, Object?>) {
      node = existing;
    } else {
      throw TextResourcesException(
        'the mount of ${mount.package} at "${mount.scope}" runs into the '
        'text "$path" of ${owner?.package ?? 'another mount'}',
      );
    }
  }
  _merge(node, block, path, mount, owners);
}

void _merge(
  Map<String, Object?> into,
  Map<String, Object?> block,
  String path,
  TextMount mount,
  Map<String, TextMount> owners,
) {
  owners.putIfAbsent(path, () => mount);
  for (final entry in block.entries) {
    final at = '$path.${entry.key}';
    final existing = into[entry.key];
    final value = entry.value;
    if (existing == null) {
      into[entry.key] = value is Map<String, Object?> ? _copy(value) : value;
      _own(at, value, mount, owners);
    } else if (existing is Map<String, Object?> &&
        value is Map<String, Object?> &&
        owners[at] == null) {
      // A junction only: the path of a mount further down.
      _merge(existing, value, at, mount, owners);
    } else {
      final owner = owners[at];
      throw TextResourcesException(
        'the mounts of ${mount.package} at "${mount.scope}" and '
        '${owner == null ? 'another package' : '${owner.package} at "${owner.scope}"'} '
        'both place the entry "$at"',
      );
    }
  }
}

void _own(
  String path,
  Object? value,
  TextMount mount,
  Map<String, TextMount> owners,
) {
  owners[path] = mount;
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _own('$path.${entry.key}', entry.value, mount, owners);
    }
  }
}

Map<String, Object?> _copy(Map<String, Object?> map) => {
  for (final entry in map.entries)
    entry.key: entry.value is Map<String, Object?>
        ? _copy(entry.value as Map<String, Object?>)
        : entry.value,
};

/// Lays [overrides] over [result]: every text must replace one that exists,
/// except in a top-level section of Tom Core's global captions
/// ([tomCoreGlobalSections]) that no mount placed, whose entries are added.
void _override(
  Map<String, Object?> result,
  Map<String, Object?> overrides,
  String path,
  String language, {
  bool adding = false,
}) {
  for (final entry in overrides.entries) {
    final at = path.isEmpty ? entry.key : '$path.${entry.key}';
    final value = entry.value;
    final existing = result[entry.key];
    final adds =
        adding ||
        (path.isEmpty &&
            existing == null &&
            tomCoreGlobalSections.contains(entry.key));
    if (value is Map<String, Object?>) {
      if (existing is Map<String, Object?>) {
        _override(existing, value, at, language, adding: adding);
      } else if (existing == null && adds) {
        result[entry.key] = _copy(value);
      } else {
        throw TextResourcesException(
          'the overrides for $language name "$at", which the assembled file '
          'does not have',
        );
      }
    } else if (value is String) {
      if (existing is String || (existing == null && adds)) {
        result[entry.key] = value;
      } else {
        throw TextResourcesException(
          'the overrides for $language name "$at", which the assembled file '
          'does not have as a text',
        );
      }
    } else {
      throw TextResourcesException(
        'the overrides for $language hold "$at" as ${value.runtimeType}; '
        'texts and maps only',
      );
    }
  }
}

/// [map] as the JSON a file holds: two-space indent, a final line break.
String encodeTextResources(Map<String, Object?> map) =>
    '${const JsonEncoder.withIndent('  ').convert(map)}\n';

/// Every language's map as a Dart source file: a `const` map from the
/// language code to its texts, for a program that cannot read a file at
/// start (a compiled executable without its assets).
String dartTextResources(
  Map<String, Map<String, Object?>> byLanguage, {
  required String app,
}) {
  final out = StringBuffer()
    ..writeln('// GENERATED by `buildkit :textresources` from the')
    ..writeln("// `text-resources:` section of $app's buildkit.yaml: do not")
    ..writeln('// edit, change the packages\' resource files and run it again.')
    ..writeln()
    ..writeln("/// $app's texts per language code, assembled from the")
    ..writeln('/// resource files of the packages it mounts (install one with')
    ..writeln('/// `TomTextResourceProvider.from`).')
    ..write('const Map<String, Map<String, Object?>> textResources = ');
  _dartMap(out, byLanguage, 0);
  out.writeln(';');
  return out.toString();
}

void _dartMap(StringBuffer out, Map<String, Object?> map, int depth) {
  final indent = '  ' * (depth + 1);
  out.writeln('<String, Object?>{');
  for (final entry in map.entries) {
    out.write('$indent${_dartString(entry.key)}: ');
    final value = entry.value;
    if (value is Map<String, Object?>) {
      _dartMap(out, value, depth + 1);
    } else {
      out.write(_dartString('$value'));
    }
    out.writeln(',');
  }
  out.write('${'  ' * depth}}');
}

String _dartString(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return "'$escaped'";
}

/// The files an assembly of the project in [projectDir] writes, by path
/// relative to it, with their contents: each language's JSON file and, when
/// configured, the Dart source.
Map<String, String> textResourceFiles(
  String projectDir,
  TextResourcesConfig config,
  TextResourcesResult result,
) {
  final app = _pubspecName(projectDir);
  String expand(String template, [String? language]) => template
      .replaceAll('{app}', app)
      .replaceAll('{language}', language ?? '');
  final files = <String, String>{
    for (final language in config.languages)
      expand(config.output, language): encodeTextResources(
        result.byLanguage[language]!,
      ),
  };
  final dart = config.dart;
  if (dart != null) {
    files[expand(dart)] = dartTextResources(result.byLanguage, app: app);
  }
  return files;
}

/// Reads the overrides file of [language] in [projectDir], or null.
Map<String, Object?>? readTextOverrides(
  String projectDir,
  TextResourcesConfig config,
  String language,
) {
  final template = config.overrides;
  if (template == null) return null;
  final path = p.join(projectDir, template.replaceAll('{language}', language));
  final file = File(path);
  if (!file.existsSync()) return null;
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    throw TextResourcesException('$path is not JSON: ${e.message}');
  }
  if (json is! Map<String, Object?>) {
    throw TextResourcesException('$path must hold a JSON object');
  }
  return json;
}

String _pubspecName(String projectDir) {
  final file = File(p.join(projectDir, 'pubspec.yaml'));
  final yaml = file.existsSync() ? loadYaml(file.readAsStringSync()) : null;
  final name = yaml is YamlMap ? yaml['name'] : null;
  return name is String ? name : p.basename(p.normalize(projectDir));
}

/// What [runTextResources] did.
class TextResourcesRun {
  TextResourcesRun({
    required this.written,
    required this.unchanged,
    required this.differing,
    required this.warnings,
  });

  /// Files written (relative paths).
  final List<String> written;

  /// Files already up to date.
  final List<String> unchanged;

  /// With `check`: files missing or differing from a fresh assembly.
  final List<String> differing;

  /// The assembly's warnings.
  final List<String> warnings;
}

/// Assembles the text resources of the project in [projectDir] and writes
/// them; with [check], writes nothing and reports the files that differ from
/// a fresh assembly. Null when the project has no `text-resources:` section.
TextResourcesRun? runTextResources(String projectDir, {bool check = false}) {
  final config = TextResourcesConfig.load(projectDir);
  if (config == null) return null;
  final result = assembleTextResources(
    config,
    TextResourceSources.ofProject(projectDir),
    readOverrides: (language) =>
        readTextOverrides(projectDir, config, language),
  );
  final files = textResourceFiles(projectDir, config, result);
  final written = <String>[];
  final unchanged = <String>[];
  final differing = <String>[];
  for (final entry in files.entries) {
    final file = File(p.join(projectDir, entry.key));
    final current = file.existsSync() ? file.readAsStringSync() : null;
    if (current == entry.value) {
      unchanged.add(entry.key);
    } else if (check) {
      differing.add(entry.key);
    } else {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      written.add(entry.key);
    }
  }
  return TextResourcesRun(
    written: written,
    unchanged: unchanged,
    differing: differing,
    warnings: result.warnings,
  );
}
