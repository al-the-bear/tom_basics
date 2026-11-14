import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// The traversal filters on Windows paths: `navigation: exclude` of
/// buildkit_master.yaml (and `--exclude`), `--exclude-projects` and
/// `--project` path patterns, and the scanner's `--recursion-exclude`, under
/// the Windows path context, so they run on any host. On Windows a folder path
/// is `C:\...\tom_ai\xternal\...`; a pattern is written with `/`.
///
/// Test IDs: BB-WINX-1..6.
void main() {
  const root = r'C:\Code\ws';
  String win(String rel) =>
      p.windows.join(root, p.windows.joinAll(rel.split('/')));

  final kept = win('tom_ai/basics/tom_build_base');
  final excluded = {
    'xternal/**': win('tom_ai/xternal/tom_xterm'),
    'tom_ai/ai_build/**': win('tom_ai/ai_build/tom_specs_core'),
    '**/zom_workspaces': win('zom_workspaces/zom_analyzer_test'),
  };

  List<String> paths(List<FsFolder> folders) => [
    for (final f in folders) f.path,
  ];
  List<FsFolder> folders() => [
    FsFolder(path: kept),
    for (final path in excluded.values) FsFolder(path: path),
  ];

  group('Windows paths', () {
    final filter = FilterPipeline(pathContext: p.windows);

    test('BB-WINX-1: each navigation exclude form (dir/**, a/b/**, **/x) '
        'excludes its Windows path [2026-11-14]', () {
      for (final MapEntry(key: pattern, value: path) in excluded.entries) {
        final result = filter.applyProjectFilters(
          folders(),
          ProjectTraversalInfo(executionRoot: root, excludePatterns: [pattern]),
        );
        expect(paths(result), isNot(contains(path)), reason: pattern);
        expect(paths(result), contains(kept), reason: pattern);
      }
    });

    test('BB-WINX-2: the workspace\'s navigation excludes together keep only '
        'the other projects [2026-11-14]', () {
      final result = filter.applyProjectFilters(
        folders(),
        ProjectTraversalInfo(
          executionRoot: root,
          excludePatterns: excluded.keys.toList(),
        ),
      );
      expect(paths(result), [kept]);
    });

    test('BB-WINX-3: --exclude-projects path patterns match the relative '
        'Windows path, also when the drive letter differs in case '
        '[2026-11-14]', () {
      for (final executionRoot in [root, root.toLowerCase()]) {
        final result = filter.applyProjectFilters(
          folders(),
          ProjectTraversalInfo(
            executionRoot: executionRoot,
            excludeProjects: ['tom_ai/xternal/**', 'tom_ai/ai_build/*'],
          ),
        );
        expect(
          paths(result),
          isNot(contains(excluded['xternal/**'])),
          reason: executionRoot,
        );
        expect(
          paths(result),
          isNot(contains(excluded['tom_ai/ai_build/**'])),
          reason: executionRoot,
        );
        expect(paths(result), contains(kept), reason: executionRoot);
      }
    });

    test('BB-WINX-4: --project path patterns select by the relative Windows '
        'path [2026-11-14]', () {
      final folder = FsFolder(path: excluded['xternal/**']!);
      expect(
        filter.matchesProjectPattern(folder, [
          'tom_ai/xternal/*',
        ], executionRoot: root),
        isTrue,
      );
      expect(
        filter.matchesProjectPattern(FsFolder(path: kept), [
          'tom_ai/xternal/*',
        ], executionRoot: root),
        isFalse,
      );
    });

    test('BB-WINX-5: --recursion-exclude matches a Windows path the way it '
        'matches a POSIX one [2026-11-14]', () {
      final winPath = win('tom_ai/xternal/tom_xterm/node_modules');
      final posixPath = '/ws/tom_ai/xternal/tom_xterm/node_modules';
      for (final pattern in ['**/node_modules', 'node_modules']) {
        expect(
          FolderScanner.matchesRecursionExclude(winPath, 'node_modules', [
            pattern,
          ]),
          FolderScanner.matchesRecursionExclude(posixPath, 'node_modules', [
            pattern,
          ]),
          reason: pattern,
        );
      }
      expect(
        FolderScanner.matchesRecursionExclude(winPath, 'node_modules', [
          '**/node_modules',
        ]),
        isTrue,
      );
    });
  });

  test('BB-WINX-6: the same patterns on POSIX paths give the same result '
      '[2026-11-14]', () {
    const posixRoot = '/Code/ws';
    String posix(String rel) => p.posix.join(posixRoot, rel);
    final filter = FilterPipeline(pathContext: p.posix);
    final result = filter.applyProjectFilters(
      [
        FsFolder(path: posix('tom_ai/basics/tom_build_base')),
        FsFolder(path: posix('tom_ai/xternal/tom_xterm')),
        FsFolder(path: posix('tom_ai/ai_build/tom_specs_core')),
        FsFolder(path: posix('zom_workspaces/zom_analyzer_test')),
      ],
      ProjectTraversalInfo(
        executionRoot: posixRoot,
        excludePatterns: excluded.keys.toList(),
      ),
    );
    expect(paths(result), [posix('tom_ai/basics/tom_build_base')]);
  });
}
