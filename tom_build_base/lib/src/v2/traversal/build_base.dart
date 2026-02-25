import 'dart:io';

import '../folder/fs_folder.dart';
import '../folder/run_folder.dart';
import '../folder/natures/dart_project_folder.dart';
import '../folder/natures/git_folder.dart';
import 'build_order.dart';
import 'command_context.dart';
import 'filter_pipeline.dart';
import 'folder_scanner.dart';
import 'nature_detector.dart';
import 'traversal_info.dart';

/// Result of a traversal operation.
class ProcessingResult {
  final List<String> _successes = [];
  final List<String> _failures = [];
  final Map<String, Object> _errors = {};

  /// Paths that were processed successfully.
  List<String> get successes => List.unmodifiable(_successes);

  /// Paths that failed processing (command returned false).
  List<String> get failures => List.unmodifiable(_failures);

  /// Paths that threw errors, with the error objects.
  Map<String, Object> get errors => Map.unmodifiable(_errors);

  /// Total number of folders processed.
  int get total => _successes.length + _failures.length + _errors.length;

  /// Number of successful operations.
  int get successCount => _successes.length;

  /// Number of failures (including errors).
  int get failureCount => _failures.length + _errors.length;

  /// Whether all operations succeeded.
  bool get allSucceeded => _failures.isEmpty && _errors.isEmpty;

  void recordSuccess(String path) => _successes.add(path);
  void recordFailure(String path) => _failures.add(path);
  void recordError(String path, Object error) => _errors[path] = error;

  @override
  String toString() =>
      'ProcessingResult(success: $successCount, failed: $failureCount, total: $total)';
}

