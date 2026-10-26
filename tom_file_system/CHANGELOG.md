# Changelog

## 0.1.0

- One file-system contract, `TomFileSystem`, addressed by `Uri` with a root:
  revision-checked atomic writes, `stat`, `readSlice`, `create`, `rename`,
  `trash`, save announcements, and a watch that can be told which folders not
  to enter. `TomMemoryFileSystem` and, in `io.dart`, `TomLocalFileSystem`
  implement it, the latter with per-folder watching on Linux, the
  freedesktop.org trash and the Windows Recycle Bin. Taken out of
  `tom_forge_core` (where the names were `Forge`-prefixed) before its first
  release; applying a multi-file workspace edit stayed in Forge.
