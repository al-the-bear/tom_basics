/// `relkit` — the multi-command "release kit" build tool this sample teaches.
///
/// Where the *introduction* sample built a one-operation tool, `relkit` is the
/// next step up: a [ToolMode.multiCommand] tool that bundles three related
/// operations under one definition —
///
///   * `:report` — print one line per Dart project (name, version, dep count),
///   * `:audit`  — fail any project that is not release-ready (no version, no
///                 description, or a description shorter than `--min-desc`),
///   * `:bump`   — dry-run the next version for each project given `--part`.
///
/// Because each command is a value with its own options and nature filter, the
/// framework can run them **individually** (`relkit :audit`), **in sequence**
/// across one traversal (`relkit :audit :report`), or **nested** against a
/// single project with no traversal (`relkit --nested :report`).
///
/// This file is "the tool". `bin/relkit.dart` is the thin entrypoint, and the
/// `example/` files each exercise one facet against a throwaway fixture tree.
library;

import 'dart:io';

import 'package:tom_build_base/tom_build_base.dart';
import 'package:yaml/yaml.dart';

/// The release-readiness facts `relkit` needs about one package.
///
/// A small immutable value object so the three commands share one notion of
/// "what we know about a package" instead of each re-reading the pubspec.
class PackageFacts {
  final String name;
  final String? version;
  final String description;
  final int dependencyCount;

  const PackageFacts({
    required this.name,
    required this.version,
    required this.description,
    required this.dependencyCount,
  });

  bool get hasVersion => version != null && version!.isNotEmpty;
  bool get hasDescription => description.trim().isNotEmpty;
}

/// Resolve [PackageFacts] for the folder a command is visiting.
///
/// In normal traversal the framework has already detected the
/// [DartProjectFolder] nature and parsed the pubspec, so we read it straight
/// off the context. In `--nested` mode the host tool hands us a bare working
/// directory with no natures attached, so we fall back to reading
/// `pubspec.yaml` ourselves. Either way the three commands get the same value —
/// which is exactly what lets one tool work both standalone and nested.
PackageFacts? packageFactsFor(CommandContext context) {
  final dart = context.tryGetNature<DartProjectFolder>();
  if (dart != null) {
    return PackageFacts(
      name: dart.projectName,
      version: dart.version,
      description: (dart.pubspec['description'] ?? '').toString(),
      dependencyCount: dart.dependencies.length,
    );
  }
  return _factsFromPubspecFile(context.path);
}

/// Parse `pubspec.yaml` under [dirPath] into [PackageFacts], or null if there
/// is no readable pubspec there. Used only on the `--nested` path.
PackageFacts? _factsFromPubspecFile(String dirPath) {
  final file = File('$dirPath/pubspec.yaml');
  if (!file.existsSync()) return null;

  final yaml = loadYaml(file.readAsStringSync());
  if (yaml is! YamlMap) return null;

  final deps = yaml['dependencies'];
  return PackageFacts(
    name: (yaml['name'] ?? dirPath.split(Platform.pathSeparator).last)
        .toString(),
    version: yaml['version']?.toString(),
    description: (yaml['description'] ?? '').toString(),
    dependencyCount: deps is YamlMap ? deps.length : 0,
  );
}

/// Compute the next semantic version after [current] for the given [part]
/// (`major`, `minor`, or `patch`). Pre-release/build suffixes are dropped.
String nextVersion(String current, String part) {
  final core = current.split(RegExp(r'[-+]')).first;
  final segments = core.split('.');
  final major = int.tryParse(segments.elementAtOrNull(0) ?? '') ?? 0;
  final minor = int.tryParse(segments.elementAtOrNull(1) ?? '') ?? 0;
  final patch = int.tryParse(segments.elementAtOrNull(2) ?? '') ?? 0;

  switch (part) {
    case 'major':
      return '${major + 1}.0.0';
    case 'minor':
      return '$major.${minor + 1}.0';
    default:
      return '$major.$minor.${patch + 1}';
  }
}