/// Main entry point for workspace traversal.
///
/// Provides static methods for scanning, filtering, and executing
/// commands on folders across a workspace.
abstract class BuildBase {
  /// Traverse folders and execute callback on each.
  ///
  /// [info] - ProjectTraversalInfo or GitTraversalInfo configuration.
  /// [run] - Callback for each matching folder.
  /// [requiredNatures] - Nature filter (see below).
  /// [worksWithNatures] - Supported natures (see below).
  ///
  /// ## Nature Filtering Logic
  ///
  /// At least one of the two nature parameters must be configured. If neither
  /// is set, an [ArgumentError] is thrown. To traverse all folders, set
  /// `requiredNatures: {FsFolder}` or `worksWithNatures: {FsFolder}`.
  ///
  /// 1. **requiredNatures is non-empty** → Folder MUST have ALL required
  ///    natures. `worksWithNatures` is ignored.
  /// 2. **worksWithNatures is non-empty** → Folder must have at least ONE
  ///    of the supported natures.
  /// 3. **Both unset/empty** → [ArgumentError] is thrown.
  ///
  /// **Special types:**
  /// - [FsFolder] in either set always matches (every folder is an FsFolder).
  /// - [DartProjectFolder] matches any Dart project subtype (hierarchy check).
  static Future<ProcessingResult> traverse({
    required BaseTraversalInfo info,
    required Future<bool> Function(CommandContext) run,
    Set<Type>? requiredNatures,
    Set<Type> worksWithNatures = const {},
    bool verbose = false,
  }) async {
    final detector = NatureDetector();
    final filter = FilterPipeline();
    final sorter = FolderSorter();
    final result = ProcessingResult();

    // Get folders based on traversal type
    List<FsFolder> folders;
    switch (info) {
      case ProjectTraversalInfo pi:
        folders = await _scanProjects(pi, verbose: verbose);
      case GitTraversalInfo gi:
        folders = await _findGitRepos(gi);
      default:
        folders = [];
    }

    // Detect natures FIRST (needed for project ID/name filtering)
    for (final folder in folders) {
      final natures = detector.detectNatures(folder);
      // Store natures in folder for filter pipeline access
      folder.natures.addAll(natures);
    }

    // Preserve unfiltered list for build order computation.
    // Build order must be computed from ALL scanned folders so that
    // dependency ordering is correct even when filters are applied.
    final allScannedFolders = List<FsFolder>.of(folders);

    // Apply filters AFTER nature detection (so ID/name matching works)
    switch (info) {
      case ProjectTraversalInfo pi:
        folders = filter.applyProjectFilters(folders, pi);
      case GitTraversalInfo gi:
        folders = filter.applyGitFilters(folders, gi);
      default:
        break;
    }

    // Create contexts from filtered folders
    final contexts = <CommandContext>[];
    for (final folder in folders) {
      contexts.add(
        CommandContext(
          fsFolder: folder,
          natures: folder.natures.whereType<RunFolder>().toList(),
          executionRoot: info.executionRoot,
          traversal: info,
        ),
      );
    }

    // Apply ordering based on traversal type
    List<CommandContext> ordered;
    switch (info) {
      case GitTraversalInfo gi:
        ordered = gi.gitMode == GitTraversalMode.innerFirst
            ? sorter.sortByInnerFirst(contexts, (c) => c.path)
            : sorter.sortByOuterFirst(contexts, (c) => c.path);
      case ProjectTraversalInfo pi when pi.buildOrder:
        // Build order: compute order from ALL scanned folders (pre-filter),
        // then sort the filtered contexts by that global order.
        final allDartPaths = allScannedFolders
            .where((f) => File('${f.path}/pubspec.yaml').existsSync())
            .map((f) => f.path)
            .toList();
        final globalOrder =
            BuildOrderComputer.computeBuildOrder(allDartPaths) ?? [];
        ordered = sorter.sortByBuildOrder(contexts, (c) => c.path, globalOrder);
      default:
        ordered = contexts;
    }

    // Validate nature configuration — at least one must be set.
    // Tools that want all folders must explicitly use FsFolder.
    final hasRequired = requiredNatures != null && requiredNatures.isNotEmpty;
    final hasWorksWith = worksWithNatures.isNotEmpty;
    if (!hasRequired && !hasWorksWith) {
      throw ArgumentError(
        'Neither requiredNatures nor worksWithNatures is configured. '
        'Set requiredNatures or worksWithNatures (use FsFolder for all folders).',
      );
    }

    // Execute on each context
    for (final ctx in ordered) {
      // Nature filtering:
      // 1. non-empty requiredNatures → must have ALL required
      // 2. non-empty worksWithNatures → must have at least ONE
      if (!_shouldInvokeForNatures(
        ctx.natures,
        requiredNatures,
        worksWithNatures,
      )) {
        continue;
      }

      try {
        final success = await run(ctx);
        success
            ? result.recordSuccess(ctx.path)
            : result.recordFailure(ctx.path);
      } catch (e) {
        result.recordError(ctx.path, e);
      }
    }

    return result;
  }

  /// Determine whether a folder should be invoked based on nature filtering.
  ///
  /// Caller must ensure at least one nature set is configured (validated
  /// at the start of [traverse]).
  ///
  /// 1. `requiredNatures` non-empty → true only if folder has ALL required
  /// 2. `worksWithNatures` non-empty → true if folder has at least ONE
  static bool _shouldInvokeForNatures(
    List<RunFolder> natures,
    Set<Type>? requiredNatures,
    Set<Type> worksWithNatures,
  ) {
    if (requiredNatures != null && requiredNatures.isNotEmpty) {
      // Must have ALL required natures
      return requiredNatures.every((type) => _matchesNature(natures, type));
    }

    if (worksWithNatures.isNotEmpty) {
      // Must have at least ONE supported nature
      return worksWithNatures.any((type) => _matchesNature(natures, type));
    }

    // Should not reach here — validated at traverse() entry
    throw StateError(
      'Neither requiredNatures nor worksWithNatures is configured.',
    );
  }

