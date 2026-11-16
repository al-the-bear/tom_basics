# Tom Git

Published on pub.dev as [`tom_git` 0.2.0](https://pub.dev/packages/tom_git).

> Tom Git is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in this package's license — see
> [LICENSE](LICENSE).

Git in pure Dart: objects, packs and the smart HTTP protocol, enough to clone,
commit and push with **no git binary** — for applications that ship to
machines without one, and for the web.

---

## Overview

`tom_git` implements the part of git an application needs to keep data in a
git repository without shelling out to `git`: the object model, loose objects
and packfiles, editing a tree and committing without an index or a working
tree, and fetching and pushing over smart HTTP. The default entry point uses
no `dart:io`, so the same code runs on the desktop, on a server, on mobile and
in a web page; a second entry point adds repositories on disk in git's own
layout, which git reads and which read what git wrote.

What it deliberately does not do: check anything out. There is no working tree
and no index — a change is a set of paths to write or delete, turned into a new
tree and a commit.

---

## Installation

```yaml
dependencies:
  tom_git: ^0.2.0
```

or

```bash
dart pub add tom_git
```

**SDK requirement:** Dart `^3.10.0`. No native code and no git executable are
needed; the runtime dependencies are pure Dart packages (see
[Dependencies](#dependencies)).

```dart
import 'package:tom_git/tom_git.dart'; // everything, all platforms
import 'package:tom_git/io.dart';      // repositories on disk (dart:io)
```

---

## Features

### What it does

- **Objects.** Blobs, trees and commits, encoded and decoded byte-for-byte as
  git writes them; ids are SHA-1 over git's framing (`GitObjectId.hash`).
- **Loose objects and packs, read and write.** Pack version 2 with its
  version 2 index; deltas (`OFS_DELTA`, `REF_DELTA`) are resolved on read. A
  pack this library writes holds whole objects; its index is the one
  `git index-pack` would write.
- **Commits without an index or a working tree.** `GitRepository.editTree`
  rewrites only the paths a changeset touches, keeps file modes, and removes
  folders a delete empties; `commit` writes the commit object.
- **Smart HTTP, fetch and push.** Fetch speaks protocol version 2 where the
  server offers it (`ls-refs`, `fetch`) and version 0 otherwise; push speaks
  `receive-pack` with `report-status` and `side-band-64k`. Credentials are
  HTTP Basic, from a provider asked per request (`GitCredentials.token` for a
  token under `x-access-token`).
- **Races measured, not read off a message.** A refused push is checked
  against a fresh listing of the remote's refs (`GitPushResult.remoteMoved`),
  because servers word the refusal differently — GitHub says `fetch first`,
  Gitea `failed to update ref`.
- **Repositories in memory or on disk.** `GitRepository.memory()` for a build
  with no file system; `gitOpenDirectory` (`io.dart`) for a bare repository in
  git's own layout — loose objects, packs with their indexes, loose refs over
  `packed-refs`, updates under git's `<ref>.lock` — which git can read and
  which reads what git wrote.
- **The repository a person works in.** `GitLocalRepository.open` (`io.dart`)
  takes the folder somebody picked — a working repository, a linked worktree
  (its `.git` file and `commondir`), a bare repository or a `.git` folder —
  and says which branches a working tree has checked out, because this
  library never updates a working tree or the index: a commit moved onto a
  checked-out branch would leave that tree describing the commit before.
- **A git server in memory for tests.** `GitMemoryServer`
  (`testing.dart`) serves a repository over the smart HTTP protocol through an
  `http.Client`, so a suite exercises fetch and push without a network.

### Supported subset

| Area | Supported | Not supported |
| --- | --- | --- |
| Transport | smart HTTP(S): fetch v2 and v0, push v0 | SSH, the `git://` protocol, dumb HTTP |
| Fetch | one branch at a time, full (non-thin) packs, `have` lines from the tracking ref | shallow and partial clones, tags, thin packs |
| Push | branch create, update and delete; whole-object packs | delta compression on push, atomic multi-ref push, push options |
| Objects | blob, tree, commit; SHA-1 | annotated tags (stored, never interpreted), SHA-256 repositories, signed commits (kept verbatim, never made) |
| Storage | loose objects, packs + v2 index, loose and packed refs | the index file, a working tree, reflogs, `gc`/repacking, alternates, commit-graph |
| Large files | — | Git-LFS (a pointer is an ordinary blob here) |

### Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_git/tom_git.dart` | objects, packs, deltas, zlib, pkt-lines, the memory stores, `GitRepository`, `GitHttpRemote`, fetch and push | all, the web included (no `dart:io`) |
| `package:tom_git/io.dart` | `gitOpenDirectory`, `GitLocalRepository`, `GitDirectoryObjectStore`, `GitDirectoryRefStore` | desktop, server, mobile |
| `package:tom_git/testing.dart` | `GitMemoryServer`: a smart HTTP server in memory, reached through an `http.Client` — for suites that must not touch a network | all |

---

## Quick start

A repository in memory: write two files, commit them, point a branch at the
commit and read the files back.

```dart
import 'dart:convert';

import 'package:tom_git/tom_git.dart';

Future<void> main() async {
  final repo = GitRepository.memory();

  // A tree with two files, and a commit of it — no index, no working tree.
  final tree = await repo.editTree(
    null,
    writes: {
      'README.md': utf8.encode('# Notes\n'),
      'notes/today.md': utf8.encode('- try tom_git\n'),
    },
  );
  final commit = await repo.commit(
    tree: tree,
    parents: [],
    message: 'First notes',
    author: GitPerson(name: 'Ada', email: 'ada@example.com', seconds: 0),
  );
  await repo.refs.write('refs/heads/main', commit);

  // Read it back through the branch.
  final tip = (await repo.refs.read('refs/heads/main'))!;
  final root = (await repo.readCommit(tip)).tree;
  for (final file in await repo.listFiles(root, '')) {
    print(file.path); // README.md, then notes/today.md
  }
  final entry = await repo.entryAt(root, 'notes/today.md');
  print(utf8.decode(await repo.readBlob(entry!.id))); // - try tom_git
  print(tip.hex); // 268f93b03724e800fcfee28db7d61b2feb982a42
}
```

The commit id is the one git computes for the same tree, author and message.

---

## Example projects

| Location | What it shows |
| --- | --- |
| [`example/tom_git_example.dart`](example/tom_git_example.dart) | Fetches from a server in memory, commits a file and pushes it (`dart run example/tom_git_example.dart`). |
| [`test/`](test/) | The offline suite: objects, packs against fixtures made by real git, the directory layout, both protocol versions, a dart2js compile. |

---

## Testing

```bash
dart test                      # offline: objects, packs, the directory layout, both protocols, a dart2js compile
tool/test_without_git.sh       # the same with every git executable removed from PATH
```

`test/no_git_binary_test.dart` fails when `git` resolves under
`tool/test_without_git.sh`, so a green run there proves the suite did not use
it. Fixtures made by real git are in `test/fixtures/`; the directory test runs
`git fsck --strict` over what this library wrote only when git is on PATH.

The live suites run with `TOM_LIVE` set (package:tom_test_support's live
contract): `test/live_github_test.dart` on `GITHUB_TEST_TOKEN` against the
scratch repository, `test/live_gitea_test.dart` against a Gitea it starts in
Docker. Each lists, clones, commits, pushes, loses a race and deletes, on a
branch of its own that is removed at the end.

---

## Dependencies

| Dependency | Kind | For |
| --- | --- | --- |
| `archive` | runtime | zlib, with the consumed length a pack read needs |
| `crypto` | runtime | SHA-1 |
| `http` | runtime | the smart HTTP transport |
| `meta` | runtime | annotations |
| `path` | runtime | paths on disk (`io.dart`) |
| `test`, `lints`, `tom_test_support` | dev | the suite, the live contract and the Gitea fixture |

---

## Further documentation

| Document | What it covers |
| --- | --- |
| [`doc/git.md`](doc/git.md) | The user guide: objects and ids, editing trees and committing, refs, fetch and push, repositories on disk, the test server, errors and limits. |
| [`example/`](example/) | The runnable example. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version. |

---

## Status

Version **0.2.0**, published on pub.dev. The offline suite and both live
suites pass with no git binary on PATH.

---

## License

BSD-3-Clause — see [LICENSE](LICENSE).
