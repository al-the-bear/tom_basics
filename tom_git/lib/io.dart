/// Git repositories on disk, in git's own layout: a bare one
/// ([gitOpenDirectory]) and one somebody works in ([GitLocalRepository]).
///
/// Uses `dart:io`; everything else of the library is in the default entry
/// point, which reaches neither `dart:io` nor Flutter.
library;

export 'src/io/directory_repository.dart';
export 'src/io/local_repository.dart';
