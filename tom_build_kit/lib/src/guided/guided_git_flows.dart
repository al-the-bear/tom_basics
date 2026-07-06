/// Interactive guided flows for the buildkit git commands (`-g` / `--guide`).
///
/// Each git command (`gitcommit`, `gitpull`, …) has a small **flow** that walks
/// the user through the relevant options with menus and prompts, then resolves
/// the answers into the exact command-line option flags the corresponding git
/// executor already understands. The dispatcher (`bin/buildkit.dart`) strips the
/// `-g` flag from the original argv, appends these resolved flags, and re-runs
/// the tool through `ToolRunner.runToCompletion` — so the guided flows reuse the
/// existing, tested per-repo git executors instead of duplicating git logic.
///
/// The design is deliberately I/O-free at the logic level: every prompt goes
/// through the injected [GuidedMode] (backed by a [PromptDriver]), so each flow
/// is unit-tested by driving a [ScriptedPromptDriver] and asserting the resolved
/// argument list. See `test/guided/guided_git_flows_test.dart`.
library;

import 'guided_mode.dart';

/// Resolves interactive git guided flows into command-line option flags.
///
/// Construct with a [GuidedMode] (real terminal in production, scripted in
/// tests) and call [resolve] with a canonical git command name. The returned
/// list contains **only the option flags** to append after the command (e.g.
/// `['--message', 'fix bug', '--push']`); it never includes the command itself.
///
/// A `null` return means the user cancelled at some step (or the command has no
/// guided flow), and the caller should abort without executing anything.
class GuidedGitFlows {
  /// Creates a flow resolver.
  ///
  /// [mode] defaults to a real-terminal [GuidedMode]; pass one wrapping a
  /// [ScriptedPromptDriver] in tests.
  GuidedGitFlows({GuidedMode? mode}) : _gm = mode ?? GuidedMode();

  final GuidedMode _gm;

  /// Canonical command names that have a guided flow, in menu order.
  static const List<String> supportedCommands = [
    'gitstatus',
    'gitcommit',
    'gitpull',
    'gitbranch',
    'gittag',
    'gitcheckout',
    'gitreset',
    'gitclean',
    'gitsync',
    'gitprune',
    'gitstash',
    'gitunstash',
    'gitcompare',
    'gitmerge',
    'gitsquash',
    'gitrebase',
  ];

  /// Whether [command] (canonical name) has a guided flow.
  static bool supports(String command) => supportedCommands.contains(command);

  /// Resolve the first supported guided git command from [typedCommands].
  ///
  /// [typedCommands] are the command tokens as typed (canonical name or alias,
  /// e.g. `gc`); [canonicalize] maps each to its canonical name (typically
  /// `(t) => tool.findCommand(t)?.name ?? t`). Returns the canonical name of the
  /// first token that has a guided flow, or `null` if none do.
  static String? targetCommand(
    Iterable<String> typedCommands,
    String Function(String) canonicalize,
  ) {
    for (final typed in typedCommands) {
      final canonical = canonicalize(typed);
      if (supports(canonical)) return canonical;
    }
    return null;
  }

  /// Rewrite [normalizedArgs] for a resolved guided invocation.
  ///
  /// Strips the guide flag (`-g` / `--guide`) — so the re-dispatched run is not
  /// itself treated as guided — and appends the gathered option [flags]. Every
  /// other token (the `:command`, navigation flags such as `-i`/`-o`, global
  /// flags like `--dry-run`) is preserved in order.
  static List<String> rewriteArgs(List<String> normalizedArgs,
      List<String> flags) {
    return <String>[
      for (final arg in normalizedArgs)
        if (arg != '-g' && arg != '--guide') arg,
      ...flags,
    ];
  }

