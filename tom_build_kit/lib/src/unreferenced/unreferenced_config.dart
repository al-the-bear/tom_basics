/// The `unreferenced:` section of a project's `buildkit.yaml`: what the
/// unreferenced-export audit checks, and the allowlist, each entry with its
/// reason.
///
/// ```yaml
/// unreferenced:
///   root: ..                      # holds the audited packages (from here)
///   package-prefix: my_           # which of them are audited
///   exclude: [my_testkit]         # audited by name, not by prefix
///   consumer-repositories:        # packages here are consumers only
///     - ../../other_repo
///   allow:
///     - package: my_core
///       symbol: Store.reserved     # `Name` or `Type.member`
///       reason: the later release that reads it
/// ```
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'unreferenced_exports.dart';

/// The section key in `buildkit.yaml`.
const unreferencedConfigKey = 'unreferenced';

/// The audit's configuration, as one project's `buildkit.yaml` states it.
class UnreferencedExportsConfig {
  const UnreferencedExportsConfig({
    required this.root,
    required this.packagePrefix,
    this.exclude = const {},
    this.consumerRepositories = const [],
    this.allowlist = const [],
  });

  /// The absolute directory holding the audited packages.
  final String root;
  final String packagePrefix;
  final Set<String> exclude;

  /// Absolute directories whose packages are consumers only.
  final List<String> consumerRepositories;
  final List<AllowedUnreferencedExport> allowlist;

  /// The section of `<projectDir>/buildkit.yaml`, paths resolved against
  /// [projectDir]; null when the file or the section is absent.
  ///
  /// A section that is present but malformed — a missing prefix, an allowlist
  /// entry without a package, symbol or reason — throws a [FormatException]
  /// naming what is wrong: an allowlist entry with no reason is the one thing
  /// the list exists to forbid.
  static UnreferencedExportsConfig? load(String projectDir) {
    final file = File(p.join(projectDir, 'buildkit.yaml'));
    if (!file.existsSync()) return null;
    final yaml = loadYaml(file.readAsStringSync());
    if (yaml is! YamlMap || !yaml.containsKey(unreferencedConfigKey)) {
      return null;
    }
    final section = yaml[unreferencedConfigKey];
    if (section is! YamlMap) {
      throw FormatException(
        '${file.path}: `$unreferencedConfigKey:` must be a map.',
      );
    }
    final prefix = section['package-prefix'];
    if (prefix is! String || prefix.isEmpty) {
      throw FormatException(
        '${file.path}: `$unreferencedConfigKey.package-prefix` is required.',
      );
    }
    String resolve(Object? path) =>
        p.normalize(p.join(projectDir, path?.toString() ?? '.'));
    final allow = <AllowedUnreferencedExport>[];
    final entries = section['allow'];
    if (entries != null && entries is! YamlList) {
      throw FormatException(
        '${file.path}: `$unreferencedConfigKey.allow` must be a list.',
      );
    }
    for (final entry in (entries as YamlList?) ?? const []) {
      final package = entry is YamlMap ? entry['package'] : null;
      final symbol = entry is YamlMap ? entry['symbol'] : null;
      final reason = entry is YamlMap ? entry['reason'] : null;
      if (package is! String ||
          symbol is! String ||
          reason is! String ||
          reason.trim().isEmpty) {
        throw FormatException(
          '${file.path}: every `$unreferencedConfigKey.allow` entry names a '
          'package, a symbol and a reason; this one does not: $entry',
        );
      }
      allow.add(AllowedUnreferencedExport(package, symbol, reason.trim()));
    }
    return UnreferencedExportsConfig(
      root: resolve(section['root']),
      packagePrefix: prefix,
      exclude: {for (final name in _strings(section['exclude'])) name},
      consumerRepositories: [
        for (final path in _strings(section['consumer-repositories']))
          resolve(path),
      ],
      allowlist: allow,
    );
  }

  /// Runs the audit this configuration describes.
  UnreferencedExportReport audit() => auditUnreferencedExports(
    root: root,
    packagePrefix: packagePrefix,
    exclude: exclude,
    consumerRepositories: consumerRepositories,
    allowlist: allowlist,
  );
}

List<String> _strings(Object? value) => switch (value) {
  null => const [],
  String() => [value],
  YamlList() => [for (final v in value) v.toString()],
  _ => throw FormatException('expected a string or a list, got $value'),
};
