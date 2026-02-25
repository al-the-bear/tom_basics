# Tom Basics

Basic utilities for the TOM framework with minimal dependencies.

## Features

- **TomBaseException** - Base exception class with UUID tracking and stack trace support

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  tom_basics: ^1.0.0
```

## Usage

### Exception Handling

```dart
import 'package:tom_basics/tom_basics.dart';

// Create and throw a tracked exception
throw TomBaseException(
  'USER_NOT_FOUND',
  'The requested user could not be found',
  parameters: {'userId': userId},
);

// Catch and inspect
try {
  // ... operation that may fail
} on TomBaseException catch (e) {
  print('Error ${e.uuid}: ${e.key}');
  print('Message: ${e.defaultUserMessage}');
  e.printStackTrace();
}
```

## Additional Information

This package provides foundational utilities that are used by other TOM framework packages, including:

- `tom_crypto` - Cryptographic utilities
- `tom_core_kernel` - Core kernel library

## License

BSD-3-Clause - See [LICENSE](LICENSE) for details.
