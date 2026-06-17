import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart';

import 'pubget_command.dart';
import 'pubupdate_command.dart';

/// Parse a command string into parts, respecting quoted strings.
///
/// Handles both single and double quotes. Quoted strings preserve their
/// quote characters (needed for dcli expression detection).
@visibleForTesting
List<String> parseCommandArgs(String command) {
  final result = <String>[];
  final buffer = StringBuffer();
  String? quoteChar;
  var escaped = false;

  for (var i = 0; i < command.length; i++) {
    final char = command[i];

    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }

    if (char == r'\') {
      escaped = true;
      buffer.write(char);
      continue;
    }

    if (quoteChar != null) {
      // Inside a quoted string
      buffer.write(char);
      if (char == quoteChar) {
        quoteChar = null;
      }
    } else if (char == '"' || char == "'") {
      // Start of quoted string
      quoteChar = char;
      buffer.write(char);
    } else if (char == ' ' || char == '\t') {
      // Whitespace separator
      if (buffer.isNotEmpty) {
        result.add(buffer.toString());
        buffer.clear();
      }
    } else {
      buffer.write(char);
    }
  }

  if (buffer.isNotEmpty) {
    result.add(buffer.toString());
  }

  return result;
}

/// Registry of built-in commands that can be executed within pipelines.
///
/// Most commands run the respective tools directly using their Dart
/// implementation. The `dcli` command spawns an external process.
class BuiltinCommands {
  final String projectPath;
  final String rootPath;
  final bool verbose;
  final bool dryRun;

  BuiltinCommands({
    required this.projectPath,
    required this.rootPath,
    required this.verbose,
    required this.dryRun,
  });

  /// Check if a command is a built-in command (supports shorthands).
  bool isBuiltin(String command) {
    final parts = command.trim().split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    return resolveShorthand(cmd) != null;
  }

  static const _builtinNames = {
    'buildsorter',
    'versioner',
    'bumpversion',
    'bumppubspec',
    'compiler',
    'runner',
    'cleanup',
    'dependencies',
    'publisher',
    'gitstatus',
    'gitcommit',
    'gitpull',
    'gitbranch',
    'gittag',
    'gitclean',
    'gitcheckout',
    'gitreset',
    'gitsync',
    'pubget',
    'pubgetall',
    'pubupdate',
    'pubupdateall',
    'status',
    'dcli',
  };

  /// Resolve a command shorthand to full command name.
  ///
  /// Returns the full command name if [shorthand] uniquely matches a single
  /// built-in command via `startsWith()`. Returns null if no match or multiple
  /// matches (ambiguous).
  @visibleForTesting
  static String? resolveShorthand(String shorthand) {
    final lower = shorthand.toLowerCase();
    if (_builtinNames.contains(lower)) return lower;
    final matches = _builtinNames
        .where((cmd) => cmd.startsWith(lower))
        .toList();
    if (matches.length == 1) {
      return matches.first;
    }
    return null; // No match or ambiguous
  }

