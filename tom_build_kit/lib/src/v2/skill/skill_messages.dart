/// The messages of the `:skill-*` commands (buildkit_ws_commands.md § 1.6,
/// § 1.10), defined once: each gives its block in the report, its JSON and
/// its help topic (`buildkit help <code>`).
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

import '../ws/ws_messages.dart' show wsManifest;

/// `skill-unknown`: a repository under the root that is no entry stops the
/// run before anything is touched.
const skillUnknown = MessageDefinition(
  code: 'skill-unknown',
  level: MessageLevel.error,
  label: 'UNKNOWN REPOSITORIES',
  summary: 'Repositories under the root that are no entry of repos.yaml.',
  description:
      'Nothing was reconciled: a repository the fleet does not know is never '
      'committed or merged. Give it an entry in repos.yaml, list it under '
      'unmanaged:, or move it out (buildkit :ws-repo-cleanup), then run '
      'again.',
);

/// `skill-driver`: the merge drivers for generated files and application
/// locks are not registered.
const skillDriver = MessageDefinition(
  code: 'skill-driver',
  level: MessageLevel.error,
  label: 'MERGE DRIVERS',
  summary: 'The merge drivers for generated files and locks are missing.',
  description:
      'Without generated-newer-wins and pubspec-lock-last-changed, a '
      'generated file or an application lock changed on two machines '
      'conflicts. Run .claude/skills/install.sh (it registers them from '
      'tom_binaries), then run again. Nothing was changed.',
);

/// `skill-decision`: a lone run found uncommitted work (exit 3).
const skillDecision = MessageDefinition(
  code: 'skill-decision',
  level: MessageLevel.error,
  label: 'DECISION NEEDED',
  summary: 'Uncommitted work this run did not make: decide on it first.',
  description:
      'A skill never commits work it did not make. Nothing was changed. The '
      'skill writes the decision document from the scan (tom_dirty_work); '
      'once it is decided, run again with --dirty=hold, which leaves '
      'everything uncommitted where it is and goes on.',
  options: [
    MessageOption(
      'dirty=hold',
      'Leave the uncommitted work where it is and reconcile around it;\n'
          'a repository whose files the merge would overwrite is held.',
      repoList: false,
    ),
  ],
  exitCode: 3,
);

/// `skill-held`: a repository left behind because of uncommitted work.
const skillHeld = MessageDefinition(
  code: 'skill-held',
  level: MessageLevel.warning,
  label: 'HELD',
  summary: 'Uncommitted work left in place, never committed.',
  description:
      'The repository keeps its uncommitted files. When the incoming merge '
      'would overwrite them it was not merged (nor pushed); decide on them '
      '(tom_dirty_work) and run again.',
);

/// `skill-failed`: a repository could not be reconciled.
const skillFailed = MessageDefinition(
  code: 'skill-failed',
  level: MessageLevel.error,
  label: 'FAILED',
  summary: 'A repository could not be reconciled.',
  description:
      'The finding says why (a conflict, a diverged fork, a rejected push, a '
      'failed clone, the wrong branch). It was left as it was; the other '
      'repositories went on.',
);

/// `skill-uncommitted`: (`:skill-dirty-scan`, a dry run) uncommitted work.
const skillUncommitted = MessageDefinition(
  code: 'skill-uncommitted',
  level: MessageLevel.warning,
  label: 'UNCOMMITTED',
  summary: 'Uncommitted work in a repository, by group.',
  description:
      'Grouped into secret, generated, modified and new, each with a '
      'fingerprint; tom_dirty_work writes the decision document from it.',
);

/// `skill-unknown-seen`: (`:skill-dirty-scan`) unknown repositories.
const skillUnknownSeen = MessageDefinition(
  code: 'skill-unknown-seen',
  level: MessageLevel.warning,
  label: 'UNKNOWN REPOSITORIES',
  summary: 'Repositories under the root that are no entry of repos.yaml.',
  description:
      'Not scanned. Give them an entry, list them under unmanaged:, or move '
      'them out with buildkit :ws-repo-cleanup.',
);

/// `skill-missing`: (`:skill-status`) an entry that is not cloned.
const skillMissing = MessageDefinition(
  code: 'skill-missing',
  level: MessageLevel.warning,
  label: 'MISSING',
  summary: 'An entry of this host that is not cloned.',
  description: 'buildkit :ws-update (or :skill-reconcile-code) clones it.',
);

/// `skill-off-pin`: (`:skill-status`) an upstream not at its pin.
const skillOffPin = MessageDefinition(
  code: 'skill-off-pin',
  level: MessageLevel.warning,
  label: 'OFF PIN',
  summary: 'An upstream that is not at its pin.',
  description: 'buildkit :ws-update (or :skill-reconcile-code) puts it back.',
);