  /// Check whether a list of natures satisfies a single type requirement.
  ///
  /// Special cases:
  /// - [FsFolder] always matches (every folder is an FsFolder by definition)
  /// - [DartProjectFolder] matches any Dart project subtype (hierarchy check)
  static bool _matchesNature(List<RunFolder> natures, Type type) {
    // FsFolder always matches — every traversed folder is an FsFolder
    if (type == FsFolder) return true;

    // Check actual natures using type hierarchy
    return natures.any((nature) {
      // Exact runtime type match
      if (nature.runtimeType == type) return true;
      // DartProjectFolder hierarchy — any Dart project subtype satisfies
      if (type == DartProjectFolder) return nature is DartProjectFolder;
      return false;
    });
  }

  /// Scan for projects based on ProjectTraversalInfo.
  static Future<List<FsFolder>> _scanProjects(
    ProjectTraversalInfo info, {
    bool verbose = false,
  }) async {
    final scanner = FolderScanner(
      verbose: verbose,
      ignoreSkipMarkers: info.ignoreSkipMarkers,
    );
    return await scanner.scan(
      info.scan,
      recursive: info.recursive,
      recursionExclude: info.recursionExclude,
    );
  }

  /// Find all git repositories based on GitTraversalInfo.
  static Future<List<FsFolder>> _findGitRepos(GitTraversalInfo info) async {
    final finder = GitRepoFinder();
    return await finder.findAll(info.executionRoot);
  }

  /// Get list of projects without executing anything.
  ///
  /// Useful for scripts that need to iterate manually or preview results.
  static Future<List<CommandContext>> findProjects({
    String scan = '.',
    bool recursive = true,
    List<String>? include,
    List<String>? exclude,
    Set<Type>? requiredNatures,
  }) async {
    final info = ProjectTraversalInfo(
      scan: scan,
      recursive: recursive,
      executionRoot: Directory.current.path,
      projectPatterns: include ?? [],
      excludeProjects: exclude ?? [],
    );

    final scanner = FolderScanner();
    final filter = FilterPipeline();
    final detector = NatureDetector();

    final folders = await scanner.scan(
      info.scan,
      recursive: info.recursive,
      recursionExclude: info.recursionExclude,
    );

    final filtered = filter.applyProjectFilters(folders, info);

    return filtered
        .map((folder) {
          final natures = detector.detectNatures(folder);
          folder.natures.addAll(natures);
          return CommandContext(
            fsFolder: folder,
            natures: natures,
            executionRoot: info.executionRoot,
          );
        })
        .where(
          (ctx) =>
              requiredNatures == null ||
              requiredNatures.every(
                (t) => ctx.natures.any((n) => n.runtimeType == t),
              ),
        )
        .toList();
  }

  /// Convenience method to iterate over all Dart projects.
  static Future<ProcessingResult> forEachDartProject(
    Future<bool> Function(CommandContext ctx) run, {
    String scan = '.',
    bool recursive = true,
    List<String>? include,
    List<String>? exclude,
  }) async {
    final info = ProjectTraversalInfo(
      scan: scan,
      recursive: recursive,
      executionRoot: Directory.current.path,
      projectPatterns: include ?? [],
      excludeProjects: exclude ?? [],
    );

    return traverse(
      info: info,
      worksWithNatures: {DartProjectFolder},
      run: run,
    );
  }

  /// Convenience method to iterate over all git repositories.
  static Future<ProcessingResult> forEachGitRepo(
    Future<bool> Function(CommandContext ctx) run, {
    GitTraversalMode mode = GitTraversalMode.innerFirst,
    List<String>? modules,
    List<String>? skipModules,
  }) async {
    final info = GitTraversalInfo(
      executionRoot: Directory.current.path,
      gitMode: mode,
      modules: modules ?? [],
      skipModules: skipModules ?? [],
    );

    return traverse(info: info, worksWithNatures: {GitFolder}, run: run);
  }
}
