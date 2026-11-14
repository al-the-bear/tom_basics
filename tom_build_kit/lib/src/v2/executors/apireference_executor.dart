/// Native v2 executor for the `:apireference` command: a package's combined
/// API reference ([assembleApiReference]) rendered to PDF by tom_md2pdf.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../apireference/api_reference.dart';
import 'generated_output.dart';

/// The folder `:apireference` writes into when `--output` is not given,
/// relative to the package: generated, so under the gitignored `build/`,
/// never in `doc/`.
const kApiReferenceDefaultOutput = 'build/api_reference';

/// The tom_md2pdf executable run when `--md2pdf` is not given: the `md2pdf`
/// of the binaries layer, found on `PATH`.
const kMd2pdfDefault = 'md2pdf';

/// Seconds md2pdf may take per package when `--timeout` is not given; it can
/// hang on a document it cannot lay out, and a run must still end.
const kMd2pdfTimeoutDefault = 600;

/// Collects one package's summaries and guides, assembles them and renders
/// the PDF.
///
/// A package without `doc/api/` documents no API: skipped and named. One with
/// missing inputs (no index, no module summary, a summary the index links to
/// that is not there) fails, naming each. Modules without a guide are listed;
/// Part III leaves them out.
class ApireferenceExecutor extends CommandExecutor {
  /// The clock the reference is dated by; the real one unless a test fixes it.
  final DateTime Function() now;

  ApireferenceExecutor({DateTime Function()? now}) : now = now ?? DateTime.now;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final options = args.optionsFor('apireference');
    final relative = p.relative(context.path, from: context.executionRoot);
    final rel = relative == '.' ? context.name : relative;
    final packageDir = p.normalize(p.absolute(context.path));
    final output = options['output'] as String? ?? kApiReferenceDefaultOutput;
    final md2pdf = options['md2pdf'] as String? ?? kMd2pdfDefault;
    final timeoutOption = options['timeout'] as String?;
    final timeout = timeoutOption == null
        ? kMd2pdfTimeoutDefault
        : int.tryParse(timeoutOption);

    ItemResult fail(String why) {
      stdout.writeln('  $rel: $why');
      return ItemResult.failure(
        path: context.path,
        name: context.name,
        error: why,
      );
    }

    if (timeout == null || timeout < 1) {
      return fail('--timeout $timeoutOption: give a number of seconds');
    }
    final refused = refuseGeneratedOutput(
      output,
      defaultDir: kApiReferenceDefaultOutput,
    );
    if (refused != null) return fail(refused);

    final inputs = collectApiReferenceInputs(packageDir);
    if (inputs == null) {
      const why = 'no doc/api/: the package documents no API';
      stdout.writeln('  $rel: NOT DOCUMENTED — $why');
      return ItemResult.skipped(
        path: context.path,
        name: context.name,
        message: why,
      );
    }
    // Straight to stdout: print() runs through the console-markdown zone.
    for (final m in inputs.missing) {
      stdout.writeln('  $rel: missing input: $m');
    }
    if (inputs.withoutGuide.isNotEmpty) {
      stdout.writeln(
        '  $rel: no guide for ${inputs.withoutGuide.join(', ')} '
        '(doc/<module>.md or doc/<module>/<module>.md); left out of Part III',
      );
    }
    if (!inputs.complete) {
      return fail('${inputs.missing.length} missing input(s)');
    }

    final name = _packageName(packageDir);
    final outDir = p.join(packageDir, output);
    final markdown = p.join(outDir, '${name}_api_reference.md');
    final pdf = p.join(outDir, '${name}_api_reference.pdf');
    final title = '${titleCase(name)} API Reference';
    final md2pdfArgs = [
      markdown,
      '--output=$outDir',
      '--title=$title',
      '--page-numbers',
    ];
    final parts =
        'index, ${inputs.summaries.length} summar'
        '${inputs.summaries.length == 1 ? 'y' : 'ies'}, '
        '${inputs.guides.length} guide${inputs.guides.length == 1 ? '' : 's'}';

    if (args.dryRun) {
      stdout.writeln(
        '  [DRY RUN] $rel: $parts -> ${p.relative(markdown, from: packageDir)}; '
        '$md2pdf ${md2pdfArgs.join(' ')}',
      );
      return ItemResult.success(
        path: context.path,
        name: context.name,
        message: 'dry-run',
      );
    }

    Directory(outDir).createSync(recursive: true);
    File(
      markdown,
    ).writeAsStringSync(assembleApiReference(inputs, name, now: now()));
    final previous = File(pdf);
    if (previous.existsSync()) previous.deleteSync();

    final Process process;
    try {
      process = await Process.start(
        md2pdf,
        md2pdfArgs,
        workingDirectory: packageDir,
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (e) {
      return fail(
        '$md2pdf could not be run (${e.message}): build tom_md2pdf '
        '(tom_ai/devops/tom_md2pdf) into the binaries layer, or pass '
        '--md2pdf <executable>',
      );
    }
    final transcript = StringBuffer();
    final collected = [
      process.stdout
          .transform(systemEncoding.decoder)
          .forEach(transcript.write),
      process.stderr
          .transform(systemEncoding.decoder)
          .forEach(transcript.write),
    ];
    int? exitCode;
    try {
      exitCode = await process.exitCode.timeout(Duration(seconds: timeout));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
    await Future.wait(collected);
    if (args.verbose || exitCode != 0) stdout.write(transcript);
    if (exitCode == null) {
      if (File(pdf).existsSync()) File(pdf).deleteSync();
      return fail(
        '$md2pdf did not finish within $timeout s and was stopped '
        '(--timeout raises the limit)',
      );
    }
    if (exitCode != 0 || !File(pdf).existsSync()) {
      return fail(
        '$md2pdf failed (exit $exitCode)'
        '${File(pdf).existsSync() ? '' : ', no PDF written'}',
      );
    }

    final where = p.relative(pdf, from: packageDir);
    final kb = (File(pdf).lengthSync() / 1024).ceil();
    stdout.writeln('  $rel: ok — $parts -> $where ($kb KB)');
    if (await trackedByGit(packageDir, pdf)) {
      print(
        '  $rel: note: git would track $where; add '
        '${p.relative(outDir, from: packageDir)} to .gitignore '
        '(the reference is generated)',
      );
    }
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: '$parts -> $where',
    );
  }

  /// The `name:` of the package's pubspec, else its folder name.
  String _packageName(String packageDir) {
    final pubspec = File(p.join(packageDir, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final m = RegExp(
        r'^name:\s*([A-Za-z0-9_]+)',
        multiLine: true,
      ).firstMatch(pubspec.readAsStringSync());
      if (m != null) return m.group(1)!;
    }
    return p.basename(packageDir);
  }
}
