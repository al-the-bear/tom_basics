# tom_basics_console

Console and standalone platform utilities for Tom applications — platform detection, console-formatted output, and HTTP client support.

## Features

- **Platform Detection** — `TomStandalonePlatformUtils` with detection for desktop, mobile, web, and individual OS platforms.
- **Console Output** — Markdown-formatted console output via `console_markdown`.
- **HTTP Client** — IO-based HTTP client for standalone Dart applications.
- Re-exports all of `tom_basics` for convenience.

## Getting Started

```yaml
dependencies:
  tom_basics_console: ^1.0.0
```

## Usage

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

final platform = TomStandalonePlatformUtils();
print('Is desktop: ${platform.isDesktop()}');
print('Is macOS: ${platform.isMacOs()}');

// Console-formatted output
platform.out('**Bold** and _italic_ text');
```

## License

BSD-3-Clause — see [LICENSE](LICENSE) for details.
