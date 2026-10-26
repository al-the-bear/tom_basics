# Changelog

## 0.1.0

- Git objects (blob, tree, commit), loose objects, and pack version 2 with its
  version 2 index, read and write; deltas resolved on read.
- `GitRepository`: reading, tree editing and committing without an index or a
  working tree, and the objects a push must send; in memory or, through
  `io.dart`, a bare repository in git's own layout.
- `GitHttpRemote`: smart HTTP fetch (protocol v2, v0 fallback) and push
  (`report-status`, `side-band-64k`), with token credentials; `fetchBranch`,
  `pushBranch`, `deleteRemoteBranch`, a lost race measured against a fresh
  ref listing.
- `package:tom_git/testing.dart`: `GitMemoryServer`.
