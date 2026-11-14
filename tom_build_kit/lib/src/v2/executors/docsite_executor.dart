/// Native v2 executor for the `:docsite` command: the selected packages'
/// dartdoc output assembled into one browsable site ([buildDocSite]).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../docsite/doc_site.dart';
import 'apidoc_executor.dart' show kApidocDefaultOutput;
import 'generated_output.dart';

/// The folder the site goes to when `--output` is not given, relative to
/// the workspace root: a build output, gitignored with `build/`.
const kDocSiteDefaultOutput = 'build/doc_site';

/// Reads each package's pubspec, README and dartdoc output during the
/// traversal and builds the site once it is over, so the site holds exactly
/// the packages of this run.
class DocsiteExecutor extends CommandExecutor {
  /// The clock the index is dated by; the real one unless a test fixes it.
  final DateTime Function() now;

  DocsiteExecutor({DateTime Function()? now}) : now = now ?? DateTime.now;

  final _packages = <DocSitePackage>[];
  String? _root;

  @override
  Future<ItemResult> execute(CommandContext context, CliArgs args) async {
    final options = args.optionsFor('docsite');
    final apiDoc = options['api-doc'] as String? ?? kApidocDefaultOutput;
    _root ??= p.normalize(p.absolute(context.executionRoot));
    final packageDir = p.normalize(p.absolute(context.path));
    final rel = p.relative(packageDir, from: _root);
    final package = DocSitePackage.read(
      packageDir,
      path: rel == '.' ? context.name : rel,
      apiDoc: apiDoc,
    );
    _packages.add(package);
    // Straight to stdout: print() runs through the console-markdown zone.
    stdout.writeln(
      package.hasApiDocs
          ? '  ${package.path}: API docs ${p.relative(package.apiDocDir!, from: packageDir)}'
          : '  ${package.path}: no API docs ($apiDoc) — run buildkit :apidoc first',
    );
    return ItemResult.success(
      path: context.path,
      name: context.name,
      message: package.hasApiDocs ? 'API docs' : 'no API docs',
    );
  }

  @override
  Future<ItemResult?> afterTraversal(
    List<ItemResult> results,
    CliArgs args,
  ) async {
    final packages = List.of(_packages);
    final root = _root;
    _packages.clear();
    _root = null;
    if (root == null) return null;

    final output =
        args.optionsFor('docsite')['output'] as String? ??
        kDocSiteDefaultOutput;
    final refused = refuseGeneratedOutput(
      output,
      defaultDir: kDocSiteDefaultOutput,
      base: 'workspace root',
    );
    if (refused != null) {
      stdout.writeln('  docsite: $refused');
      return ItemResult.failure(path: root, name: 'docsite', error: refused);
    }
    final siteDir = p.join(root, output);
    final withDocs = packages.where((p) => p.hasApiDocs).length;
    final index = p.join(output, 'index.html');

    if (args.dryRun) {
      stdout.writeln(
        '  [DRY RUN] docsite: $withDocs of ${packages.length} package(s) '
        'with API docs -> $index',
      );
      return null;
    }
    buildDocSite(siteDir, packages, now: now());
    stdout.writeln(
      '  docsite: $withDocs of ${packages.length} package(s) with API docs '
      '-> $index',
    );
    stdout.writeln(
      '  serve it: dart pub global run dhttpd --path $output  '
      '(then http://localhost:8080/)',
    );
    if (await trackedByGit(root, p.join(siteDir, 'index.html'))) {
      stdout.writeln(
        '  docsite: note: git would track $output; add it to .gitignore '
        '(the site is generated)',
      );
    }
    return null;
  }
}
