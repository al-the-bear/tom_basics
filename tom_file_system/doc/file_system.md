# Tom File System

The Tom File System is one file-system contract, `TomFileSystem`, that every
read and write of a Tom application goes through, with two implementations: an
in-memory one for tests, previews and the browser, and a local one over a folder
on disk. Writes are atomic and may be checked against the revision they were
read at; a delete goes to the platform's trash; a link that leaves the root is
never followed; and every result is a plain value rather than a `dart:io`
object.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
  - [The contract](#the-contract)
  - [TomMemoryFileSystem](#tommemoryfilesystem)
  - [TomLocalFileSystem](#tomlocalfilesystem)
- [Addressing: Root, URIs and Paths](#addressing-root-uris-and-paths)
- [Reading](#reading)
- [Writing and Revisions](#writing-and-revisions)
- [Listing, Stat and Links](#listing-stat-and-links)
- [Create, Rename, Trash and Delete](#create-rename-trash-and-delete)
- [Watching](#watching)
- [Change and Save Events](#change-and-save-events)
- [Folder Helpers](#folder-helpers)
- [Text Detection](#text-detection)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

## Overview

| Type | Kind | Purpose |
| ---- | ---- | ------- |
| `TomFileSystem` | interface | The contract: list, stat, read, write, create, rename, trash, delete, watch, save and the event streams |
| `TomFileSystemBase` | abstract class | What every implementation does the same way: URIs against the root, text over bytes, `save` and the event streams |
| `TomMemoryFileSystem` | class | A file system held in memory |
| `TomLocalFileSystem` | class | A local folder as a file system (`io.dart`) |
| `TomFileSystemFolders` | extension | `folderOf`, `ensureFolder`, `writeTextMakingFolder`, `readTextIfExists` on any `TomFileSystem` |
| `TomFileEntry` | class | One entry of a listed directory |
| `TomFileEntryKind` | enum | `file`, `directory`, `link` |
| `TomFileRevision` | class | The version of a file as it was read: size, SHA-256 and modification time |
| `TomFileContent` | class | A file's bytes and the revision they were read at |
| `TomFileConflict` | exception | A write refused because the file is no longer the expected revision |
| `TomFileSystemException` | exception | A path the in-memory file system does not have, or already has |
| `TomFileChange` | class | A change under a watched root |
| `TomFileChangeEvent` | class | A create, write, rename or delete made through a file system |
| `TomFileChangeType` | enum | `created`, `modified`, `deleted` |
| `TomWillSaveEvent` | class | Announced before a save, with the content to be saved |
| `TomSaveReason` | enum | `manual`, `autoSave`, `focusLoss` |
| `TomDirectoryWatches` | class | Recursive watching built from one watch per directory (`io.dart`) |
| `tomLooksLikeText` | function | Whether a file's first bytes are text |
| `tomTrimToLineStart` / `tomTrimToLineEnd` | functions | Drop the partial first / last line of a cut text slice |
| `tomXdgTrash` | function | Move an item into the freedesktop.org home trash (`io.dart`) |
| `tomWindowsRecycle` | function | Move an item to the Windows Recycle Bin (`io.dart`) |

`package:tom_file_system/tom_file_system.dart` holds everything that works
without a disk and reaches no `dart:io`, so a browser build links it.
`package:tom_file_system/io.dart` exports the same plus the local file system
and its platform parts; it uses `dart:io` and `dart:ffi`.

### Why use it

- **No lost edits** — a write can name the revision it was read at and is
  refused when someone changed the file since.
- **No half-written files** — writes are atomic.
- **A way back** — delete moves to the platform's trash; deleting for good is a
  separate call.
- **No escape from the root** — a link that leaves it is shown, never expanded.
- **One API for disk, memory and browser** — code written against
  `TomFileSystem` runs on either implementation, and tests use the in-memory one.

## Quick Start

```dart
import 'package:tom_file_system/tom_file_system.dart';

Future<void> main() async {
  final fs = TomMemoryFileSystem(seed: {'/notes.txt': 'first line\n'});
  final read = await fs.read(fs.uriOf('notes.txt'));
  await fs.writeText(
    fs.uriOf('notes.txt'),
    'second line\n',
    expected: read.revision,
  );
  print(await fs.readText(fs.uriOf('notes.txt'))); // second line
}
```

The same code over a folder on disk:

```dart
import 'package:tom_file_system/io.dart';

Future<void> main() async {
  final fs = TomLocalFileSystem('/path/to/folder');
  await fs.writeText(fs.uriOf('notes.txt'), 'first line\n');
  print(await fs.readText(fs.uriOf('notes.txt'))); // first line
}
```

## Core Components

### The contract

`TomFileSystem` is an interface; both implementations extend
`TomFileSystemBase`, which supplies `uriOf`, `pathOf`, `readText`, `writeText`,
`save`, the event streams and `dispose`, and leaves the primitives — list, stat,
read, write, create, rename, trash, delete, exists, watch — to the
implementation. A further implementation (a repository, a remote folder)
attaches by extending `TomFileSystemBase` and announcing its own changes with
`emitChange`.

| Member | What it does |
| ------ | ------------ |
| `root` | The root directory, an absolute directory URI with a trailing `/`. |
| `uriOf(path)` / `pathOf(uri)` | A root-relative path to its absolute URI, and back. |
| `list(directory)` | The entries of a directory, one level, unsorted. |
| `stat(uri)` | An entry without reading it, or null when it does not exist. |
| `read(uri)` / `readText(uri)` | The bytes with their revision / the text as UTF-8. |
| `readSlice(uri, maxBytes:, fromEnd:)` | At most `maxBytes` of a file as text, cut at a whole line. |
| `write(uri, bytes, expected:)` / `writeText(uri, text, expected:)` | An atomic write, optionally revision-checked; answers the revision written. |
| `create(uri, directory:)` | An empty file, or a folder with its parents. |
| `rename(from, to)` | Renames or moves a file or folder. |
| `trash(uri)` | Moves to the platform's trash; answers false when there is none. |
| `delete(uri)` | Deletes for good, a folder with everything in it. |
| `exists(uri)` | Whether the entry exists. |
| `watch(descend:)` | A stream of changes under the root, or null. |
| `save(uri)` | Announces a save: `onWillSave`, then `onDidSave`. |
| `onDidChange` / `onWillSave` / `onDidSave` | The event streams. |
| `dispose()` | Ends the event streams. |

### TomMemoryFileSystem

```dart
final fs = TomMemoryFileSystem(
  root: Uri.directory('/project'), // default: '/'
  seed: {'/project/README.md': '# Notes\n'},
);
print(fs.paths); // [/project/README.md]
```

Files and folders are keyed by their absolute path; `seed` maps absolute paths
to text. A folder holding a file exists implicitly, and `create(directory:
true)` makes an empty one. Writes are atomic by construction and revisions are
checked as on disk. Its clock starts at 2026-01-01 UTC and moves one
millisecond per write, so two writes never share a modification time. There is
no trash: `trash` answers false. `watch` reports every change made through it,
and `paths` lists every file, sorted, for tests.

### TomLocalFileSystem

```dart
import 'package:tom_file_system/io.dart';

final fs = TomLocalFileSystem('/path/to/folder');
print(fs.rootPath); // /path/to/folder
print(fs.localPathOf(fs.uriOf('lib/main.dart'))); // /path/to/folder/lib/main.dart
```

The root is normalised to an absolute path (`rootPath`); `localPathOf` turns a
URI into a local path. Writes go to a sibling temporary file
(`.<name>.tom-<time>.tmp`), flushed and renamed over the target. The optional
`watchEachDirectory` chooses how `watch` is recursive (see
[Watching](#watching)).

## Addressing: Root, URIs and Paths

Every call takes a `Uri`. A relative URI resolves against `root`, so
`fs.uriOf('lib/main.dart')` and `Uri(path: 'lib/main.dart')` address the same
file. Paths in entries and changes are relative to the root, with `/`
separators; `''` is the root itself.

```dart
final fs = TomMemoryFileSystem(root: Uri.directory('/project'));
print(fs.uriOf('lib/main.dart')); // file:///project/lib/main.dart
print(fs.pathOf(Uri.file('/project/lib/main.dart'))); // lib/main.dart
print(fs.pathOf(Uri.file('/elsewhere/x.dart'))); // null
print(fs.uriOf('')); // file:///project/
```

`pathOf` answers null for a URI outside the root, including one with another
scheme or authority.

## Reading

`read` answers a `TomFileContent`: the bytes and the `TomFileRevision` they were
read at. `readText` decodes the bytes as UTF-8; malformed sequences become
replacement characters rather than an error.

`readSlice` reads at most `maxBytes` from the start of a file, or from its end
with `fromEnd: true` — how a growing log is followed. A slice that had to be cut
drops the partial line at the cut, so its first (or last) line is whole; a
slice without any line break is kept as it is. It answers null for a file that
does not exist.

```dart
final fs = TomMemoryFileSystem(seed: {'/app.log': 'one\ntwo\nthree\n'});
print(await fs.readSlice(fs.uriOf('app.log'), maxBytes: 9, fromEnd: true));
// three
```

The two cuts are also available on their own as `tomTrimToLineStart` and
`tomTrimToLineEnd`.

## Writing and Revisions

A `TomFileRevision` is a file's size, the SHA-256 of its bytes (hex) and its
modification time. Two revisions are equal when size and hash are; the time is
not compared, so rewriting identical bytes is not a change.

`write` and `writeText` replace the whole file atomically and answer the
revision written. With `expected`, the write is refused with a
`TomFileConflict` when the file is no longer that revision — changed, or deleted
(`current` is then null) — and nothing is written:

```dart
final fs = TomMemoryFileSystem(seed: {'/a.txt': 'v1'});
final mine = await fs.read(fs.uriOf('a.txt'));
await fs.writeText(fs.uriOf('a.txt'), 'theirs'); // someone else writes
try {
  await fs.writeText(fs.uriOf('a.txt'), 'mine', expected: mine.revision);
} on TomFileConflict catch (e) {
  print(e); // "/a.txt" changed on disk since it was read
}
```

The usual loop is read, edit, write with the revision read, and on a conflict
read again and let the user decide. A write without `expected` always writes,
and creates the file when it does not exist. The local file system writes into
an existing folder only; use `writeTextMakingFolder` when the folder may be
missing.

## Listing, Stat and Links

`list` answers the entries of one directory, unsorted. A `TomFileEntry` carries:

| Field | Meaning |
| ----- | ------- |
| `name` | The entry's own name. |
| `path` | Its path relative to the root (`''` for the root). |
| `uri` | Its absolute URI. |
| `kind` | `file`, `directory` or `link`. |
| `size` | Size in bytes; 0 for a directory. |
| `modified` | Last modification time. |
| `linksToDirectory` | For a link: whether it leads to a directory. |
| `linkLeavesRoot` | For a link: whether its target lies outside the root or is one of its own ancestors. |
| `readable` | Whether the process may read it. |

`isDirectory` is true for a directory and for a link to one; `expandable` is
true only when it is a directory, the link does not leave the root, and it is
readable. A tree that expands only `expandable` entries can neither leave the
root nor loop forever.

The local file system lists links without following them, compares targets as
real paths (so a root behind a link, such as macOS's `/var`, is handled), and
marks a broken link as not readable. The in-memory file system has no links.

`stat` answers the entry of one URI without reading it, or null when nothing is
there; on disk it follows links and reports what they lead to.

## Create, Rename, Trash and Delete

- **`create(uri)`** makes an empty file and refuses one that already exists.
  `create(uri, directory: true)` makes a folder with its parents; an existing
  folder is fine.
- **`rename(from, to)`** renames or moves a file or folder; an existing `to` is
  refused.
- **`trash(uri)`** moves the entry to the platform's trash and answers whether
  it did. On macOS it is Finder's own delete, so the item can be put back. On
  Linux it tries `gio trash`, then `trash-put`, then writes the freedesktop.org
  home trash directly (`tomXdgTrash`: a `.trashinfo` record, then the item;
  false when there is no home directory or the item is on another file system
  than the trash). On Windows it calls the shell's `SHFileOperationW` with undo
  allowed (`tomWindowsRecycle`), without a dialog. Elsewhere, and in memory, it
  answers false.
- **`delete(uri)`** deletes for good, a folder with everything in it.

`trash` answering false is the signal to ask the user before calling `delete`:
nothing is unlinked without a way back unless somebody said so.

```dart
final uri = fs.uriOf('old.txt');
if (!await fs.trash(uri)) {
  // No trash here: confirm with the user, then
  await fs.delete(uri);
}
```

## Watching

`watch` answers a stream of `TomFileChange`s — the changed entry's root-relative
`path` and its `uri` — or null when the platform does not watch. A watch is
advisory: it may miss a change, and code that must know compares revisions.

`descend` is asked with a folder's root-relative path whether changes inside it
are wanted, so a folder a tree does not enter (`.git`, a build folder) need not
be watched. An implementation may watch more than asked, never less.

```dart
final changes = fs.watch(descend: (path) => !path.startsWith('.git'));
final subscription = changes?.listen((change) => print(change.path));
```

How each implementation watches:

| Implementation | Watching |
| -------------- | -------- |
| `TomMemoryFileSystem` | Every change made through it. |
| `TomLocalFileSystem` on macOS and Windows | The platform's recursive `Directory.watch`. |
| `TomLocalFileSystem` on Linux | `TomDirectoryWatches`: one watch per directory `descend` admits, a new one for each directory that appears, and the watches of a directory that goes are dropped. `Directory.watch` is not recursive on Linux. |

`watch` answers null when the platform does not support watching, or when the
root cannot be watched. `TomLocalFileSystem(root, watchEachDirectory: true)`
uses the per-directory watch on any platform.

`TomDirectoryWatches` can also be used on its own:
`TomDirectoryWatches(root, descend: ...)` reports the absolute path of each
change on `stream` once listened to; `started` completes when the directories
present at that moment are all watched, and `watchedCount` says how many are. A
watch on the root that fails ends the stream with the error; one below it that
fails is dropped while the rest keep running. Links are not followed.

## Change and Save Events

Every create, write, rename and delete made through a file system is announced
on `onDidChange` as a `TomFileChangeEvent` with the absolute `uri` and its
`type` (`created`, `modified`, `deleted`). A rename is a `deleted` of the source
and a `created` of the target. These events cover only what went through this
file system; changes made by other processes arrive through `watch`.

`save(uri)` announces a save. It reads the file's text, emits a
`TomWillSaveEvent` (the absolute `uri`, the `content` read and `reason`
`TomSaveReason.manual`) on `onWillSave`, writes `content` back when it differs
from what was read, and then emits the URI on `onDidSave`.

```dart
fs.onWillSave.listen((event) => print('saving ${event.uri}'));
fs.onDidSave.listen((uri) => print('saved $uri'));
await fs.save(fs.uriOf('notes.txt'));
// saving file:///notes.txt
// saved file:///notes.txt
```

The event streams are broadcast streams, which deliver their events
asynchronously: a listener on `onWillSave` runs after `save` has compared the
content, so a change it makes to `event.content` is not written by that `save`.
`dispose` closes the streams.

## Folder Helpers

The `TomFileSystemFolders` extension adds, on every `TomFileSystem`:

| Member | What it does |
| ------ | ------------ |
| `folderOf(uri)` | The folder holding `uri`. |
| `ensureFolder(folder)` | Makes the folder and its parents when it does not exist. |
| `writeTextMakingFolder(uri, text)` | `writeText`, making the folder first when it is missing. |
| `readTextIfExists(uri)` | The text, or null when the file does not exist. |

```dart
final state = fs.uriOf('.state/settings.json');
final previous = await fs.readTextIfExists(state); // null on the first run
await fs.writeTextMakingFolder(state, '{"theme": "dark"}');
```

## Text Detection

`tomLooksLikeText(head)` judges whether a file is text from its first bytes: a
UTF-16 byte-order mark answers true; otherwise the first 8 KiB must hold no NUL
byte and be valid UTF-8, a character cut off at the end allowed.

```dart
final head = (await fs.read(fs.uriOf('notes.txt'))).bytes;
print(tomLooksLikeText(head)); // true
```

## Error Handling

| Situation | What happens |
| --------- | ------------ |
| A revision-checked write to a changed file | `TomFileConflict`; `current` is the revision there now. Nothing is written. |
| A revision-checked write to a deleted file | `TomFileConflict` with `current` null. |
| `read` of a missing file | In memory: `TomFileSystemException` ("No such file"). On disk: `dart:io`'s `FileSystemException`. |
| `readSlice` / `stat` of a missing entry | null. |
| `create` of an existing file | In memory: `TomFileSystemException` ("Already exists"). On disk: `FileSystemException`. |
| `rename` onto an existing entry | In memory: `TomFileSystemException` ("Already exists"). On disk: `FileSystemException` ("already exists"). |
| `rename` of a missing entry | In memory: `TomFileSystemException` ("No such entry"). On disk: `FileSystemException`. |
| `write` into a missing folder on disk | `FileSystemException`; use `writeTextMakingFolder`. In memory the folder exists implicitly. |
| `delete` of a missing entry | In memory: nothing happens. On disk: `FileSystemException`. |
| No trash available | `trash` answers false. |
| No watching available | `watch` answers null. |

## Best Practices

- **Write with the revision you read.** Keep the `revision` of every `read` an
  editor shows, pass it as `expected`, and treat `TomFileConflict` as a question
  for the user, not an error to retry.
- **Trash first.** Call `trash`, and only on false ask before `delete`.
- **Use the in-memory file system in tests** of code written against the
  contract, and `TomLocalFileSystem` only where the disk is the subject.
- **Import `tom_file_system.dart` in code that must run in a browser**, and
  `io.dart` only where a local folder is opened.
- **Expand only `expandable` entries** when walking a tree, so links that leave
  the root or loop are never followed.
- **Do not rely on a watch for correctness**; compare revisions before writing.
