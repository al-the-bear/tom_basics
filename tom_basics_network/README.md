# tom_basics_network

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Network utilities for Tom applications — HTTP retry with exponential backoff
and LAN server discovery.

`tom_basics_network` packages the two networking concerns that almost every
distributed Tom application needs but that the standard `http` package leaves
to the caller: **surviving transient failures** and **finding a peer on the
local network without a configured address**. It is a small, focused, pure-Dart
package — two independent subsystems, no shared state, no platform plugins —
built directly on `package:http` and `dart:io`.

The two subsystems are deliberately decoupled. You can take `withRetry` to wrap
any `Future`-returning operation and never touch discovery, or use
`ServerDiscovery` to locate a server and hand the URL to your own client. They
share a package only because they share an audience: code that talks to other
machines over an unreliable link.

---

## Overview

A networked operation fails for two broad reasons. Either the *transport*
hiccuped — a dropped socket, a timeout, a server that returned `503` because it
was briefly overloaded — or something is *actually wrong* — a `404`, a
malformed request, an authentication failure. The first kind is worth retrying;
the second is not. Retrying a `400` just wastes time and hammers the server.

`tom_basics_network` encodes that distinction:

- **HTTP retry** (`withRetry`, `RetryConfig`, `RetryableResponse`) — wraps an
  operation in a backoff loop that retries *only* transient transport errors
  and *only* retryable HTTP status codes (`5xx`, `408`, `429`), and surfaces a
  single `RetryExhaustedException` when the budget runs out.
- **Server discovery** (`ServerDiscovery`, `DiscoveryOptions`,
  `DiscoveredServer`) — probes `localhost`, this machine's own LAN addresses,
  and (optionally) the whole `/24` subnet for a Tom server answering a
  known status endpoint, returning the first match, all matches, or throwing if
  none respond.

Neither subsystem holds state between calls. `withRetry` is a top-level
function; `ServerDiscovery` exposes only static methods. Configuration is
passed in per call as immutable value objects (`RetryConfig`,
`DiscoveryOptions`), so the same code is safe to call concurrently from
multiple isolates.

---

## Installation

```yaml
dependencies:
  tom_basics_network: ^1.0.1
```

Or from the command line:

```sh
dart pub add tom_basics_network
```

Then import the single entry point:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';
```

Requires Dart SDK `^3.10.4`. The package depends only on
[`package:http`](https://pub.dev/packages/http); everything else comes from the
Dart core libraries (`dart:io`, `dart:async`). It runs on any platform with
`dart:io` (desktop, server, CLI) — server discovery uses `dart:io` networking
and is not available on the web.

---

## Features

### HTTP retry

| API | Kind | Purpose |
| --- | --- | --- |
| `withRetry<T>` | function | Run an operation, retrying transient failures with backoff |
| `RetryConfig` | class | Per-call retry policy: delay schedule + retry callback |
| `RetryConfig.defaultConfig` | const | The default policy (5 retries: 2/4/8/16/32 s) |
| `kDefaultRetryDelaysMs` | const list | The default backoff schedule in milliseconds |
| `RetryExhaustedException` | exception | Thrown when every retry has failed |
| `RetryableResponse` | extension | `http.Response.isRetryable` for status-code checks |

### Server discovery

| API | Kind | Purpose |
| --- | --- | --- |
| `ServerDiscovery.discover` | static | First server found, or `null` |
| `ServerDiscovery.discoverOrThrow` | static | First server found, or throw |
| `ServerDiscovery.discoverAll` | static | Every reachable server |
| `ServerDiscovery.getLocalIpAddresses` | static | This machine's non-loopback IPv4 addresses |
| `ServerDiscovery.getSubnetAddresses` | static | The 253 other hosts in a `/24` |
| `DiscoveryOptions` | class | Port, timeout, concurrency, subnet toggle, validator |
| `DiscoveredServer` | class | A found server: URL + parsed status payload |
| `DiscoveryFailedException` | exception | Thrown by `discoverOrThrow` when nothing answers |

---

## Quick start

### Retry a flaky request

```dart
import 'package:http/http.dart' as http;
import 'package:tom_basics_network/tom_basics_network.dart';

