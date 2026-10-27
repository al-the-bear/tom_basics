# tom_file_system

One file-system contract, `TomFileSystem`, that every read and write of a Tom
application goes through — Tom Forge's editors and explorer, and Webwork's
workspace browser — addressed by `Uri`. A file system has a `root`; `uriOf` and
`pathOf` map a path relative to it to a `Uri` and back.

```yaml
dependencies:
  tom_file_system:
    path: ../../tom_ai/basics/tom_file_system
```

## Entry points

- **`package:tom_file_system/tom_file_system.dart`** — the contract and its
  values (`TomFileEntry`, `TomFileRevision`, `TomFileContent`,
  `TomFileConflict`, `TomFileChange`), the change and save events
  (`TomFileChangeEvent`, `TomWillSaveEvent`, `TomSaveReason`), the shared base
  (`TomFileSystemBase`: text reads and writes, `save` with its will-save and
  did-save events), the in-memory `TomMemoryFileSystem` and the text test
  `tomLooksLikeText`. It reaches no `dart:io` and no Flutter, so a browser
  build links it; a dart2js compile and a walk of its imports hold that on
  every test run.
- **`package:tom_file_system/io.dart`** — `TomLocalFileSystem` over a folder
  on disk, with the platform parts it stands on.

```dart
import 'package:tom_file_system/tom_file_system.dart';

Future<void> main() async {
  final fs = TomMemoryFileSystem(seed: {'/notes.txt': 'first line\n'});
  final read = await fs.read(fs.uriOf('notes.txt'));
  // Refused with a TomFileConflict if somebody changed the file since.
  await fs.writeText(fs.uriOf('notes.txt'), 'second line\n',
      expected: read.revision);
}
```

## What the contract guarantees

On every implementation:

- **Revision-checked writes.** `read` answers the bytes with the revision
  they were read at (size and SHA-256); `write` with an `expected` revision is
  refused with a `TomFileConflict` when the file is no longer that revision,
  so a change made by someone else is never written over.
- **Atomic writes.** The local file system writes a temporary file beside the
  target and renames it over it; a crash leaves the old file or the new one,
  never half of either.
- **Containment.** A symbolic link that leaves the root is listed, marked
  (`linkLeavesRoot`) and never followed.
- **Trash.** `trash` moves to the platform's trash — Finder's on macOS; on
  Linux `gio trash`, `trash-put`, or with neither the freedesktop.org home
  trash written directly (`tomXdgTrash`); on Windows the Recycle Bin through
  the shell's `SHFileOperationW` (`tomWindowsRecycle`) — and answers false
  where there is none (the in-memory file system), so the caller can offer a
  permanent `delete` instead.
- **Watching.** `watch` reports changes below the root, or is null where the
  platform does not watch. On macOS and Windows it is the platform's recursive
  watch; on Linux, where `Directory.watch` is not recursive, every folder is
  watched on its own (`TomDirectoryWatches`), a folder that appears is
  watched as it appears, and a folder the caller's `descend` excludes is never
  entered.
- **Slices.** `readSlice` reads at most a given number of bytes from a file's
  start or end, cut at a whole line — how a growing log is followed.

What builds on it lives elsewhere: the editing session, the tree filter and
the `.env` codec are `tom_file_session`; applying an editor's multi-file
workspace edit is `tom_forge_core`'s `forgeApplyWorkspaceEdit`.

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

## License

BSD-3-Clause — See [LICENSE](LICENSE) for details.
