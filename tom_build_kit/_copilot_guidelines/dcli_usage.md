# DCli Usage Guidelines

Guidelines for using the DCli library for shell-like operations in tom_build_kit.

## Overview

tom_build_kit uses DCli extensively for build operations: compiling Dart executables, managing file trees, executing shell commands, and cleanup operations.

## Import

```dart
import 'package:dcli/dcli.dart';
```

## Common Patterns in tom_build_kit

### 1. Compilation Commands

```dart
// Execute dart compile
final compileCmd = 'dart compile exe ${join(projectDir, 'bin', entryPoint)} -o $outputPath';
compileCmd.run;

// With progress tracking
start(compileCmd, progress: Progress((line) {
  if (verbose) print(line);
}));
```

### 2. Cleanup Operations (cleanup_config.dart)

```dart
// Delete build artifacts
for (final pattern in cleanupPatterns) {
  find(pattern, recursive: true, workingDirectory: projectRoot)
    .forEach((file) => delete(file.pathTo));
}

// Safe directory cleanup
if (exists(buildDir) && isDirectory(buildDir)) {
  deleteDir(buildDir, recursive: true);
}
```

### 3. File Copying for Distribution

```dart
// Copy binary to output
copy(sourceBinary, truepath(outputDir, basename(sourceBinary)));

// Copy entire tree
copyTree(resourcesDir, outputDir, overwrite: true);
```

### 4. Script Execution

```dart
// Run build scripts
if (exists(preBuildScript) && isExecutable(preBuildScript)) {
  preBuildScript.run;
}

// Run with shell for pipes/redirects
start('script.sh | tee output.log', runInShell: true);
```

### 5. Version Management (versioner_config.dart)

```dart
// Read and parse version files
if (exists(versionFile)) {
  final content = read(versionFile).toList().join('\n');
  // Parse version...
}

// Write updated version
touch(versionFile, create: true);  // Ensure exists
// Write content...
```

## Build-Specific Patterns

### Cross-Platform Target Path

```dart
// Get platform-specific output path
final outputBinary = Platform.isWindows 
  ? truepath(outputDir, '$name.exe')
  : truepath(outputDir, name);
```

### Checking Build Prerequisites

```dart
// Verify dart SDK available
final dartPath = which('dart').path;
if (dartPath == null) {
  throw BuildException('Dart SDK not found on PATH');
}
```

## Best Practices

1. **Use `truepath()`** for all path construction in build configs
2. **Check executability** before running scripts: `isExecutable()`
3. **Use `start()` with `Progress`** for long-running builds to show output
4. **Handle `RunException`** for failed command executions
5. **Clean before build** - use `deleteDir()` with `recursive: true`

## Related Documentation

- [DCli Overview](../../../../_copilot_guidelines/d4rt/dcli_overview.md) - General DCli documentation
- [DCli Scripting Guide](../../../../_copilot_guidelines/d4rt/dcli_scripting_guide.md) - Complete API reference
- [DCli Repository](../../dcli/) - Source code and examples