Future<String> fetchScore() => withRetry(() async {
      final response = await http.get(Uri.parse('https://example.com/score'));
      if (response.isRetryable) {
        // A 5xx/408/429 — throw so withRetry backs off and tries again.
        throw http.ClientException('transient ${response.statusCode}');
      }
      return response.body;
    });
```

With no `RetryConfig`, `withRetry` uses `RetryConfig.defaultConfig`: up to five
retries spaced 2 s, 4 s, 8 s, 16 s, 32 s apart. A `ClientException` is one of
the error types it treats as transient, so the call above retries on those
status codes and rethrows anything else immediately.

### See the backoff schedule

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

void main() {
  final schedule = kDefaultRetryDelaysMs.map((ms) => '${ms / 1000}s').join(', ');
  print('Default retry schedule: $schedule');
}
```

Output:

```text
Default retry schedule: 2.0s, 4.0s, 8.0s, 16.0s, 32.0s
```

### Find a Tom server on the LAN

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  final server = await ServerDiscovery.discover();
  if (server == null) {
    print('No server responded.');
    return;
  }
  print('Found ${server.service} v${server.version} at ${server.serverUrl}');
}
```

`discover()` returns the first server that answers `GET /status` with `200` and
a JSON object, scanning `localhost` first, then this machine's LAN addresses,
then the rest of the `/24`. It returns `null` rather than throwing when nothing
answers — see [`discoverOrThrow`](#fail-loudly-when-no-server-is-found) for the
throwing variant.

---

## Example projects

| Example | What it shows |
| --- | --- |
| [`example/tom_basics_network_example.dart`](example/tom_basics_network_example.dart) | The default and a custom retry schedule, printed |

Run it with:

```sh
dart run example/tom_basics_network_example.dart
```

> A runnable `tom_basics_network_sample` covering the full retry and discovery
> surface is planned under `../tom_basics_samples/`; until it lands, the usage
> sections below are the worked reference.

---

## Usage

### HTTP retry

#### What counts as retryable

`withRetry` retries an operation when it throws one of these *transport* errors:

- `SocketException` — connection refused / reset / no route
- `HttpException` — a `dart:io` HTTP-layer failure
- `TimeoutException` — the operation took too long
- `http.ClientException` — a `package:http` transport failure
- `OSError` — a lower-level OS networking error

Anything else — an `ArgumentError`, a `FormatException`, a thrown `404`
handler — is **not** retried and propagates immediately. The point is to retry
the network, not your bugs.

For HTTP *status codes*, the `RetryableResponse` extension classifies a
response without you memorising the numbers:

```dart
import 'package:http/http.dart' as http;
import 'package:tom_basics_network/tom_basics_network.dart';

bool worthRetrying(http.Response r) => r.isRetryable;
// true for 500–599, 408 (Request Timeout), 429 (Too Many Requests)
// false for 200, 404, 400, 401, ...
```

Because `withRetry` reacts to *thrown* errors, the idiom is to inspect the
response and throw a transient error when `isRetryable` is true (as in the
quick-start example), letting non-retryable responses return normally.

#### Configuring the backoff

`RetryConfig` carries two things: the delay schedule and an optional callback.

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

const fastConfig = RetryConfig(
  // Three retries: 100 ms, 200 ms, 400 ms.
  retryDelaysMs: [100, 200, 400],
  onRetry: _logRetry,
);

void _logRetry(int attempt, Object error, Duration nextDelay) {
  print('attempt $attempt failed ($error); retrying in '
      '${nextDelay.inMilliseconds}ms');
}
```

The length of `retryDelaysMs` *is* the retry budget: a list of three delays
means the operation runs at most four times (one initial attempt plus three
retries). `onRetry` fires once before each backoff sleep, receiving the 1-based
attempt number, the error that triggered the retry, and the delay about to be
waited — useful for logging or metrics without changing the control flow.

