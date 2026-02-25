# DCli Usage Guidelines

Guidelines for using the DCli library for shell-like operations in tom_build_base.

## Overview

tom_build_base uses DCli for file system operations, process execution, and path manipulation. The DCli library is preferred over direct `dart:io` calls for cleaner, more readable code.

## Import

```dart
import 'package:dcli/dcli.dart';
```

## Common Patterns in tom_build_base

### 1. File Discovery (folder_scanner.dart)

```dart
// Find all Dart files
find('*.dart', recursive: true, workingDirectory: projectPath)
  .forEach((file) => processFile(file.pathTo));

// Check if file exists before processing
if (exists(configPath) && isFile(configPath)) {
  final content = read(configPath).toList();
}
```

### 2. Directory Operations

```dart
// Create output directory
if (!exists(outputDir)) {
  createDir(outputDir, recursive: true);
}

// Clean and recreate
if (exists(tempDir)) {
  deleteDir(tempDir, recursive: true);
}
createDir(tempDir);
```

### 3. Process Execution

```dart
// Run dart commands
'dart pub get'.run;

// Capture output
final version = 'dart --version'.firstLine ?? 'unknown';

// Handle failures gracefully
final result = 'command'.toList(nothrow: true);
```

### 4. Path Construction

```dart
// Build paths safely
final pubspecPath = truepath(projectRoot, 'pubspec.yaml');
final testDir = join(projectRoot, 'test');
final parentDir = dirname(filePath);
```

## Best Practices

1. **Use `truepath()` for absolute paths** - ensures consistent path resolution
2. **Check existence before operations** - use `exists()`, `isFile()`, `isDirectory()`
3. **Use `nothrow: true`** - when command failure is expected/acceptable
4. **Prefer `.toList()` over `.run`** - when output needs processing
5. **Handle DCli exceptions** - `CopyException`, `DeleteException`, etc.

## Related Documentation

- [DCli Overview](../../../../_copilot_guidelines/d4rt/dcli_overview.md) - General DCli documentation
- [DCli Scripting Guide](../../../../_copilot_guidelines/d4rt/dcli_scripting_guide.md) - Complete API reference
- [DCli Repository](../../dcli/) - Source code and examples
