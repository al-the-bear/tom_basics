# Tom File System

Published on pub.dev as [`tom_file_system` 0.2.0](https://pub.dev/packages/tom_file_system).

> Tom File System is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in this package's license — see
> [LICENSE](LICENSE).

One file-system contract for every Tom application — atomic writes,
revision-checked saves, delete to the platform's trash, links that never leave
the root, values instead of `dart:io` objects — with an in-memory and a local
implementation (watching, freedesktop.org trash, Windows Recycle Bin).

---

## Overview

Every read and write of a Tom application goes through one contract,
`TomFileSystem` — Tom Forge's editors and explorer, and Webwork's workspace
browser — addressed by `Uri`. A file system has a `root`; `uriOf` and `pathOf`
map a path relative to it to a `Uri` and back. Results are values
(`TomFileEntry`, `TomFileContent`, `TomFileRevision`), not `dart:io` objects, so
the contract links into a browser build.

Two implementations ship with it:

| Implementation | Library | Where it fits |
| -------------- | ------- | ------------- |
| `TomMemoryFileSystem` | `tom_file_system.dart` | Tests, previews and anything that must not touch a disk; also in a browser. |
| `TomLocalFileSystem` | `io.dart` | A folder on the local disk, on macOS, Linux and Windows. |

What builds on the contract lives elsewhere: the editing session, the tree
filter and the `.env` codec are `tom_file_session`; applying an editor's
multi-file workspace edit is `tom_forge_core`'s `forgeApplyWorkspaceEdit`.

---

## Installation

```yaml
dependencies:
  tom_file_system: ^0.2.0
```

or

```bash
dart pub add tom_file_system
```

A package inside this workspace may name it by path instead, e.g. from a
package two folder levels below the workspace root:

```yaml
dependencies:
  tom_file_system:
    path: ../../tom_ai/basics/tom_file_system
```

**SDK requirement:** Dart `^3.10.8`. **Runtime dependencies:** `crypto`
(SHA-256 revisions), `ffi` (the Windows Recycle Bin call) and `path`.

### Entry points

- **`package:tom_file_system/tom_file_system.dart`** — the contract and its
  values (`TomFileEntry`, `TomFileRevision`, `TomFileContent`,
  `TomFileConflict`, `TomFileChange`), the change and save events
  (`TomFileChangeEvent`, `TomWillSaveEvent`, `TomSaveReason`), the shared base
  (`TomFileSystemBase`: text reads and writes, `save` with its will-save and
  did-save events), the folder helpers (`TomFileSystemFolders`), the in-memory
  `TomMemoryFileSystem` and the text test `tomLooksLikeText`. It reaches no
  `dart:io` and no Flutter, so a browser build links it; a dart2js compile and
  a walk of its imports hold that on every test run.
- **`package:tom_file_system/io.dart`** — everything above plus
  `TomLocalFileSystem` over a folder on disk, with the platform parts it stands
  on (`TomDirectoryWatches`, `tomXdgTrash`, `tomWindowsRecycle`).

---

## Features

What the contract guarantees, on every implementation:

| Guarantee | What it means |
| --------- | ------------- |
| **Revision-checked writes** | `read` answers the bytes with the revision they were read at (size and SHA-256); `write` with an `expected` revision is refused with a `TomFileConflict` when the file is no longer that revision, so a change made by someone else is never written over. |
| **Atomic writes** | The local file system writes a temporary file beside the target and renames it over it; a crash leaves the old file or the new one, never half of either. |
| **Containment** | A symbolic link that leaves the root, or loops back into its own ancestors, is listed, marked (`linkLeavesRoot`) and never followed. |
| **Trash** | `trash` moves to the platform's trash — Finder's on macOS; on Linux `gio trash`, `trash-put`, or with neither the freedesktop.org home trash written directly (`tomXdgTrash`); on Windows the Recycle Bin through the shell's `SHFileOperationW` (`tomWindowsRecycle`) — and answers false where there is none (the in-memory file system), so the caller can offer a permanent `delete` instead. |
| **Watching** | `watch` reports changes below the root, or is null where the platform does not watch. On macOS and Windows it is the platform's recursive watch; on Linux, where `Directory.watch` is not recursive, every folder is watched on its own (`TomDirectoryWatches`), a folder that appears is watched as it appears, and a folder the caller's `descend` excludes is never entered. |
| **Slices** | `readSlice` reads at most a given number of bytes from a file's start or end, cut at a whole line — how a growing log is followed. |
| **Save announcements** | `save` announces `onWillSave` and then `onDidSave`; every create, write, rename and delete is announced on `onDidChange`. |
| **Folder helpers** | `writeTextMakingFolder`, `readTextIfExists`, `ensureFolder` and `folderOf` — what a store keeping its state in a file of its own does on every load and save. |
| **Text detection** | `tomLooksLikeText` judges a file's first bytes: a UTF-16 byte-order mark, or no NUL byte and a valid UTF-8 prefix. |

---

## Quick start

```dart
import 'package:tom_file_system/tom_file_system.dart';

Future<void> main() async {
  final fs = TomMemoryFileSystem(seed: {'/notes.txt': 'first line\n'});
  final read = await fs.read(fs.uriOf('notes.txt'));
  // Refused with a TomFileConflict if somebody changed the file since.
  await fs.writeText(
    fs.uriOf('notes.txt'),
    'second line\n',
    expected: read.revision,
  );
  print(await fs.readText(fs.uriOf('notes.txt'))); // second line
}
```

The same program is
[`example/tom_file_system_example.dart`](example/tom_file_system_example.dart):

```bash
dart run example/tom_file_system_example.dart
```

For a folder on disk, import `io.dart` and construct
`TomLocalFileSystem('/path/to/folder')`; the calls are the same.

---

## Checking it on Linux and Windows

`tool/platform_check/run.sh` runs the parts that differ per platform from this
machine alone, in Docker:

- **linux** — `tool/platform_check/check.dart` on the Linux Dart VM (atomic
  writes, a stale revision refused, the watch one folder down and in a folder
  made later, the trash), then this package's suite, whose watch tests run
  only on Linux.
- **windows** — the same check on the Windows Dart VM under Wine: atomic
  writes and the Recycle Bin call. Wine reports no file-system events to Dart,
  so the watch is printed as not measured there.

It is started by hand and writes its logs to `testlog/platform_check/`.

---

## Documentation

| Document | What it covers |
| -------- | -------------- |
| [`doc/file_system.md`](doc/file_system.md) | The user guide — addressing, reading and writing with revisions, listing and links, trash and delete, watching, save events, the folder helpers, errors and limits. |
| [`example/`](example/) | The runnable quick start. |
| [`CHANGELOG.md`](CHANGELOG.md) | What changed in each version. |

---

## Status

- **Version:** 0.2.0, published on pub.dev.
- **SDK:** Dart `^3.10.8`.
- **Tests:** the suite under `test/` runs with `testkit :test` (or
  `dart test`); the watch tests of the local file system run only on Linux, and
  the per-platform behaviour is checked by hand with `tool/platform_check/`.

---

## License

BSD-3-Clause — see [LICENSE](LICENSE) for details.
