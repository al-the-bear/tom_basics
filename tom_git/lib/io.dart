/// A bare git repository on disk, in git's own layout.
///
/// Uses `dart:io`; everything else of the library is in the default entry
/// point, which reaches neither `dart:io` nor Flutter.
library;

export 'src/io/directory_repository.dart';
