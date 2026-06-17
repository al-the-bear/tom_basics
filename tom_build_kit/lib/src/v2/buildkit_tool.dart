/// Buildkit v2 — Build orchestration tool using tom_build_base v2.
///
/// This file defines the buildkit tool using the v2 CLI framework.
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

import '../version.versioner.dart';

// =============================================================================
// Common Options
// =============================================================================

/// Options for versioner command.
const versionerOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'output',
    abbr: 'O',
    description: 'Output file path relative to project',
    defaultValue: 'lib/src/version.versioner.dart',
    valueName: 'path',
  ),
  OptionDefinition.flag(
    name: 'no-git',
    description: 'Skip git commit hash in version file',
  ),
  OptionDefinition.option(
    name: 'version',
    description: 'Override version string (instead of pubspec.yaml)',
    valueName: 'version',
  ),
  OptionDefinition.option(
    name: 'variable-prefix',
    description:
        'Prefix for generated class name (e.g., "myApp" → MyAppVersionInfo)',
    valueName: 'name',
  ),
];

/// Options for bumpversion command.
const bumpversionOptions = <OptionDefinition>[
  OptionDefinition.multi(
    name: 'minor',
    description: 'Projects to bump minor version (comma-separated or repeated)',
    valueName: 'projects',
  ),
  OptionDefinition.multi(
    name: 'major',
    description: 'Projects to bump major version (comma-separated or repeated)',
    valueName: 'projects',
  ),
  OptionDefinition.flag(
    name: 'versioner',
    description: 'Run versioner after bumping to regenerate version files',
  ),
];

/// Options for bumppubspec command.
const bumppubspecOptions = <OptionDefinition>[
  OptionDefinition.multi(
    name: 'refs',
    description:
        'Package names to update (comma-separated or repeated); defaults to auto-discovery',
    valueName: 'package',
  ),
  OptionDefinition.flag(
    name: 'replace-any',
    description: 'Replace "any" dependency constraints',
  ),
  OptionDefinition.flag(
    name: 'replace-path',
    description: 'Replace path: dependencies with concrete versions',
  ),
  OptionDefinition.flag(
    name: 'replace-git',
    description: 'Replace git: dependencies with concrete versions',
  ),
];

/// Options for compiler command.
const compilerOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'all-platforms',
    description:
        'Compile all configured targets for the current build platform',
  ),
  OptionDefinition.multi(
    name: 'targets',
    abbr: 't',
    description: 'Target platform(s) filter (e.g., linux-x64,darwin-arm64)',
    valueName: 'platform',
  ),
  OptionDefinition.multi(
    name: 'executable',
    abbr: 'e',
    description:
        'Executable file(s) filter (e.g., buildkit.dart,compiler.dart)',
    valueName: 'file',
  ),
];

/// Options for runner command.
const runnerOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'command',
    abbr: 'c',
    description: 'Build runner command (build, watch, clean)',
    valueName: 'cmd',
  ),
  OptionDefinition.multi(
    name: 'include-builders',
    abbr: 'I',
    description: 'Only run these builders',
    valueName: 'builder',
  ),
  OptionDefinition.multi(
    name: 'exclude-builders',
    description: 'Exclude these builders',
    valueName: 'builder',
  ),
  OptionDefinition.option(
    name: 'config',
    description: 'Build config name',
    valueName: 'name',
  ),
  OptionDefinition.flag(name: 'release', description: 'Build in release mode'),
  OptionDefinition.flag(
    name: 'delete-conflicting',
    description: 'Delete conflicting outputs without prompting',
  ),
];

/// Options for cleanup command.
const cleanupOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'force',
    abbr: 'f',
    description: 'Skip safety check on file count',
  ),
  OptionDefinition.option(
    name: 'max-files',
    abbr: 'M',
    description: 'Maximum files to delete without --force (default: 100)',
    valueName: 'count',
  ),
];

/// Options for dependencies command.
const dependenciesOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'dev',
    abbr: 'd',
    description: 'Show dev dependencies only',
  ),
  OptionDefinition.flag(
    name: 'all',
    abbr: 'a',
    description: 'Show all dependencies (normal + dev)',
  ),
  OptionDefinition.flag(
    name: 'deep',
    abbr: 'D',
    description: 'Show recursive dependency tree',
  ),
];

