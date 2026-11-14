/// Native v2 executor for the `:apidoc` command: `dart doc` in every Dart
/// package of the traversal, into a generated folder outside `doc/`, with the
/// warnings counted per package.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base.dart' show ProcessRunner;
import 'package:tom_build_base/tom_build_base_v2.dart';

import 'generated_output.dart';

/// The folder `:apidoc` writes into when `--output` is not given, relative
/// to the package: the workspace's place for generated API reference
/// (`_bin/check_doc_runner_output.py`), gitignored with `build/`; `doc/`
/// holds hand-authored documents only, so dartdoc's own default `doc/api` is
/// not used.
const kApidocDefaultOutput = 'build/api_doc';

/// What one `dart doc` run said, read from its output and the `index.json`
/// it wrote.
class DartdocResult {
  /// The process exit code.
  final int exitCode;

  /// dartdoc's own count, from `Found N warnings and M errors.`; null when
  /// that line is missing (dartdoc stopped before it).
  final int? warnings, errors;

  /// `warning:` / `error:` lines naming an unresolved doc reference.
  final int unresolvedReferences;

  /// Public libraries documented, from `Documented N public libraries`.
  final int? libraries;

  /// Public elements in `index.json`, and how many of them have no doc
  /// comment (an empty `desc`); null when no index was written.
  final int? elements, undocumented;

  /// The `warning:` and `error:` lines, as dartdoc printed them.
  final List<String> findings;

  const DartdocResult({
    required this.exitCode,
    this.warnings,
    this.errors,
    this.unresolvedReferences = 0,
    this.libraries,
    this.elements,
    this.undocumented,
    this.findings = const [],
  });

  /// Reads dartdoc's [output] (stdout and stderr) and, when it wrote one,
  /// its [indexJson].
  /// A finding's `from <element>: (<file uri>:<line>:<col>)` line is kept
  /// with it, the file relative to [packageDir] when given.
  factory DartdocResult.parse(
    int exitCode,
    String output, {
    String? indexJson,
    String? packageDir,
  }) {
    final found = RegExp(
      r'Found (\d+) warnings? and (\d+) errors?',
    ).allMatches(output).lastOrNull;
    final documented = RegExp(
      r'Documented (\d+) public librar',
    ).allMatches(output).lastOrNull;
    final lines = const LineSplitter().convert(output);
    final findings = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!RegExp(r'^\s*(warning|error): ').hasMatch(lines[i])) continue;
      var finding = lines[i].trim();
      final from = i + 1 < lines.length
          ? RegExp(r'^\s+from (.*)$').firstMatch(lines[i + 1])
          : null;
      if (from != null) {
        var where = from.group(1)!;
        if (packageDir != null) {
          where = where.replaceAll(Uri.directory(packageDir).toString(), '');
        }
        finding = '$finding ($where)';
      }
      findings.add(finding);
    }
    int? elements, undocumented;
    if (indexJson != null) {
      try {
        final entries = (jsonDecode(indexJson) as List)
            .whereType<Map<String, dynamic>>()
            .toList();
        elements = entries.length;
        undocumented = entries
            .where((e) => (e['desc'] as String? ?? '').trim().isEmpty)
            .length;
      } on FormatException {
        // An index dartdoc did not finish writing: no element counts.
      }
    }
    return DartdocResult(
      exitCode: exitCode,
      warnings: found == null ? null : int.parse(found.group(1)!),
      errors: found == null ? null : int.parse(found.group(2)!),
      unresolvedReferences: findings
          .where((f) => f.contains('unresolved doc reference'))
          .length,
      libraries: documented == null ? null : int.parse(documented.group(1)!),
      elements: elements,
      undocumented: undocumented,
      findings: findings,
    );
  }

  /// Why the run did not produce API documentation, or null when it did:
  /// a non-zero exit, dartdoc errors, or no public library at all.
  String? get failure {
    if (exitCode != 0) {
      return 'dart doc failed (exit $exitCode'
          '${errors != null && errors! > 0 ? ', $errors error(s)' : ''})';
    }
    if (errors != null && errors! > 0) return 'dart doc: $errors error(s)';
    if (libraries == 0) return 'no public library to document';
    return null;
  }

  /// `2 libraries, 1 warning (1 unresolved reference), 3 of 91 public
  /// elements undocumented`.
  String describe() {
    final parts = <String>[];
    if (libraries != null) {
      parts.add('$libraries librar${libraries == 1 ? 'y' : 'ies'}');
    }
    final w = warnings ?? findings.where((f) => f.startsWith('warning')).length;
    parts.add(
      '$w warning${w == 1 ? '' : 's'}'
      '${unresolvedReferences > 0 ? ' ($unresolvedReferences unresolved '
                'reference${unresolvedReferences == 1 ? '' : 's'})' : ''}',
    );
    if (errors != null && errors! > 0) parts.add('$errors error(s)');
    if (elements != null) {
      parts.add('$undocumented of $elements public elements undocumented');
    }
    return parts.join(', ');
  }
}

