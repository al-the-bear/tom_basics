/// Tracks results of processing operations across multiple projects.
class ProcessingResult {
  /// Number of successfully processed projects
  int successCount;
  
  /// Number of failed project operations
  int failureCount;
  
  /// Total number of files processed
  int fileCount;
  
  /// Creates a new processing result with default values.
  ProcessingResult({
    this.successCount = 0,
    this.failureCount = 0,
    this.fileCount = 0,
  });

  /// Records a successful project operation.
  /// 
  /// [files] - Number of files processed in this operation (default 0)
  void addSuccess([int files = 0]) {
    successCount++;
    fileCount += files;
  }

  /// Records a failed project operation.
  void addFailure() {
    failureCount++;
  }

  /// Merges another result into this one.
  void merge(ProcessingResult other) {
    successCount += other.successCount;
    failureCount += other.failureCount;
    fileCount += other.fileCount;
  }

  /// Returns true if any operations were performed.
  bool get hasResults => successCount > 0 || failureCount > 0;

  /// Returns true if all operations succeeded.
  bool get isSuccess => failureCount == 0;

  /// Returns true if any operation failed.
  bool get hasFailures => failureCount > 0;

  /// Total number of operations (successful + failed).
  int get totalCount => successCount + failureCount;

  @override
  String toString() {
    return 'ProcessingResult(success: $successCount, failed: $failureCount, files: $fileCount)';
  }
}