/// Options for publisher command.
const publisherOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'show-all',
    abbr: 'a',
    description: 'Include projects with publish_to: none',
  ),
  OptionDefinition.flag(
    name: 'fix',
    abbr: 'f',
    description: 'Attempt to fix common publishing issues',
  ),
];

/// Options for pubget/pubupdate commands.
const pubOptions = <OptionDefinition>[
  OptionDefinition.flag(name: 'offline', description: 'Use cached packages'),
];

/// Options for status command.
const statusOptions = <OptionDefinition>[
  OptionDefinition.flag(name: 'json', description: 'Output in JSON format'),
  OptionDefinition.flag(
    name: 'skip-binaries',
    description: 'Skip binary version checks',
  ),
  OptionDefinition.flag(
    name: 'skip-git',
    description: 'Skip git status checks',
  ),
];

// =============================================================================
// Git Command Options
// =============================================================================

/// Options for gitstatus command.
const gitstatusOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'details',
    abbr: 'd',
    description: 'Show detailed status information',
  ),
  OptionDefinition.flag(
    name: 'no-fetch',
    description: 'Skip fetching from remote before status',
  ),
  OptionDefinition.flag(name: 'stash', description: 'Show stash information'),
];

/// Options for gitcommit command.
const gitcommitOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'message',
    abbr: 'm',
    description: 'Commit message',
    valueName: 'msg',
  ),
  OptionDefinition.flag(name: 'amend', description: 'Amend last commit'),
  OptionDefinition.flag(name: 'push', description: 'Push after commit'),
  OptionDefinition.flag(
    name: 'all',
    abbr: 'a',
    description: 'Stage all modified files',
  ),
];

/// Options for gitpull command.
const gitpullOptions = <OptionDefinition>[
  OptionDefinition.flag(name: 'rebase', description: 'Rebase instead of merge'),
  OptionDefinition.flag(name: 'ff-only', description: 'Fast-forward only'),
];

/// Options for gitbranch command.
const gitbranchOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'create',
    abbr: 'c',
    description: 'Create new branch',
    valueName: 'name',
  ),
  OptionDefinition.option(
    name: 'delete',
    abbr: 'd',
    description: 'Delete branch',
    valueName: 'name',
  ),
  OptionDefinition.flag(
    name: 'all',
    abbr: 'a',
    description: 'Show all branches (including remotes)',
  ),
];

/// Options for gittag command.
const gittagOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'create',
    abbr: 'c',
    description: 'Create new tag',
    valueName: 'name',
  ),
  OptionDefinition.option(
    name: 'message',
    abbr: 'm',
    description: 'Tag message (creates annotated tag)',
    valueName: 'msg',
  ),
  OptionDefinition.option(
    name: 'delete',
    abbr: 'd',
    description: 'Delete tag',
    valueName: 'name',
  ),
  OptionDefinition.flag(name: 'push', description: 'Push tags after creating'),
];

/// Options for gitcheckout command.
const gitcheckoutOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'branch',
    abbr: 'b',
    description: 'Branch to checkout',
    valueName: 'name',
  ),
  OptionDefinition.flag(
    name: 'create',
    abbr: 'c',
    description: 'Create branch if it doesn\'t exist',
  ),
];

/// Options for gitreset command.
const gitresetOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'hard',
    description: 'Hard reset (discard changes)',
  ),
  OptionDefinition.flag(
    name: 'soft',
    description: 'Soft reset (keep changes staged)',
  ),
  OptionDefinition.option(
    name: 'to',
    description: 'Reset to specific commit/ref',
    valueName: 'ref',
  ),
];

/// Options for gitclean command.
const gitcleanOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'directories',
    abbr: 'd',
    description: 'Remove untracked directories too',
  ),
  OptionDefinition.flag(name: 'force', abbr: 'f', description: 'Force removal'),
];

/// Options for gitsync command.
const gitsyncOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'rebase',
    description: 'Rebase instead of merge when pulling',
  ),
];

/// Options for gitprune command.
const gitpruneOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'remote',
    description: 'Remote to prune (default: origin)',
    valueName: 'name',
  ),
];