  /// Execute a built-in command.
  ///
  /// Returns true if successful, false otherwise.
  /// Automatically injects `--project <projectPath>` into tool args
  /// when no `--project` or `-p` is already specified in the args.
  /// Supports command shorthands (e.g., 'v' → 'versioner' if unique).
  Future<bool> execute(String command) async {
    final parts = parseCommandArgs(command.trim());
    if (parts.isEmpty) {
      print('  Empty command');
      return false;
    }
    final rawCmd = parts.first.toLowerCase();
    final cmd = resolveShorthand(rawCmd);
    if (cmd == null) {
      print('  Unknown or ambiguous command: $rawCmd');
      return false;
    }
    var args = parts.skip(1).toList();

    // Forward --project and --root to tool if not already in args (bug #18 fix).
    // Skip injection for dcli — it doesn't use --project; it uses
    // the working directory instead.
    if (cmd != 'dcli' &&
        projectPath.isNotEmpty &&
        !args.contains('--project') &&
        !args.contains('-p')) {
      args = ['--project', projectPath, ...args];
    }
    // Forward --root to tool for proper path validation (bug #38 fix).
    // Without this, tools compute executionRoot from current directory
    // instead of using the buildkit-determined workspace root.
    if (cmd != 'dcli' &&
        rootPath.isNotEmpty &&
        !args.contains('--root') &&
        !args.contains('-R')) {
      args = ['--root', rootPath, ...args];
    }

    switch (cmd) {
      case 'buildsorter':
        return _runBuildSorter(args);
      case 'versioner':
        return _runVersioner(args);
      case 'bumpversion':
        return _runBumpVersion(args);
      case 'bumppubspec':
        return _runBumpPubspec(args);
      case 'compiler':
        return _runCompiler(args);
      case 'runner':
        return _runRunner(args);
      case 'cleanup':
        return _runCleanup(args);
      case 'dependencies':
        return _runDependencies(args);
      case 'pubget':
        return _runPubGet(args);
      case 'pubgetall':
        return _runPubGetAll(args);
      case 'pubupdate':
        return _runPubUpdate(args);
      case 'pubupdateall':
        return _runPubUpdateAll(args);
      case 'publisher':
        return _runPublisher(args);
      case 'gitstatus':
        return _runGitStatus(args);
      case 'gitcommit':
        return _runGitCommit(args);
      case 'gitpull':
        return _runGitPull(args);
      case 'gitbranch':
        return _runGitBranch(args);
      case 'gittag':
        return _runGitTag(args);
      case 'gitclean':
        return _runGitClean(args);
      case 'gitcheckout':
        return _runGitCheckout(args);
      case 'gitreset':
        return _runGitReset(args);
      case 'gitsync':
        return _runGitSync(args);
      case 'status':
        return _runStatus(args);
      case 'dcli':
        return _runDcli(args);
      default:
        print('  Unknown built-in command: $cmd');
        return false;
    }
  }

  Future<bool> _runVersioner(List<String> args) =>
      _runViaBuildkit('versioner', args);

  Future<bool> _runBumpVersion(List<String> args) =>
      _runViaBuildkit('bumpversion', args);

  Future<bool> _runBumpPubspec(List<String> args) =>
      _runViaBuildkit('bumppubspec', args);

  Future<bool> _runCompiler(List<String> args) =>
      _runViaBuildkit('compiler', args);

  Future<bool> _runRunner(List<String> args) => _runViaBuildkit('runner', args);

  Future<bool> _runCleanup(List<String> args) =>
      _runViaBuildkit('cleanup', args);

  Future<bool> _runDependencies(List<String> args) =>
      _runViaBuildkit('dependencies', args);

  Future<bool> _runBuildSorter(List<String> args) =>
      _runViaBuildkit('buildsorter', args);

  Future<bool> _runPublisher(List<String> args) =>
      _runViaBuildkit('publisher', args);

  Future<bool> _runGitStatus(List<String> args) =>
      _runViaBuildkit('gitstatus', args);

  Future<bool> _runGitCommit(List<String> args) =>
      _runViaBuildkit('gitcommit', args);

  Future<bool> _runGitPull(List<String> args) =>
      _runViaBuildkit('gitpull', args);

  Future<bool> _runGitBranch(List<String> args) =>
      _runViaBuildkit('gitbranch', args);

  Future<bool> _runGitTag(List<String> args) => _runViaBuildkit('gittag', args);

  Future<bool> _runGitClean(List<String> args) =>
      _runViaBuildkit('gitclean', args);

  Future<bool> _runGitCheckout(List<String> args) =>
      _runViaBuildkit('gitcheckout', args);

  Future<bool> _runGitReset(List<String> args) =>
      _runViaBuildkit('gitreset', args);

  Future<bool> _runGitSync(List<String> args) =>
      _runViaBuildkit('gitsync', args);

  Future<bool> _runStatus(List<String> args) => _runViaBuildkit('status', args);

