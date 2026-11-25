/// Finding external native components — a helper program, a shared library —
/// inside the running application's bundle first, then in the binaries layer
/// named by `TOM_BINARY_PATH`: [TomNativeBinaries], [TomNativeFileKind].
///
/// Needs `dart:io`, so the `tom_basics.dart` barrel does not export it.
library;

export 'src/native/native_binaries.dart';