/// `skill-no-branch`: (`:skill-status`) origin lacks the entry's branch.
const skillNoBranch = MessageDefinition(
  code: 'skill-no-branch',
  level: MessageLevel.warning,
  label: 'NO BRANCH ON ORIGIN',
  summary: 'Origin has no branch of the entry\'s name: nothing to compare.',
  description:
      'Publishing the branch is a decision; or correct branch: in repos.yaml.',
);

/// `skill-run-branch`: (`:skill-status`) an unmerged run branch.
const skillRunBranch = MessageDefinition(
  code: 'skill-run-branch',
  level: MessageLevel.warning,
  label: 'RUN BRANCH',
  summary: 'A run worktree under .worktrees/ whose branch is not merged.',
  description: 'Its commits are on the run\'s branch only; merge or drop it.',
);

/// `skill-old-tree`: (`:skill-status`) a tree beside the root.
const skillOldTree = MessageDefinition(
  code: 'skill-old-tree',
  level: MessageLevel.warning,
  label: 'OLD TREE',
  summary: 'A folder <root>_old* beside the root (the tree before a cutover).',
  description: 'Delete it once nothing in it is needed.',
);

/// The messages of `:skill-reconcile-code`.
final skillReconcileMessages = MessageCatalog([
  wsManifest,
  skillUnknown,
  skillDriver,
  skillDecision,
  skillHeld,
  skillFailed,
  skillUncommitted,
]);

/// The messages of `:skill-status`.
final skillStatusMessages = MessageCatalog([
  wsManifest,
  skillMissing,
  skillOffPin,
  skillNoBranch,
  skillRunBranch,
  skillOldTree,
]);

/// The messages of `:skill-dirty-scan`.
final skillDirtyScanMessages = MessageCatalog([
  wsManifest,
  skillUncommitted,
  skillUnknownSeen,
]);

/// The messages of the `:skill-*` commands, once (`wsManifest` is a `:ws-*`
/// topic already).
final skillAllMessages = MessageCatalog([
  skillUnknown,
  skillDriver,
  skillDecision,
  skillHeld,
  skillFailed,
  skillUncommitted,
  skillUnknownSeen,
  skillMissing,
  skillOffPin,
  skillNoBranch,
  skillRunBranch,
  skillOldTree,
]);

/// `buildkit help skill-json`.
const skillJsonTopic = HelpTopic(
  name: 'skill-json',
  summary:
      'The JSON the :skill-* commands write (--json), which the skills read',
  content: '''
# The JSON of the :skill-* commands

Every :skill-* command writes, with --json, one JSON document: the run report
every :ws-* command writes, plus one section of its own.

## The report (every command)

  command    "buildkit :skill-status", ...
  root, host, started (ISO time), options (the arguments as given)
  exitCode   what the command exits with
  summary    {repositories, changed, needsYou, warnings, refused}
  messages   [{code, level (refusal | error | warning), repository {name,
             path}, branch, finding, evidence {<kind>: [lines]}, state,
             options [{option, explanation, commandLine}]}]
  done       [{repository, actions, files}]: what changed
  unchanged  [paths]: looked at, nothing to do

## :skill-status: "status"

  repositories [{path, kind, state, head, behind, lagAt, ahead, unpushedAt,
                dirty, syncAt}]
      state: ok | missing | offpin | nobranch; behind / ahead against
      origin/<branch> after a fetch; lagAt the commit time (unix seconds) of
      the oldest commit the clone is missing, unpushedAt of the oldest it has
      not pushed, syncAt the last pull / merge / rebase / clone in the reflog;
      a value that does not apply is null.
  runBranches  [{path, branch, commits, worktree}]
  oldTrees     [{path, sizeKiB (null when measuring took too long)}]
  probed       the repositories listed

--rows prints instead the rows status_probe.sh prints (REPO, RUNBRANCH,
OLDTREE, PROBED), byte for byte: what tom_fleet_status reads today.

## :skill-dirty-scan: "scan"

  label         the root's folder name
  scanned       the repositories walked
  files         uncommitted files in all
  repositories  [{path, groups [{group (secret | generated | modified | new),
                count, newestAge, fingerprint, files [{xy, path, age}]}]}]
  unknown       [paths]: repositories that are no entry

--rows prints the rows of tom_dirty_work --scan (DIRTY, GROUP, UNKNOWN,
SCANNED), byte for byte: the fingerprints are the ones tom_dirty_work
--apply-group checks.

## :skill-reconcile-code: "reconcile"

  changed  [{repository, what}]   held  [{repository, why}]
  failed   [{repository, why}]    repositories (walked)
''',
);
