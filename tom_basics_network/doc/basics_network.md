# Tom Basics Network — User Guide

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](../LICENSE).

This guide describes how the two parts of Tom Basics Network behave: the retry
loop (`withRetry`) and LAN server discovery (`ServerDiscovery`). The
[README](../README.md) lists the API and shows the first steps; this page is
about what happens inside a call, what it costs, and where its limits are.

Everything is imported from the single library:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';
```

---

## 1. Concepts

| Concept | Meaning |
| ------- | ------- |
| **Operation** | A `Future<T> Function()` handed to `withRetry`. It is called once per attempt. |
| **Attempt** | One call of the operation. A schedule of *n* delays allows *n + 1* attempts. |
| **Transient error** | An error type `withRetry` is willing to retry: `SocketException`, `HttpException` (`dart:io`), `TimeoutException`, `http.ClientException`, `OSError`. |
| **Retryable status** | An HTTP status that `Response.isRetryable` reports: `500`–`599`, `408`, `429`. |
| **Candidate** | A base URL `http://<host>:<port>` that discovery probes. |
| **Probe** | One `GET <candidate><statusPath>`; it qualifies a server when it answers `200` with a JSON object. |

The two parts share no state and no types. Each call takes its configuration
as an immutable value (`RetryConfig`, `DiscoveryOptions`), so concurrent calls
do not influence each other.

---

## 2. Retrying an operation

### 2.1 The loop

`withRetry(operation, {config, shouldRetry})` runs this loop:

1. Call `operation()`. If it completes, return its value.
2. If it throws, decide whether to retry:
   - when `shouldRetry` is given and answers `false`, the error is rethrown
     unchanged;
   - when the error is not a transient error (section 1), it is rethrown
     unchanged;
   - when no delay is left in the schedule, `RetryExhaustedException` is thrown.
3. Otherwise call `config.onRetry(attempt, error, delay)`, wait `delay`, and go
   back to step 1.

The delay schedule is `config.retryDelaysMs`, used in order; the default is
`kDefaultRetryDelaysMs` = `[2000, 4000, 8000, 16000, 32000]`, i.e. five retries
and at most 62 seconds of waiting. There is no jitter and no cap other than the
list itself: the schedule is exactly the list you pass.

```dart
import 'dart:async';

import 'package:tom_basics_network/tom_basics_network.dart';

Future<void> main() async {
  var calls = 0;
  final value = await withRetry(
    () async {
      calls++;
      if (calls < 3) throw TimeoutException('slow');
      return 'ok after $calls calls';
    },
    config: RetryConfig(
      retryDelaysMs: const [10, 10, 10],
      onRetry: (attempt, error, delay) =>
          print('retry $attempt in ${delay.inMilliseconds} ms'),
    ),
  );
  print(value);
}
// retry 1 in 10 ms
// retry 2 in 10 ms
// ok after 3 calls
```

### 2.2 The callback

`onRetry` is called once before every wait, never after the last failure. Its
`attempt` argument is 1-based and names the attempt that just failed. The
callback cannot change the schedule or stop the loop; to stop early, throw from
the operation an error that is not transient, or use `shouldRetry`.

### 2.3 `shouldRetry` narrows, it does not widen

`shouldRetry` is checked before the built-in classification, and both must
agree for a retry. A predicate that answers `true` for a `FormatException` does
not make it retryable — the error is still rethrown at once. Use it to be
stricter, for example to retry refused connections but not timeouts:

```dart
final body = await withRetry(
  fetch,
  shouldRetry: (error) => error is SocketException,
);
```

### 2.4 HTTP status codes

`withRetry` only reacts to thrown errors. An `http.Response` with status `503`
is a normal return value and ends the loop. To retry on status codes, check
`response.isRetryable` inside the operation and throw a transient error:

```dart
final body = await withRetry(() async {
  final response = await http.get(uri);
  if (response.isRetryable) {
    throw http.ClientException('status ${response.statusCode}', uri);
  }
  return response.body;
});
```

A `Retry-After` header on a `429` is not read; the schedule decides the wait.

### 2.5 When the budget is spent

`RetryExhaustedException` carries:

| Field | Content |
| ----- | ------- |
| `lastError` | The error of the final attempt. |
| `lastStackTrace` | Its stack trace. |
| `attempts` | Total attempts, the initial one included (schedule length + 1). |

Its `toString()` reads
`RetryExhaustedException: All <n> attempts failed. Last error: <error>`.

Note which errors reach the caller unchanged: anything non-transient, and
anything `shouldRetry` rejected. Code that calls `withRetry` therefore catches
`RetryExhaustedException` for "the network kept failing" and its own error
types for everything else.

### 2.6 Edge cases

- `RetryConfig(retryDelaysMs: [])` runs the operation once; a transient error
  then becomes `RetryExhaustedException` with `attempts == 1`.
- The operation is called again from scratch on every attempt. Any side effect
  it has before failing (a partly sent upload, a counter) repeats; make the
  operation idempotent or guard it yourself.
- The loop waits with `Future.delayed`; it cannot be cancelled from outside.

---

## 3. Discovering a server

### 3.1 Which hosts are probed

