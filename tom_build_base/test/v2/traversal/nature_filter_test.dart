/// Tests for the nature filtering logic in BuildBase.traverse().
///
/// Verifies the behavior documented in BuildBase.traverse():
///
/// 1. requiredNatures non-empty → Must have ALL required natures
/// 2. worksWithNatures non-empty → Must have at least ONE
/// 3. Neither set → ArgumentError (tool must configure natures)
///
/// To traverse all folders, use FsFolder explicitly.
///
/// Special: FsFolder in either set always matches (every folder is an FsFolder).
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  late Directory tempDir;

  /// Creates a minimal temp workspace with known folder types:
  /// - dart_console/ (bin/ + pubspec.yaml → DartConsoleFolder)
  /// - dart_package/ (lib/src/ + pubspec.yaml → DartPackageFolder)
  /// - dart_generic/ (pubspec.yaml only → DartProjectFolder)
  /// - ts_project/ (tsconfig.json → TypeScriptFolder)
  /// - plain_dir/ (no markers → no natures)
  /// - git_dart/ (.git/ + pubspec.yaml → GitFolder + DartProjectFolder)
  /// - buildkit_proj/ (buildkit.yaml + pubspec.yaml → BuildkitFolder + DartProjectFolder)
  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('nature_filter_test_');

    // dart_console
    Directory('${tempDir.path}/dart_console/bin').createSync(recursive: true);
    File(
      '${tempDir.path}/dart_console/pubspec.yaml',
    ).writeAsStringSync('name: dart_console\n');

    // dart_package
    Directory(
      '${tempDir.path}/dart_package/lib/src',
    ).createSync(recursive: true);
    File(
      '${tempDir.path}/dart_package/pubspec.yaml',
    ).writeAsStringSync('name: dart_package\n');

    // dart_generic (pubspec only, no bin/ or lib/src/)
    Directory('${tempDir.path}/dart_generic').createSync(recursive: true);
    File(
      '${tempDir.path}/dart_generic/pubspec.yaml',
    ).writeAsStringSync('name: dart_generic\n');

    // ts_project
    Directory('${tempDir.path}/ts_project').createSync(recursive: true);
    File('${tempDir.path}/ts_project/tsconfig.json').writeAsStringSync('{}');

    // plain_dir (no markers at all)
    Directory('${tempDir.path}/plain_dir').createSync(recursive: true);

    // git_dart (git + dart)
    Directory('${tempDir.path}/git_dart/.git').createSync(recursive: true);
    File(
      '${tempDir.path}/git_dart/pubspec.yaml',
    ).writeAsStringSync('name: git_dart\n');

    // buildkit_proj (buildkit + dart)
    Directory('${tempDir.path}/buildkit_proj').createSync(recursive: true);
    File('${tempDir.path}/buildkit_proj/buildkit.yaml').writeAsStringSync('');
    File(
      '${tempDir.path}/buildkit_proj/pubspec.yaml',
    ).writeAsStringSync('name: buildkit_proj\n');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Helper: traverse with given nature params and collect folder names.
  Future<List<String>> traverseWithNatures({
    Set<Type>? requiredNatures,
    Set<Type> worksWithNatures = const {},
  }) async {
    final names = <String>[];
    await BuildBase.traverse(
      info: ProjectTraversalInfo(
        scan: tempDir.path,
        recursive: true,
        executionRoot: tempDir.path,
      ),
      requiredNatures: requiredNatures,
      worksWithNatures: worksWithNatures,
      run: (ctx) async {
        names.add(ctx.name);
        return true;
      },
    );
    return names;
  }

  group('Error — no nature configuration (ArgumentError)', () {
    test(
      'NF-ERR-1: null requiredNatures + empty worksWithNatures throws ArgumentError [2026-02-21]',
      () async {
        expect(
          () =>
              traverseWithNatures(requiredNatures: null, worksWithNatures: {}),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'NF-ERR-2: empty requiredNatures + empty worksWithNatures throws ArgumentError [2026-02-21]',
      () async {
        expect(
          () => traverseWithNatures(requiredNatures: {}, worksWithNatures: {}),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'NF-ERR-3: null requiredNatures + non-empty worksWithNatures does NOT throw [2026-02-21]',
      () async {
        // worksWithNatures is configured → filtering applies (no error)
        final names = await traverseWithNatures(
          requiredNatures: null,
          worksWithNatures: {TypeScriptFolder},
        );

        // Only TypeScript folder matches
        expect(names, contains('ts_project'));
        expect(names, isNot(contains('dart_console')));
        expect(names, isNot(contains('plain_dir')));
      },
    );
  });

  group('Tier 2 — requiredNatures is non-empty (must have ALL)', () {
    test(
      'NF-T2-1: requiredNatures {DartProjectFolder} matches all Dart projects [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {DartProjectFolder},
        );

        // DartProjectFolder hierarchy: DartConsoleFolder, DartPackageFolder, DartProjectFolder
        expect(names, contains('dart_console'));
        expect(names, contains('dart_package'));
        expect(names, contains('dart_generic'));
        expect(names, contains('git_dart'));
        expect(names, contains('buildkit_proj'));
        // NOT TypeScript or plain
        expect(names, isNot(contains('ts_project')));
        expect(names, isNot(contains('plain_dir')));
      },
    );

    test(
      'NF-T2-2: requiredNatures {DartConsoleFolder} matches only console projects [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {DartConsoleFolder},
        );

        expect(names, equals(['dart_console']));
      },
    );

    test(
      'NF-T2-3: requiredNatures {DartPackageFolder} matches only package projects [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {DartPackageFolder},
        );

        expect(names, equals(['dart_package']));
      },
    );

    test(
      'NF-T2-4: requiredNatures {TypeScriptFolder} matches only TS projects [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {TypeScriptFolder},
        );

        expect(names, equals(['ts_project']));
      },
    );

    test(
      'NF-T2-5: requiredNatures {GitFolder, DartProjectFolder} requires BOTH natures [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {GitFolder, DartProjectFolder},
        );

        // Only git_dart has BOTH GitFolder and DartProjectFolder
        expect(names, equals(['git_dart']));
      },
    );

    test(
      'NF-T2-6: requiredNatures {BuildkitFolder, DartProjectFolder} requires BOTH [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {BuildkitFolder, DartProjectFolder},
        );

        expect(names, equals(['buildkit_proj']));
      },
    );

    test(
      'NF-T2-7: requiredNatures {FsFolder} matches ALL folders [2026-02-20]',
      () async {
        final names = await traverseWithNatures(requiredNatures: {FsFolder});

        // FsFolder is a special type — every folder is an FsFolder
        expect(names, contains('dart_console'));
        expect(names, contains('dart_package'));
        expect(names, contains('ts_project'));
        expect(names, contains('plain_dir'));
        expect(names, contains('git_dart'));
        expect(names, contains('buildkit_proj'));
      },
    );

    test(
      'NF-T2-8: worksWithNatures is ignored when requiredNatures is set [2026-02-20]',
      () async {
        // Even though worksWithNatures includes TypeScriptFolder,
        // requiredNatures {DartConsoleFolder} is decisive
        final names = await traverseWithNatures(
          requiredNatures: {DartConsoleFolder},
          worksWithNatures: {TypeScriptFolder},
        );

        expect(names, equals(['dart_console']));
      },
    );
  });

  group('worksWithNatures — requiredNatures empty, worksWithNatures set', () {
    test(
      'NF-T3a-1: worksWithNatures {DartProjectFolder} invokes on any Dart project [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {DartProjectFolder},
        );

        expect(names, contains('dart_console'));
        expect(names, contains('dart_package'));
        expect(names, contains('dart_generic'));
        expect(names, contains('git_dart'));
        expect(names, contains('buildkit_proj'));
        expect(names, isNot(contains('ts_project')));
        expect(names, isNot(contains('plain_dir')));
      },
    );

    test(
      'NF-T3a-2: worksWithNatures {TypeScriptFolder, DartConsoleFolder} invokes on either [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {TypeScriptFolder, DartConsoleFolder},
        );

        // Should match ts_project (TypeScript) AND dart_console (DartConsole)
        expect(names, containsAll(['ts_project', 'dart_console']));
        expect(names, isNot(contains('plain_dir')));
        expect(names, isNot(contains('dart_package')));
      },
    );

    test(
      'NF-T3a-3: worksWithNatures {GitFolder} invokes only on git repos [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {GitFolder},
        );

        expect(names, equals(['git_dart']));
      },
    );

    test(
      'NF-T3a-4: worksWithNatures {FsFolder} matches ALL folders [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {FsFolder},
        );

        expect(names, contains('dart_console'));
        expect(names, contains('plain_dir'));
        expect(names, contains('ts_project'));
      },
    );

    test(
      'NF-T3a-5: worksWithNatures {BuildkitFolder} matches only buildkit folders [2026-02-20]',
      () async {
        final names = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {BuildkitFolder},
        );

        expect(names, equals(['buildkit_proj']));
      },
    );
  });

  // Tier 3b tests moved to 'Error — no nature configuration' group above
  // (both empty now throws ArgumentError instead of silently skipping)

  group('Edge cases', () {
    test(
      'NF-EDGE-1: non-existent type in requiredNatures matches nothing [2026-02-20]',
      () async {
        // FlutterProjectFolder requires flutter SDK dep — none of our test folders have it
        final names = await traverseWithNatures(
          requiredNatures: {FlutterProjectFolder},
        );

        expect(names, isEmpty);
      },
    );

    test(
      'NF-EDGE-2: mixed natures — folder must have ALL required [2026-02-20]',
      () async {
        // Require Git + TypeScript — no folder has both
        final names = await traverseWithNatures(
          requiredNatures: {GitFolder, TypeScriptFolder},
        );

        expect(names, isEmpty);
      },
    );

    test(
      'NF-EDGE-3: FsFolder combined with other nature in requiredNatures [2026-02-20]',
      () async {
        // FsFolder always matches, so {FsFolder, DartProjectFolder} = just DartProjectFolder
        final names = await traverseWithNatures(
          requiredNatures: {FsFolder, DartProjectFolder},
        );

        expect(names, contains('dart_console'));
        expect(names, contains('dart_package'));
        expect(names, isNot(contains('ts_project')));
        expect(names, isNot(contains('plain_dir')));
      },
    );

    test(
      'NF-EDGE-4: plain directory has no natures — only matched by FsFolder [2026-02-21]',
      () async {
        // With FsFolder in requiredNatures
        final namesFsFolder = await traverseWithNatures(
          requiredNatures: {FsFolder},
        );
        expect(namesFsFolder, contains('plain_dir'));

        // With FsFolder in worksWithNatures
        final namesFsWorks = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {FsFolder},
        );
        expect(namesFsWorks, contains('plain_dir'));

        // With DartProjectFolder
        final namesDart = await traverseWithNatures(
          requiredNatures: {DartProjectFolder},
        );
        expect(namesDart, isNot(contains('plain_dir')));

        // With worksWithNatures (empty required)
        final namesWorks = await traverseWithNatures(
          requiredNatures: {},
          worksWithNatures: {DartProjectFolder},
        );
        expect(namesWorks, isNot(contains('plain_dir')));
      },
    );
  });
}
