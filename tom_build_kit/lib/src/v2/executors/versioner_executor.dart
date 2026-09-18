/// Native v2 executor for the versioner command.
///
/// Generates version.versioner.dart files with build metadata (version, git commit,
/// build number, SDK version, timestamp). Config is merged from three sources:
/// CLI args > project buildkit.yaml > workspace buildkit_master.yaml.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart'
    show TomBuildConfig, hasTomBuildConfig, findWorkspaceRoot, ProcessRunner;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

// =============================================================================
// Versioner Configuration
// =============================================================================

/// Configuration for the versioner tool.
///
/// Supports 3-way merge: CLI args > project buildkit.yaml > workspace
/// buildkit_master.yaml. The [merge] method implements priority ordering.
class VersionerConfig {
  final String output;
  final bool includeGitCommit;
  final String? versionOverride;
  final String? variablePrefix;

  const VersionerConfig({
    this.output = 'lib/src/version.versioner.dart',
    this.includeGitCommit = true,
    this.versionOverride,
    this.variablePrefix,
  });

  /// Load config from buildkit.yaml in a project directory.
  static VersionerConfig? loadFromYaml(String dir) {
    final config = TomBuildConfig.load(dir: dir, toolKey: 'versioner');
    if (config == null) return null;

    final options = config.toolOptions;
    return VersionerConfig(
      output: options['output'] as String? ?? 'lib/src/version.versioner.dart',
      includeGitCommit: options['includeGitCommit'] as bool? ?? true,
      versionOverride: options['version'] as String?,
      variablePrefix:
          options['variable-prefix'] as String? ??
          options['variablePrefix'] as String?,
    );
  }

  /// Load config from buildkit_master.yaml (workspace level).
  static VersionerConfig? loadFromMasterYaml(String dir) {
    final config = TomBuildConfig.loadMaster(dir: dir, toolKey: 'versioner');
    if (config == null) return null;

    final options = config.toolOptions;
    return VersionerConfig(
      output: options['output'] as String? ?? 'lib/src/version.versioner.dart',
      includeGitCommit: options['includeGitCommit'] as bool? ?? true,
      versionOverride: options['version'] as String?,
      variablePrefix:
          options['variable-prefix'] as String? ??
          options['variablePrefix'] as String?,
    );
  }

  /// Merge with another config (this takes precedence for explicitly set values).
  ///
  /// The caller is the higher-priority config (e.g., CLI args).
  /// The [other] is the lower-priority config (e.g., project YAML).
  VersionerConfig merge(VersionerConfig other) {
    return VersionerConfig(
      output: output != 'lib/src/version.versioner.dart'
          ? output
          : other.output,
      includeGitCommit: includeGitCommit,
      versionOverride: versionOverride ?? other.versionOverride,
      variablePrefix: variablePrefix ?? other.variablePrefix,
    );
  }

  /// Get the generated class name based on variablePrefix.
  ///
  /// If [variablePrefix] is set, generates `{Prefix}VersionInfo`.
  /// Otherwise generates `TomVersionInfo`.
  String get className {
    if (variablePrefix == null || variablePrefix!.isEmpty) {
      return 'TomVersionInfo';
    }
    final prefix = variablePrefix!;
    final capitalized = prefix[0].toUpperCase() + prefix.substring(1);
    return '${capitalized}VersionInfo';
  }
}

// =============================================================================
// Versioner Executor
// =============================================================================

/// Native v2 executor for the `:versioner` command.
///
/// Uses `requiresTraversal: true` — ToolRunner traverses projects and calls
/// [execute] per folder. Each folder is checked for versioner config before
/// generating the version file.
class VersionerExecutor extends CommandExecutor {
  /// Cached workspace config (loaded once on first execute call).
  VersionerConfig? _wsConfig;
  String? _wsRoot;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final projectPath = context.path;
    final projectName = context.name;

    // Load workspace config (cached)
    _wsRoot ??= findWorkspaceRoot(context.executionRoot);
    _wsConfig ??=
        VersionerConfig.loadFromMasterYaml(_wsRoot!) ?? const VersionerConfig();