Every entry point builds the same candidate list, in this order:

1. `http://127.0.0.1:<port>` and `http://localhost:<port>`;
2. `http://<ip>:<port>` for each non-loopback IPv4 address of this machine
   (`getLocalIpAddresses`);
3. when `scanSubnet` is true: for each distinct `/24` among those addresses,
   `.1` to `.254` of that subnet, skipping URLs already in the list.

A machine with Ethernet, Wi-Fi and a VPN therefore sweeps three subnets.
`getLocalIpAddresses` answers an empty list when the interfaces cannot be
listed; discovery then probes only `localhost`.

### 3.2 What qualifies a server

A probe is one `GET http://<host>:<port><statusPath>` through `dart:io`'s
`HttpClient`. The host qualifies when:

- the connection is made within `timeout`, and the response headers arrive
  within `timeout`;
- the status is `200`;
- the body is a JSON **object** (an array, a string or an empty body do not
  count);
- `statusValidator`, when given, answers `true` for that object.

Every failure — refused, timed out, HTTP error, malformed JSON, rejected by the
validator — makes the probe answer "no server" silently. Discovery never throws
because of a single host.

### 3.3 The three entry points

| Method | Order of probing | Result |
| ------ | ---------------- | ------ |
| `discover([options])` | One candidate at a time, in list order | The first match, or `null` |
| `discoverOrThrow([options])` | As `discover` | The first match, or `DiscoveryFailedException('No server found on port <port>')` |
| `discoverAll([options])` | In batches of `maxConcurrent`, all batches | Every match, in candidate order |

Two consequences follow from the order:

- `discover` is fast when the server runs on this machine and slow when it
  does not: with the defaults, a full sweep of one empty subnet is up to 253
  sequential probes, each of which can wait out the 500 ms connect timeout.
  Set `scanSubnet: false` when the server is known to be local, or use
  `discoverAll` (which is parallel) and take the first result.
- `discoverAll` reports one server once per URL it answered on. A server on
  this machine typically appears as `127.0.0.1`, `localhost` and this host's
  LAN address when it listens on all interfaces. De-duplicate by a field of
  the status payload when that matters.

### 3.4 Options

| Field | Default | Effect |
| ----- | ------- | ------ |
| `port` | `19880` | Port used for every candidate. |
| `timeout` | `500 ms` | Connect timeout and response-header timeout of each probe. |
| `scanSubnet` | `true` | Sweep the `/24` subnets (step 3 of 3.1). |
| `maxConcurrent` | `20` | Batch size of `discoverAll`; `discover` ignores it. |
| `statusPath` | `/status` | Path appended to each candidate. |
| `logger` | `null` | Called with `Trying <url>...` per probe and `Found server at <url>` per match. |
| `statusValidator` | `null` | Extra check on the decoded payload. |

`copyWith` returns a changed copy. Passing `null` to it keeps the current value,
so it cannot remove a `logger` or `statusValidator`; construct a new
`DiscoveryOptions` for that.

### 3.5 Reading the result

`DiscoveredServer.serverUrl` is the candidate base URL without the status path
(for example `http://192.168.1.20:19880`). `status` is the decoded payload.
The getters `service`, `version` and `port` read `status['service']`,
`status['version']` and `status['port']` and expect a `String`, a `String` and
an `int`; a payload with another type in one of those fields makes that getter
throw a `TypeError`. Read `status` directly when the server's payload shape is
not under your control.

### 3.6 Writing a discoverable server

A server is found when it listens on the probed port on an IPv4 interface and
answers the status path with `200` and a JSON object. A payload that works with
the typed getters:

```json
{"service": "my_service", "version": "1.2.0", "port": 19880}
```

Clients then select it with
`DiscoveryOptions(statusValidator: (s) => s['service'] == 'my_service')`.

### 3.7 Limits

- IPv4 only; IPv6 interfaces are not listed or probed.
- Only `/24` subnets are swept, whatever the real netmask is.
- Plain `http`; there is no TLS probing.
- `dart:io` is required, so discovery does not run in a browser.
- A probe opens a connection to every candidate host. On networks where port
  scans are monitored, keep `scanSubnet: false`.

---

## 4. Address helpers

The two helpers behind the candidate list are public:

```dart
import 'package:tom_basics_network/tom_basics_network.dart';

void main() {
  final peers = ServerDiscovery.getSubnetAddresses('10.8.0.7');
  print(peers.length); // 253
  print(peers.first); // 10.8.0.1
  print(peers.contains('10.8.0.7')); // false
  print(ServerDiscovery.getSubnetAddresses('not-an-ip')); // []
}
```

`getSubnetAddresses` splits on dots and needs exactly four parts; it does not
validate the numbers. `getLocalIpAddresses` is asynchronous because it lists
the network interfaces.

---

## 5. See also

- [README](../README.md) — installation, feature tables, quick start.
- [`example/tom_basics_network_example.dart`](../example/tom_basics_network_example.dart)
  — the default and a custom retry schedule.
- [`test/tom_basics_network_test.dart`](../test/tom_basics_network_test.dart) —
  the behaviour above, as tests.
- [CHANGELOG](../CHANGELOG.md).
