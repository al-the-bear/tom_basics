/// The local file system: [TomLocalFileSystem], with the platform parts it
/// stands on — one watch per directory where the platform has no recursive
/// watch, the freedesktop.org home trash, and the Windows Recycle Bin.
///
/// Uses `dart:io` and `dart:ffi`; a browser build takes
/// `tom_file_system.dart` alone.
library;

export 'tom_file_system.dart';
export 'src/io/directory_watches.dart';
export 'src/io/local_file_system.dart';
export 'src/io/xdg_trash.dart';
export 'src/io/windows_recycle_bin.dart';
