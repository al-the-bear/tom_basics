import 'dart:io';

import 'package:dcli/dcli.dart';
import 'package:glob/glob.dart';
import 'package:glob/list_local_fs.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../tom_build_base.dart';

/// Default tool key used by the show-versions tool.
const showVersionsToolKey = 'show_versions';

/// Result of a [showVersions] run.
class ShowVersionsResult {
  /// Projects with their versions (path → version string).
  final Map<String, String> versions;

  /// Projects where the version could not be read.
  final List<String> failures;

  /// The underlying [ProcessingResult] with counts.
  final ProcessingResult processingResult;

  const ShowVersionsResult({
    required this.versions,
    required this.failures,
    required this.processingResult,
  });

  /// Whether every discovered project was read successfully.
  bool get isSuccess => failures.isEmpty;
}

/// Options for [showVersions].
class ShowVersionsOptions {
  /// Workspace root path.  Defaults to the current directory.
  final String basePath;

  /// Tool key for config lookup.  Defaults to [showVersionsToolKey].
  final String toolKey;

  /// Enable verbose / debug output.
  final bool verbose;

  /// Optional log callback for diagnostic messages.
  final void Function(String message)? log;

  const ShowVersionsOptions({
    required this.basePath,
    this.toolKey = showVersionsToolKey,
    this.verbose = false,
    this.log,
  });
}

/// Discover all Dart projects under [options.basePath] and read their
/// `pubspec.yaml` version field.
///
/// This function exercises the full `tom_build_base` surface:
///
///   • [TomBuildConfig] — loading and merging workspace / project config
///   • [ConfigMerger] — additive exclude-list merging
///   • Directory scanning — recursive project discovery
///   • build.yaml utilities — skipping builder-definition packages
///   • Path utilities — containment validation
///   • [ProcessingResult] — batch success / failure tracking
Future<ShowVersionsResult> showVersions(ShowVersionsOptions options) async {
  final basePath = options.basePath;
  final toolKey = options.toolKey;
  final verbose = options.verbose;
  void log(String msg) => options.log?.call(msg);

  // ── 1. Load configuration (master + project, merged) ────────────────────
  final masterConfig = TomBuildConfig.loadMaster(
    dir: basePath,
    toolKey: toolKey,
  );
  final projectConfig = TomBuildConfig.load(dir: basePath, toolKey: toolKey);

  TomBuildConfig config;
  if (masterConfig != null && projectConfig != null) {
    config = masterConfig.merge(projectConfig);
    log('Config: merged master + project');
  } else {
    config =
        projectConfig ?? masterConfig ?? const TomBuildConfig(verbose: true);
    log(
      'Config: ${projectConfig != null
          ? "project"
          : masterConfig != null
          ? "master"
          : "defaults"}',
    );
  }

  // ── 2. ConfigMerger — combine workspace and project exclusions ──────────
  final mergedExclude = ConfigMerger.mergeAdditive<String>(
    masterConfig?.exclude ?? const <String>[],
    projectConfig?.exclude ?? const <String>[],
  );

  final effectiveVerbose = ConfigMerger.mergeScalar(
    masterConfig?.verbose ?? false,
    projectConfig?.verbose ?? verbose,
  );

  if (effectiveVerbose) {
    log('Merged excludes: $mergedExclude');
  }

  // ── 3. Path validation ──────────────────────────────────────────────────
  final pathError = validatePathContainment(
    project: config.project,
    projects: config.projects,
    scan: config.scan,
    basePath: basePath,
  );
  if (pathError != null) {
    throw ArgumentError('Path validation failed: $pathError');
  }

  // ── 4. Discover projects ────────────────────────────────────────────────
  List<String> projectPaths;

  if (config.projects.isNotEmpty) {
    // Glob-based discovery
    projectPaths = await _resolveGlobPatterns(
      config.projects,
      basePath: basePath,
      projectFilter: (path) => !isBuildYamlBuilderDefinition(path),
      verbose: effectiveVerbose,
      log: (msg) => log('[discovery] $msg'),
    );
    log('Glob discovery found ${projectPaths.length} projects');
  } else {
    // Recursive directory scan (workspace-boundary-aware)
    projectPaths = scanForDartProjects(
      basePath,
      recursive: true,
      verbose: effectiveVerbose,
    );
    log('Directory scan found ${projectPaths.length} projects');
  }

  // Apply exclusions
  projectPaths = _applyExclusions(projectPaths, mergedExclude, basePath);

  log('After exclusions: ${projectPaths.length} projects');

  // ── 5. Process each project — read version, track results ───────────────
  final result = ProcessingResult();
  final versions = <String, String>{};
  final failures = <String>[];

  for (final projectPath in projectPaths) {
    // Skip builder-definition packages
    if (isBuildYamlBuilderDefinition(projectPath)) {
      log('Skipping builder definition: ${p.basename(projectPath)}');
      continue;
    }

    // Log builder consumer info when verbose
    if (effectiveVerbose) {
      if (hasBuildYamlConsumerConfig(
        projectPath,
        'tom_version_builder:version_builder',
      )) {
        log('${p.basename(projectPath)} has version_builder consumer config');
      }
      if (isBuildYamlBuilderEnabled(
        projectPath,
        'tom_version_builder:version_builder',
      )) {
        log('${p.basename(projectPath)} — version_builder is enabled');
      }
      final builderOpts = getBuildYamlBuilderOptions(
        projectPath,
        'tom_version_builder:version_builder',
      );
      if (builderOpts != null) {
        log('${p.basename(projectPath)} — builder options: $builderOpts');
      }
      if (hasTomBuildConfig(projectPath, toolKey)) {
        log('${p.basename(projectPath)} has $toolKey in tom_build.yaml');
      }
    }

    // Read version
    final version = readPubspecVersion(projectPath);
    if (version != null) {
      result.addSuccess(1);
      versions[projectPath] = version;
    } else {
      result.addFailure();
      failures.add(projectPath);
    }
  }

  return ShowVersionsResult(
    versions: versions,
    failures: failures,
    processingResult: result,
  );
}