    // Only process projects that have a versioner: entry in their own
    // buildkit.yaml. Workspace-level config (buildkit_master.yaml) provides
    // defaults but does not cause every Dart project to get a version file.
    final hasLocalConfig = hasTomBuildConfig(projectPath, 'versioner');
    if (!hasLocalConfig) {
      return ItemResult.success(
        path: projectPath,
        name: projectName,
        message: 'skipped (no versioner config)',
      );
    }

    // Build CLI config from parsed args
    final cliConfig = _buildCliConfig(args);

    // List mode: just print project path
    if (args.listOnly) {
      print('  ${p.relative(projectPath, from: context.executionRoot)}');
      return ItemResult.success(
        path: projectPath,
        name: projectName,
        message: 'listed',
      );
    }

    // Dump config mode
    if (args.dumpConfig) {
      _printConfig(projectPath, context.executionRoot);
      return ItemResult.success(
        path: projectPath,
        name: projectName,
        message: 'config shown',
      );
    }

    // Generate version file
    final success = await _generateVersionFile(
      projectPath: projectPath,
      cliConfig: cliConfig,
      wsConfig: _wsConfig!,
      verbose: args.verbose,
      dryRun: args.dryRun,
    );

    // sce48: the message says what happened, not what was intended. A dry run
    // writes nothing, and reporting 'version file generated' for it is the
    // same failure as the one this todo is about, one step smaller: a reader
    // who trusts the summary believes a stamp was refreshed when it was not.
    return success
        ? ItemResult.success(
            path: projectPath,
            name: projectName,
            message: args.dryRun
                ? 'dry run — no version file written'
                : 'version file generated',
          )
        : ItemResult.failure(
            path: projectPath,
            name: projectName,
            error: 'failed to generate version file',
          );
  }

  /// Build a [VersionerConfig] from the parsed CLI args.
  VersionerConfig _buildCliConfig(CliArgs args) {
    // Get per-command options (options after :versioner)
    final cmdOpts = _getCommandOptions(args);

    return VersionerConfig(
      output: cmdOpts['output'] as String? ?? 'lib/src/version.versioner.dart',
      includeGitCommit: cmdOpts['no-git'] != true,
      versionOverride: cmdOpts['version'] as String?,
      variablePrefix: cmdOpts['variable-prefix'] as String?,
    );
  }

  /// Get the per-command options for the versioner command.
  /// The options for `:versioner`, written in EITHER position.
  ///
  /// Was a private copy of this lookup, one of eight in this package. The
  /// copies also only CHOSE between the per-command and global maps;
  /// `optionsFor` merges them, so an option given in both positions no
  /// longer hides the other.
  Map<String, dynamic> _getCommandOptions(CliArgs args) =>
      args.optionsFor('versioner', aliases: const ['v', 'ver']);

  /// Print the versioner config for a project.
  void _printConfig(String projectPath, String executionRoot) {
    print('Project: ${p.relative(projectPath, from: executionRoot)}');
    final config = TomBuildConfig.load(dir: projectPath, toolKey: 'versioner');
    if (config != null) {
      print('  versioner:');
      for (final entry in config.toolOptions.entries) {
        if (entry.key != 'project' &&
            entry.key != 'scan' &&
            entry.key != 'recursive' &&
            entry.key != 'exclude' &&
            entry.key != 'recursionExclude' &&
            entry.key != 'recursion-exclude') {
          print('    ${entry.key}: ${entry.value}');
        }
      }
    } else {
      print('  (no versioner config)');
    }
  }

  /// Generate version.versioner.dart for a single project.
  ///
  /// Config merge order: CLI > project > workspace.
  Future<bool> _generateVersionFile({
    required String projectPath,
    required VersionerConfig cliConfig,
    required VersionerConfig wsConfig,
    required bool verbose,
    required bool dryRun,
  }) async {
    if (verbose) print('Processing: ${p.basename(projectPath)}');

    // 3-way merge: CLI > project > workspace
    final yamlConfig = VersionerConfig.loadFromYaml(projectPath);
    VersionerConfig config;
    if (yamlConfig != null) {
      config = cliConfig.merge(yamlConfig.merge(wsConfig));
    } else {
      config = cliConfig.merge(wsConfig);
    }

    // Read pubspec.yaml
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      print('  Error: No pubspec.yaml found in $projectPath');
      return false;
    }

    try {
      final pubspecContent = pubspecFile.readAsStringSync();
      final pubspec = loadYaml(pubspecContent) as YamlMap;
      final packageName = pubspec['name'] as String;
      final version =
          config.versionOverride ?? pubspec['version'] as String? ?? '0.0.0';

      // Get git commit
      String? gitCommit;
      if (config.includeGitCommit) {
        gitCommit = await _getGitCommit(projectPath);
      }

      // Get/increment build number
      final buildNumber = _getAndIncrementBuildNumber(projectPath, dryRun);

      // Get Dart SDK version
      final dartSdkVersion = await _getDartSdkVersion();

      // Build timestamp
      final buildTime = DateTime.now().toUtc().toIso8601String();

      // Generate content
      final content = generateVersionFileContent(
        packageName: packageName,
        version: version,
        buildTime: buildTime,
        gitCommit: gitCommit,
        buildNumber: buildNumber,
        dartSdkVersion: dartSdkVersion,
        className: config.className,
      );

      // Write file
      final outputPath = '$projectPath/${config.output}';
      if (dryRun) {
        print('  [DRY RUN] Would generate: ${config.output}');
        print('    Version: $version');
        print('    Build: $buildNumber');
        if (gitCommit != null) print('    Git: $gitCommit');
        print('    Class: ${config.className}');
        return true;
      }

      final outputFile = File(outputPath);
      outputFile.parent.createSync(recursive: true);
      outputFile.writeAsStringSync(content);
      _formatInPlace(outputPath);

      // sce48: read back before reporting success, so "generated" means the
      // file on disk carries this version rather than that a write was
      // attempted. The installed binary that motivated this printed
      // "Version file generated: … v1.37.0" over a stamp that still read
      // 0.0.1 — a tool reporting intent instead of outcome sends the reader
      // round the loop its own failure message names.
      //
      // `writeAsStringSync` throwing is already caught below; this covers the
      // quieter half — a write that lands somewhere other than where the
      // caller will look, or is undone by the formatter.
      final written = outputFile.existsSync()
          ? outputFile.readAsStringSync()
          : '';
      if (!written.contains("version = '$version'")) {
        print(
          '  Error: wrote ${config.output} but it does not carry version '
          '$version. The stamp on disk is not what was generated.',
        );
        return false;
      }

      if (verbose) {
        print('  Generated: ${config.output}');
        print('    Version: $version');
        print('    Build: $buildNumber');
        if (gitCommit != null) print('    Git: $gitCommit');
      }

      return true;
    } catch (e) {
      print('  Error generating version file: $e');
      return false;
    }
  }

  /// Get short git commit hash.
  /// Runs `dart format` over the file just written, if a `dart` is reachable.
  ///
  /// [generateVersionFileContent] already emits the tall style, so this changes
  /// nothing today. It is here because the template alone cannot cover the two
  /// things that would reintroduce the defect: an SDK that changes the default
  /// style, and a package whose class name is long enough to push a line past
  /// the page width.
  ///
  /// Failure is ignored on purpose. A machine with no `dart` on PATH still gets
  /// the template's own output, which is correct; refusing to write a version
  /// file because a formatter is missing would break a build for a cosmetic
  /// reason.
  void _formatInPlace(String path) {
    try {
      Process.runSync('dart', ['format', path]);
    } on ProcessException {
      // No `dart` on PATH — the emitted template is already formatted.
    }
  }

  Future<String?> _getGitCommit(String projectPath) async {
    try {
      final result = await ProcessRunner.run('git', [
        'rev-parse',
        '--short',
        'HEAD',
      ], workingDirectory: projectPath);
      if (result.exitCode == 0) {
        return result.stdout.trim();
      }
    } catch (_) {}
    return null;
  }

  /// Get and increment the build number from tom_build_state.json.
  int _getAndIncrementBuildNumber(String projectPath, bool dryRun) {
    final stateFile = File('$projectPath/tom_build_state.json');
    int buildNumber = 1;

    if (stateFile.existsSync()) {
      try {
        final content = stateFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        buildNumber = (json['buildNumber'] as int? ?? 0) + 1;
      } catch (_) {}
    }

    // Write incremented build number (skip in dry-run)
    if (!dryRun) {
      try {
        stateFile.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert({
            'buildNumber': buildNumber,
            'lastBuild': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      } catch (e) {
        print('  Warning: Could not write build state: $e');
      }
    }

    return buildNumber;
  }

  /// Get Dart SDK version.
  Future<String?> _getDartSdkVersion() async {
    try {
      final result = await ProcessRunner.run('dart', ['--version']);
      final output = result.stdout + result.stderr;
      final match = RegExp(r'Dart SDK version:\s+(\S+)').firstMatch(output);
      if (match != null) return match.group(1);
      final versionMatch = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(output);
      return versionMatch?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Generate the version.versioner.dart file content.
  /// The Dart source of a `version.versioner.dart` file.
  ///
  /// **Emitted already `dart format` clean, and that is a requirement rather
  /// than a nicety.** This file is generated into packages that hold themselves
  /// to a formatting gate, so a template the formatter would rewrite makes such
  /// a gate unaddable: clean until the next version bump, red after it, and red
  /// for something nobody did. That was the state until 2026-09-09 — two getter
  /// lines ran past the page width and the tall formatter wrapped them after
  /// `=>`.
  ///
  /// Static and public so `test/versioner_format_test.dart` can run the real
  /// `dart format` over its output and require it to be unchanged. A template
  /// nothing can call is a template nothing can check.
  static String generateVersionFileContent({
    required String packageName,
    required String version,
    required String buildTime,
    String? gitCommit,
    int? buildNumber,
    String? dartSdkVersion,
    String className = 'TomVersionInfo',
  }) {
    final gitLine = gitCommit != null
        ? "  static const String gitCommit = '$gitCommit';"
        : "  static const String gitCommit = '';";
    final buildNumLine = buildNumber != null
        ? '  static const int buildNumber = $buildNumber;'
        : '  static const int buildNumber = 0;';
    final sdkLine = dartSdkVersion != null
        ? "  static const String dartSdkVersion = '$dartSdkVersion';"
        : "  static const String dartSdkVersion = '';";

    return '''// GENERATED FILE - DO NOT EDIT
// Generated by versioner at $buildTime

/// Version information generated at build time.
///
/// This class contains static fields and methods for accessing
/// version information embedded during the build process.
class $className {
  $className._();

  /// Package version from pubspec.yaml
  static const String version = '$version';

  /// Build timestamp (ISO 8601 UTC format)
  static const String buildTime = '$buildTime';

  /// Git commit hash (short form)
$gitLine

  /// Build number (increments with each build)
$buildNumLine

  /// Dart SDK version used to build
$sdkLine

  /// Short version string: version + build number
  /// Example: "1.0.0+42"
  static String get versionShort => '\$version+\$buildNumber';

  /// Medium version string: version + build number + git commit + build time
  /// Example: "1.0.0+42.abc1234 (2026-02-01T10:30:00.000Z)"
  static String get versionMedium =>
      '\$version+\$buildNumber.\$gitCommit (\$buildTime)';

  /// Long version string: includes all available information including SDK version
  /// Example: "1.0.0+42.abc1234 (2026-02-01T10:30:00.000Z) [Dart 3.x.x]"
  static String get versionLong =>
      '\$version+\$buildNumber.\$gitCommit (\$buildTime) [Dart \$dartSdkVersion]';
}
''';
  }
}
