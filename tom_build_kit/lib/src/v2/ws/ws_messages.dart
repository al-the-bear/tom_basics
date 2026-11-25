/// The messages of the `:ws-*` commands (buildkit_ws_commands.md § 1.10),
/// defined once: each gives its block in the report, its JSON and its help
/// topic (`buildkit help <code>`).
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

const _skip = MessageOption(
  'skip',
  'Leave the repository out of this run (the run then exits 1).',
);

/// `ws-active`: a Tom AI window on this host is sending a prompt or running.
const wsActive = MessageDefinition(
  code: 'ws-active',
  level: MessageLevel.refusal,
  label: 'ACTIVE',
  summary:
      'A Tom AI window on this host has a queue item sending or a run '
      'running.',
  description:
      'What those sessions are writing would be committed half done, and a '
      'merge could change files under them. Wait until their prompts '
      'finish, or pause their queues, then run again. The windows are read '
      'from the window-state files in _ai/local (a window counts while its '
      'heartbeat is less than 90 seconds old).',
  options: [
    MessageOption(
      'ignore-active',
      'Run anyway: whatever those sessions have written so far is committed\n'
          'with the rest, possibly half done.',
      repoList: false,
    ),
  ],
);

/// `ws-secret`: a file that would be committed matches the secret list.
const wsSecret = MessageDefinition(
  code: 'ws-secret',
  level: MessageLevel.refusal,
  label: 'SECRET',
  summary: 'A file that would be committed matches the secret list.',
  description:
      'The list is the one tom_push_code uses: .env and .env.*, *.pem, '
      'credentials.*. A committed secret stays in the history even after it '
      'is deleted. Add the file to the repository\'s .gitignore, or name it '
      'with one of the options.',
  options: [
    MessageOption(
      'skip-file',
      'Leave it uncommitted in this run (the run then exits 1).',
      repoList: false,
      valueName: 'glob',
    ),
    MessageOption(
      'allow-file',
      'Commit it anyway: it is pushed with the rest.',
      repoList: false,
      valueName: 'glob',
    ),
  ],
);

/// `ws-large`: a file over 50 MB would be committed.
const wsLarge = MessageDefinition(
  code: 'ws-large',
  level: MessageLevel.refusal,
  label: 'LARGE',
  summary: 'A file over 50 MB would be committed.',
  description:
      'GitHub refuses files over 100 MB, and every clone carries a committed '
      'file for ever. Add it to the repository\'s .gitignore, or name it with '
      'one of the options.',
  options: [
    MessageOption(
      'skip-file',
      'Leave it uncommitted in this run (the run then exits 1).',
      repoList: false,
      valueName: 'glob',
    ),
    MessageOption(
      'allow-file',
      'Commit it anyway (a file over 100 MB makes the push fail).',
      repoList: false,
      valueName: 'glob',
    ),
  ],
);

/// `ws-driver`: a merge driver a `.gitattributes` names is not registered.
const wsDriver = MessageDefinition(
  code: 'ws-driver',
  level: MessageLevel.refusal,
  label: 'DRIVER',
  summary: 'A merge driver that a .gitattributes names is not registered.',
  description:
      'Without it git merges the files with its text merge, which breaks '
      'generated and state files (trails, locks, version stamps). Register '
      'the drivers with .claude/skills/install.sh (from tom_binaries), then '
      'run again. There is no override.',
);

/// `ws-in-progress`: a repository is mid-merge, mid-rebase or mid-cherry-pick.
const wsInProgress = MessageDefinition(
  code: 'ws-in-progress',
  level: MessageLevel.refusal,
  label: 'IN PROGRESS',
  summary: 'A repository is mid-merge, mid-rebase or mid-cherry-pick.',
  description:
      'Committing now would record a half-finished operation. Finish or '
      'abort it by hand (git merge --continue / --abort, git rebase '
      '--continue / --abort, git cherry-pick --continue / --abort), or leave '
      'the repository out of this run.',
  options: [_skip],
);

/// `ws-manifest`: no repos.yaml, or one that breaks its schema.
const wsManifest = MessageDefinition(
  code: 'ws-manifest',
  level: MessageLevel.refusal,
  label: 'MANIFEST',
  summary: 'There is no repos.yaml, or it breaks its schema.',
  description:
      'The :ws-* commands work on the repositories repos.yaml lists (at the '
      'root of the tree, at or above the folder they are started in, or '
      'named with --manifest). Fix the file; there is no override.',
);

