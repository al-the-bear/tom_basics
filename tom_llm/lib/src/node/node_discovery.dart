/// Finding the Node.js an agent server runs on.
///
/// **Why a search and not `node`.** The transport, its installer and the
/// availability probe all used to spawn the bare name `node`, which the
/// operating system resolves on `PATH`. A desktop app launched from a
/// launcher — Finder on macOS is the measured case — gets the launcher's
/// `PATH`, `/usr/bin:/bin:/usr/sbin:/sbin`, which holds no Node on any
/// machine where Node was installed the usual ways (nvm, Homebrew, the
/// installer into `/usr/local`). So the gate reported *no Node.js runtime* on
/// a machine with nine of them, and the sentence named a remedy the user had
/// already performed.
///
/// **What the search is.** In order: every `PATH` entry; nvm's versions,
/// newest first; Homebrew's prefix; `/usr/local`. Each candidate that exists
/// is asked its version, and the first at or above the floor wins. The order
/// is by *likelihood of being the user's own choice* — a `PATH` entry is what
/// their shell would run — and the version floor is what stops the order from
/// mattering too much: on the measured machine `/usr/local/bin/node` is a
/// v16 that must be passed over by its version, not by its position.
///
/// **What it records.** Every place looked at and what was there, so the
/// availability gate can say "`/usr/local/bin/node` is v16.17.0, below 20; nothing under
/// `~/.nvm`" instead of "no Node.js runtime", and so the settings panel can
/// show what discovery would do before the user overrides it.
///
/// **The setting replaces the search.** `ai.nodePath` names one
/// executable, and then only that one is looked at: a setting that turned out
/// to be an old Node and was quietly passed over for a discovered one would
/// make the setting a suggestion, and a user who typed it would not learn
/// they typed the wrong one.
///
/// **Platform-neutral by construction.** This library takes a
/// [LlmNodeHost] — the filesystem reads, `PATH`, the home directory and a
/// `--version` run — and performs none of it, so it links under dart2js and
/// is tested against a fake. The `dart:io` host is
/// `LlmProcessNodeHost`, behind `package:tom_llm/io.dart`.
library;

import 'package:meta/meta.dart';

/// The lowest Node major version an agent server built on the Anthropic Agent
/// SDK accepts. Declared once, so the discovery, a transport's probe and an
/// installer compare against one number; a server's `engines.node` is kept in
/// step with it.
const llmRequiredNodeMajorVersion = 20;

/// What a Node search needs from the machine it runs on.
///
/// A port rather than `dart:io`, so the search itself stays in the default
/// barrel and a test can describe a machine instead of building one.
abstract interface class LlmNodeHost {
  /// The entries of `PATH`, in order; empty when there is none.
  List<String> get pathEntries;

  /// The user's home directory, or null when the host cannot say.
  String? get homeDirectory;

  /// Whether paths join with `\` and the executable is `node.exe`.
  bool get isWindows;

  /// Whether [path] is an existing file; a symlink to one counts.
  bool fileExists(String path);

  /// The names of the entries directly under [directory]; empty when it does
  /// not exist or cannot be read.
  List<String> directoryEntries(String directory);

  /// Runs `[executable] --version` and answers its first non-blank output
  /// line, or null when it could not be run or exited non-zero.
  Future<String?> versionOf(String executable);
}

/// Where a candidate came from — the vocabulary of the report.
enum LlmNodeSource {
  /// `ai.nodePath`.
  setting,

  /// A `PATH` entry.
  path,

  /// `~/.nvm/versions/node/<version>/bin/node`.
  nvm,

  /// `/opt/homebrew/bin/node`.
  homebrew,

  /// `/usr/local/bin/node`.
  usrLocal,

  /// `C:\Program Files\nodejs\node.exe`.
  programFiles;

  /// How the report names the place.
  String get label => switch (this) {
    LlmNodeSource.setting => 'the Node.js path setting',
    LlmNodeSource.path => 'PATH',
    LlmNodeSource.nvm => 'nvm',
    LlmNodeSource.homebrew => 'Homebrew',
    LlmNodeSource.usrLocal => '/usr/local',
    LlmNodeSource.programFiles => 'Program Files',
  };
}

/// What was found at one place.
enum LlmNodeLookOutcome {
  /// No file there.
  absent,

  /// A file that did not answer `--version`.
  notRunnable,

  /// A Node below the floor.
  tooOld,

  /// A Node at or above the floor — or one whose version could not be read,
  /// which passes for the reason the transport's probe lets it pass: the
  /// floor catches a *known-too-old* Node, and refusing what it cannot parse
  /// would refuse every wrapper that works.
  accepted,
}

/// One place the search looked at, and what was there.
class LlmNodeCandidate {
  /// The executable path that was tried.
  final String path;

  /// How the path was arrived at.
  final LlmNodeSource source;

  final LlmNodeLookOutcome outcome;

  /// The `--version` answer, normalised to `vMAJOR.MINOR.PATCH` when it had
  /// that shape; null when nothing ran.
  final String? version;

  /// The major version, or null when [version] is null or unparsable.
  final int? major;