  /// Run a command by spawning `buildkit :command` as a subprocess.
  ///
  /// This replaces the old in-process v1 tool execution. All builtin tools
  /// now have v2 executors registered in the buildkit CLI, so they can be
  /// invoked as `buildkit :command [args...]`.
  Future<bool> _runViaBuildkit(String command, List<String> args) async {
    if (verbose) print('  [builtin] Running $command...');
    if (dryRun) {
      print(
        '  [DRY RUN] Would run buildkit :$command ${args.join(' ')}'
            .trimRight(),
      );
      return true;
    }

    try {
      final result = await ProcessRunner.run(
        'buildkit',
        [':$command', ...args],
        workingDirectory: projectPath,
        environment: {
          ...Platform.environment,
          'BUILDKIT_PROJECT': projectPath,
          'BUILDKIT_ROOT': rootPath,
        },
      );

      if (result.stdout.isNotEmpty) {
        stdout.write(result.stdout);
      }
      if (result.stderr.isNotEmpty) {
        stderr.write(result.stderr);
      }

      if (result.exitCode != 0) {
        print('  $command failed with exit code ${result.exitCode}');
        return false;
      }

      return true;
    } catch (e) {
      print('  Error executing $command: $e');
      print('  Make sure buildkit is installed and on your PATH.');
      return false;
    }
  }

  Future<bool> _runPubGet(List<String> args) async {
    if (verbose) print('  [builtin] Running pubget...');
    final cmdArgs = [...args];
    if (dryRun) cmdArgs.add('--dry-run');
    final pubGetCommand = PubGetCommand(rootPath: rootPath, verbose: verbose);
    return pubGetCommand.execute(cmdArgs);
  }

  Future<bool> _runPubGetAll(List<String> args) async {
    final wsRoot = rootPath.isNotEmpty
        ? rootPath
        : findWorkspaceRoot(Directory.current.path);
    if (verbose) {
      print(
        '  [builtin] Running pubgetall (-R $wsRoot --scan $wsRoot --recursive)...',
      );
    }
    final pubGetCommand = PubGetCommand(rootPath: wsRoot, verbose: verbose);
    final fullArgs = ['--scan', wsRoot, '--recursive', ...args];
    if (dryRun) fullArgs.add('--dry-run');
    return pubGetCommand.execute(fullArgs);
  }

  Future<bool> _runPubUpdate(List<String> args) async {
    if (verbose) print('  [builtin] Running pubupdate...');
    final cmdArgs = [...args];
    if (dryRun) cmdArgs.add('--dry-run');
    final pubUpdateCommand = PubUpdateCommand(
      rootPath: rootPath,
      verbose: verbose,
    );
    return pubUpdateCommand.execute(cmdArgs);
  }

  Future<bool> _runPubUpdateAll(List<String> args) async {
    final wsRoot = rootPath.isNotEmpty
        ? rootPath
        : findWorkspaceRoot(Directory.current.path);
    if (verbose) {
      print(
        '  [builtin] Running pubupdateall (-R $wsRoot --scan $wsRoot --recursive)...',
      );
    }
    final pubUpdateCommand = PubUpdateCommand(
      rootPath: wsRoot,
      verbose: verbose,
    );
    final fullArgs = ['--scan', wsRoot, '--recursive', ...args];
    if (dryRun) fullArgs.add('--dry-run');
    return pubUpdateCommand.execute(fullArgs);
  }

  // ---------------------------------------------------------------------------
  // dcli command — external process with path resolution
  // ---------------------------------------------------------------------------

  /// Execute `dcli` with path resolution and conditional file existence.
  ///
  /// Syntax: `dcli <file|expression> [-init-source <file>] [-no-init-source]`
  ///
  /// Path notations:
  /// - `~w/path` — workspace root
  /// - `~s/path` — workspace `_scripts/` folder
  /// - `::name`  — workspace `_scripts/bin/` folder
  ///
  /// If the argument has no extension, `.dart` is appended.
  /// If wrapped in double quotes, it's treated as an expression (always runs).
  /// For file targets, the command is only executed if the file exists (silent
  /// skip otherwise). This allows optional per-project build scripts.
  Future<bool> _runDcli(List<String> args) async {
    if (args.isEmpty) {
      print('  Error: dcli requires a file, script, or expression argument.');
      return false;
    }

    // Separate the target (file/expression) from dcli options.
    // The target is the first argument that is NOT an option.
    String? target;
    final dcliArgs = <String>[];
    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if (arg == '-init-source') {
        // Consumes the next argument as the init-source file.
        dcliArgs.add(arg);
        i++;
        if (i < args.length) {
          dcliArgs.add(_resolveDcliPath(args[i]));
        } else {
          print('  Error: -init-source requires a file argument.');
          return false;
        }
      } else if (arg == '-no-init-source') {
        dcliArgs.add(arg);
      } else if (arg.startsWith('-')) {
        // Unknown option — reject.
        print('  Error: Unknown dcli option "$arg".');
        print(
          '  Only -init-source <file> and -no-init-source are allowed '
          'in buildkit context.',
        );
        return false;
      } else if (target == null) {
        target = arg;
      } else {
        print('  Error: Unexpected extra argument "$arg" for dcli command.');
        return false;
      }
      i++;
    }