/// `ws-conflict`: the merge of `origin/<branch>` conflicts.
const wsConflict = MessageDefinition(
  code: 'ws-conflict',
  level: MessageLevel.error,
  label: 'CONFLICT',
  summary: 'The merge of origin/<branch> conflicts.',
  description:
      'Your local commits and the incoming ones change the same lines. The '
      'merge was aborted and nothing was pushed for the repository: your '
      'commits are safe on this machine. Choose how to go on; there is no '
      'force push.',
  options: [
    MessageOption(
      'merge-branch',
      'Push your commits to ws-push/<host>/<yymmdd-hhmm> and leave the branch\n'
          'as it is on the remote. Your work is on the remote at once; merge later.',
    ),
    MessageOption(
      'ours',
      'Merge again; where both sides changed a line, yours wins. Then push.\n'
          'The incoming change on those lines is lost (it stays in the history).',
    ),
    MessageOption(
      'theirs',
      'Merge again; where both sides changed a line, the incoming one wins.\n'
          'Your change on those lines is lost (it stays in your commit).',
    ),
    MessageOption(
      'leave-conflict',
      'Merge again and stop with the conflict in the working tree for you\n'
          'to resolve by hand; then commit and run :ws-push again.',
    ),
    _skip,
  ],
);

/// `ws-off-branch`: a repository on another branch than expected.
const wsOffBranch = MessageDefinition(
  code: 'ws-off-branch',
  level: MessageLevel.error,
  label: 'OFF BRANCH',
  summary:
      'A repository is on another branch than repos.yaml (or '
      '_ai/quests.yaml) expects.',
  description:
      'The fleet keeps every repository on its expected branch; work on '
      'another branch would not reach the other machines. Nothing was '
      'committed or pushed for it.',
  options: [
    MessageOption(
      'push-current',
      'Commit and push the branch it is on (the expected branch stays as it is).',
    ),
    MessageOption(
      'to-branch',
      'Commit, switch to the expected branch, merge the current one into it,\n'
          'then go on as usual (merge origin, push).',
    ),
    MessageOption(
      'set-branch',
      "Record the current branch as the entry's branch: in repos.yaml (the\n"
          'root commits the change), then go on with it.',
    ),
    _skip,
  ],
);

/// `ws-detached`: a detached HEAD that is not the head of its branch.
const wsDetached = MessageDefinition(
  code: 'ws-detached',
  level: MessageLevel.error,
  label: 'DETACHED',
  summary: 'A detached HEAD that is not the head of its branch.',
  description:
      'The commits since the branch are on no branch; switching back would '
      'leave them behind. Nothing was committed or pushed for it.',
  options: [
    MessageOption(
      'rescue-detached',
      'Put them (and the uncommitted work) on ws-push/<host>/<yymmdd-hhmm>,\n'
          'push it, and return the repository to its branch.',
    ),
    _skip,
  ],
);

/// `ws-unknown`: a clone that is no entry and not unmanaged.
const wsUnknown = MessageDefinition(
  code: 'ws-unknown',
  level: MessageLevel.error,
  label: 'UNKNOWN',
  summary: 'A clone on disk that repos.yaml does not list.',
  description:
      'It was left alone: the fleet does not know it, so its work reaches no '
      'other machine. Give it an entry in repos.yaml, list it under '
      'unmanaged:, or remove it with :ws-repo-cleanup.',
  options: [
    MessageOption(
      'include-unknown',
      'Treat it as an entry for this run: commit, merge and push its branch\n'
          'to its own origin.',
    ),
  ],
);

/// `ws-push-rejected`: the push still fails after one more merge.
const wsPushRejected = MessageDefinition(
  code: 'ws-push-rejected',
  level: MessageLevel.error,
  label: 'REJECTED',
  summary: 'The push still fails after one more merge.',
  description:
      'The remote refused the push (a protected branch, missing permission, '
      'the network, or commits pushed meanwhile). Your commits are safe on '
      'this machine. Repeat later, check your access, or put them on a '
      'branch of their own.',
  options: [
    MessageOption(
      'merge-branch',
      'Push your commits to ws-push/<host>/<yymmdd-hhmm> instead; merge later.',
    ),
    _skip,
  ],
);

