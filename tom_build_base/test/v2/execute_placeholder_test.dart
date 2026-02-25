import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base.dart';

void main() {
  group('ExecutePlaceholderResolver', () {
    late FsFolder folder;
    late ExecutePlaceholderContext ctx;

    setUp(() {
      folder = FsFolder(path: '/workspace/my-project');
    });

    group('Path placeholders', () {
      setUp(() {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
      });

      test('BB-EPH-01: resolves root placeholder', () {
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('root', ctx),
          equals('/workspace'),
        );
      });

      test('BB-EPH-02: resolves folder placeholder', () {
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('folder', ctx),
          equals('/workspace/my-project'),
        );
      });

      test('BB-EPH-03: resolves folder.name placeholder', () {
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('folder.name', ctx),
          equals('my-project'),
        );
      });

      test('BB-EPH-04: resolves folder.relative placeholder', () {
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('folder.relative', ctx),
          equals('my-project'),
        );
      });
    });

    group('Platform placeholders', () {
      test('BB-EPH-05: resolves current-os placeholder', () {
        ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
          currentOs: 'linux',
        );
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('current-os', ctx),
          equals('linux'),
        );
      });

      test('BB-EPH-06: resolves current-arch placeholder', () {
        ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
          currentArch: 'arm64',
        );
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('current-arch', ctx),
          equals('arm64'),
        );
      });

      test('BB-EPH-07: resolves current-platform placeholder', () {
        ctx = ExecutePlaceholderContext(
          rootPath: '/workspace',
          folder: folder,
          currentOs: 'macos',
          currentArch: 'arm64',
        );
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder(
            'current-platform',
            ctx,
          ),
          equals('darwin-arm64'),
        );
      });
    });

    group('Nature existence placeholders', () {
      test('BB-EPH-08: dart.exists returns false when no Dart nature', () {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('dart.exists', ctx),
          equals('false'),
        );
      });

      test('BB-EPH-09: dart.exists returns true when Dart nature present', () {
        folder.natures.add(
          DartProjectFolder(folder, projectName: 'test_project'),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('dart.exists', ctx),
          equals('true'),
        );
      });

      test('BB-EPH-10: git.exists returns true when Git nature present', () {
        folder.natures.add(GitFolder(folder, currentBranch: 'main'));
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('git.exists', ctx),
          equals('true'),
        );
      });

      test(
        'BB-EPH-11: flutter.exists returns true when Flutter nature present',
        () {
          folder.natures.add(
            FlutterProjectFolder(
              folder,
              projectName: 'my_app',
              platforms: ['ios', 'android'],
            ),
          );
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.resolvePlaceholder(
              'flutter.exists',
              ctx,
            ),
            equals('true'),
          );
        },
      );
    });

    group('Dart attribute placeholders', () {
      test('BB-EPH-12: dart.name returns project name', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'my_package',
            version: '1.2.3',
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('dart.name', ctx),
          equals('my_package'),
        );
      });

      test('BB-EPH-13: dart.version returns version', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'my_package',
            version: '1.2.3',
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('dart.version', ctx),
          equals('1.2.3'),
        );
      });

      test(
        'BB-EPH-14: dart.publishable returns true for publishable package',
        () {
          folder.natures.add(
            DartProjectFolder(
              folder,
              projectName: 'my_package',
              version: '1.0.0',
              pubspec: {'name': 'my_package', 'version': '1.0.0'},
            ),
          );
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.resolvePlaceholder(
              'dart.publishable',
              ctx,
            ),
            equals('true'),
          );
        },
      );

      test(
        'BB-EPH-15: dart.publishable returns false for publish_to: none',
        () {
          folder.natures.add(
            DartProjectFolder(
              folder,
              projectName: 'my_package',
              version: '1.0.0',
              pubspec: {
                'name': 'my_package',
                'version': '1.0.0',
                'publish_to': 'none',
              },
            ),
          );
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.resolvePlaceholder(
              'dart.publishable',
              ctx,
            ),
            equals('false'),
          );
        },
      );

      test('BB-EPH-16: dart.name throws when not a Dart project', () {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          () => ExecutePlaceholderResolver.resolvePlaceholder('dart.name', ctx),
          throwsA(
            isA<UnresolvedPlaceholderException>()
                .having((e) => e.placeholder, 'placeholder', 'dart.name')
                .having((e) => e.message, 'message', 'not a Dart project'),
          ),
        );
      });
    });

    group('Git attribute placeholders', () {
      test('BB-EPH-17: git.branch returns current branch', () {
        folder.natures.add(
          GitFolder(
            folder,
            currentBranch: 'feature/test',
            remotes: ['origin', 'upstream'],
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('git.branch', ctx),
          equals('feature/test'),
        );
      });

      test('BB-EPH-18: git.remotes returns comma-separated list', () {
        folder.natures.add(
          GitFolder(
            folder,
            currentBranch: 'main',
            remotes: ['origin', 'upstream'],
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('git.remotes', ctx),
          equals('origin,upstream'),
        );
      });

      test(
        'BB-EPH-19: git.hasChanges returns true when uncommitted changes',
        () {
          folder.natures.add(
            GitFolder(
              folder,
              currentBranch: 'main',
              hasUncommittedChanges: true,
            ),
          );
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.resolvePlaceholder(
              'git.hasChanges',
              ctx,
            ),
            equals('true'),
          );
        },
      );

      test('BB-EPH-20: git.branch throws when not a git repo', () {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          () =>
              ExecutePlaceholderResolver.resolvePlaceholder('git.branch', ctx),
          throwsA(
            isA<UnresolvedPlaceholderException>().having(
              (e) => e.message,
              'message',
              'not a git repository',
            ),
          ),
        );
      });
    });

    group('Flutter attribute placeholders', () {
      test(
        'BB-EPH-21: flutter.platforms returns comma-separated platforms',
        () {
          folder.natures.add(
            FlutterProjectFolder(
              folder,
              projectName: 'my_app',
              platforms: ['ios', 'android', 'web'],
            ),
          );
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.resolvePlaceholder(
              'flutter.platforms',
              ctx,
            ),
            equals('ios,android,web'),
          );
        },
      );

      test('BB-EPH-22: flutter.isPlugin returns true for plugins', () {
        folder.natures.add(
          FlutterProjectFolder(
            folder,
            projectName: 'my_plugin',
            isPlugin: true,
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder(
            'flutter.isPlugin',
            ctx,
          ),
          equals('true'),
        );
      });
    });

    group('VS Code extension placeholders', () {
      test('BB-EPH-23: vscode.name returns extension name', () {
        folder.natures.add(
          VsCodeExtensionFolder(
            folder,
            extensionName: 'my-extension',
            version: '0.1.0',
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('vscode.name', ctx),
          equals('my-extension'),
        );
      });

      test('BB-EPH-24: vscode.version returns extension version', () {
        folder.natures.add(
          VsCodeExtensionFolder(
            folder,
            extensionName: 'my-extension',
            version: '0.1.0',
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          ExecutePlaceholderResolver.resolvePlaceholder('vscode.version', ctx),
          equals('0.1.0'),
        );
      });
    });

    group('Unknown placeholder', () {
      test('BB-EPH-25: throws for unknown placeholder', () {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          () => ExecutePlaceholderResolver.resolvePlaceholder(
            'unknown.thing',
            ctx,
          ),
          throwsA(
            isA<UnresolvedPlaceholderException>().having(
              (e) => e.message,
              'message',
              'unknown placeholder',
            ),
          ),
        );
      });
    });

    group('Ternary expression resolution', () {
      test('BB-EPH-26: resolves ternary with true condition', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'test',
            version: '1.0.0',
            pubspec: {'name': 'test', 'version': '1.0.0'},
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        final result = ExecutePlaceholderResolver.resolveCommand(
          r'echo ${dart.publishable?(Publishable):(Not Publishable)}',
          ctx,
        );
        expect(result, equals('echo Publishable'));
      });

      test('BB-EPH-27: resolves ternary with false condition', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'test',
            version: '1.0.0',
            pubspec: {'name': 'test', 'version': '1.0.0', 'publish_to': 'none'},
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        final result = ExecutePlaceholderResolver.resolveCommand(
          r'echo ${dart.publishable?(Publishable):(Not Publishable)}',
          ctx,
        );
        expect(result, equals('echo Not Publishable'));
      });

      test('BB-EPH-28: resolves ternary with empty false branch', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'test',
            version: '1.0.0',
            pubspec: {'name': 'test', 'version': '1.0.0', 'publish_to': 'none'},
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        final result = ExecutePlaceholderResolver.resolveCommand(
          r'${dart.publishable?(dart publish):()}',
          ctx,
        );
        expect(result, equals(''));
      });

      test('BB-EPH-29: throws for ternary on non-boolean placeholder', () {
        folder.natures.add(DartProjectFolder(folder, projectName: 'test'));
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          () => ExecutePlaceholderResolver.resolveCommand(
            r'${dart.name?(yes):(no)}',
            ctx,
          ),
          throwsA(
            isA<UnresolvedPlaceholderException>().having(
              (e) => e.message,
              'message',
              'not a boolean placeholder (cannot use ternary syntax)',
            ),
          ),
        );
      });
    });

    group('Full command resolution', () {
      test('BB-EPH-30: resolves multiple simple placeholders', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'my_project',
            version: '2.0.0',
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        final result = ExecutePlaceholderResolver.resolveCommand(
          r'echo ${folder.name} is version ${dart.version}',
          ctx,
        );
        expect(result, equals('echo my-project is version 2.0.0'));
      });

      test('BB-EPH-31: resolves mixed simple and ternary placeholders', () {
        folder.natures.add(
          DartProjectFolder(
            folder,
            projectName: 'test_pkg',
            version: '1.0.0',
            pubspec: {'name': 'test_pkg', 'version': '1.0.0'},
          ),
        );
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        final result = ExecutePlaceholderResolver.resolveCommand(
          r'Publishing ${dart.name}: ${dart.publishable?(dart pub publish):(skipping)}',
          ctx,
        );
        expect(result, equals('Publishing test_pkg: dart pub publish'));
      });

      test('BB-EPH-32: resolves command with path placeholders', () {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        final result = ExecutePlaceholderResolver.resolveCommand(
          r'cd ${folder} && ls ${root}',
          ctx,
        );
        expect(result, equals('cd /workspace/my-project && ls /workspace'));
      });
    });

    group('Condition checking', () {
      test(
        'BB-EPH-33: checkCondition returns true for satisfied condition',
        () {
          folder.natures.add(DartProjectFolder(folder, projectName: 'test'));
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.checkCondition('dart.exists', ctx),
            isTrue,
          );
        },
      );

      test(
        'BB-EPH-34: checkCondition returns false for unsatisfied condition',
        () {
          ctx = ExecutePlaceholderContext(
            rootPath: '/workspace',
            folder: folder,
          );
          expect(
            ExecutePlaceholderResolver.checkCondition('dart.exists', ctx),
            isFalse,
          );
        },
      );

      test('BB-EPH-35: checkCondition throws for non-boolean placeholder', () {
        ctx = ExecutePlaceholderContext(rootPath: '/workspace', folder: folder);
        expect(
          () => ExecutePlaceholderResolver.checkCondition('folder.name', ctx),
          throwsA(
            isA<UnresolvedPlaceholderException>().having(
              (e) => e.message,
              'message',
              'not a boolean placeholder (invalid condition)',
            ),
          ),
        );
      });
    });

    group('Placeholder help', () {
      test('BB-EPH-36: getPlaceholderHelp returns non-empty map', () {
        final help = ExecutePlaceholderResolver.getPlaceholderHelp();
        expect(help, isNotEmpty);
        expect(help.containsKey('root'), isTrue);
        expect(help.containsKey('dart.exists'), isTrue);
        expect(help.containsKey('git.branch'), isTrue);
      });
    });
  });

  group('UnresolvedPlaceholderException', () {
    test('BB-EPH-37: formats message correctly without details', () {
      final exception = UnresolvedPlaceholderException(
        'dart.name',
        '/path/to/folder',
      );
      expect(
        exception.toString(),
        equals(r'Unresolved placeholder ${dart.name} in /path/to/folder'),
      );
    });

    test('BB-EPH-38: formats message correctly with details', () {
      final exception = UnresolvedPlaceholderException(
        'dart.name',
        '/path/to/folder',
        message: 'not a Dart project',
      );
      expect(
        exception.toString(),
        equals(
          r'Unresolved placeholder ${dart.name} in /path/to/folder: not a Dart project',
        ),
      );
    });
  });
}
