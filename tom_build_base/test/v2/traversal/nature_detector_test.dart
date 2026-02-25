import 'dart:io';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

/// Tests for NatureDetector using real test projects.
void main() {
  late String workspaceRoot;
  late String zomTestRoot;
  late NatureDetector detector;

  setUpAll(() {
    final currentDir = Directory.current.path;
    workspaceRoot = p.normalize(p.join(currentDir, '..', '..', '..'));
    zomTestRoot = p.join(workspaceRoot, 'zom_workspaces', 'zom_analyzer_test');

    final testDir = Directory(zomTestRoot);
    if (!testDir.existsSync()) {
      fail('Test projects not found at $zomTestRoot');
    }
  });

  setUp(() {
    detector = NatureDetector();
  });

  group('NatureDetector', () {
    group('Flutter project detection', () {
      test('BB-NAT-1: Detects FlutterProjectFolder for zom_test_flutter [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_flutter');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is FlutterProjectFolder), isTrue,
            reason: 'Should detect FlutterProjectFolder');
        expect(natures.any((n) => n is DartConsoleFolder), isFalse,
            reason: 'Should NOT be detected as console app');
        expect(natures.any((n) => n is DartPackageFolder), isFalse,
            reason: 'Should NOT be detected as package');
      });

      test('BB-NAT-2: FlutterProjectFolder has correct metadata [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_flutter');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final flutter = natures.whereType<FlutterProjectFolder>().first;

        expect(flutter.projectName, equals('zom_test_flutter'));
        expect(flutter.platforms, isNotEmpty,
            reason: 'Should detect at least one platform');
      });
    });

    group('Dart console app detection', () {
      test('BB-NAT-3: Detects DartConsoleFolder for zom_test_standalone [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_standalone');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is DartConsoleFolder), isTrue,
            reason: 'Should detect DartConsoleFolder');
        expect(natures.any((n) => n is FlutterProjectFolder), isFalse,
            reason: 'Should NOT be detected as Flutter');
        expect(natures.any((n) => n is DartPackageFolder), isFalse,
            reason: 'Should NOT be detected as package');
      });

      test('BB-NAT-4: DartConsoleFolder has executables [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_standalone');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final console = natures.whereType<DartConsoleFolder>().first;

        expect(console.projectName, equals('zom_test_standalone'));
        expect(console.executables, isNotEmpty,
            reason: 'Should detect executables in bin/');
      });
    });

    group('Dart package detection', () {
      test('BB-NAT-5: Detects DartPackageFolder for zom_test_package [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_package');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is DartPackageFolder), isTrue,
            reason: 'Should detect DartPackageFolder');
        expect(natures.any((n) => n is FlutterProjectFolder), isFalse,
            reason: 'Should NOT be detected as Flutter');
        expect(natures.any((n) => n is DartConsoleFolder), isFalse,
            reason: 'Should NOT be detected as console app');
      });

      test('BB-NAT-6: DartPackageFolder has correct metadata [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_package');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final pkg = natures.whereType<DartPackageFolder>().first;

        expect(pkg.projectName, equals('zom_test_package'));
      });

      test('BB-NAT-7: DartPackageFolder requires lib/src/ per design spec [2026-02-12]', () {
        // Design spec: "DartPackageFolder: pubspec.yaml exists AND lib/src/ exists"
        // zom_test_package has lib/src/, so it should be detected
        final path = p.join(zomTestRoot, 'zom_test_package');
        final hasLibSrc = Directory(p.join(path, 'lib', 'src')).existsSync();

        expect(hasLibSrc, isTrue,
            reason: 'Test precondition: zom_test_package should have lib/src/');

        final folder = FsFolder(path: path);
        final natures = detector.detectNatures(folder);
        final pkg = natures.whereType<DartPackageFolder>().firstOrNull;

        expect(pkg, isNotNull,
            reason: 'Project with pubspec.yaml AND lib/src/ should be DartPackageFolder');
        expect(pkg!.hasLibSrc, isTrue,
            reason: 'DartPackageFolder should have hasLibSrc=true');
      });
    });

    group('VS Code extension detection', () {
      test('BB-NAT-8: Detects VsCodeExtensionFolder for zom_extension [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_extension');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is VsCodeExtensionFolder), isTrue,
            reason: 'Should detect VsCodeExtensionFolder');
      });

      test('BB-NAT-9: VsCodeExtensionFolder has correct metadata [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_extension');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final ext = natures.whereType<VsCodeExtensionFolder>().first;

        expect(ext.extensionName, equals('zom-extension'));
        expect(ext.displayName, equals('Zom Extension'));
      });
    });

    group('TypeScript project detection', () {
      test('BB-NAT-10: Detects TypeScriptFolder for zom_typescript [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_typescript');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is TypeScriptFolder), isTrue,
            reason: 'Should detect TypeScriptFolder');
      });

      test('BB-NAT-11: Zom_extension also has TypeScriptFolder nature [2026-02-12]', () {
        // VS Code extensions are also TypeScript projects
        final path = p.join(zomTestRoot, 'zom_extension');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is TypeScriptFolder), isTrue,
            reason: 'VS Code extension should also have TypeScriptFolder');
        expect(natures.any((n) => n is VsCodeExtensionFolder), isTrue,
            reason: 'Should also have VsCodeExtensionFolder');
      });
    });

    group('Git folder detection', () {
      test('BB-NAT-12: Detects GitFolder for workspace root [2026-02-12]', () {
        final folder = FsFolder(path: workspaceRoot);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is GitFolder), isTrue,
            reason: 'Workspace root should be a git repo');
      });

      test('BB-NAT-13: GitFolder has branch information [2026-02-12]', () {
        final folder = FsFolder(path: workspaceRoot);

        final natures = detector.detectNatures(folder);
        final git = natures.whereType<GitFolder>().first;

        expect(git.currentBranch, isNotEmpty);
        expect(git.remotes, isNotEmpty,
            reason: 'Should have at least one remote');
      });
    });

    group('TomBuildFolder detection', () {
      test('BB-NAT-14: Detects TomBuildFolder when tom_project.yaml exists [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_flutter');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.any((n) => n is TomBuildFolder), isTrue,
            reason: 'Should detect TomBuildFolder from tom_project.yaml');
      });
    });

    group('Multiple natures', () {
      test('BB-NAT-15: Folder can have multiple natures [2026-02-12]', () {
        // zom_test_flutter has: FlutterProjectFolder, TomBuildFolder
        final path = p.join(zomTestRoot, 'zom_test_flutter');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        expect(natures.length, greaterThan(1),
            reason: 'Flutter project should have multiple natures');

        // Should have at least Flutter and TomBuild natures
        expect(natures.any((n) => n is FlutterProjectFolder), isTrue);
        expect(natures.any((n) => n is TomBuildFolder), isTrue);
      });

      test('BB-NAT-16: VS Code extension has multiple natures [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_extension');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        // Should have VsCodeExtension and TypeScript natures
        expect(natures.any((n) => n is VsCodeExtensionFolder), isTrue);
        expect(natures.any((n) => n is TypeScriptFolder), isTrue);
      });
    });

    group('Non-project folders', () {
      test('BB-NAT-17: Empty folder has no project natures [2026-02-12]', () {
        // Create a temp directory to test
        final tempDir = Directory.systemTemp.createTempSync('nature_test_');
        try {
          final folder = FsFolder(path: tempDir.path);

          final natures = detector.detectNatures(folder);

          // Should have no project natures (might have git if in a git repo)
          expect(natures.any((n) => n is DartProjectFolder), isFalse);
          expect(natures.any((n) => n is TypeScriptFolder), isFalse);
          expect(natures.any((n) => n is VsCodeExtensionFolder), isFalse);
        } finally {
          tempDir.deleteSync();
        }
      });
    });

    group('Nature type hierarchy', () {
      test('BB-NAT-18: FlutterProjectFolder is a DartProjectFolder [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_flutter');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final flutter = natures.whereType<FlutterProjectFolder>().first;

        expect(flutter, isA<DartProjectFolder>());
      });

      test('BB-NAT-19: DartConsoleFolder is a DartProjectFolder [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_standalone');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final console = natures.whereType<DartConsoleFolder>().first;

        expect(console, isA<DartProjectFolder>());
      });

      test('BB-NAT-20: DartPackageFolder is a DartProjectFolder [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_package');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);
        final pkg = natures.whereType<DartPackageFolder>().first;

        expect(pkg, isA<DartProjectFolder>());
      });

      test('BB-NAT-21: All nature types extend RunFolder [2026-02-12]', () {
        final path = p.join(zomTestRoot, 'zom_test_flutter');
        final folder = FsFolder(path: path);

        final natures = detector.detectNatures(folder);

        for (final nature in natures) {
          expect(nature, isA<RunFolder>());
        }
      });
    });
  });

  group('DartProjectFolder static methods', () {
    test('BB-NAT-22: IsDartProject returns true for Dart projects [2026-02-12]', () {
      expect(DartProjectFolder.isDartProject(
          p.join(zomTestRoot, 'zom_test_flutter')), isTrue);
      expect(DartProjectFolder.isDartProject(
          p.join(zomTestRoot, 'zom_test_package')), isTrue);
      expect(DartProjectFolder.isDartProject(
          p.join(zomTestRoot, 'zom_test_standalone')), isTrue);
    });

    test('BB-NAT-23: IsDartProject returns false for non-Dart projects [2026-02-12]', () {
      expect(DartProjectFolder.isDartProject(
          p.join(zomTestRoot, 'zom_typescript')), isFalse);
      expect(DartProjectFolder.isDartProject(
          p.join(zomTestRoot, 'zom_extension')), isFalse);
    });
  });

  group('GitFolder static methods', () {
    test('BB-NAT-24: IsGitFolder returns true for git repos [2026-02-12]', () {
      expect(GitFolder.isGitFolder(workspaceRoot), isTrue);
    });

    test('BB-NAT-25: IsGitFolder returns false for non-git folders [2026-02-12]', () {
      final tempDir = Directory.systemTemp.createTempSync('git_test_');
      try {
        expect(GitFolder.isGitFolder(tempDir.path), isFalse);
      } finally {
        tempDir.deleteSync();
      }
    });
  });

  group('VsCodeExtensionFolder static methods', () {
    test('BB-NAT-26: IsVsCodeExtension returns true for extensions [2026-02-12]', () {
      expect(VsCodeExtensionFolder.isVsCodeExtension(
          p.join(zomTestRoot, 'zom_extension')), isTrue);
    });

    test('BB-NAT-27: IsVsCodeExtension returns false for regular TS projects [2026-02-12]', () {
      expect(VsCodeExtensionFolder.isVsCodeExtension(
          p.join(zomTestRoot, 'zom_typescript')), isFalse);
    });
  });

  group('TypeScriptFolder static methods', () {
    test('BB-NAT-28: IsTypeScriptProject returns true for TS projects [2026-02-12]', () {
      expect(TypeScriptFolder.isTypeScriptProject(
          p.join(zomTestRoot, 'zom_typescript')), isTrue);
      expect(TypeScriptFolder.isTypeScriptProject(
          p.join(zomTestRoot, 'zom_extension')), isTrue);
    });

    test('BB-NAT-29: IsTypeScriptProject returns false for Dart projects [2026-02-12]', () {
      expect(TypeScriptFolder.isTypeScriptProject(
          p.join(zomTestRoot, 'zom_test_flutter')), isFalse);
    });
  });

  // Design specification verification tests
  group('Design specification: Detection Rules', () {
    // From cli_v2_design.md Detection Rules table
    test('BB-NAT-30: GitFolder: .git/ directory or .git file exists [2026-02-12]', () {
      // .git directory case (workspace root is a normal git repo)
      expect(Directory(p.join(workspaceRoot, '.git')).existsSync() ||
             File(p.join(workspaceRoot, '.git')).existsSync(), isTrue,
          reason: 'Test precondition: workspace root should have .git');

      final folder = FsFolder(path: workspaceRoot);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is GitFolder), isTrue,
          reason: 'Folder with .git should be detected as GitFolder');
    });

    test('BB-NAT-31: DartProjectFolder: pubspec.yaml exists [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_test_package');
      expect(File(p.join(path, 'pubspec.yaml')).existsSync(), isTrue,
          reason: 'Test precondition: should have pubspec.yaml');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is DartProjectFolder), isTrue,
          reason: 'Folder with pubspec.yaml should be DartProjectFolder');
    });

    test('BB-NAT-32: FlutterProjectFolder: pubspec.yaml contains sdk: flutter [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_test_flutter');
      final pubspec = File(p.join(path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec.contains('sdk: flutter'), isTrue,
          reason: 'Test precondition: should have sdk: flutter');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is FlutterProjectFolder), isTrue,
          reason: 'Dart project with sdk: flutter should be FlutterProjectFolder');
    });

    test('BB-NAT-33: DartConsoleFolder: pubspec.yaml exists AND bin/ exists [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_test_standalone');
      expect(File(p.join(path, 'pubspec.yaml')).existsSync(), isTrue,
          reason: 'Test precondition: should have pubspec.yaml');
      expect(Directory(p.join(path, 'bin')).existsSync(), isTrue,
          reason: 'Test precondition: should have bin/');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is DartConsoleFolder), isTrue,
          reason: 'Dart project with bin/ should be DartConsoleFolder');
    });

    test('BB-NAT-34: DartPackageFolder: pubspec.yaml exists AND lib/src/ exists [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_test_package');
      expect(File(p.join(path, 'pubspec.yaml')).existsSync(), isTrue,
          reason: 'Test precondition: should have pubspec.yaml');
      expect(Directory(p.join(path, 'lib', 'src')).existsSync(), isTrue,
          reason: 'Test precondition: should have lib/src/');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is DartPackageFolder), isTrue,
          reason: 'Dart project with lib/src/ should be DartPackageFolder');
    });

    test('BB-NAT-35: VsCodeExtensionFolder: package.json contains engines.vscode [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_extension');
      final packageJson = File(p.join(path, 'package.json')).readAsStringSync();
      expect(packageJson.contains('"engines"') && packageJson.contains('"vscode"'), isTrue,
          reason: 'Test precondition: should have engines.vscode in package.json');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is VsCodeExtensionFolder), isTrue,
          reason: 'Folder with engines.vscode should be VsCodeExtensionFolder');
    });

    test('BB-NAT-36: TypeScriptFolder: tsconfig.json exists [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_typescript');
      expect(File(p.join(path, 'tsconfig.json')).existsSync(), isTrue,
          reason: 'Test precondition: should have tsconfig.json');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is TypeScriptFolder), isTrue,
          reason: 'Folder with tsconfig.json should be TypeScriptFolder');
    });

    test('BB-NAT-37: TomBuildFolder: tom_project.yaml exists [2026-02-12]', () {
      final path = p.join(zomTestRoot, 'zom_test_flutter');
      expect(File(p.join(path, 'tom_project.yaml')).existsSync(), isTrue,
          reason: 'Test precondition: should have tom_project.yaml');

      final folder = FsFolder(path: path);
      final natures = NatureDetector().detectNatures(folder);

      expect(natures.any((n) => n is TomBuildFolder), isTrue,
          reason: 'Folder with tom_project.yaml should be TomBuildFolder');
    });

    test('BB-NAT-38: BUG: Dart project without bin/ or lib/src/ should NOT be DartP... [2026-02-12]', () {
      // Design spec states:
      // - DartConsoleFolder: pubspec.yaml AND bin/ exists
      // - DartPackageFolder: pubspec.yaml AND lib/src/ exists  
      // Therefore a Dart project with NEITHER should not be DartPackageFolder
      
      // Create a temp Dart project with pubspec.yaml but no bin/ or lib/src/
      final tempDir = Directory.systemTemp.createTempSync('dart_no_bin_no_lib_');
      try {
        // Create minimal pubspec.yaml
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test_minimal
version: 1.0.0

environment:
  sdk: ^3.0.0
''');
        // Verify preconditions - NO bin/ and NO lib/src/
        expect(Directory(p.join(tempDir.path, 'bin')).existsSync(), isFalse,
            reason: 'Test precondition: should NOT have bin/');
        expect(Directory(p.join(tempDir.path, 'lib', 'src')).existsSync(), isFalse,
            reason: 'Test precondition: should NOT have lib/src/');

        final folder = FsFolder(path: tempDir.path);
        final natures = NatureDetector().detectNatures(folder);

        // Should be detected as some kind of DartProjectFolder
        expect(natures.any((n) => n is DartProjectFolder), isTrue,
            reason: 'Should be detected as DartProjectFolder (pubspec.yaml exists)');
        
        // But should NOT be DartPackageFolder (no lib/src/ per design spec)
        expect(natures.any((n) => n is DartPackageFolder), isFalse,
            reason: 'Per design spec: DartPackageFolder requires lib/src/');
        
        // Should NOT be DartConsoleFolder (no bin/)
        expect(natures.any((n) => n is DartConsoleFolder), isFalse,
            reason: 'Per design spec: DartConsoleFolder requires bin/');
        
        // Should NOT be FlutterProjectFolder (no flutter sdk)
        expect(natures.any((n) => n is FlutterProjectFolder), isFalse,
            reason: 'Per design spec: FlutterProjectFolder requires sdk: flutter');
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