/// `ws-fetch-failed`: the remote cannot be reached.
const wsFetchFailed = MessageDefinition(
  code: 'ws-fetch-failed',
  level: MessageLevel.error,
  label: 'FETCH FAILED',
  summary: 'The remote cannot be reached.',
  description:
      'Nothing was committed, merged or pushed for the repository. Repeat '
      'when the network is back, or check the remote URL.',
  options: [_skip],
);

/// `ws-binaries`: tom_binaries has uncommitted binaries.
const wsBinaries = MessageDefinition(
  code: 'ws-binaries',
  level: MessageLevel.warning,
  label: 'BINARIES',
  summary: 'tom_binaries has uncommitted binaries.',
  description:
      'Binaries are committed by the build (tom_push_binaries); :ws-push '
      'pushes tom_binaries only when it has local commits and otherwise '
      'leaves the files for the next build.',
  options: [
    MessageOption(
      'commit-binaries',
      'Commit and push them now, as :skill-push-binaries does.',
      repoList: false,
    ),
  ],
);

/// `ws-rescue-open`: `ws-push/*` branches on a remote that are not merged.
const wsRescueOpen = MessageDefinition(
  code: 'ws-rescue-open',
  level: MessageLevel.warning,
  label: 'RESCUE OPEN',
  summary: 'ws-push/* branches on the remote are not merged.',
  description:
      'An earlier :ws-push put commits there (--merge-branch, '
      '--rescue-detached). Merge them by hand (git merge origin/ws-push/...) '
      'and delete them; they are listed until then.',
);

/// `ws-upstream-dirty`: an upstream clone has local changes.
const wsUpstreamDirty = MessageDefinition(
  code: 'ws-upstream-dirty',
  level: MessageLevel.warning,
  label: 'UPSTREAM DIRTY',
  summary: 'An upstream clone has local changes.',
  description:
      'Upstreams (third-party projects pinned to a commit) are never '
      'committed or pushed; :ws-update leaves a dirty upstream off its pin '
      'and says so. Nothing is needed unless you want the changes gone.',
);

/// `ws-held`: (`:ws-update`) uncommitted files the merge would overwrite.
const wsHeld = MessageDefinition(
  code: 'ws-held',
  level: MessageLevel.error,
  label: 'HELD',
  summary:
      'Uncommitted files that the merge of origin/<branch> would overwrite.',
  description:
      'The repository was held: neither merged nor changed, so your '
      'uncommitted work is as you left it. Commit it first, stash it around '
      'the merge, or push it with :ws-push and update again.',
  options: [
    MessageOption(
      'commit-first',
      'Commit them (with -m, or "ws-update on <host> at <time>"), then merge.\n'
          'The commit is not pushed; :ws-push pushes it later.',
    ),
    MessageOption(
      'stash-merge',
      'Stash them, merge, and put them back; a conflict on the way back\n'
          'leaves them in the stash for you (git stash list).',
    ),
    _skip,
  ],
);

/// `ws-fork-diverged`: (`:ws-update`) a fork that cannot fast-forward.
const wsForkDiverged = MessageDefinition(
  code: 'ws-fork-diverged',
  level: MessageLevel.error,
  label: 'FORK DIVERGED',
  summary:
      'A fork has local commits and incoming ones: it cannot fast-forward.',
  description:
      'Forks follow their own branch and are only fast-forwarded, so a '
      'patch series stays as it was written. Nothing was changed. Merge like '
      'code if that is what you want, or rebase it by hand.',
  options: [
    MessageOption(
      'merge-fork',
      'Merge origin/<branch> into it like a code repository (a merge commit).',
    ),
    _skip,
  ],
);

/// `ws-clone-failed`: (`:ws-update`) a missing entry cannot be cloned.
const wsCloneFailed = MessageDefinition(
  code: 'ws-clone-failed',
  level: MessageLevel.error,
  label: 'CLONE FAILED',
  summary: 'A missing entry of repos.yaml could not be cloned.',
  description:
      'Check the URL in repos.yaml and your access to it (an SSH key, a '
      'token), then run :ws-update again.',
  options: [_skip],
);

/// `ws-move-blocked`: (`:ws-update`) a moved entry whose old checkout is
/// not clean or not pushed.
const wsMoveBlocked = MessageDefinition(
  code: 'ws-move-blocked',
  level: MessageLevel.error,
  label: 'MOVE BLOCKED',
  summary:
      'An entry moved in repos.yaml, but its old checkout is not clean or not '
      'fully pushed.',
  description:
      'Moving it would carry work that is on no remote. Run :ws-push first '
      '(with --include-unknown <repo> for the old checkout), then repeat.',
  options: [_skip],
);

