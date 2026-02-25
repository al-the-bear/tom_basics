# tom_basics_network

Network utilities for Tom applications — HTTP retry with exponential backoff and network server discovery.

## Features

- **HTTP Retry** — Automatic retry logic with configurable exponential backoff, max attempts, and retry conditions via `RetryConfig`.
- **Server Discovery** — Network-based server discovery for distributed Tom applications.

## Getting Started

```yaml
dependencies:
  tom_basics_network: ^1.0.0
```

## Usage

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

final config = RetryConfig(
  maxAttempts: 3,
  initialDelay: Duration(milliseconds: 500),
);
```

## License

BSD-3-Clause — see [LICENSE](LICENSE) for details.
