/// Native v2 executor for the bumpversion command.
///
/// Bumps pubspec.yaml versions across projects. All projects get a patch
/// bump by default; use --minor/--major to specify projects for different
/// bump types. Optionally runs the versioner after bumping.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:yaml/yaml.dart';

import 'versioner_executor.dart';

// =============================================================================
// Bump Types
// =============================================================================

/// The type of version bump.
enum BumpType {
  major,
  minor,
  patch;

  @override
  String toString() => name;
}

// =============================================================================
// BumpVersion Executor
// =============================================================================

/// Native v2 executor for the `:bumpversion` command.
///
/// Uses `requiresTraversal: false` because it needs post-traversal processing
/// (optionally running versioner after all bumps). Performs its own traversal
/// via [BuildBase.traverse].
class BumpVersionExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    return ItemResult.failure(
      path: context.path,
      name: context.name,
      error: ':bumpversion uses executeWithoutTraversal',
    );
  }

  @override
  Future<ToolResult> executeWithoutTraversal(CliArgs args) async {
    final cmdOpts = _getCommandOptions(args);

    // Parse minor/major project lists
    final minorProjects = _expandProjectList(cmdOpts['minor']);
    final majorProjects = _expandProjectList(cmdOpts['major']);
    // SCE10: every selector that named at least one project. What is left over
    // named none, and used to become a silent patch bump.
    final matchedSelectors = <String>{};
    /// What the failure message lists, so a wrong selector can be corrected
    /// without a second run to find out what the right one would have been.
    final processedProjects = <String>{};
    final runVersioner = cmdOpts['versioner'] == true;

    final executionRoot = args.root ?? Directory.current.path;

    // Build traversal info from CLI args
    final traversalInfo = args.toProjectTraversalInfo(executionRoot: executionRoot);

    // List mode
    if (args.listOnly) {
      print('Projects with pubspec.yaml:');
      await BuildBase.traverse(
        info: traversalInfo,
        worksWithNatures: {DartProjectFolder},
        run: (context) async {
          if (File('${context.path}/pubspec.yaml').existsSync()) {
            print('  ${context.relativePath}');
          }
          return true;
        },
      );
      return const ToolResult.success();
    }

    // Bump each project
    final results = <ItemResult>[];
    var bumped = 0;
    var skipped = 0;

    await BuildBase.traverse(
      info: traversalInfo,
      worksWithNatures: {DartProjectFolder},
      run: (context) async {
        final pubspecFile = File('${context.path}/pubspec.yaml');
        if (!pubspecFile.existsSync()) {
          skipped++;
          return true;
        }

        final bumpType = _determineBumpType(
          context.name,
          context.path,
          _readPubspecName(context.path),
          minorProjects,
          majorProjects,
          matchedSelectors,
        );
        processedProjects.add(_readPubspecName(context.path) ?? context.name);

        // Show mode
        if (args.dumpConfig) {
          final version = _readCurrentVersion(context.path);
          if (version != null) {
            print('  ${context.relativePath}: '
                '$version -> ${_bumpVersionString(version, bumpType)} ($bumpType)');
          }
          return true;
        }

        final success = _bumpProject(
          context.path,
          bumpType,
          executionRoot,
          verbose: args.verbose,
          dryRun: args.dryRun,
        );

        if (success) {
          bumped++;
          results.add(ItemResult.success(
            path: context.path,
            name: context.name,
            message: 'bumped ($bumpType)',
          ));
        } else {
          results.add(ItemResult.failure(
            path: context.path,
            name: context.name,
            error: 'bump failed',
          ));
        }
        return true;
      },
    );

    if (bumped > 0 || skipped > 0) {
      print('');
      print('Version bump summary: $bumped bumped, $skipped skipped');
    }

    // Run versioner if requested
    if (runVersioner && results.every((r) => r.success)) {
      print('');
      print('________ Running versioner');
      print('');

      final versionerExecutor = VersionerExecutor();
      await BuildBase.traverse(
        info: traversalInfo,
        worksWithNatures: {DartProjectFolder},
        run: (context) async {
          final result = await versionerExecutor.execute(context, args);
          return result.success;
        },
      );
    }

    // SCE10: a selector that named no project is an error, not a default.
    // Silently falling back to a patch bump produced releases whose pubspec,
    // version stamp and CHANGELOG all agreed with each other and with the
    // wrong number - the one shape a release checklist cannot catch by eye.
    final complaint = unmatchedSelectorFailure(
      selectors: {...minorProjects, ...majorProjects},
      matched: matchedSelectors,
      processed: processedProjects,
    );
    if (complaint != null) {
      // Printed as well as returned: a non-zero exit with nothing on stdout is
      // only half the fix, and the whole point here is that the operator is
      // TOLD which selector was wrong rather than left to infer it from a
      // version that came out one digit off.
      print('');
      print(complaint);
      return ToolResult.failure(complaint);
    }

    return ToolResult.fromItems(results);
  }

  /// Get the per-command options for the bumpversion command.
  /// The options for `:bumpversion`, written in EITHER position.
  ///
  /// Was a private copy of this lookup, one of eight in this package. The
  /// copies also only CHOSE between the per-command and global maps;
  /// `optionsFor` merges them, so an option given in both positions no
  /// longer hides the other.
  Map<String, dynamic> _getCommandOptions(CliArgs args) =>
      args.optionsFor('bumpversion', aliases: const ['bump']);

  /// Expand a list of project arguments, splitting comma-separated values.
  Set<String> _expandProjectList(dynamic value) {
    final result = <String>{};
    if (value == null) return result;

    List<String> items;
    if (value is String) {
      items = [value];
    } else if (value is List) {
      items = value.map((e) => e.toString()).toList();
    } else {
      return result;
    }

    for (final arg in items) {
      for (final name in arg.split(',')) {
        final trimmed = name.trim();
        if (trimmed.isNotEmpty) result.add(trimmed);
      }
    }
    return result;
  }

  /// Determine bump type for a project, recording which selectors matched.
  ///
  /// [matched] collects every selector that named this project, so the caller
  /// can fail on one that named nothing rather than let it become a silent
  /// patch bump (SCE10).
  BumpType _determineBumpType(
    String projectName,
    String projectPath,
    String? pubspecName,
    Set<String> minorProjects,
    Set<String> majorProjects,
    Set<String> matched,
  ) {
    bool hits(Set<String> selectors) {
      var any = false;
      for (final selector in selectors) {
        if (projectMatchesSelector(
          projectName: projectName,
          projectPath: projectPath,
          pubspecName: pubspecName,
          selectors: {selector},
        )) {
          matched.add(selector);
          any = true;
        }
      }
      return any;
    }

    // Both are evaluated, not short-circuited: a selector in the list that
    // loses to a higher precedence still MATCHED, and reporting it as
    // unmatched would be a false alarm.
    final isMajor = hits(majorProjects);
    final isMinor = hits(minorProjects);
    if (isMajor) return BumpType.major;
    if (isMinor) return BumpType.minor;
    return BumpType.patch;
  }


  /// Read `name:` from a project's pubspec, or null when there is none.
  String? _readPubspecName(String projectPath) {
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) return null;
    try {
      final yaml = loadYaml(pubspecFile.readAsStringSync()) as YamlMap?;
      return yaml?['name']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Read the current version from pubspec.yaml.
  String? _readCurrentVersion(String projectPath) {
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) return null;

    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      return yaml?['version']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Bump the version in a project's pubspec.yaml.
  bool _bumpProject(
    String projectPath,
    BumpType bumpType,
    String basePath, {
    required bool verbose,
    required bool dryRun,
  }) {
    final pubspecFile = File('$projectPath/pubspec.yaml');
    if (!pubspecFile.existsSync()) {
      print('  Error: No pubspec.yaml in ${p.relative(projectPath, from: basePath)}');
      return false;
    }

    try {
      final content = pubspecFile.readAsStringSync();
      final yaml = loadYaml(content) as YamlMap?;
      if (yaml == null || !yaml.containsKey('version')) {
        if (verbose) {
          print('  Skipping ${p.basename(projectPath)}: no version field');
        }
        return true;
      }

      final currentVersion = yaml['version'].toString();
      final newVersion = _bumpVersionString(currentVersion, bumpType);

      if (dryRun) {
        print('  [DRY RUN] ${p.basename(projectPath)}: '
            '$currentVersion -> $newVersion ($bumpType)');
        return true;
      }

      // Update pubspec.yaml
      final newContent = _updateVersionInYaml(content, newVersion);
      pubspecFile.writeAsStringSync(newContent);

      // Reset build counter
      _resetBuildCounter(projectPath, verbose: verbose);

      print('  ${p.basename(projectPath)}: $currentVersion -> $newVersion ($bumpType)');
      return true;
    } catch (e) {
      print('  Error bumping ${p.basename(projectPath)}: $e');
      return false;
    }
  }

  /// Bump a version string.
  String _bumpVersionString(String version, BumpType type) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return version;

    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    final patch = int.parse(match.group(3)!);

    switch (type) {
      case BumpType.major:
        return '${major + 1}.0.0';
      case BumpType.minor:
        return '$major.${minor + 1}.0';
      case BumpType.patch:
        return '$major.$minor.${patch + 1}';
    }
  }

  /// Update the version field in YAML content while preserving formatting.
  String _updateVersionInYaml(String content, String newVersion) {
    final versionRegex = RegExp(r'^version:\s*[\S]+', multiLine: true);
    return content.replaceFirst(versionRegex, 'version: $newVersion');
  }

  /// Reset the build counter in tom_build_state.json.
  void _resetBuildCounter(String projectPath, {required bool verbose}) {
    final stateFile = File('$projectPath/tom_build_state.json');
    try {
      stateFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'buildNumber': 0,
          'lastBuild': DateTime.now().toUtc().toIso8601String(),
          'lastVersionBump': DateTime.now().toUtc().toIso8601String(),
        }),
      );
      if (verbose) print('    Build counter reset to 0');
    } catch (e) {
      if (verbose) print('    Warning: Could not reset build counter: $e');
    }
  }
}