/// `ws-unknown-seen`: (`:ws-update`) unknown clones exist.
const wsUnknownSeen = MessageDefinition(
  code: 'ws-unknown-seen',
  level: MessageLevel.warning,
  label: 'UNKNOWN CLONES',
  summary: 'A clone on disk that repos.yaml does not list.',
  description:
      ':ws-update leaves it alone. Update it for one run with '
      '--include-unknown, give it an entry, list it under unmanaged:, or '
      'remove it with :ws-repo-cleanup.',
  options: [
    MessageOption(
      'include-unknown',
      'Treat it as an entry for this run: bring its branch up to its own\n'
          'origin (merge origin/<branch>); nothing is pushed.',
    ),
  ],
);

/// `ws-surplus`: (`:ws-repo-cleanup`) a surplus clone that can be removed.
const wsSurplus = MessageDefinition(
  code: 'ws-surplus',
  level: MessageLevel.warning,
  label: 'SURPLUS',
  summary: 'A clone on disk that repos.yaml does not list, clean and pushed.',
  description:
      'Nothing would be lost by removing it: no uncommitted files, every '
      'commit on a remote branch, no stash. Without --apply it is only '
      'reported. Or give it an entry in repos.yaml, or list it under '
      'unmanaged:.',
  options: [
    MessageOption(
      'apply',
      'Move it to ztmp/<yymmdd>_ws_repo_cleanup/<path> under the root;\n'
          'delete that folder by hand once you are sure.',
      repoList: false,
    ),
    MessageOption(
      'delete',
      'Delete it at once (with or without --apply). Its commits stay on\n'
          'its remote; nothing local is kept.',
      repoList: false,
    ),
  ],
);

/// `ws-not-removable`: (`:ws-repo-cleanup`) a surplus clone with work that
/// would be lost, or with repositories inside it.
const wsNotRemovable = MessageDefinition(
  code: 'ws-not-removable',
  level: MessageLevel.error,
  label: 'NOT REMOVABLE',
  summary:
      'A surplus clone with uncommitted work, unpushed commits or stashes, or '
      'with repositories inside it.',
  description:
      'It stays where it is. Push its work first (buildkit :ws-push '
      '--include-unknown <repo>), give it an entry in repos.yaml, list it '
      'under unmanaged:, or move it anyway. A clone that holds an entry or '
      'another clone is never moved as a whole: deal with what is inside '
      'first.',
  options: [
    MessageOption(
      'force-remove',
      'Move it anyway to ztmp/<yymmdd>_ws_repo_cleanup/<path>, with its\n'
          'work; never deleted, even with --delete.',
    ),
    _skip,
  ],
);

/// The messages of `:ws-push`.
final wsPushMessages = MessageCatalog([
  wsActive,
  wsSecret,
  wsLarge,
  wsDriver,
  wsInProgress,
  wsManifest,
  wsUnknown,
  wsConflict,
  wsOffBranch,
  wsDetached,
  wsPushRejected,
  wsFetchFailed,
  wsBinaries,
  wsRescueOpen,
  wsUpstreamDirty,
]);

/// The messages of `:ws-update`.
final wsUpdateMessages = MessageCatalog([
  wsManifest,
  wsDriver,
  wsInProgress,
  wsHeld,
  wsConflict,
  wsOffBranch,
  wsDetached,
  wsForkDiverged,
  wsCloneFailed,
  wsMoveBlocked,
  wsFetchFailed,
  wsPushRejected,
  wsUpstreamDirty,
  wsUnknownSeen,
]);

/// The messages of `:ws-repo-cleanup`.
final wsRepoCleanupMessages = MessageCatalog([
  wsManifest,
  wsSurplus,
  wsNotRemovable,
]);

/// Every message of the `:ws-*` commands, once: their help topics.
final wsAllMessages = MessageCatalog(
  [
    for (final d in [
      ...wsPushMessages.definitions,
      ...wsUpdateMessages.definitions,
      ...wsRepoCleanupMessages.definitions,
    ])
      d,
  ].fold<List<MessageDefinition>>([], (list, d) {
    if (!list.any((x) => x.code == d.code)) list.add(d);
    return list;
  }),
);
