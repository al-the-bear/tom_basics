/// The file-system contract and everything that works without a disk: the
/// contract and its values, the change and save events, the shared base, the
/// in-memory file system and the text test.
///
/// Reaches no `dart:io` and no Flutter, so a browser build links it. The
/// local file system is [`io.dart`](io.dart).
library;

export 'src/file_system.dart';
export 'src/file_system_base.dart';
export 'src/memory_file_system.dart';
export 'src/text_detection.dart';
