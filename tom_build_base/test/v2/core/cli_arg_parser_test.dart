import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

void main() {
  late CliArgParser parser;

  setUp(() {
    parser = CliArgParser();
  });

  group('CliArgs', () {
    group('constructor', () {
      test('BB-CLI-1: Creates args with defaults [2026-02-12]', () {
        const args = CliArgs();

        expect(args.scan, isNull);
        expect(args.recursive, isFalse);
        expect(args.notRecursive, isFalse);
        expect(args.root, isNull);
        expect(args.bareRoot, isFalse);
        expect(args.excludePatterns, isEmpty);
        expect(args.excludeProjects, isEmpty);
        expect(args.recursionExclude, isEmpty);
        expect(args.projectPatterns, isEmpty);
        expect(args.modules, isEmpty);
        expect(args.skipModules, isEmpty);
        expect(args.innerFirstGit, isFalse);
        expect(args.outerFirstGit, isFalse);
        expect(args.topRepo, isFalse);
        expect(args.buildOrder, isTrue);
        expect(args.workspaceRecursion, isFalse);
        expect(args.verbose, isFalse);
        expect(args.dryRun, isFalse);
        expect(args.listOnly, isFalse);
        expect(args.force, isFalse);
        expect(args.guide, isFalse);
        expect(args.dumpConfig, isFalse);
        expect(args.configPath, isNull);
        expect(args.help, isFalse);
        expect(args.version, isFalse);
        expect(args.includeTestProjects, isFalse);
        expect(args.testProjectsOnly, isFalse);
        expect(args.positionalArgs, isEmpty);
        expect(args.commands, isEmpty);
        expect(args.commandArgs, isEmpty);
        expect(args.extraOptions, isEmpty);
      });
    });

    group('effectiveRecursive', () {
      test(
        'BB-CLI-2: effectiveRecursive true when recursive set [2026-02-12]',
        () {
          const args = CliArgs(recursive: true, notRecursive: false);
          expect(args.effectiveRecursive, isTrue);
        },
      );

      test(
        'BB-CLI-3: effectiveRecursive false when both flags set [2026-02-12]',
        () {
          const args = CliArgs(recursive: true, notRecursive: true);
          expect(args.effectiveRecursive, isFalse);
        },
      );

      test(
        'BB-CLI-4: effectiveRecursive false when not recursive [2026-02-12]',
        () {
          const args = CliArgs(recursive: false, notRecursive: false);
          expect(args.effectiveRecursive, isFalse);
        },
      );
    });

    group('isHelpOrVersion', () {
      test('BB-CLI-5: isHelpOrVersion true when help set [2026-02-12]', () {
        const args = CliArgs(help: true);
        expect(args.isHelpOrVersion, isTrue);
      });

      test('BB-CLI-6: isHelpOrVersion true when version set [2026-02-12]', () {
        const args = CliArgs(version: true);
        expect(args.isHelpOrVersion, isTrue);
      });

      test('BB-CLI-7: isHelpOrVersion false when neither set [2026-02-12]', () {
        const args = CliArgs();
        expect(args.isHelpOrVersion, isFalse);
      });
    });

    group('toProjectTraversalInfo', () {
      test(
        'BB-CLI-8: Converts basic args to ProjectTraversalInfo [2026-02-12]',
        () {
          const args = CliArgs(
            scan: './src',
            recursive: true,
            recursiveExplicitlySet: true, // CLI explicitly set -r
            projectPatterns: ['tom_*'],
            excludeProjects: ['tom_test_*'],
          );

          final info = args.toProjectTraversalInfo(executionRoot: '/workspace');

          expect(info.scan, equals('./src'));
          expect(info.recursive, isTrue);
          expect(info.executionRoot, equals('/workspace'));
          expect(info.projectPatterns, equals(['tom_*']));
          expect(info.excludeProjects, equals(['tom_test_*']));
        },
      );

      test('BB-CLI-9: Uses root from args if provided [2026-02-12]', () {
        const args = CliArgs(root: '/custom/root');

        final info = args.toProjectTraversalInfo(executionRoot: '/default');
        expect(info.executionRoot, equals('/custom/root'));
      });

      test('BB-CLI-10: Respects notRecursive override [2026-02-12]', () {
        const args = CliArgs(recursive: true, notRecursive: true);

        final info = args.toProjectTraversalInfo(executionRoot: '/workspace');
        expect(info.recursive, isFalse);
      });

      test('BB-CLI-11: Defaults scan to current directory [2026-02-12]', () {
        const args = CliArgs();

        final info = args.toProjectTraversalInfo(executionRoot: '/workspace');
        expect(info.scan, equals('.'));
      });

      test('BB-CLI-11b: Defaults to not recursive [2026-02-18]', () {
        const args = CliArgs();

        final info = args.toProjectTraversalInfo(executionRoot: '/workspace');
        expect(
          info.recursive,
          isFalse,
          reason: 'Default is --scan . -R --not-recursive',
        );
      });
    });

    group('toGitTraversalInfo', () {
      test(
        'BB-CLI-12: Converts basic args to GitTraversalInfo [2026-02-12]',
        () {
          const args = CliArgs(
            modules: ['basics', 'd4rt'],
            skipModules: ['crypto'],
            innerFirstGit: true,
          );

          final info = args.toGitTraversalInfo(executionRoot: '/workspace');

          expect(info, isNotNull);
          expect(info!.modules, equals(['basics', 'd4rt']));
          expect(info.skipModules, equals(['crypto']));
          expect(info.gitMode, equals(GitTraversalMode.innerFirst));
        },
      );

      test(
        'BB-CLI-13: Returns null when git mode not specified [2026-02-12]',
        () {
          const args = CliArgs();

          final info = args.toGitTraversalInfo(executionRoot: '/workspace');
          expect(info, isNull, reason: 'Git mode must be explicitly specified');
        },
      );

      test(
        'BB-CLI-13b: Uses command default git mode when provided [2026-02-12]',
        () {
          const args = CliArgs();

          final info = args.toGitTraversalInfo(
            executionRoot: '/workspace',
            commandDefaultGitOrder: GitTraversalOrder.innerFirst,
          );
          expect(info, isNotNull);
          expect(info!.gitMode, equals(GitTraversalMode.innerFirst));
        },
      );

      test('BB-CLI-14: Uses outerFirst when specified [2026-02-12]', () {
        const args = CliArgs(outerFirstGit: true);

        final info = args.toGitTraversalInfo(executionRoot: '/workspace');
        expect(info, isNotNull);
        expect(info!.gitMode, equals(GitTraversalMode.outerFirst));
      });
    });
  });

  group('PerCommandArgs', () {
    test('BB-CLI-15: Creates PerCommandArgs with defaults [2026-02-12]', () {
      const args = PerCommandArgs(commandName: 'test');

      expect(args.commandName, equals('test'));
      expect(args.projectPatterns, isEmpty);
      expect(args.excludePatterns, isEmpty);
      expect(args.options, isEmpty);
    });

    test('BB-CLI-16: Creates PerCommandArgs with all fields [2026-02-12]', () {
      const args = PerCommandArgs(
        commandName: 'compile',
        projectPatterns: ['tom_*'],
        excludePatterns: ['tom_test_*'],
        options: {'force': true, 'verbose': true},
      );

      expect(args.commandName, equals('compile'));
      expect(args.projectPatterns, equals(['tom_*']));
      expect(args.excludePatterns, equals(['tom_test_*']));
      expect(args.options['force'], isTrue);
    });
  });

  group('CliArgParser', () {
    group('long options', () {
      test('BB-CLI-17: Parses --help [2026-02-12]', () {
        final args = parser.parse(['--help']);
        expect(args.help, isTrue);
      });

      test('BB-CLI-18: Parses --version [2026-02-12]', () {
        final args = parser.parse(['--version']);
        expect(args.version, isTrue);
      });

      test('BB-CLI-19: Parses --verbose [2026-02-12]', () {
        final args = parser.parse(['--verbose']);
        expect(args.verbose, isTrue);
      });

      test('BB-CLI-20: Parses --dry-run [2026-02-12]', () {
        final args = parser.parse(['--dry-run']);
        expect(args.dryRun, isTrue);
      });

      test('BB-CLI-21: Parses --recursive [2026-02-12]', () {
        final args = parser.parse(['--recursive']);
        expect(args.recursive, isTrue);
      });

      test('BB-CLI-22: Parses --not-recursive [2026-02-12]', () {
        final args = parser.parse(['--not-recursive']);
        expect(args.notRecursive, isTrue);
      });

      test('BB-CLI-23: Parses --scan with = value [2026-02-12]', () {
        final args = parser.parse(['--scan=./src']);
        expect(args.scan, equals('./src'));
      });

      test('BB-CLI-24: Parses --scan with space value [2026-02-12]', () {
        final args = parser.parse(['--scan', './src']);
        expect(args.scan, equals('./src'));
      });

      test('BB-CLI-25: Parses --exclude with multiple values [2026-02-12]', () {
        final args = parser.parse(['--exclude=*.dart', '--exclude=*.yaml']);
        expect(args.excludePatterns, equals(['*.dart', '*.yaml']));
      });

      test(
        'BB-CLI-26: Parses --exclude with comma-separated values [2026-02-12]',
        () {
          final args = parser.parse(['--exclude=*.dart,*.yaml']);
          expect(args.excludePatterns, equals(['*.dart', '*.yaml']));
        },
      );

      test('BB-CLI-27: Parses --project patterns [2026-02-12]', () {
        final args = parser.parse(['--project=tom_*', '--project=d4rt_*']);
        expect(args.projectPatterns, equals(['tom_*', 'd4rt_*']));
      });

      test('BB-CLI-28: Parses --modules [2026-02-12]', () {
        final args = parser.parse(['--modules=basics,d4rt']);
        expect(args.modules, equals(['basics', 'd4rt']));
      });

      test('BB-CLI-29: Parses --skip-modules [2026-02-12]', () {
        final args = parser.parse(['--skip-modules=crypto']);
        expect(args.skipModules, equals(['crypto']));
      });

      test('BB-CLI-30: Parses --inner-first-git [2026-02-12]', () {
        final args = parser.parse(['--inner-first-git']);
        expect(args.innerFirstGit, isTrue);
      });

      test('BB-CLI-31: Parses --outer-first-git [2026-02-12]', () {
        final args = parser.parse(['--outer-first-git']);
        expect(args.outerFirstGit, isTrue);
      });

      test('BB-CLI-31b: Parses --top-repo [2026-02-14]', () {
        final args = parser.parse(['--top-repo']);
        expect(args.topRepo, isTrue);
      });

      test('BB-CLI-32: Parses --build-order [2026-02-12]', () {
        final args = parser.parse(['--build-order']);
        expect(args.buildOrder, isTrue);
      });
    });

    group('short options', () {
      test('BB-CLI-33: Parses -h [2026-02-12]', () {
        final args = parser.parse(['-h']);
        expect(args.help, isTrue);
      });

      test('BB-CLI-34: Parses -V [2026-02-12]', () {
        final args = parser.parse(['-V']);
        expect(args.version, isTrue);
      });

      test('BB-CLI-35: Parses -v [2026-02-12]', () {
        final args = parser.parse(['-v']);
        expect(args.verbose, isTrue);
      });

      test('BB-CLI-36: Parses -r [2026-02-12]', () {
        final args = parser.parse(['-r']);
        expect(args.recursive, isTrue);
      });

      test('BB-CLI-37: Parses -s with value [2026-02-12]', () {
        final args = parser.parse(['-s', './src']);
        expect(args.scan, equals('./src'));
      });

      test('BB-CLI-38: Parses -s with attached value [2026-02-12]', () {
        final args = parser.parse(['-s./src']);
        expect(args.scan, equals('./src'));
      });

      test('BB-CLI-39: Parses -x [2026-02-12]', () {
        final args = parser.parse(['-x', '*.dart']);
        expect(args.excludePatterns, equals(['*.dart']));
      });

      test('BB-CLI-40: Parses -p [2026-02-12]', () {
        final args = parser.parse(['-p', 'tom_*']);
        expect(args.projectPatterns, equals(['tom_*']));
      });

      test('BB-CLI-41: Parses -m [2026-02-12]', () {
        final args = parser.parse(['-m', 'basics']);
        expect(args.modules, equals(['basics']));
      });

      test('BB-CLI-42: Parses -i [2026-02-12]', () {
        final args = parser.parse(['-i']);
        expect(args.innerFirstGit, isTrue);
      });

      test('BB-CLI-43: Parses -o [2026-02-12]', () {
        final args = parser.parse(['-o']);
        expect(args.outerFirstGit, isTrue);
      });

      test('BB-CLI-43b: Parses -T [2026-02-14]', () {
        final args = parser.parse(['-T']);
        expect(args.topRepo, isTrue);
      });

      test('BB-CLI-44: Parses -b [2026-02-12]', () {
        final args = parser.parse(['-b']);
        expect(args.buildOrder, isTrue);
      });

      test('BB-CLI-45: Parses -n [2026-02-12]', () {
        final args = parser.parse(['-n']);
        expect(args.dryRun, isTrue);
      });

      test('BB-CLI-46: Parses -l [2026-02-12]', () {
        final args = parser.parse(['-l']);
        expect(args.listOnly, isTrue);
      });

      test('BB-CLI-47: Parses -f [2026-02-12]', () {
        final args = parser.parse(['-f']);
        expect(args.force, isTrue);
      });
    });

    group('bundled short options', () {
      test('BB-CLI-48: Parses -rv bundled [2026-02-12]', () {
        final args = parser.parse(['-rv']);
        expect(args.recursive, isTrue);
        expect(args.verbose, isTrue);
      });

      test('BB-CLI-49: Parses -rvb bundled [2026-02-12]', () {
        final args = parser.parse(['-rvb']);
        expect(args.recursive, isTrue);
        expect(args.verbose, isTrue);
        expect(args.buildOrder, isTrue);
      });
    });

    group('commands', () {
      test('BB-CLI-50: Parses single command [2026-02-12]', () {
        final args = parser.parse([':cleanup']);
        expect(args.commands, equals(['cleanup']));
      });

      test('BB-CLI-51: Parses multiple commands [2026-02-12]', () {
        final args = parser.parse([':cleanup', ':compile']);
        expect(args.commands, equals(['cleanup', 'compile']));
      });

      test('BB-CLI-52: Parses command with options [2026-02-12]', () {
        final args = parser.parse(['-r', ':cleanup', ':compile']);
        expect(args.recursive, isTrue);
        expect(args.commands, equals(['cleanup', 'compile']));
      });
    });

    group('per-command options', () {
      test('BB-CLI-53: Parses per-command --project [2026-02-12]', () {
        final args = parser.parse([':cleanup', '--project=tom_*']);

        expect(args.commands, equals(['cleanup']));
        expect(args.commandArgs['cleanup'], isNotNull);
        expect(args.commandArgs['cleanup']!.projectPatterns, equals(['tom_*']));
      });

      test('BB-CLI-54: Parses per-command --exclude [2026-02-12]', () {
        final args = parser.parse([':compile', '--exclude=*.bak']);

        expect(args.commandArgs['compile']!.excludePatterns, equals(['*.bak']));
      });

      test('BB-CLI-55: Parses per-command custom options [2026-02-12]', () {
        final args = parser.parse([':test', '--failed', '--coverage']);

        expect(args.commandArgs['test']!.options['failed'], isTrue);
        expect(args.commandArgs['test']!.options['coverage'], isTrue);
      });

      test(
        'BB-CLI-56: Parses multiple commands with per-command options [2026-02-12]',
        () {
          final args = parser.parse([
            ':cleanup',
            '--project=tom_*',
            ':compile',
            '--project=d4rt_*',
          ]);

          expect(args.commands, equals(['cleanup', 'compile']));
          expect(
            args.commandArgs['cleanup']!.projectPatterns,
            equals(['tom_*']),
          );
          expect(
            args.commandArgs['compile']!.projectPatterns,
            equals(['d4rt_*']),
          );
        },
      );
    });

    group('positional arguments', () {
      test('BB-CLI-57: Captures positional args at start [2026-02-12]', () {
        final args = parser.parse(['script.dart']);
        expect(args.positionalArgs, equals(['script.dart']));
      });

      test(
        'BB-CLI-58: Captures positional args before options [2026-02-12]',
        () {
          final args = parser.parse(['file1.dart', 'file2.dart', '-v']);
          expect(args.positionalArgs, equals(['file1.dart', 'file2.dart']));
          expect(args.verbose, isTrue);
        },
      );

      test(
        'BB-CLI-59: Captures positional args before commands [2026-02-12]',
        () {
          final args = parser.parse(['config.yaml', ':build']);
          expect(args.positionalArgs, equals(['config.yaml']));
          expect(args.commands, equals(['build']));
        },
      );
    });

    group('extra options', () {
      test('BB-CLI-60: Captures unknown options [2026-02-12]', () {
        final args = parser.parse(['--custom-flag']);
        expect(args.extraOptions['custom-flag'], isTrue);
      });

      test('BB-CLI-61: Captures unknown options with values [2026-02-12]', () {
        final args = parser.parse(['--custom-option=value']);
        expect(args.extraOptions['custom-option'], equals('value'));
      });
    });

    group('complex command lines', () {
      test('BB-CLI-62: Parses buildkit-style command [2026-02-12]', () {
        final args = parser.parse([
          '-s',
          '.',
          '-r',
          '-p',
          'tom_*',
          ':cleanup',
          ':compile',
        ]);

        expect(args.scan, equals('.'));
        expect(args.recursive, isTrue);
        expect(args.projectPatterns, equals(['tom_*']));
        expect(args.commands, equals(['cleanup', 'compile']));
      });

      test('BB-CLI-63: Parses testkit-style command [2026-02-12]', () {
        final args = parser.parse([
          '-v',
          ':test',
          '--failed',
          '--test-args=--name parser',
        ]);

        expect(args.verbose, isTrue);
        expect(args.commands, equals(['test']));
        expect(args.commandArgs['test']!.options['failed'], isTrue);
        expect(
          args.commandArgs['test']!.options['test-args'],
          equals('--name parser'),
        );
      });

      test('BB-CLI-64: Parses git command line [2026-02-12]', () {
        final args = parser.parse([
          '-s',
          '.',
          '-r',
          '--inner-first-git',
          ':gitstatus',
          ':commit',
        ]);

        expect(args.scan, equals('.'));
        expect(args.recursive, isTrue);
        expect(args.innerFirstGit, isTrue);
        expect(args.commands, equals(['gitstatus', 'commit']));
      });
    });
  });
}