/// Options for gitstash command.
const gitstashOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'message',
    abbr: 'm',
    description: 'Stash message',
    valueName: 'msg',
  ),
  OptionDefinition.flag(
    name: 'include-untracked',
    abbr: 'u',
    description: 'Include untracked files',
  ),
];

/// Options for gitunstash command.
const gitunstashOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'pop',
    description: 'Pop stash (remove after applying)',
  ),
  OptionDefinition.option(
    name: 'index',
    description: 'Stash index to restore',
    valueName: 'n',
  ),
];

/// Options for gitcompare command.
const gitcompareOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'base',
    description: 'Base branch/ref to compare against',
    valueName: 'ref',
  ),
  OptionDefinition.flag(name: 'stat', description: 'Show diffstat only'),
];

/// Options for gitmerge command.
const gitmergeOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'branch',
    abbr: 'b',
    description: 'Branch to merge from',
    valueName: 'name',
  ),
  OptionDefinition.flag(
    name: 'no-ff',
    description: 'Create merge commit even for fast-forward',
  ),
  OptionDefinition.flag(
    name: 'squash',
    description: 'Squash commits before merging',
  ),
];

/// Options for gitsquash command.
const gitsquashOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'count',
    abbr: 'n',
    description: 'Number of commits to squash',
    valueName: 'n',
  ),
  OptionDefinition.option(
    name: 'message',
    abbr: 'm',
    description: 'Squash commit message',
    valueName: 'msg',
  ),
];

/// Options for gitrebase command.
const gitrebaseOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'onto',
    description: 'Rebase onto branch',
    valueName: 'branch',
  ),
  OptionDefinition.flag(
    name: 'interactive',
    abbr: 'i',
    description: 'Interactive rebase',
  ),
  OptionDefinition.flag(
    name: 'continue',
    description: 'Continue rebase after resolving conflicts',
  ),
  OptionDefinition.flag(name: 'abort', description: 'Abort rebase'),
];

/// Options for git passthrough command.
const gitOptions = <OptionDefinition>[
  // Git passthrough takes all arguments after --
];

// =============================================================================
// Other Command Options
// =============================================================================

/// Options for buildsorter command.
const buildsorterOptions = <OptionDefinition>[
  OptionDefinition.flag(
    name: 'reverse',
    description: 'Show reverse build order',
  ),
  OptionDefinition.flag(
    name: 'names',
    description: 'Show package names instead of paths',
  ),
  OptionDefinition.flag(
    name: 'include-dev',
    description: 'Include dev_dependencies in the graph',
  ),
];

/// Options for execute command.
const executeOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'condition',
    abbr: 'c',
    description:
        'Boolean placeholder condition to filter folders (e.g., dart.exists)',
    valueName: 'placeholder',
  ),
  OptionDefinition.flag(
    name: 'summary',
    abbr: 'S',
    description: 'Print a summary of executed commands with project names',
  ),
];

/// Options for dcli command.
const dcliOptions = <OptionDefinition>[
  OptionDefinition.option(
    name: 'init-source',
    description: 'Custom init source file',
    valueName: 'file',
  ),
  OptionDefinition.flag(
    name: 'no-init-source',
    description: 'Skip loading init source',
  ),
];

/// Options for findproject command.
const findProjectOptions = <OptionDefinition>[];

// =============================================================================
// Command Definitions - Build Tools
// =============================================================================

const versionerCommand = CommandDefinition(
  name: 'versioner',
  description: 'Generate version.versioner.dart files with build metadata',
  aliases: ['v', 'ver'],
  options: versionerOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: [
    'buildkit :versioner',
    'buildkit :versioner --output lib/src/version.versioner.dart',
    'buildkit :versioner --variable-prefix myApp',
  ],
);

const bumpversionCommand = CommandDefinition(
  name: 'bumpversion',
  description: 'Bump pubspec.yaml versions across projects',
  aliases: ['bump'],
  options: bumpversionOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: false,
  canRunStandalone: true,
  examples: ['buildkit :bumpversion --type=minor', 'bumpversion --set=2.0.0'],
);

const bumppubspecCommand = CommandDefinition(
  name: 'bumppubspec',
  description: 'Update package version references in pubspec.yaml files',
  aliases: ['bumprefs'],
  options: bumppubspecOptions,
  worksWithNatures: {DartProjectFolder},
  requiresTraversal: false,
  supportsProjectTraversal: true,
  examples: [
    'buildkit -s . -r :bumppubspec',
    'bumppubspec --refs tom_build_base --replace-path',
  ],
);