/// Runs `dart doc` in one Dart package.
class ApidocExecutor extends CommandExecutor {
  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final options = args.optionsFor('apidoc');
    final relative = p.relative(context.path, from: context.executionRoot);
    final rel = relative == '.' ? context.name : relative;
    final outputOption = options['output'] as String? ?? kApidocDefaultOutput;

    final refused = refuseGeneratedOutput(
      outputOption,
      defaultDir: kApidocDefaultOutput,
    );
    if (refused != null) {
      print('  $rel: $refused');
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: refused,
      );
    }
    // Why absolute: context.path is relative to the starting directory under
    // a relative --scan, and dart doc runs inside the package, so a relative
    // output would be resolved against the package a second time.
    final packageDir = p.normalize(p.absolute(context.path));
    final outputDir = p.join(packageDir, outputOption);
    final docArgs = ['doc', '--output', outputDir, '.'];

    if (!_hasPublicLibrary(packageDir)) {
      // A samples or tool folder: no API to document, so nothing failed.
      stdout.writeln('  $rel: skipped — no lib/ library to document');
      return ItemResult.skipped(
        path: context.path,
        name: context.name,
        message: 'no lib/ library to document',
      );
    }

    if (args.dryRun) {
      print('  [DRY RUN] $rel: dart ${docArgs.join(' ')}');
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'dry-run',
      );
    }

    // Why: without a resolution dartdoc still "succeeds", documenting the
    // package against imports it cannot see, so the pages lie quietly.
    if (!File(
      p.join(packageDir, '.dart_tool', 'package_config.json'),
    ).existsSync()) {
      const why =
          'not resolved (no .dart_tool/package_config.json): '
          'run buildkit :pubget first';
      print('  $rel: $why');
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: why,
      );
    }
    final preflight = pubCachePreflight(context);
    if (preflight != null) return preflight;

    // Generated: an older run's pages for a library that is gone would stay.
    final outDir = Directory(outputDir);
    if (outDir.existsSync()) outDir.deleteSync(recursive: true);

    final run = await ProcessRunner.run(
      'dart',
      docArgs,
      workingDirectory: packageDir,
      runInShell: Platform.isWindows,
    );
    final output = '${run.stdout}\n${run.stderr}';
    if (args.verbose) stdout.write(output);

    final index = File(p.join(outputDir, 'index.json'));
    final result = DartdocResult.parse(
      run.exitCode,
      output,
      indexJson: index.existsSync() ? index.readAsStringSync() : null,
      packageDir: packageDir,
    );

    if (!args.verbose) {
      // Straight to stdout: print() runs through the console-markdown zone,
      // which would read `[Ref]` and backticks as markup.
      for (final finding in result.findings) {
        stdout.writeln('  $rel: $finding');
      }
    }
    final where = p.relative(outputDir, from: packageDir);
    final failure = result.failure;
    stdout.writeln(
      '  $rel: ${failure ?? 'ok'} — ${result.describe()}'
      '${failure == null ? ' -> $where' : ''}',
    );
    if (failure == null &&
        await trackedByGit(packageDir, p.join(outputDir, 'index.html'))) {
      print(
        '  $rel: note: git would track $where; add it to .gitignore '
        '(API docs are generated)',
      );
    }

    return failure == null
        ? ItemResult.success(
            path: context.path,
            name: context.name,
            message: result.describe(),
          )
        : ItemResult.failure(
            path: context.path,
            name: context.name,
            error: failure,
          );
  }

  /// Whether [packageDir] has a library dartdoc documents: a `.dart` file
  /// in `lib/` outside `lib/src/`.
  bool _hasPublicLibrary(String packageDir) {
    final lib = Directory(p.join(packageDir, 'lib'));
    if (!lib.existsSync()) return false;
    final src = p.join(lib.path, 'src');
    return lib
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .any((f) => f.path.endsWith('.dart') && !p.isWithin(src, f.path));
  }
}
