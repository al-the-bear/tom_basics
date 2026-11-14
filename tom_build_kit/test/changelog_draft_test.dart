// BK-CLOG: `buildkit :bumpversion --changelog` — a CHANGELOG draft from the
// commits since the package's version last changed. Each test builds a git
// repository under .dart_tool; BK-CLOG-6..7 run the real executable rooted
// there (-R), so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart' show ProjectVersionFile;
import 'package:tom_build_kit/src/changelog/changelog_draft.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

const _gitEnv = {
  'GIT_AUTHOR_NAME': 'Test',
  'GIT_AUTHOR_EMAIL': 'test@example.com',
  'GIT_COMMITTER_NAME': 'Test',
  'GIT_COMMITTER_EMAIL': 'test@example.com',
};

void main() {
  late Directory root;
  late String pkg;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('changelog_test_');
    pkg = p.join(root.path, 'pkg');
    Directory(pkg).createSync();
    File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    _git(root.path, ['init', '-q', '-b', 'main']);
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// Writes [files] (relative to the repository) and commits them as
  /// [subject].
  void commit(String subject, Map<String, String> files) {
    files.forEach((path, text) {
      File(p.join(root.path, path))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    _git(root.path, ['add', '-A']);
    _git(root.path, ['commit', '-q', '-m', subject]);
  }

  String pubspec(String version) =>
      'name: pkg\nversion: $version\nenvironment:\n  sdk: ^3.0.0\n';

  ChangelogHistory history() =>
      changelogHistory(pkg, ProjectVersionFile.of(pkg)!);

  test('BK-CLOG-1: with earlier versions, the commits since the last '
      'version change that touched the package, newest first '
      '[2026-11-14]', () {
    commit('Create the package', {'pkg/pubspec.yaml': pubspec('1.0.0')});
    commit('Add A', {'pkg/lib/a.dart': 'class A {}\n'});
    commit('Release 1.1.0', {'pkg/pubspec.yaml': pubspec('1.1.0')});
    commit('Fix B', {'pkg/lib/b.dart': 'class B {}\n'});
    commit('Another package', {'other/x.txt': 'x'});
    commit('Add C', {'pkg/lib/c.dart': 'class C {}\n'});
    final h = history();
    expect(h.sinceVersion, '1.1.0');
    expect(h.subjects, ['Add C', 'Fix B']);
    expect(h.uncommitted, isFalse);
  });

  test('BK-CLOG-2: without an earlier version change, everything since the '
      'package was created [2026-11-14]', () {
    commit('Create the package', {'pkg/pubspec.yaml': pubspec('0.1.0')});
    commit('Add A', {'pkg/lib/a.dart': 'class A {}\n'});
    commit('Add B', {'pkg/lib/b.dart': 'class B {}\n'});
    final h = history();
    expect(h.sinceVersion, '0.1.0');
    expect(h.subjects, ['Add B', 'Add A']);

    File(p.join(pkg, 'lib', 'c.dart')).writeAsStringSync('class C {}\n');
    expect(history().uncommitted, isTrue);
  });

  test('BK-CLOG-3: the draft section: the version, where it is drawn from, '
      'the subjects; uncommitted changes and no git named [2026-11-14]', () {
    final section = changelogDraftSection(
      '1.1.1',
      const ChangelogHistory(
        since: '0123456789abcdef',
        sinceVersion: '1.1.0',
        subjects: ['Add C', 'Fix B'],
        uncommitted: true,
      ),
    );
    expect(
      section,
      startsWith(
        '## 1.1.1\n\n<!-- Draft from the commits since 0123456 (1.1.0);',
      ),
    );
    expect(
      section,
      contains(
        '- (uncommitted changes in the package: no commit describes them yet)\n'
        '- Add C\n- Fix B\n',
      ),
    );
    expect(
      changelogDraftSection('0.1.0', const ChangelogHistory()),
      allOf(
        contains('no git history for the package'),
        contains('- (no commit touched the package since then)'),
      ),
    );
    Directory(pkg).deleteSync(recursive: true);
    final outside = Directory.systemTemp.createTempSync('changelog_nogit_');
    addTearDown(() => outside.deleteSync(recursive: true));
    File(
      p.join(outside.path, 'pubspec.yaml'),
    ).writeAsStringSync(pubspec('1.0.0'));
    final h = changelogHistory(
      outside.path,
      ProjectVersionFile.of(outside.path)!,
    );
    expect(h.since, isNull);
  });

  test('BK-CLOG-4: inserted at the top, under a title; a section of that '
      'version is never replaced; no CHANGELOG is created [2026-11-14]', () {
    const draft = '## 1.1.1\n\n- Add C\n\n';
    var r = insertChangelogDraft('## 1.1.0\n\n- Old.\n', draft, '1.1.1');
    expect(r.outcome, ChangelogDraftOutcome.inserted);
    expect(r.text, '## 1.1.1\n\n- Add C\n\n## 1.1.0\n\n- Old.\n');

    r = insertChangelogDraft('# Changelog\n\n## 1.1.0\n', draft, '1.1.1');
    expect(r.text, '# Changelog\n\n## 1.1.1\n\n- Add C\n\n## 1.1.0\n');
    r = insertChangelogDraft('# Changelog\n\nNothing yet.\n', draft, '1.1.1');
    expect(r.text, '# Changelog\n\n## 1.1.1\n\n- Add C\n\nNothing yet.\n');

    for (final existing in [
      '## 1.1.1\n\n- Written.\n',
      '## [1.1.1] - 2026-11-14\n',
      '# Changelog\n\n## 1.1.1 - 2026-11-14\n',
    ]) {
      r = insertChangelogDraft(existing, draft, '1.1.1');
      expect(r.outcome, ChangelogDraftOutcome.kept, reason: existing);
      expect(r.text, existing);
    }
    expect(
      insertChangelogDraft('## 1.1.10\n', draft, '1.1.1').outcome,
      ChangelogDraftOutcome.inserted,
      reason: '1.1.10 is not 1.1.1',
    );

    r = insertChangelogDraft(null, draft, '1.1.1');
    expect((r.outcome, r.text), (ChangelogDraftOutcome.created, draft));
  });

  group('the command', () {
    Future<ProcessResult> buildkit(List<String> args) => Process.run('dart', [
      'run',
      _buildkit,
      '-R',
      root.path,
      '-s',
      root.path,
      ...args,
    ], workingDirectory: root.path);

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    setUp(() {
      commit('Create the package', {
        'pkg/pubspec.yaml': pubspec('1.0.0'),
        'pkg/CHANGELOG.md': '# Changelog\n\n## 1.0.0\n\n- First.\n',
      });
      commit('Add A', {'pkg/lib/a.dart': 'class A {}\n'});
    });

    test('BK-CLOG-5: a bump drafts the entry; --dry-run prints it and writes '
        'nothing [2026-11-14]', () async {
      var r = await buildkit(['--dry-run', ':bumpversion', '--changelog']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('[DRY RUN] pkg: CHANGELOG.md draft:'));
      expect(out(r), contains('    ## 1.0.1'));
      expect(out(r), contains('    - Add A'));
      expect(
        File(p.join(pkg, 'CHANGELOG.md')).readAsStringSync(),
        isNot(contains('1.0.1')),
      );

      r = await buildkit([':bumpversion', '--changelog']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('pkg: CHANGELOG.md draft for 1.0.1 inserted'));
      expect(
        File(p.join(pkg, 'pubspec.yaml')).readAsStringSync(),
        contains('version: 1.0.1'),
      );
      final changelog = File(p.join(pkg, 'CHANGELOG.md')).readAsStringSync();
      expect(changelog, startsWith('# Changelog\n\n## 1.0.1\n\n<!-- Draft'));
      expect(changelog, contains('- Add A\n\n## 1.0.0\n'));
      expect(changelog, isNot(contains('- Create the package')));
    });

    test('BK-CLOG-6: an existing section of the new version is kept; the '
        'bump still happens; without --changelog nothing is drafted '
        '[2026-11-14]', () async {
      const written =
          '# Changelog\n\n## 1.0.1\n\n- Written by hand.\n\n## 1.0.0\n';
      File(p.join(pkg, 'CHANGELOG.md')).writeAsStringSync(written);
      var r = await buildkit([':bumpversion', '--changelog']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('pkg: CHANGELOG.md has a 1.0.1 section; kept'));
      expect(File(p.join(pkg, 'CHANGELOG.md')).readAsStringSync(), written);
      expect(
        File(p.join(pkg, 'pubspec.yaml')).readAsStringSync(),
        contains('version: 1.0.1'),
      );

      r = await buildkit([':bumpversion']);
      expect(r.exitCode, 0, reason: out(r));
      expect(File(p.join(pkg, 'CHANGELOG.md')).readAsStringSync(), written);
    });
  });
}

void _git(String dir, List<String> args) {
  final r = Process.runSync(
    'git',
    args,
    workingDirectory: dir,
    environment: _gitEnv,
  );
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')}: ${r.stderr}');
}
