/// The messages of `:skill-build-binaries`, `:skill-build-all-binaries` and
/// `:skill-push-binaries` (buildkit_ws_commands.md § 1.9, § 1.10).
library;

import 'package:tom_build_base/tom_build_base_v2.dart';

/// `bin-no-clone`: tom_binaries is not there.
const binNoClone = MessageDefinition(
  code: 'bin-no-clone',
  level: MessageLevel.refusal,
  label: 'NO TOM_BINARIES',
  summary: 'No tom_binaries clone to build into or push from.',
  description:
      'Clone it (buildkit :ws-update clones the binaries entry of repos.yaml) '
      'or name it with --binaries.',
);

/// `bin-not-ignored`: tom_binaries/all/ is not ignored.
const binNotIgnored = MessageDefinition(
  code: 'bin-not-ignored',
  level: MessageLevel.refusal,
  label: 'ALL/ NOT IGNORED',
  summary: 'tom_binaries/all/ is not ignored by git.',
  description:
      'The full build writes every binary that is no release binary into '
      'all/<platform>/; tom_binaries/.gitignore must ignore it (/all/) so '
      'none of them is ever committed. Nothing was built.',
);

/// `bin-set`: the release set does not add up.
const binSet = MessageDefinition(
  code: 'bin-set',
  level: MessageLevel.refusal,
  label: 'RELEASE SET',
  summary: 'The declarations of the release set do not add up.',
  description:
      'An entry of buildkit_master.yaml names a project that is not there, '
      'or says neither which project compiles it, nor built-by, nor bundled. '
      'Fix buildkit_master.yaml or the project\'s buildkit.yaml; nothing was '
      'built.',
);

/// `bin-build-failed`: a build step failed.
const binBuildFailed = MessageDefinition(
  code: 'bin-build-failed',
  level: MessageLevel.error,
  label: 'BUILD FAILED',
  summary: 'A build step failed.',
  description:
      'The evidence is the end of its output. The binaries built before it '
      'are in place; the others are as they were.',
);

/// `bin-missing`: a release binary the build should have written is not there.
const binMissing = MessageDefinition(
  code: 'bin-missing',
  level: MessageLevel.error,
  label: 'NOT BUILT',
  summary: 'A release binary the build should have written is not there.',
  description:
      'Its project\'s :compiler did not write it for this platform: check '
      'the compiles: of its buildkit.yaml (platforms:, the output name) or '
      'limit the entry\'s platforms: in buildkit_master.yaml.',
);

/// `bin-not-built`: the release binaries no command here builds.
const binNotBuilt = MessageDefinition(
  code: 'bin-not-built',
  level: MessageLevel.warning,
  label: 'NOT BUILT HERE',
  summary: 'Release binaries another tool builds, or that are bundled.',
  description:
      'Left as they are: each says what builds it. One that is missing on '
      'this platform is marked so.',
);

/// `bin-unrelated`: the clone's history is unrelated to origin's.
const binUnrelated = MessageDefinition(
  code: 'bin-unrelated',
  level: MessageLevel.error,
  label: 'UNRELATED HISTORY',
  summary: "This clone's history shares no commit with origin's.",
  description:
      'origin was recreated (tom_binaries went public with a fresh history); '
      'rebasing would publish the old one. Nothing was pushed; the build is '
      'committed locally. Delete the clone, clone it fresh and build there.',
);

/// `bin-push-failed`: the push did not go through.
const binPushFailed = MessageDefinition(
  code: 'bin-push-failed',
  level: MessageLevel.error,
  label: 'PUSH FAILED',
  summary: 'The binaries could not be pushed.',
  description:
      'A rebase onto what the other platforms pushed could not be completed, '
      'or origin kept moving. Nothing was forced; the commit is local. Run '
      'again later.',
);

/// The messages of the build commands.
final binBuildMessages = MessageCatalog([
  binNoClone,
  binNotIgnored,
  binSet,
  binBuildFailed,
  binMissing,
  binNotBuilt,
]);

/// The messages of `:skill-push-binaries`.
final binPushMessages = MessageCatalog([binUnrelated, binPushFailed]);

/// Every message of the binaries commands, once.
final binAllMessages = MessageCatalog([
  binNoClone,
  binNotIgnored,
  binSet,
  binBuildFailed,
  binMissing,
  binNotBuilt,
  binUnrelated,
  binPushFailed,
]);