  /// Run the guided flow for [command] and return the resolved option flags.
  ///
  /// Returns `null` if the user cancels, if the flow is declined at the final
  /// confirmation gate, or if [command] has no guided flow.
  List<String>? resolve(String command) {
    final builder = _builderFor(command);
    if (builder == null) return null;

    final args = builder();
    if (args == null) return null; // cancelled mid-flow

    // Final confirmation gate — preview the resolved command and require an
    // explicit yes before the caller executes it (matches doc/git_guide_mode.md).
    final preview = [command, ...args].join(' ');
    _gm.showPreview(command: preview);
    if (!_gm.confirm('Proceed?')) return null;

    return args;
  }

  List<String>? Function()? _builderFor(String command) {
    switch (command) {
      case 'gitstatus':
        return _gitstatus;
      case 'gitcommit':
        return _gitcommit;
      case 'gitpull':
        return _gitpull;
      case 'gitbranch':
        return _gitbranch;
      case 'gittag':
        return _gittag;
      case 'gitcheckout':
        return _gitcheckout;
      case 'gitreset':
        return _gitreset;
      case 'gitclean':
        return _gitclean;
      case 'gitsync':
        return _gitsync;
      case 'gitprune':
        return _gitprune;
      case 'gitstash':
        return _gitstash;
      case 'gitunstash':
        return _gitunstash;
      case 'gitcompare':
        return _gitcompare;
      case 'gitmerge':
        return _gitmerge;
      case 'gitsquash':
        return _gitsquash;
      case 'gitrebase':
        return _gitrebase;
      default:
        return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────
  // Per-command flows. Each returns the option flags to append, or null on
  // cancellation. Flows must not perform git or filesystem side-effects — they
  // only gather choices and map them to flags.
  // ───────────────────────────────────────────────────────────────────────

  List<String>? _gitstatus() {
    _gm.header('Git Status — Guided Mode');
    final view = _gm.menu('What would you like to see?', [
      'Quick overview',
      'Detailed with files',
    ]);
    if (view == -1) return null;

    final args = <String>[];
    if (view == 1) args.add('--details');
    if (_gm.confirm('Show stash information?', defaultYes: false)) {
      args.add('--stash');
    }
    if (_gm.confirm('Skip fetching from remote first?', defaultYes: false)) {
      args.add('--no-fetch');
    }
    return args;
  }

  List<String>? _gitcommit() {
    _gm.header('Git Commit — Guided Mode');

    final stage = _gm.menu('What files to stage?', [
      'All modified files (git add -A)',
      'Only already-staged files',
    ]);
    if (stage == -1) return null;
    final stageAll = stage == 0;

    final action = _gm.menu('Commit action?', [
      'Commit and push',
      'Commit only (no push)',
      'Amend previous commit',
    ]);
    if (action == -1) return null;

    final args = <String>[];

    // Amend does not take a message (the executor amends with --no-edit).
    if (action == 2) {
      args.add('--amend');
      if (stageAll) args.add('--all');
      return args;
    }

    final message = _gm.input(
      'Commit message',
      validator: (v) => v.trim().isNotEmpty,
      validationError: 'Commit message cannot be empty.',
    );
    args.addAll(['--message', message]);
    if (stageAll) args.add('--all');
    if (action == 0) args.add('--push');
    return args;
  }

  List<String>? _gitpull() {
    _gm.header('Git Pull — Guided Mode');
    final strategy = _gm.menu('Pull strategy?', [
      'Fast-forward only (safe)',
      'Allow merge commits',
      'Rebase instead of merge',
    ]);
    switch (strategy) {
      case -1:
        return null;
      case 0:
        return ['--ff-only'];
      case 2:
        return ['--rebase'];
      default:
        return <String>[];
    }
  }

  List<String>? _gitbranch() {
    _gm.header('Git Branch — Guided Mode');
    final action = _gm.menu('What would you like to do?', [
      'List branches',
      'Create new branch',
      'Delete branch',
    ]);
    switch (action) {
      case -1:
        return null;
      case 0:
        return _gm.confirm('Include remote branches?', defaultYes: false)
            ? ['--all']
            : <String>[];
      case 1:
        final name = _gm.input(
          'New branch name',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Branch name cannot be empty.',
        );
        return ['--create', name];
      case 2:
        final name = _gm.input(
          'Branch to delete',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Branch name cannot be empty.',
        );
        return ['--delete', name];
      default:
        return null;
    }
  }

  List<String>? _gittag() {
    _gm.header('Git Tag — Guided Mode');
    final action = _gm.menu('What would you like to do?', [
      'List tags',
      'Create tag',
      'Delete tag',
    ]);
    switch (action) {
      case -1:
        return null;
      case 0:
        return <String>[];
      case 1:
        final name = _gm.input(
          'Tag name',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Tag name cannot be empty.',
        );
        final args = ['--create', name];
        if (_gm.confirm('Annotated tag (add a message)?', defaultYes: true)) {
          final msg = _gm.input(
            'Tag message',
            validator: (v) => v.trim().isNotEmpty,
            validationError: 'Tag message cannot be empty.',
          );
          args.addAll(['--message', msg]);
        }
        if (_gm.confirm('Push tag to remote?', defaultYes: false)) {
          args.add('--push');
        }
        return args;
      case 2:
        final name = _gm.input(
          'Tag to delete',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Tag name cannot be empty.',
        );
        return ['--delete', name];
      default:
        return null;
    }
  }

  List<String>? _gitcheckout() {
    _gm.header('Git Checkout — Guided Mode');
    final kind = _gm.menu('What would you like to checkout?', [
      'Existing branch',
      'New branch from current',
    ]);
    if (kind == -1) return null;
    final name = _gm.input(
      'Branch name',
      validator: (v) => v.trim().isNotEmpty,
      validationError: 'Branch name cannot be empty.',
    );
    final args = ['--branch', name];
    if (kind == 1) args.add('--create');
    return args;
  }

  List<String>? _gitreset() {
    _gm.header('Git Reset — Guided Mode');
    _gm.warning('Reset can discard work — review carefully.');
    final kind = _gm.menu('Reset type?', [
      'Mixed — unstage changes, keep working dir',
      'Soft — keep staged and working changes',
      'Hard — discard ALL changes (DANGER)',
    ]);
    if (kind == -1) return null;

    final args = <String>[];
    if (kind == 1) args.add('--soft');
    if (kind == 2) {
      args.add('--hard');
      if (!_gm.confirm(
        'Hard reset permanently discards all changes. Continue?',
        defaultYes: false,
      )) {
        return null;
      }
    }

    final target = _gm.menu('Reset to?', [
      'HEAD (current commit)',
      'HEAD~1 (previous commit)',
      'Specific commit/ref',
    ]);
    switch (target) {
      case -1:
        return null;
      case 1:
        args.addAll(['--to', 'HEAD~1']);
      case 2:
        final ref = _gm.input(
          'Commit/ref to reset to',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Ref cannot be empty.',
        );
        args.addAll(['--to', ref]);
      default:
        break; // HEAD → no --to
    }
    return args;
  }

  List<String>? _gitclean() {
    _gm.header('Git Clean — Guided Mode');
    _gm.warning('This permanently deletes untracked files.');
    final scope = _gm.menu('What to remove?', [
      'Untracked files only',
      'Untracked files and directories',
    ]);
    if (scope == -1) return null;

    if (!_gm.confirm(
      'Permanently delete untracked files? (run with --dry-run first to preview)',
      defaultYes: false,
    )) {
      return null;
    }

    final args = ['--force'];
    if (scope == 1) args.add('--directories');
    return args;
  }

  List<String>? _gitsync() {
    _gm.header('Git Sync — Guided Mode');
    final strategy = _gm.menu('Sync strategy (fetch + pull)?', [
      'Merge',
      'Rebase',
    ]);
    switch (strategy) {
      case -1:
        return null;
      case 1:
        return ['--rebase'];
      default:
        return <String>[];
    }
  }

  List<String>? _gitprune() {
    _gm.header('Git Prune — Guided Mode');
    final remote = _gm.input('Remote to prune', defaultValue: 'origin');
    final effective = remote.trim().isEmpty ? 'origin' : remote.trim();
    return ['--remote', effective];
  }

  List<String>? _gitstash() {
    _gm.header('Git Stash — Guided Mode');
    final action = _gm.menu('What would you like to stash?', [
      'Tracked changes',
      'With a message',
      'Include untracked files',
    ]);
    switch (action) {
      case -1:
        return null;
      case 0:
        return <String>[];
      case 1:
        final msg = _gm.input(
          'Stash message',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Stash message cannot be empty.',
        );
        return ['--message', msg];
      case 2:
        return ['--include-untracked'];
      default:
        return null;
    }
  }

  List<String>? _gitunstash() {
    _gm.header('Git Unstash — Guided Mode');
    final action = _gm.menu('What would you like to do?', [
      'Apply most recent stash',
      'Pop most recent (apply and drop)',
      'Apply a specific stash',
    ]);
    switch (action) {
      case -1:
        return null;
      case 0:
        return <String>[];
      case 1:
        return ['--pop'];
      case 2:
        final index = _gm.input(
          'Stash index (e.g. 0)',
          validator: (v) => int.tryParse(v.trim()) != null,
          validationError: 'Enter a numeric stash index.',
        );
        return ['--index', index.trim()];
      default:
        return null;
    }
  }

  List<String>? _gitcompare() {
    _gm.header('Git Compare — Guided Mode');
    final base = _gm.input('Base branch/ref to compare against',
        defaultValue: 'main');
    final effective = base.trim().isEmpty ? 'main' : base.trim();
    final format = _gm.menu('How to display differences?', [
      'Short summary',
      'Full diffstat',
    ]);
    switch (format) {
      case -1:
        return null;
      case 1:
        return ['--base', effective, '--stat'];
      default:
        return ['--base', effective];
    }
  }

  List<String>? _gitmerge() {
    _gm.header('Git Merge — Guided Mode');
    final branch = _gm.input(
      'Branch to merge from',
      validator: (v) => v.trim().isNotEmpty,
      validationError: 'Branch name cannot be empty.',
    );
    final strategy = _gm.menu('Merge strategy?', [
      'Standard merge',
      'Squash commits',
      'No fast-forward (always create merge commit)',
    ]);
    switch (strategy) {
      case -1:
        return null;
      case 1:
        return ['--branch', branch, '--squash'];
      case 2:
        return ['--branch', branch, '--no-ff'];
      default:
        return ['--branch', branch];
    }
  }

  List<String>? _gitsquash() {
    _gm.header('Git Squash — Guided Mode');
    final count = _gm.input(
      'Number of commits to squash (>= 2)',
      validator: (v) {
        final n = int.tryParse(v.trim());
        return n != null && n >= 2;
      },
      validationError: 'Enter a whole number >= 2.',
    );
    final args = ['--count', count.trim()];
    if (_gm.confirm('Provide a squash commit message?', defaultYes: true)) {
      final msg = _gm.input(
        'Squash commit message',
        validator: (v) => v.trim().isNotEmpty,
        validationError: 'Message cannot be empty.',
      );
      args.addAll(['--message', msg]);
    }
    return args;
  }

  List<String>? _gitrebase() {
    _gm.header('Git Rebase — Guided Mode');
    _gm.warning('Rebase rewrites history — only rebase unpushed commits.');
    final action = _gm.menu('What would you like to do?', [
      'Rebase onto another branch',
      'Interactive rebase',
      'Abort in-progress rebase',
      'Continue after resolving conflicts',
    ]);
    switch (action) {
      case -1:
        return null;
      case 0:
        final onto = _gm.input(
          'Rebase onto branch',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Branch name cannot be empty.',
        );
        return ['--onto', onto];
      case 1:
        final onto = _gm.input(
          'Rebase onto branch',
          validator: (v) => v.trim().isNotEmpty,
          validationError: 'Branch name cannot be empty.',
        );
        return ['--onto', onto, '--interactive'];
      case 2:
        return ['--abort'];
      case 3:
        return ['--continue'];
      default:
        return null;
    }
  }
}
