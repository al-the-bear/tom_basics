# tom_git

Git in pure Dart: objects, packs and the smart HTTP protocol, enough to clone,
commit and push with **no git binary** — for applications that ship to
machines without one, and for the web.

License: BSD-3-Clause. Internal (`publish_to: none`), consumed by path.

## What it does

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

## Supported subset

| Area | Supported | Not supported |
| --- | --- | --- |
| Transport | smart HTTP(S): fetch v2 and v0, push v0 | SSH, the `git://` protocol, dumb HTTP |
| Fetch | one branch at a time, full (non-thin) packs, `have` lines from the tracking ref | shallow and partial clones, tags, thin packs |
| Push | branch create, update and delete; whole-object packs | delta compression on push, atomic multi-ref push, push options |
| Objects | blob, tree, commit; SHA-1 | annotated tags (stored, never interpreted), SHA-256 repositories, signed commits (kept verbatim, never made) |
| Storage | loose objects, packs + v2 index, loose and packed refs | the index file, a working tree, reflogs, `gc`/repacking, alternates, commit-graph |
| Large files | — | Git-LFS (a pointer is an ordinary blob here; `tom_core_storage` refuses it by name) |

## Entry points

| Import | Holds | Platforms |
| --- | --- | --- |
| `package:tom_git/tom_git.dart` | objects, packs, deltas, zlib, pkt-lines, the memory stores, `GitRepository`, `GitHttpRemote`, fetch and push | all, the web included (no `dart:io`) |
| `package:tom_git/io.dart` | `gitOpenDirectory`, `GitDirectoryObjectStore`, `GitDirectoryRefStore` | desktop, server, mobile |
| `package:tom_git/testing.dart` | `GitMemoryServer`: a smart HTTP server in memory, reached through an `http.Client` — for suites that must not touch a network | all |

## Example

`example/tom_git_example.dart` fetches from a server in memory, commits a
file and pushes it:

```bash
dart run example/tom_git_example.dart
```

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

## Dependencies

| Dependency | Kind | For |
| --- | --- | --- |
| `archive` | runtime | zlib, with the consumed length a pack read needs |
| `crypto` | runtime | SHA-1 |
| `http` | runtime | the smart HTTP transport |
| `meta` | runtime | annotations |
| `path` | runtime | paths on disk (`io.dart`) |
| `test`, `lints`, `tom_test_support` | dev | the suite, the live contract and the Gitea fixture |

## Status

Version **0.1.0**. The offline suite and both live suites pass with no git
binary on PATH.