    if (target == null) {
      print('  Error: dcli requires a file, script, or expression argument.');
      return false;
    }

    // Detect expression mode: wrapped in double quotes.
    final isExpression =
        target.startsWith('"') && target.endsWith('"') && target.length > 1;

    if (isExpression) {
      // Expression mode — always execute.
      // Strip the outer quotes since Process.run doesn't do shell parsing.
      final expression = target.substring(1, target.length - 1);
      if (verbose) print('  [builtin] Running dcli expression...');
      if (dryRun) {
        print(
          '  [DRY RUN] Would run dcli "$expression" ${dcliArgs.join(' ')}'
              .trimRight(),
        );
        return true;
      }
      return _executeDcliProcess([expression, ...dcliArgs]);
    }

    // File mode — resolve path and check existence.
    final resolvedPath = _resolveDcliPath(target);

    // Determine absolute path for existence check.
    final absolutePath = p.isAbsolute(resolvedPath)
        ? resolvedPath
        : p.join(projectPath, resolvedPath);

    if (!File(absolutePath).existsSync()) {
      // Silent skip — file doesn't exist (optional script pattern).
      if (verbose) {
        print('  [builtin] Skipping dcli — file not found: $resolvedPath');
      }
      return true;
    }

    if (verbose) print('  [builtin] Running dcli $resolvedPath...');
    if (dryRun) {
      print(
        '  [DRY RUN] Would run dcli $resolvedPath ${dcliArgs.join(' ')}'
            .trimRight(),
      );
      return true;
    }

    return _executeDcliProcess([resolvedPath, ...dcliArgs]);
  }

  /// Resolve dcli path notations.
  ///
  /// - `~w/path` → `<rootPath>/path`
  /// - `~s/path` → `<rootPath>/_scripts/path`
  /// - `::name`  → `<rootPath>/_scripts/bin/name`
  /// - No extension → append `.dart`
  String _resolveDcliPath(String input) {
    var resolved = input;

    if (resolved.startsWith('~w/')) {
      resolved = p.join(rootPath, resolved.substring(3));
    } else if (resolved.startsWith('~s/')) {
      resolved = p.join(rootPath, '_scripts', resolved.substring(3));
    } else if (resolved.startsWith('::')) {
      resolved = p.join(rootPath, '_scripts', 'bin', resolved.substring(2));
    }

    // Auto-add .dart extension if none present.
    if (p.extension(resolved).isEmpty) {
      resolved = '$resolved.dart';
    }

    return resolved;
  }

  /// Spawn the `dcli` process with the given arguments.
  Future<bool> _executeDcliProcess(List<String> args) async {
    final dcliArgs = args.join(' ');
    if (verbose) print('  Executing: dcli $dcliArgs');

    try {
      final result = await ProcessRunner.run(
        'dcli',
        args,
        workingDirectory: projectPath,
        environment: {
          ...Platform.environment,
          'BUILDKIT_PROJECT': projectPath,
          'BUILDKIT_ROOT': rootPath,
        },
      );

      if (result.stdout.isNotEmpty) {
        stdout.write(result.stdout);
      }
      if (result.stderr.isNotEmpty) {
        stderr.write(result.stderr);
      }

      if (result.exitCode != 0) {
        print('  dcli command failed with exit code ${result.exitCode}');
        return false;
      }

      return true;
    } catch (e) {
      print('  Error executing dcli: $e');
      print('  Make sure dcli is installed and on your PATH.');
      return false;
    }
  }
}