  const LlmNodeCandidate({
    required this.path,
    required this.source,
    required this.outcome,
    this.version,
    this.major,
  });

  /// One clause of the report, for a place that held something.
  String describe(int floor) => switch (outcome) {
    LlmNodeLookOutcome.absent => '"$path" does not exist',
    LlmNodeLookOutcome.notRunnable => '"$path" could not be run',
    LlmNodeLookOutcome.tooOld => '"$path" is $version, below $floor',
    LlmNodeLookOutcome.accepted =>
      version == null ? '"$path" runs, version unknown' : '"$path" is $version',
  };

  @override
  String toString() =>
      'LlmNodeCandidate(${source.name}: $path → ${outcome.name}'
      '${version == null ? '' : ' $version'})';
}

/// The outcome of a Node search: the executable to run, or the account of
/// where the search looked and what it found.
class LlmNodeResolution {
  /// The Node to run, or null when none at or above [floor] was found.
  final String? executable;

  /// Its version, when it was read.
  final String? version;

  /// Every place looked at, in the order looked at. Ends at the accepted one.
  final List<LlmNodeCandidate> looked;

  /// The `ai.nodePath` the search was given, or null for a discovery.
  final String? setting;

  /// The `PATH` entries the search saw — part of the report, because "no
  /// node on PATH" is only an explanation when the reader can see which
  /// PATH it was.
  final List<String> pathEntries;

  /// The version floor the search enforced.
  final int floor;

  const LlmNodeResolution({
    required this.executable,
    required this.version,
    required this.looked,
    required this.setting,
    required this.pathEntries,
    this.floor = llmRequiredNodeMajorVersion,
  });

  /// A path the caller vouches for, with no search behind it: a developer's
  /// `--node` flag, a test's stand-in. The transport still probes it, so a
  /// wrong one is reported as not runnable or too old, never as "not found".
  const LlmNodeResolution.explicit(String path)
    : executable = path,
      version = null,
      looked = const [],
      setting = path,
      pathEntries = const [],
      floor = llmRequiredNodeMajorVersion;

  /// Whether there is a Node to run.
  bool get found => executable != null;

  /// Where the search looked and what it found, as one sentence fragment —
  /// the account the availability gate puts after "no Node.js 20 or newer was found".
  ///
  /// A found Node is named with its version and nothing else: the places
  /// passed over on the way to it are in [looked] for the log, not in the
  /// sentence. For a search that found nothing, places that held something
  /// are named one by one with their version, and places that held nothing
  /// are summarised by source, so a `PATH` of six entries with no Node on any
  /// of them is one clause, not six.
  String get report {
    if (looked.isEmpty) {
      return executable == null
          ? 'nothing was looked at'
          : '"$executable", as given';
    }
    final accepted = looked
        .where((c) => c.outcome == LlmNodeLookOutcome.accepted)
        .firstOrNull;
    if (accepted != null) {
      final clause = accepted.describe(floor);
      return accepted.source == LlmNodeSource.setting
          ? '$clause (${accepted.source.label})'
          : clause;
    }
    final clauses = <String>[];
    final absentBySource = <LlmNodeSource, List<String>>{};
    for (final candidate in looked) {
      if (candidate.outcome == LlmNodeLookOutcome.absent &&
          candidate.source != LlmNodeSource.setting) {
        absentBySource
            .putIfAbsent(candidate.source, () => [])
            .add(candidate.path);
        continue;
      }
      final clause = candidate.describe(floor);
      clauses.add(
        candidate.source == LlmNodeSource.setting
            ? '$clause (${candidate.source.label})'
            : clause,
      );
    }
    if (absentBySource.containsKey(LlmNodeSource.path)) {
      clauses.add(
        pathEntries.isEmpty
            ? 'PATH is empty'
            : 'no node on PATH (${pathEntries.join(':')})',
      );
    } else if (setting == null && pathEntries.isEmpty) {
      clauses.add('PATH is empty');
    }
    if (absentBySource.containsKey(LlmNodeSource.nvm)) {
      clauses.add('nothing under ~/.nvm/versions/node');
    }
    final fixed = [
      for (final source in const [
        LlmNodeSource.homebrew,
        LlmNodeSource.usrLocal,
        LlmNodeSource.programFiles,
      ])
        ...?absentBySource[source],
    ];
    if (fixed.isNotEmpty) clauses.add('no ${fixed.join(' or ')}');
    return clauses.join('; ');
  }

  @override
  String toString() => found
      ? 'LlmNodeResolution($executable${version == null ? '' : ' $version'})'
      : 'LlmNodeResolution(none: $report)';
}

/// Produces the Node resolution a transport runs on, when it is asked for —
/// so a selector can be built before the settings are read and a search can
/// run on the probe rather than at construction.
typedef LlmNodeResolver = Future<LlmNodeResolution> Function();

/// A resolver for a path the caller vouches for — see
/// [LlmNodeResolution.explicit].
@visibleForTesting
LlmNodeResolver llmNodeAt(String path) =>
    () async => LlmNodeResolution.explicit(path);

