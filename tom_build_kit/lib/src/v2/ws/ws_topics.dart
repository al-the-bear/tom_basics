/// The help topics `buildkit help ws` and `buildkit help ws-options`
/// (buildkit_ws_commands.md § 1.11).
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

import 'ws_messages.dart';

/// `buildkit help ws`: the repository set, the three commands, synchronizing
/// a quiet workspace machine by machine.
const wsTopic = HelpTopic(
  name: 'ws',
  summary: 'The workspace commands :ws-push, :ws-update, :ws-repo-cleanup',
  content: '''
# The workspace commands

Three commands keep a workspace committed, pushed and in sync from the
repos.yaml at or above the folder you start in (or --manifest), wherever in
the tree you start them.

## The repository set

  the root and every entry of repos.yaml for this host (code, fork, ai)
                                       included
  tom_binaries (kind binaries)         latest build wins: pushed only with
                                       local commits (:ws-push --commit-binaries)
  kind upstream                        skipped by :ws-push; :ws-update clones
                                       it when missing and puts it at its pin
  quest clones inside _ai/quests/      included
  paths under unmanaged:, .worktrees/, _ai/.quest-repos/
                                       skipped (tools own them)
  a clone that is no entry             unknown: :ws-push skips it and exits 1,
                                       :ws-repo-cleanup reports it
  an entry not on disk                 missing: :ws-update clones it
  ztmp/, build/, node_modules/, .dart_tool/, hidden folders
                                       never looked at

Every entry has its expected branch (branch: in repos.yaml; the root's
root.branch). A repository on another branch, or on a detached HEAD, is
reported with the options that resolve it.

## The commands

  :ws-push [-m "<message>"]   everything this machine has, committed (one
                              commit per repository, the same message),
                              merged with origin/<branch> and pushed; never
                              forced. Refuses while a Tom AI window is busy,
                              for a secret or a file over 50 MB, an
                              unregistered merge driver, a repository mid-merge.
  :ws-update                  this machine brought up to the remotes: the
                              root first, missing entries cloned, every
                              repository merged. Uncommitted files a merge
                              would overwrite hold the repository. Nothing is
                              pushed but what --rescue-detached,
                              --merge-branch and --push-current push for the
                              repositories they name.
  :ws-repo-cleanup            the surplus clones reported; --apply moves the
                              removable ones to ztmp/<yymmdd>_ws_repo_cleanup/,
                              --delete deletes them.

Each ends with one report: what changed, and for every problem the finding,
the evidence, the state it was left in, every option that resolves it and
the command line to repeat. The code in brackets is its help topic
(buildkit help ws-conflict). The options: buildkit help ws-options. --json
writes the same report as JSON; -n shows the plan and changes nothing.

## Synchronizing a quiet workspace, machine by machine

The commands are yours: an agent runs one only when your prompt asks for it.
With no session at work anywhere:

  1. On the machine with the work:   buildkit :ws-push -m "Evening state"
  2. On each other machine:          buildkit :ws-update
  3. Anything a report names: repeat with the option it offers, e.g.
                                     buildkit :ws-push --merge-branch core

:ws-push here and :ws-update there never lose work: a conflict is aborted
(its commits stay on this machine, or on a ws-push/<host>/<stamp> branch with
--merge-branch), a merge that would overwrite uncommitted files is held, and
nothing is ever force-pushed. While sessions are working, use the fleet
skills instead: they never commit work they did not make.
''',
);

/// The run options without a repository list (named in the message that
/// refuses or warns), and the value options.
const _runOptions = {
  'ignore-active':
      'Run although a Tom AI window is busy; whatever its sessions wrote so '
      'far is committed with the rest (:ws-push, ws-active).',
  'commit-binaries':
      'Commit and push tom_binaries\' uncommitted binaries too (:ws-push, '
      'ws-binaries).',
  'apply':
      'Move every removable surplus clone to ztmp/<yymmdd>_ws_repo_cleanup/ '
      '(:ws-repo-cleanup, ws-surplus).',
  'delete':
      'Delete the removable surplus clones instead of moving them (with or '
      'without --apply; :ws-repo-cleanup, ws-surplus).',
};

/// `buildkit help ws-options`: the vocabulary of the options that resolve
/// the problems of the `:ws-*` commands (§ 1.8), read off the messages that
/// offer them, so the page names exactly what the reports offer.
///
/// [accepted]: the options each command accepts (its option definitions); an
/// option a shared message lists is credited only to the commands that take
/// it.
HelpTopic wsOptionsTopic(Map<String, Set<String>> accepted) {
  final commands = {
    ':ws-push': wsPushMessages,
    ':ws-update': wsUpdateMessages,
    ':ws-repo-cleanup': wsRepoCleanupMessages,
  };
  final explanation = <String, String>{};
  final syntax = <String, String>{};
  final offeredBy = <String, Set<String>>{};
  final inCommands = <String, Set<String>>{};
  for (final e in commands.entries) {
    for (final d in e.value.definitions) {
      for (final o in d.options) {
        if (!(accepted[e.key]?.contains(o.name) ?? false)) continue;
        explanation.putIfAbsent(
          o.name,
          () => o.explanation.replaceAll('\n', ' '),
        );
        syntax.putIfAbsent(
          o.name,
          () => o.valueName != null
              ? '--${o.name} <${o.valueName}>'
              : o.repoList
              ? '--${o.name} <repos>'
              : '--${o.name}',
        );
        offeredBy.putIfAbsent(o.name, () => {}).add(d.code);
        inCommands.putIfAbsent(o.name, () => {}).add(e.key);
      }
    }
  }
  final b = StringBuffer()
    ..writeln('# The options that resolve the problems of the :ws-* commands')
    ..writeln()
    ..writeln(
      'A problem never blocks the other repositories: each is reported with '
      'its options, and the report prints the command line to repeat with '
      'the chosen option. An option given repositories acts only on those '
      '(--<option> <repo>[,<repo>...]); a repository is named by the last '
      'segment of its path when that is unique, else by its path from the '
      'root. Nothing force-pushes: there is no --force.',
    )
    ..writeln()
    ..writeln('## Per repository, or per file (offered by the messages named)')
    ..writeln();
  final names = syntax.keys.toList()..sort();
  for (final n in names) {
    if (_runOptions.containsKey(n)) continue;
    b
      ..writeln('  ${syntax[n]}')
      ..writeln('      ${explanation[n]}')
      ..writeln(
        '      ${(inCommands[n]!.toList()..sort()).join(', ')}: '
        '${(offeredBy[n]!.toList()..sort()).join(', ')}',
      );
  }
  b
    ..writeln()
    ..writeln('## For the whole run')
    ..writeln();
  for (final e in _runOptions.entries) {
    b
      ..writeln('  --${e.key}')
      ..writeln('      ${e.value}');
  }
  b
    ..writeln()
    ..writeln(
      'buildkit help <code> explains each message at length; buildkit help ws '
      'the commands.',
    );
  return HelpTopic(
    name: 'ws-options',
    summary: 'The options that resolve the problems of the :ws-* commands',
    content: '$b',
  );
}
