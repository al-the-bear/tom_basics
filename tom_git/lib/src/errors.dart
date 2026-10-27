/// Failures that are not about the wire.
library;

/// Raised when a folder holds no git repository.
///
/// In the default entry point although only `io.dart` opens a folder, so a
/// caller that reaches repositories through an injected opener can recognise
/// it without importing `dart:io`.
class GitNotARepositoryException implements Exception {
  GitNotARepositoryException(this.path);

  /// The folder that was opened.
  final String path;

  @override
  String toString() =>
      'GitNotARepositoryException: $path is not a git '
      'repository (no .git in it, and it is not a bare repository)';
}