/// The Node a search is for: `node.exe` on Windows, `node` elsewhere.
String llmNodeExecutableName({required bool isWindows}) =>
    isWindows ? 'node.exe' : 'node';

/// Finds a Node at or above [floor] through [host], or accounts for why not.
///
/// With [nodePath] set, only that executable is looked at — the setting
/// replaces the search (library note). Without one the search runs in the
/// order the library note states and stops at the first acceptable Node; a
/// place that `PATH` and a fixed location both name is looked at once.
Future<LlmNodeResolution> llmDiscoverNode({
  required LlmNodeHost host,
  String? nodePath,
  int floor = llmRequiredNodeMajorVersion,
}) async {
  final pathEntries = List<String>.unmodifiable(host.pathEntries);
  final looked = <LlmNodeCandidate>[];

  Future<LlmNodeCandidate> look(String path, LlmNodeSource source) async {
    if (!host.fileExists(path)) {
      return LlmNodeCandidate(
        path: path,
        source: source,
        outcome: LlmNodeLookOutcome.absent,
      );
    }
    final answer = await host.versionOf(path);
    if (answer == null) {
      return LlmNodeCandidate(
        path: path,
        source: source,
        outcome: LlmNodeLookOutcome.notRunnable,
      );
    }
    final parsed = llmParseNodeVersion(answer);
    if (parsed == null) {
      return LlmNodeCandidate(
        path: path,
        source: source,
        outcome: LlmNodeLookOutcome.accepted,
        version: answer.trim(),
      );
    }
    return LlmNodeCandidate(
      path: path,
      source: source,
      outcome: parsed.major < floor
          ? LlmNodeLookOutcome.tooOld
          : LlmNodeLookOutcome.accepted,
      version: parsed.version,
      major: parsed.major,
    );
  }

  LlmNodeResolution resolve() {
    final accepted = looked
        .where((c) => c.outcome == LlmNodeLookOutcome.accepted)
        .firstOrNull;
    return LlmNodeResolution(
      executable: accepted?.path,
      version: accepted?.version,
      looked: List.unmodifiable(looked),
      setting: nodePath,
      pathEntries: pathEntries,
      floor: floor,
    );
  }

  if (nodePath != null) {
    looked.add(await look(nodePath, LlmNodeSource.setting));
    return resolve();
  }

  final seen = <String>{};
  for (final (path, source) in llmNodeSearchPlaces(host)) {
    if (!seen.add(path)) continue;
    final candidate = await look(path, source);
    looked.add(candidate);
    if (candidate.outcome == LlmNodeLookOutcome.accepted) break;
  }
  return resolve();
}

/// The places a discovery looks at, in order, before deduplication: every
/// `PATH` entry, nvm's versions newest first, then the fixed locations.
///
/// Exposed so the order is a fact a test states rather than one it infers
/// from which candidate won.
List<(String, LlmNodeSource)> llmNodeSearchPlaces(LlmNodeHost host) {
  final sep = host.isWindows ? r'\' : '/';
  final name = llmNodeExecutableName(isWindows: host.isWindows);
  String join(String dir, String leaf) =>
      dir.endsWith(sep) ? '$dir$leaf' : '$dir$sep$leaf';

  final places = <(String, LlmNodeSource)>[
    for (final entry in host.pathEntries)
      if (entry.isNotEmpty) (join(entry, name), LlmNodeSource.path),
  ];

  final home = host.homeDirectory;
  if (home != null && home.isNotEmpty) {
    final versions = join(join(home, '.nvm'), join('versions', 'node'));
    final installed = <(List<int>, String)>[
      for (final dir in host.directoryEntries(versions))
        if (_nvmVersion(dir) case final v?) (v, dir),
    ]..sort((a, b) => _compareVersions(b.$1, a.$1));
    if (installed.isEmpty) {
      // Recorded as one absent place, so the report can say "nothing under
      // ~/.nvm" rather than silently never having looked.
      places.add((
        join(versions, join('*', join('bin', name))),
        LlmNodeSource.nvm,
      ));
    }
    for (final (_, dir) in installed) {
      places.add((
        join(join(versions, dir), join('bin', name)),
        LlmNodeSource.nvm,
      ));
    }
  }

  if (host.isWindows) {
    places.add((
      r'C:\Program Files\nodejs\node.exe',
      LlmNodeSource.programFiles,
    ));
  } else {
    places.add(('/opt/homebrew/bin/node', LlmNodeSource.homebrew));
    places.add(('/usr/local/bin/node', LlmNodeSource.usrLocal));
  }
  return places;
}

/// `v22.22.3`, `22.22.3` or a line starting with either → the normalised
/// version and its major; null for anything else.
({String version, int major})? llmParseNodeVersion(String answer) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(answer.trim());
  if (match == null) return null;
  return (
    version: 'v${match.group(1)}.${match.group(2)}.${match.group(3)}',
    major: int.parse(match.group(1)!),
  );
}

List<int>? _nvmVersion(String directoryName) {
  final match = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$').firstMatch(directoryName);
  if (match == null) return null;
  return [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
}

int _compareVersions(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}