/// Read the `version:` field from a project's pubspec.yaml.
///
/// Returns `null` if the file doesn't exist or can't be parsed.
String? readPubspecVersion(String projectPath) {
  final pubspecPath = p.join(projectPath, 'pubspec.yaml');
  if (!exists(pubspecPath)) return null;

  try {
    final content = read(pubspecPath).toParagraph();
    final yaml = loadYaml(content) as YamlMap?;
    return yaml?['version']?.toString();
  } catch (_) {
    return null;
  }
}

// =============================================================================
// Internal helpers (replacing deleted v1 ProjectDiscovery / ProjectScanner)
// =============================================================================

/// Resolve glob patterns to a list of project paths.
Future<List<String>> _resolveGlobPatterns(
  List<String> patterns, {
  required String basePath,
  bool Function(String)? projectFilter,
  bool verbose = false,
  void Function(String)? log,
}) async {
  final results = <String>[];
  final seen = <String>{};

  for (final pattern in patterns) {
    final trimmed = pattern.trim();
    if (trimmed.isEmpty) continue;

    try {
      final glob = Glob(trimmed);
      await for (final entity in glob.list(root: basePath)) {
        if (entity is Directory) {
          final path = p.normalize(p.absolute(entity.path));
          if (File(p.join(path, 'pubspec.yaml')).existsSync() &&
              (projectFilter == null || projectFilter(path)) &&
              !seen.contains(path)) {
            seen.add(path);
            results.add(path);
          }
        }
      }
    } catch (e) {
      if (verbose) {
        log?.call('Warning: Error resolving glob "$trimmed": $e');
      }
    }
  }

  return results;
}

/// Apply exclusion patterns to a list of project paths.
List<String> _applyExclusions(
  List<String> projectPaths,
  List<String> excludePatterns,
  String basePath,
) {
  if (excludePatterns.isEmpty) return projectPaths;

  final globs = excludePatterns
      .map((pattern) {
        try {
          return Glob(pattern);
        } catch (_) {
          return null;
        }
      })
      .whereType<Glob>()
      .toList();

  if (globs.isEmpty) return projectPaths;

  return projectPaths.where((projectPath) {
    final relative = p.relative(projectPath, from: basePath);
    final dirName = p.basename(projectPath);
    return !globs.any(
      (glob) => glob.matches(relative) || glob.matches(dirName),
    );
  }).toList();
}