const compilerCommand = CommandDefinition(
  name: 'compiler',
  description: 'Cross-platform Dart compilation',
  aliases: ['c', 'comp'],
  options: compilerOptions,
  worksWithNatures: {DartConsoleFolder, BuildkitFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: [
    'buildkit :compiler',
    'buildkit :compiler --all-platforms',
    'buildkit :compiler --targets=linux-x64,darwin-arm64',
    'buildkit :compiler --executable=buildkit.dart,compiler.dart',
    'buildkit :compiler -e buildkit.dart -t linux-x64',
  ],
);

const runnerCommand = CommandDefinition(
  name: 'runner',
  description: 'Build_runner wrapper with builder filtering',
  aliases: ['run'],
  options: runnerOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: [
    'buildkit :runner',
    'buildkit :runner --command=watch',
    'buildkit :runner --include-builders=freezed',
  ],
);

const cleanupCommand = CommandDefinition(
  name: 'cleanup',
  description: 'Clean generated and temporary files',
  aliases: ['clean', 'cl'],
  options: cleanupOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: [
    'buildkit :cleanup',
    'buildkit :cleanup --force',
    'buildkit :cleanup --max-files=200',
  ],
);

const dependenciesCommand = CommandDefinition(
  name: 'dependencies',
  description: 'Dependency tree visualization',
  aliases: ['deps'],
  options: dependenciesOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: [
    'buildkit :dependencies',
    'buildkit :deps --dev',
    'buildkit :deps --deep',
  ],
);

const publisherCommand = CommandDefinition(
  name: 'publisher',
  description: 'Show publishing status for all projects',
  aliases: ['pub'],
  options: publisherOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :publisher', 'buildkit :publisher --show-all'],
);

const statusCommand = CommandDefinition(
  name: 'status',
  description: 'Show buildkit version, binary status, and git state',
  aliases: [],
  options: statusOptions,
  worksWithNatures: {DartProjectFolder},
  requiresTraversal: false,
  supportsProjectTraversal: true,
  examples: ['buildkit :status', 'status --json --skip-git'],
);

const pubgetCommand = CommandDefinition(
  name: 'pubget',
  description: 'Run dart/flutter pub get on projects',
  aliases: ['pg'],
  options: pubOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  examples: ['buildkit :pubget'],
);

const pubgetallCommand = CommandDefinition(
  name: 'pubgetall',
  description: 'Shortcut for :pubget (defaults to recursive)',
  aliases: ['pga'],
  options: pubOptions,
  worksWithNatures: {DartProjectFolder},
  requiresTraversal: true,
  supportsProjectTraversal: true,
  examples: ['buildkit :pubgetall'],
);

const pubupdateCommand = CommandDefinition(
  name: 'pubupdate',
  description: 'Run dart/flutter pub upgrade on projects',
  aliases: ['pu'],
  options: pubOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: true,
  examples: ['buildkit :pubupdate'],
);

const pubupdateallCommand = CommandDefinition(
  name: 'pubupdateall',
  description: 'Shortcut for :pubupdate (defaults to recursive)',
  aliases: ['pua'],
  options: pubOptions,
  worksWithNatures: {DartProjectFolder},
  requiresTraversal: true,
  supportsProjectTraversal: true,
  examples: ['buildkit :pubupdateall'],
);

const buildsorterCommand = CommandDefinition(
  name: 'buildsorter',
  description: 'Show projects in dependency build order',
  aliases: ['sort'],
  options: buildsorterOptions,
  worksWithNatures: {DartProjectFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: false,
  canRunStandalone: true,
  examples: ['buildkit :buildsorter'],
);

const executeCommand = CommandDefinition(
  name: 'execute',
  description:
      'Execute shell command in each traversed folder with placeholder support',
  aliases: ['exec', 'x'],
  options: executeOptions,
  worksWithNatures: {FsFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: true,
  requiresTraversal: true,
  canRunStandalone: false,
  examples: [
    'buildkit :execute echo %{folder.name}',
    'buildkit :execute --condition dart.exists dart pub get',
    'buildkit :execute --condition dart.exists echo %{dart.publishable?(Publishable):(Not publishable)}',
    'buildkit -g :execute --condition git.exists git status',
  ],
);

// =============================================================================
// Command Definitions - Git Tools
// =============================================================================

const gitCommand = CommandDefinition(
  name: 'git',
  description: 'Run git commands in each repository',
  aliases: [],
  options: gitOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: null, // User must specify -i or -o
  requiresTraversal: true,
  canRunStandalone: true,
  examples: [
    'buildkit :git -i -- log --oneline -5',
    'buildkit :git -o -- stash list',
  ],
);

const gitstatusCommand = CommandDefinition(
  name: 'gitstatus',
  description: 'Show git status for all repositories',
  aliases: ['gs'],
  options: gitstatusOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst,
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitstatus', 'gitstatus --short'],
);

const gitcommitCommand = CommandDefinition(
  name: 'gitcommit',
  description: 'Commit and push all repositories',
  aliases: ['gc'],
  options: gitcommitOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitcommit -m "feat: add feature"', 'gitcommit --amend'],
);

const gitpullCommand = CommandDefinition(
  name: 'gitpull',
  description: 'Pull latest from all repositories',
  aliases: ['gpl'],
  options: gitpullOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.outerFirst, // Fixed: outer first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitpull', 'gitpull --rebase'],
);

const gitbranchCommand = CommandDefinition(
  name: 'gitbranch',
  description: 'Branch management across repositories',
  aliases: ['gb'],
  options: gitbranchOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitbranch', 'gitbranch --create feature-x'],
);

const gittagCommand = CommandDefinition(
  name: 'gittag',
  description: 'Tag management across repositories',
  aliases: ['gt'],
  options: gittagOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gittag', 'gittag --create v1.0.0 --push'],
);

const gitcheckoutCommand = CommandDefinition(
  name: 'gitcheckout',
  description: 'Checkout branches/tags across repositories',
  aliases: ['gco'],
  options: gitcheckoutOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.outerFirst, // Fixed: outer first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitcheckout --branch=main'],
);

const gitresetCommand = CommandDefinition(
  name: 'gitreset',
  description: 'Reset repositories to specific state',
  aliases: ['grst'],
  options: gitresetOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.outerFirst, // Fixed: outer first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitreset --hard'],
);

const gitcleanCommand = CommandDefinition(
  name: 'gitclean',
  description: 'Clean untracked files from repositories',
  aliases: ['gcl'],
  options: gitcleanOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitclean -df'],
);

const gitsyncCommand = CommandDefinition(
  name: 'gitsync',
  description: 'Sync (fetch + merge/rebase) all repositories',
  aliases: ['gsync'],
  options: gitsyncOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.outerFirst, // Fixed: outer first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitsync'],
);

const gitpruneCommand = CommandDefinition(
  name: 'gitprune',
  description: 'Remove stale remote-tracking branches',
  aliases: ['gpr'],
  options: gitpruneOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.outerFirst, // Fixed: outer first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitprune'],
);

const gitstashCommand = CommandDefinition(
  name: 'gitstash',
  description: 'Stash uncommitted changes across repositories',
  aliases: ['gst'],
  options: gitstashOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitstash -m "wip"'],
);

const gitunstashCommand = CommandDefinition(
  name: 'gitunstash',
  description: 'Restore stashed changes across repositories',
  aliases: ['gust'],
  options: gitunstashOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.outerFirst, // Fixed: outer first (reverse)
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitunstash --pop'],
);

const gitcompareCommand = CommandDefinition(
  name: 'gitcompare',
  description: 'Compare branches across repositories',
  aliases: ['gcmp'],
  options: gitcompareOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitcompare --base=main'],
);

const gitmergeCommand = CommandDefinition(
  name: 'gitmerge',
  description: 'Merge branches across repositories',
  aliases: ['gm'],
  options: gitmergeOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitmerge --branch=feature-x'],
);

const gitsquashCommand = CommandDefinition(
  name: 'gitsquash',
  description: 'Squash commits across repositories',
  aliases: ['gsq'],
  options: gitsquashOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitsquash -n 3 -m "combined commit"'],
);

const gitrebaseCommand = CommandDefinition(
  name: 'gitrebase',
  description: 'Rebase across repositories',
  aliases: ['grb'],
  options: gitrebaseOptions,
  worksWithNatures: {GitFolder},
  supportsProjectTraversal: false,
  supportsGitTraversal: true,
  requiresGitTraversal: true,
  defaultGitOrder: GitTraversalOrder.innerFirst, // Fixed: inner first
  requiresTraversal: true,
  canRunStandalone: true,
  examples: ['buildkit :gitrebase --onto=main'],
);

// =============================================================================
// Command Definitions - Other
// =============================================================================

const findProjectCommand = CommandDefinition(
  name: 'findproject',
  description: 'Resolve project by name/ID/folder and print its path',
  aliases: ['fp'],
  options: findProjectOptions,
  worksWithNatures: {DartProjectFolder},
  requiresTraversal: false,
  supportsProjectTraversal: false,
  supportsGitTraversal: false,
  canRunStandalone: true,
  examples: [
    'buildkit :findproject tom_build_kit',
    'findproject buildkit',
    'findproject "Tom Build Kit"',
    r'goto() { local d; d="$(findproject "$@" 2>/dev/null)"; if [[ -n "$d" && -d "$d" ]]; then cd "$d"; else findproject "$@"; return 1; fi; }',
  ],
);

const dcliCommand = CommandDefinition(
  name: 'dcli',
  description: 'Execute Dart scripts via dcli',
  aliases: [],
  options: dcliOptions,
  worksWithNatures: {FsFolder},
  supportsProjectTraversal: true,
  supportsGitTraversal: false,
  requiresTraversal: false,
  examples: [
    'buildkit :dcli ~s/build_hook.dart',
    'buildkit :dcli "print(DateTime.now())"',
  ],
);

// =============================================================================
// Tool Definition
// =============================================================================

/// Buildkit tool definition.
final buildkitTool = ToolDefinition(
  name: 'buildkit',
  description: 'Pipeline-based build orchestration tool',
  version: BuildkitVersionInfo.version,
  versionString: 'BuildKit ${BuildkitVersionInfo.versionLong}',
  mode: ToolMode.multiCommand,
  wiringFile: ToolDefinition.kAutoWiringFile,
  helpTopics: defaultHelpTopics,
  features: const NavigationFeatures(
    projectTraversal: true,
    gitTraversal: true,
    recursiveScan: true,
    interactiveMode: false,
    dryRun: true,
    jsonOutput: false,
    verbose: true,
  ),
  globalOptions: const [
    OptionDefinition.flag(
      name: 'list',
      abbr: 'l',
      description: 'List available pipelines and commands',
    ),
    OptionDefinition.flag(
      name: 'workspace-recursion',
      abbr: 'w',
      description: 'Shell out to sub-workspaces instead of skipping',
    ),
  ],
  commands: [
    // Build tools
    versionerCommand,
    bumpversionCommand,
    bumppubspecCommand,
    compilerCommand,
    runnerCommand,
    cleanupCommand,
    dependenciesCommand,
    publisherCommand,
    statusCommand,
    buildsorterCommand,
    executeCommand,
    // Pub commands
    pubgetCommand,
    pubgetallCommand,
    pubupdateCommand,
    pubupdateallCommand,
    // Git tools
    gitCommand,
    gitstatusCommand,
    gitcommitCommand,
    gitpullCommand,
    gitbranchCommand,
    gittagCommand,
    gitcheckoutCommand,
    gitresetCommand,
    gitcleanCommand,
    gitsyncCommand,
    gitpruneCommand,
    gitstashCommand,
    gitunstashCommand,
    gitcompareCommand,
    gitmergeCommand,
    gitsquashCommand,
    gitrebaseCommand,
    // Other
    findProjectCommand,
    dcliCommand,
  ],
  helpFooter: '''
Execution Modes:
  Project Mode (default): Runs from current directory with -s . -r -b defaults
  Workspace Mode:         Runs from workspace root (triggered by -R, -s <path>, -i, -o)

Pipeline Execution:
  Pipelines are defined in buildkit_master.yaml or buildkit.yaml under buildkit.pipelines.
  Run a pipeline by name: buildkit <pipeline-name>

Configuration:
  buildkit_master.yaml — Workspace-level configuration
  buildkit.yaml        — Project-level configuration
''',
);