/// Whether a project is named by one of [selectors].
///
/// SCE10. This used to match the traversal's project name and a path SUFFIX,
/// and nothing else — so `--minor=tom_d4rt_generator`, the package's own
/// pubspec name and the obvious thing to type, selected nothing and the
/// project took the default PATCH bump in silence. The pubspec name is
/// accepted here because it is the name every release checklist, CHANGELOG
/// and pub.dev page uses.
///
/// The path is still matched as a suffix, which is how `--minor=.` works —
/// BuildKit prints `.` for the project it is standing in. A NAME, by
/// contrast, must match whole: `tom_d4rt` and `tom_d4rt_generator` are
/// different packages, and a prefix rule would bump the wrong one.
bool projectMatchesSelector({
  required String projectName,
  required String projectPath,
  required String? pubspecName,
  required Set<String> selectors,
}) {
  if (selectors.contains(projectName)) return true;
  if (pubspecName != null && selectors.contains(pubspecName)) return true;
  for (final pattern in selectors) {
    if (projectPath.endsWith(pattern)) return true;
  }
  return false;
}

/// The failure message for selectors that named no project, or null when
/// every selector found one.
///
/// SCE10. A selector matching nothing used to leave the project on the default
/// PATCH bump and say nothing. Every downstream signal then agreed with the
/// wrong number: the pubspec, the version stamp `--versioner` writes from it,
/// and the CHANGELOG section written beside them. That is the one shape a
/// release checklist cannot catch by eye, because nothing disagrees.
///
/// [processed] is listed because the correction is otherwise a second run
/// spent finding out what the right selector would have been.
String? unmatchedSelectorFailure({
  required Set<String> selectors,
  required Set<String> matched,
  required Set<String> processed,
}) {
  final unmatched = selectors.difference(matched).toList()..sort();
  if (unmatched.isEmpty) return null;
  final names = processed.toList()..sort();
  return 'These --minor/--major selectors matched no project: '
      '${unmatched.join(', ')}\n'
      'Processed: ${names.isEmpty ? '(none)' : names.join(', ')}\n'
      'A selector may be a project name, its pubspec `name:`, or a suffix of '
      'its path (`.` is the project you are standing in).';
}