#### Narrowing what gets retried

Pass a `shouldRetry` predicate to override the default transport-error set. When
supplied, an error is retried only if **both** `shouldRetry(error)` returns true
*and* the error is in the built-in retryable set:

```dart
import 'dart:io';
import 'package:tom_basics_network/tom_basics_network.dart';

final result = await withRetry(
  _doRequest,
  shouldRetry: (error) => error is SocketException, // timeouts won't retry
);
```

This lets you be *stricter* than the default (retry connection failures but not
timeouts, say). It cannot make a non-transport error retryable — that set is
the floor.

#### When retries run out

After the last delay, `withRetry` gives up by throwing `RetryExhaustedException`,
which packages the final failure for inspection:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

try {
  await withRetry(_doRequest, config: const RetryConfig(retryDelaysMs: [50, 50]));
} on RetryExhaustedException catch (e) {
  print('Gave up after ${e.attempts} attempts; last error: ${e.lastError}');
  // e.lastStackTrace is available for logging the original failure site.
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `lastError` | `Object` | The error from the final failed attempt |
| `lastStackTrace` | `StackTrace?` | Where that error was thrown |
| `attempts` | `int` | Total attempts made (initial + retries) |

### Server discovery

#### How a scan proceeds

`ServerDiscovery` looks for a Tom server by probing candidate hosts in order of
likelihood:

```text
ServerDiscovery.discover(options)
        │
        ├─ 1. localhost            (the same machine)
        ├─ 2. local IPv4 addresses (this host's LAN interfaces)
        └─ 3. /24 subnet           (the other 253 hosts) — only if scanSubnet
                 │
                 └─ for each candidate: GET http://<host>:<port><statusPath>
                        expect 200 + JSON object → DiscoveredServer
```

Each probe is a single `GET` to `http://<host>:<port><statusPath>` with a short
timeout. A host qualifies when it answers `200` with a JSON object body; that
object becomes the `DiscoveredServer.status` map. Subnet scanning is batched so
no more than `maxConcurrent` probes are in flight at once.

#### Choosing the right entry point

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

// Best effort — null when nothing answers.
final maybe = await ServerDiscovery.discover();

// Every server on the network (e.g. to pick or list them).
final all = await ServerDiscovery.discoverAll();
print('Found ${all.length} server(s).');
```

<a id="fail-loudly-when-no-server-is-found"></a>
When a missing server is a hard error, `discoverOrThrow` saves you the
null-check:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

try {
  final server = await ServerDiscovery.discoverOrThrow();
  print('Connected to ${server.serverUrl}');
} on DiscoveryFailedException catch (e) {
  print('Discovery failed: $e');
}
```

#### Tuning the scan

`DiscoveryOptions` controls every knob; all fields have defaults and
`copyWith` makes per-call tweaks ergonomic:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

const base = DiscoveryOptions(
  port: 8080,           // default 19880
  scanSubnet: false,    // localhost + local IPs only — fast, no subnet sweep
);

final verbose = base.copyWith(
  timeout: const Duration(seconds: 1),
  logger: print,       // trace each candidate as it is probed
);
```

| Field | Default | Purpose |
| --- | --- | --- |
| `port` | `19880` | TCP port probed on each host |
| `timeout` | `500 ms` | Per-host connection/response timeout |
| `scanSubnet` | `true` | Whether to sweep the `/24` after local checks |
| `maxConcurrent` | `20` | Max simultaneous probes during a subnet sweep |
| `statusPath` | `/status` | Path appended to each candidate URL |
| `logger` | `null` | Optional `void Function(String)` progress trace |
| `statusValidator` | `null` | Optional extra check on the parsed status map |

Use `statusValidator` to reject servers that answer but aren't the one you
want — for example, requiring a specific `service` name:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

const options = DiscoveryOptions(
  statusValidator: _isLedgerService,
);

bool _isLedgerService(Map<String, dynamic> status) =>
    status['service'] == 'tom_dist_ledger';
```

#### Reading a discovered server

`DiscoveredServer` pairs the URL with the parsed status payload and surfaces the
common fields as typed getters:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

void describe(DiscoveredServer s) {
  print('URL:     ${s.serverUrl}');
  print('Service: ${s.service}');   // status['service']
  print('Version: ${s.version}');   // status['version']
  print('Port:    ${s.port}');      // status['port']
  // Anything else is in s.status, the raw decoded JSON map.
}
```

#### Working with addresses directly

The two address helpers that drive the scan are public, so you can reuse them
for your own probing:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  final mine = await ServerDiscovery.getLocalIpAddresses();
  print('This host: $mine');

  // Every other host in a /24, excluding the address you pass in.
  final peers = ServerDiscovery.getSubnetAddresses('192.168.1.100');
  print('${peers.length} candidates'); // 253: .1 … .254 minus .100
}
```

---

## Architecture

```text
package:tom_basics_network/tom_basics_network.dart   (single entry point)
        │
        ├── src/http_retry.dart
        │     withRetry<T>()  ──uses──▶ RetryConfig ──holds──▶ delays + onRetry
        │         │
        │         ├─ classifies errors  (SocketException, TimeoutException, …)
        │         ├─ RetryableResponse   (status-code helper on http.Response)
        │         └─ throws RetryExhaustedException when the budget is spent
        │
        └── src/server_discovery.dart
              ServerDiscovery (static)
                  │  discover / discoverOrThrow / discoverAll
                  ├─ getLocalIpAddresses / getSubnetAddresses
                  ├─ probes GET <host>:<port><statusPath>
                  └─ DiscoveryOptions → DiscoveredServer | DiscoveryFailedException
```

The package exposes no mutable singletons and no initialisation step. Both
subsystems are pure functions over immutable configuration, which keeps them
trivially testable and isolate-safe.

| Type | Role |
| --- | --- |
| `withRetry<T>` | The retry loop; the only stateful logic, scoped to one call |
| `RetryConfig` | Immutable retry policy (delays + `onRetry` callback) |
| `RetryExhaustedException` | Carries the final error, stack trace, attempt count |
| `RetryableResponse` | Extension classifying HTTP status codes |
| `ServerDiscovery` | Static façade over the probe/scan logic |
| `DiscoveryOptions` | Immutable scan policy with `copyWith` |
| `DiscoveredServer` | A result: URL plus parsed status map |
| `DiscoveryFailedException` | Raised by `discoverOrThrow` on an empty scan |

---

## Ecosystem

`tom_basics_network` is one of the [`tom_ai/basics`](../) foundation packages:

- [`tom_basics`](../tom_basics/) — exceptions, logging, the platform seam, and
  the runtime model that the rest of the basics layer builds on.
- [`tom_basics_console`](../tom_basics_console/) — the standalone/server
  platform implementation, including an IO-based HTTP client that pairs
  naturally with `withRetry`.

This package depends on neither — it stands alone on `package:http` and
`dart:io` — but it is built to sit alongside them in a Tom application. A typical
server uses `tom_basics_console` for its platform layer, `withRetry` to harden
its outbound calls, and `ServerDiscovery` to locate its peers.

---

## Further documentation

- [`example/tom_basics_network_example.dart`](example/tom_basics_network_example.dart)
  — runnable demonstration of the retry schedule.
- [`test/tom_basics_network_test.dart`](test/tom_basics_network_test.dart) —
  the behavioural specification: retry success/exhaustion, error classification,
  subnet maths, and option defaults.
- [`../README.md`](../README.md) — the `tom_ai/basics` package map.

---

## Status

- **Version:** 1.0.1
- **Tests:** 12 passing (`dart test`) — `RetryConfig`,
  `RetryExhaustedException`, `withRetry`, and `ServerDiscovery`.
- **Analysis:** clean under `package:lints` (`dart analyze` — no issues).
- **Platforms:** any Dart runtime with `dart:io` (desktop, server, CLI).
