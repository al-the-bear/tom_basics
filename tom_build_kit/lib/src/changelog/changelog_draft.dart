/// The CHANGELOG draft behind `buildkit :bumpversion --changelog`: the
/// subjects of the commits that touched a package since its version last
/// changed, inserted as a draft section `## <new version>` at the top of its
/// CHANGELOG.md for the author to rewrite. The workspace does not use
/// conventional commits, so the draft is raw material, not an entry.
///
/// **Since when.** The newest commit whose version file states another
/// version than its parent's (or adds the file): the last release, or the
/// package's first version when it has never been bumped. Commits after it
/// that touched the package folder are listed, newest first, merges left
/// out. A package outside git, or whose version file has no history, gets a
/// draft without commits.
///
/// **Where.** Above the first `## ` section, under the file's `# ` title if
/// it has one; a missing CHANGELOG.md is created. A section of the new
/// version (`## 1.2.3`, `## [1.2.3]`, `## 1.2.3 - date`) is never replaced:
/// the draft is then left out and the existing section kept.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart' show ProjectVersionFile;

/// The commits a draft is made of.
class ChangelogHistory {
  /// The commit that last changed the version, or null when there is no
  /// history (not in git, or the version file was never committed).
  final String? since;

  /// The version that commit set.
  final String? sinceVersion;

  /// The subjects of the commits after [since] that touched the package,
  /// newest first.
  final List<String> subjects;

  /// Whether the package folder has uncommitted changes, which no commit
  /// subject describes yet.
  final bool uncommitted;

  const ChangelogHistory({
    this.since,
    this.sinceVersion,
    this.subjects = const [],
    this.uncommitted = false,
  });
}

/// What [insertChangelogDraft] did.
enum ChangelogDraftOutcome {
  /// The draft section was inserted.
  inserted,

  /// CHANGELOG.md did not exist and was created with the draft.
  created,

  /// A section of that version exists; nothing changed.
  kept,
}

/// Reads the git history of the package at [packageDir], whose version file
/// is [versionFile].
ChangelogHistory changelogHistory(
  String packageDir,
  ProjectVersionFile versionFile,
) {
  ProcessResult git(List<String> args) => Process.runSync(
    'git',
    args,
    workingDirectory: packageDir,
    runInShell: Platform.isWindows,
  );

  // The commits that touched the version file, newest first.
  final touched = git([
    'log',
    '--format=%H',
    '--follow',
    '--',
    versionFile.fileName,
  ]);
  if (touched.exitCode != 0) return const ChangelogHistory();
  final commits = (touched.stdout as String)
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (commits.isEmpty) return const ChangelogHistory();

  String? versionAt(String rev) {
    final shown = git(['show', '$rev:./${versionFile.fileName}']);
    if (shown.exitCode != 0) return null;
    return versionFile.read(shown.stdout as String);
  }

  String? since;
  String? sinceVersion;
  for (final commit in commits) {
    final version = versionAt(commit);
    final before = versionAt('$commit^');
    if (version != before) {
      since = commit;
      sinceVersion = version;
      break;
    }
  }
  // Every commit kept the version: it was set before the oldest one.
  since ??= commits.last;
  sinceVersion ??= versionAt(commits.last);

  final log = git([
    'log',
    '--no-merges',
    '--format=%s',
    '$since..HEAD',
    '--',
    '.',
  ]);
  final status = git(['status', '--porcelain', '--', '.']);
  return ChangelogHistory(
    since: since,
    sinceVersion: sinceVersion,
    uncommitted:
        status.exitCode == 0 && (status.stdout as String).trim().isNotEmpty,
    subjects: log.exitCode != 0
        ? const []
        : (log.stdout as String)
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList(),
  );
}

/// The draft section for [newVersion] from [history].
String changelogDraftSection(String newVersion, ChangelogHistory history) {
  final from = history.since == null
      ? 'no git history for the package'
      : 'the commits since ${history.since!.substring(0, 7)}'
            '${history.sinceVersion == null ? '' : ' (${history.sinceVersion})'}';
  final items = [
    if (history.uncommitted)
      '- (uncommitted changes in the package: no commit describes them yet)',
    if (history.subjects.isEmpty && !history.uncommitted)
      '- (no commit touched the package since then)',
    for (final s in history.subjects) '- $s',
  ];
  return [
    '## $newVersion',
    '',
    '<!-- Draft from $from; rewrite it for the reader before publishing. -->',
    '',
    ...items,
    '',
    '',
  ].join('\n');
}

/// Whether [changelog] has a section for [version].
bool hasChangelogSection(String changelog, String version) => RegExp(
  '^##\\s+\\[?${RegExp.escape(version)}\\]?(\\s|\$)',
  multiLine: true,
).hasMatch(changelog);

/// [changelog] (null when there is none) with [section] for [version]
/// inserted at the top, or unchanged when it has that version's section.
({String text, ChangelogDraftOutcome outcome}) insertChangelogDraft(
  String? changelog,
  String section,
  String version,
) {
  if (changelog == null) {
    return (text: section, outcome: ChangelogDraftOutcome.created);
  }
  if (hasChangelogSection(changelog, version)) {
    return (text: changelog, outcome: ChangelogDraftOutcome.kept);
  }
  final firstSection = RegExp(r'^## ', multiLine: true).firstMatch(changelog);
  if (firstSection != null) {
    return (
      text: changelog.replaceRange(
        firstSection.start,
        firstSection.start,
        section,
      ),
      outcome: ChangelogDraftOutcome.inserted,
    );
  }
  // No section yet: after a `# ` title, else at the top.
  final title = RegExp(r'^# .*\n', multiLine: true).matchAsPrefix(changelog);
  final at = title?.end ?? 0;
  final prefix = changelog.substring(0, at);
  final rest = changelog.substring(at).trimLeft();
  return (
    text: '$prefix${at > 0 ? '\n' : ''}$section$rest',
    outcome: ChangelogDraftOutcome.inserted,
  );
}

/// Drafts the CHANGELOG section of [newVersion] for the package at
/// [packageDir] and, unless [dryRun], writes it. Answers the outcome and the
/// section.
({ChangelogDraftOutcome outcome, String section}) draftChangelog(
  String packageDir,
  ProjectVersionFile versionFile,
  String newVersion, {
  required bool dryRun,
}) {
  final section = changelogDraftSection(
    newVersion,
    changelogHistory(packageDir, versionFile),
  );
  final file = File(p.join(packageDir, 'CHANGELOG.md'));
  final result = insertChangelogDraft(
    file.existsSync() ? file.readAsStringSync() : null,
    section,
    newVersion,
  );
  if (!dryRun && result.outcome != ChangelogDraftOutcome.kept) {
    file.writeAsStringSync(result.text);
  }
  return (outcome: result.outcome, section: section);
}