/// The declarative description of the tool — an immutable `const` value.
///
/// `mode: ToolMode.multiCommand` is what turns on the `:command` calling
/// convention, the per-command help, and folder-by-folder sequencing. Each
/// [CommandDefinition] carries its own options and a `requiredNatures` filter;
/// `defaultCommand` is what runs when the user names no command at all.
const relkitTool = ToolDefinition(
  name: 'relkit',
  description: 'Release kit: report, audit, and (dry-run) bump the Dart '
      'projects in a workspace.',
  version: '1.0.0',
  mode: ToolMode.multiCommand,
  defaultCommand: 'report',
  commands: [
    CommandDefinition(
      name: 'report',
      description: 'Print one line per Dart project (name, version, deps).',
      requiredNatures: {DartProjectFolder},
      options: [
        OptionDefinition.flag(
          name: 'with-path',
          description: 'Append each project\'s path to its line.',
        ),
      ],
      examples: ['relkit :report', 'relkit :report --with-path'],
    ),
    CommandDefinition(
      name: 'audit',
      description: 'Fail projects that are not release-ready.',
      requiredNatures: {DartProjectFolder},
      options: [
        OptionDefinition.option(
          name: 'min-desc',
          description: 'Minimum required description length (0 = any).',
          defaultValue: '0',
          valueName: 'n',
        ),
      ],
      examples: ['relkit :audit', 'relkit :audit --min-desc=20'],
    ),
    CommandDefinition(
      name: 'bump',
      description: 'Show the next version each project would get (dry-run).',
      requiredNatures: {DartProjectFolder},
      options: [
        OptionDefinition.option(
          name: 'part',
          description: 'Which version part to bump.',
          defaultValue: 'patch',
          allowedValues: ['major', 'minor', 'patch'],
          valueName: 'part',
        ),
      ],
      examples: ['relkit :bump', 'relkit :bump --part=minor'],
    ),
  ],
);

/// The three behaviours the framework cannot supply — one executor per command,
/// keyed by command name (this is how a multi-command tool wires up, in
/// contrast to a single-command tool's lone `'default'` executor).
///
/// Each executor returns an [ItemResult]; in multi-command traversal the
/// framework renders those results as a per-folder tree (`>>> folder` then
/// `  -> :command <message>`), so the executors here do no printing of their
/// own — they just describe the outcome.
Map<String, CommandExecutor> relkitExecutors() {
  return {
    'report': CallbackExecutor(onExecute: _report),
    'audit': CallbackExecutor(onExecute: _audit),
    'bump': CallbackExecutor(onExecute: _bump),
  };
}

Future<ItemResult> _report(CommandContext context, CliArgs args) async {
  final facts = packageFactsFor(context);
  if (facts == null) {
    return ItemResult.skipped(
      path: context.path,
      name: context.name,
      message: 'not a Dart project',
    );
  }
  final withPath = args.commandArgs['report']?.options['with-path'] == true;
  final version = facts.hasVersion ? 'v${facts.version}' : '(no version)';
  final suffix = withPath ? '  [${context.relativePath}]' : '';
  return ItemResult.success(
    path: context.path,
    name: context.name,
    message: '${facts.name} $version — ${facts.dependencyCount} deps$suffix',
  );
}

Future<ItemResult> _audit(CommandContext context, CliArgs args) async {
  final facts = packageFactsFor(context);
  if (facts == null) {
    return ItemResult.skipped(
      path: context.path,
      name: context.name,
      message: 'not a Dart project',
    );
  }
  final minDesc =
      int.tryParse(args.commandArgs['audit']?.options['min-desc']?.toString() ??
              '') ??
          0;

  final problems = <String>[];
  if (!facts.hasVersion) problems.add('no version');
  if (!facts.hasDescription) {
    problems.add('no description');
  } else if (facts.description.trim().length < minDesc) {
    problems.add(
      'description too short (${facts.description.trim().length} < $minDesc)',
    );
  }

  if (problems.isNotEmpty) {
    return ItemResult.failure(
      path: context.path,
      name: facts.name,
      error: problems.join(', '),
    );
  }
  return ItemResult.success(
    path: context.path,
    name: facts.name,
    message: 'release-ready',
  );
}

Future<ItemResult> _bump(CommandContext context, CliArgs args) async {
  final facts = packageFactsFor(context);
  if (facts == null || !facts.hasVersion) {
    return ItemResult.skipped(
      path: context.path,
      name: context.name,
      message: 'no version to bump',
    );
  }
  final part = args.commandArgs['bump']?.options['part']?.toString() ?? 'patch';
  final next = nextVersion(facts.version!, part);
  return ItemResult.success(
    path: context.path,
    name: facts.name,
    message: 'would bump ${facts.version} -> $next ($part)',
  );
}

/// Build a [ToolRunner] for the tool, wired to a single [output] sink.
///
/// The framework writes its per-folder tree and any messages to [output]; pass
/// a `StringBuffer` to capture everything for a deterministic, testable run
/// (that is how the `example/` files work). With no sink the runner writes to
/// `stdout`, which is what `bin/relkit.dart` wants.
ToolRunner relkitRunner({StringSink? output}) {
  return ToolRunner(
    tool: relkitTool,
    executors: relkitExecutors(),
    output: output ?? stdout,
    verbose: false,
  );
}
