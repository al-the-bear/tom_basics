# Tom Git User Guide

Tom Git keeps data in git repositories from Dart code alone: it reads and
writes git's objects and packs, edits trees and makes commits without a
working tree or an index, and fetches and pushes branches over smart HTTP. No
git executable is involved at any point.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
- [Objects and Ids](#objects-and-ids)
- [Reading a Repository](#reading-a-repository)
- [Changing a Repository](#changing-a-repository)
- [Refs](#refs)
- [Fetching and Pushing](#fetching-and-pushing)
- [Repositories on Disk](#repositories-on-disk)
- [Testing Against a Server in Memory](#testing-against-a-server-in-memory)
- [Error Handling](#error-handling)
- [Limits](#limits)
- [Best Practices](#best-practices)

## Overview

A `GitRepository` is an object store plus a ref store. Nothing is ever checked
out: you read a file by walking from a commit to its tree to a blob, and you
change files by asking `editTree` for a new tree with some paths written or
deleted, then `commit` that tree. Branches are refs you move yourself, or that
`fetchBranch` and `pushBranch` move for you.

The library has three entry points:

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_git/tom_git.dart` | the object model, packs, the memory stores, `GitRepository`, `GitHttpRemote`, fetch and push | all, the web included |
| `package:tom_git/io.dart` | `gitOpenDirectory`, `GitLocalRepository` and the directory stores | platforms with `dart:io` |
| `package:tom_git/testing.dart` | `GitMemoryServer`, a smart HTTP server in memory | all; for tests |

## Quick Start

```dart
import 'dart:convert';

import 'package:tom_git/tom_git.dart';

Future<void> main() async {
  final repo = GitRepository.memory();
  final tree = await repo.editTree(
    null,
    writes: {'README.md': utf8.encode('# Notes\n')},
  );
  final commit = await repo.commit(
    tree: tree,
    parents: [],
    message: 'First notes',
    author: GitPerson.now('Ada', 'ada@example.com'),
  );
  await repo.refs.write('refs/heads/main', commit);
  print((await repo.listFiles(tree, '')).single.path); // README.md
}
```

## Core Components

| Type | Role |
| --- | --- |
| `GitObjectId` | A 20-byte SHA-1 object id: `fromHex`, `fromBytes`, `hash`, `hex`, `zero`, `isZero`. |
| `GitObject`, `GitObjectType` | An object's type and content; `id` is computed from both. `GitObject.blob(bytes)` makes a blob. |
| `GitTree`, `GitTreeEntry` | A tree and its entries (mode, name, id), encoded in git's sort order. |
| `GitCommit`, `GitPerson` | A commit (tree, parents, author, committer, message) and a `Name <email> seconds +hhmm` line. |
| `GitObjectStore`, `GitMemoryObjectStore` | Where objects live; read, write, write a whole pack. |
| `GitRefStore`, `GitMemoryRefStore` | Where refs live; read, write with an expected value, delete, list. |
| `GitRepository` | Reading paths, editing trees, committing, and the objects a push must send. |
| `GitHttpRemote` | A remote over smart HTTP(S): `listRefs`, `fetchPack`, `listPushRefs`, `push`. |
| `GitRepositoryRemote` (extension) | `fetchBranch`, `pushBranch`, `deleteRemoteBranch` on a `GitRepository`. |
| `GitPushResult` | What the server reported for a push: `ok`, `refErrors`, `unpackError`, `remoteMoved`, `isRace`. |
| `GitLocalRepository` (`io.dart`) | A repository a person works in, opened from the folder they picked. |
| `GitMemoryServer` (`testing.dart`) | A git server in memory for test suites. |

Lower-level building blocks are exported as well, for callers that handle
packs or the wire format themselves: `gitReadPack`, `gitWritePack`,
`gitBuildPackIndex`, `GitPackIndex`, `gitReadPackEntry`, `gitApplyDelta`,
`gitDeflate` / `gitInflate`, and the pkt-line codec (`GitPktWriter`,
`GitPktReader`, `GitSideBand`).

## Objects and Ids

An object id is SHA-1 over git's framing — `<type> <length>\0<content>` — so
an object made here has the same id git gives it:

```dart
final blob = GitObject.blob(utf8.encode('hello\n'));
print(blob.id.hex); // ce013625030ba8dba906f756967f9e9ca394464a
```

Trees hold entries with git's modes as strings: `GitTreeEntry.fileMode`
(`100644`), `executableMode` (`100755`), `treeMode` (`40000`), `symlinkMode`
(`120000`) and `gitlinkMode` (`160000`, a submodule commit). `GitTree.decode`
and `GitCommit.decode` read an object's content; `encode` and `toObject` write
it back byte-for-byte.

`GitPerson.now(name, email)` stamps the current time in UTC (`+0000`); pass
`seconds` and `timezone` to the constructor for a fixed time. A commit message
gets a trailing newline when it lacks one, as git writes it.

## Reading a Repository

| Method | Returns |
| --- | --- |
| `readObject(id, [type])` | The object; throws `GitMissingObjectException` when absent and `FormatException` when it has another type. |
| `readCommit(id)`, `readTree(id)`, `readBlob(id)` | The decoded commit, tree or blob bytes. |
| `entryAt(root, path)` | The tree entry at a slash-separated path, or null. The empty path names the root tree itself. |
| `listFiles(root, path, {includeTrees})` | Every file under `path`, recursively, sorted, with paths relative to `path`; folders too with `includeTrees: true`. An absent path or a file gives an empty list. |

```dart
final root = (await repo.readCommit(tip)).tree;
final entry = await repo.entryAt(root, 'notes/today.md');
if (entry != null) {
  print(utf8.decode(await repo.readBlob(entry.id)));
}
```

## Changing a Repository

`editTree(base, writes: ..., deletes: ...)` returns the id of a new root tree:
`base` (or an empty tree when `base` is null) with each file of `writes`
stored at its path and each path of `deletes` removed — a file or a whole
folder; the empty path clears everything. Behaviour:

- Only the trees on changed paths are rewritten; every other subtree keeps
  its id, so unchanged folders are shared with the base.
- A file that already exists keeps its mode, so an executable stays
  executable when its content changes. A new file gets `100644`.
- A folder a delete leaves empty disappears, since git has no empty trees.
- A write needs a non-empty path; an empty one throws `ArgumentError`.

`commit(tree:, parents:, message:, author:, committer:)` stores a commit and
returns its id. It moves no ref — point a branch at it with `refs.write`, or
push it.

```dart
final next = await repo.editTree(
  root,
  writes: {'notes/tomorrow.md': utf8.encode('- push\n')},
  deletes: {'notes/today.md'},
);
final id = await repo.commit(
  tree: next,
  parents: [tip],
  message: 'Plan tomorrow',
  author: GitPerson.now('Ada', 'ada@example.com'),
);
await repo.refs.write('refs/heads/main', id, expected: tip);
```

`objectsToSend(tips, excluded: ...)` lists every object reachable from `tips`
that is not reachable from `excluded` — what a remote holding `excluded` still
needs. `pushBranch` uses it; call it yourself when you build a pack with
`gitWritePack`.

## Refs

Ref names are full names (`refs/heads/main`). `GitRefStore.write` takes an
optional `expected` value and refuses the update with `GitRefConflict` unless
the ref is there now; `GitObjectId.zero` as `expected` means "must not exist
yet". This is the compare-and-swap that keeps two writers from overwriting
each other's commits.

```dart
try {
  await repo.refs.write('refs/heads/main', id, expected: tip);
} on GitRefConflict catch (e) {
  print('main moved to ${e.actual} meanwhile');
}
```

`delete` removes a ref (an absent ref is no error); `list(prefix)` returns
every ref under a prefix, `refs/` by default.

## Fetching and Pushing

A `GitHttpRemote` talks to one repository URL over smart HTTP(S). Credentials
come from a provider called for each request:

```dart
final remote = GitHttpRemote(
  Uri.parse('https://github.com/owner/repo.git'),
  credentials: (_) async => GitCredentials.token(token),
);
```

`GitCredentials.token` sends the token as the password of HTTP Basic under the
user name `x-access-token`, which the major hosts accept; use
`GitCredentials(user, password)` for anything else. The remote creates its own
`http.Client` unless you pass `client:`, and `close()` closes only a client it
created.

The extension methods on `GitRepository` do the usual work:

| Method | What it does |
| --- | --- |
| `fetchBranch(remote, branch, {remoteName, refs})` | Brings the branch's objects in and sets `refs/remotes/<remoteName>/<branch>`. Transfers nothing when the tip is already present; deletes the tracking ref when the remote has no such branch. Returns `GitFetchResult` (`tip`, `fetched`). |
| `pushBranch(remote, branch, newTip, {remoteTip, remoteName})` | Moves the branch from `remoteTip` (null creates it) to `newTip`, sending only the objects the remote lacks. On success the tracking ref follows. |
| `deleteRemoteBranch(remote, branch, remoteTip:)` | Deletes the branch, which must be at `remoteTip`, and the tracking ref. |

Pass a listing from `remote.listRefs()` to `fetchBranch` to save a round trip
when one listing serves several branches; `GitRemoteRefs.defaultBranch` is the
branch the server's `HEAD` names.

### A refused push is a result, not an exception

The server decides whether a push lands, and its refusal comes back in the
`GitPushResult`:

```dart
final result = await repo.pushBranch(remote, 'main', commit, remoteTip: tip);
if (result.ok) {
  // landed
} else if (result.isRace) {
  // somebody pushed first: fetch, rebuild the commit on the new tip, retry
} else {
  print(result); // unpackError or refErrors say why
}
```

When a ref is refused, `pushBranch` lists the remote's refs again and records
in `remoteMoved` whether the branch is somewhere other than `remoteTip`.
`isRace` uses that measurement, so a lost race is recognised whatever words
the server uses (`fetch first` on GitHub, `failed to update ref` on Gitea);
only without a measurement does it fall back to known wordings.

## Repositories on Disk

`package:tom_git/io.dart` stores repositories in git's own layout, so git and
this library read each other's work.

`gitOpenDirectory(path, {create, defaultBranch})` opens a **bare** repository.
With `create: true` and nothing at `path`, it makes one (`objects/`, `refs/`,
a `config` with `bare = true` and `HEAD` naming `defaultBranch`, `main` by
default); without it, a folder with no `HEAD` throws `FileSystemException`.
The stores behave as git's do: objects are read from loose files and from
packs through their indexes, a received pack is kept as it arrived with an
index written beside it, refs are read from loose files over `packed-refs`,
and a ref update takes git's `<ref>.lock` — an update that finds the lock
taken throws `GitRefConflict`.

`GitLocalRepository.open(folder)` opens the repository a person works in,
from whichever folder they picked: a folder with a `.git` folder, a linked
worktree (a `.git` file naming its git directory; objects and branches come
from its `commondir`), a bare repository, or a `.git` folder itself. Anything
else throws `GitNotARepositoryException`.

```dart
import 'package:tom_git/io.dart';

final local = GitLocalRepository.open('/home/ada/notes');
final branch = 'main';
if (local.checkedOutBranches().contains(branch)) {
  // Moving it would leave that working tree describing the old commit.
  throw StateError('$branch is checked out; commit on another branch');
}
final repo = local.repository; // a GitRepository over the common directory
```

`headBranch()` is the branch `HEAD` names (null when detached);
`checkedOutBranches()` is every branch the main working tree and each linked
worktree has checked out. Both read `HEAD` when called, never from a cache,
because the person may switch branches while the repository is open. The
check matters because this library never updates a working tree or the index:
git refuses a push to a checked-out branch for the same reason
(`receive.denyCurrentBranch`).

## Testing Against a Server in Memory

`GitMemoryServer` (`package:tom_git/testing.dart`) serves one repository over
the smart HTTP protocol through an `http.Client`, so fetch and push run
without a network:

```dart
import 'package:tom_git/testing.dart';

final server = GitMemoryServer(); // protocol v2 for fetch, branch `main`
await server.seed({'a.txt': utf8.encode('a\n')});
final remote = GitHttpRemote(server.url, client: server.client);
```

| Member | Use |
| --- | --- |
| `seed(files, {branch, message})` | Commits files directly on the server. |
| `repository` | The hosted `GitRepository`, to inspect what was pushed. |
| `requests` | Requests answered, by kind (`ls-refs`, `fetch`, `push`). |
| `beforePush` | Runs before a push is applied — move a branch here to make a client lose a race deterministically. |
| `protocolV2: false` | Serves fetch over protocol version 0 only. |
| `requiredPassword` | Makes every request need Basic credentials with that password. |

It is for test suites; no shipped library should import it.

## Error Handling

| Exception | When |
| --- | --- |
| `GitTransportException` | The base of the wire failures; also an unexpected HTTP status (carries `statusCode`) or a server that does not speak smart HTTP. |
| `GitAuthException` | HTTP 401 or 403: credentials missing or refused. |
| `GitRepositoryNotFoundException` | HTTP 404: no repository at the URL. |
| `GitUnreachableException` | No answer at all. In a web page the message names both possible causes — the server is down, or it does not send CORS headers on its git endpoints — because the browser reports them the same way. |
| `GitRemoteError` | The server sent an `ERR` line. |
| `GitMissingObjectException` | A repository was asked for an object it does not have. |
| `GitRefConflict` | A ref update found the ref elsewhere than `expected`, or (on disk) locked. |
| `GitNotARepositoryException` | `GitLocalRepository.open` found no repository in the folder. |
| `FormatException` | Malformed object, pack, index or delta data, or an object of the wrong type. |

A push the server refuses does not throw; see
[A refused push is a result](#a-refused-push-is-a-result-not-an-exception).

## Limits

| Area | Not supported |
| --- | --- |
| Transport | SSH, the `git://` protocol, dumb HTTP |
| Fetch | shallow and partial clones, tags, thin packs; one branch per `fetchBranch` |
| Push | delta compression (packs hold whole objects), atomic multi-ref push, push options |
| Objects | SHA-256 repositories; annotated tags are stored but not interpreted; signed commits are kept verbatim but never made |
| Storage | the index file, a working tree, reflogs, `gc`/repacking, alternates, commit-graph |
| Large files | Git-LFS: a pointer file is an ordinary blob |

## Best Practices

- Move a branch with `expected:` set to the tip you built on, so a concurrent
  writer makes your update fail instead of disappear.
- On a refused push, branch on `isRace`: a race is cured by fetching and
  rebuilding the commit on the new tip; anything else is a fault to report.
- Before moving a branch of a `GitLocalRepository`, check
  `checkedOutBranches()`.
- Pass `client:` to `GitHttpRemote` when your application already owns an
  `http.Client`, and call `close()` on remotes that created their own.
- Use `GitMemoryServer` in tests rather than a live host; keep live checks
  opt-in.
