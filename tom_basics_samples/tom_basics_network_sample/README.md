# tom_basics_network — Sample

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

A runnable, article-grade tour of [`tom_basics_network`](../../tom_basics_network/):
**HTTP retry with exponential backoff** and **local server discovery**. Every
example in this folder stands up its own tiny in-process HTTP server, so the
whole set runs **offline** — no live endpoints, no tokens, no flaky network.

> **Pairs with** the module manual at
> [`tom_ai/basics/tom_basics_network/README.md`](../../tom_basics_network/README.md).
> This sample shows the API *by example*; the manual documents the full surface.

---

## What you will learn

`tom_basics_network` is two small, decoupled subsystems that share nothing but
a package boundary:

1. **HTTP retry** — `withRetry()` re-runs an async operation when it throws a
   *retryable* error, waiting a configured (exponential, by default) delay
   between attempts. You decide what "retryable" means; the library ships a
   sensible default set of transport failures and a `.isRetryable` helper for
   HTTP status codes.

2. **Server discovery** — `ServerDiscovery` finds a running service on the
   local network by probing localhost, your machine's IPv4 addresses, and (by
   default) the whole `/24` subnet, looking for a host that answers `200` with
   a JSON status document.

Neither subsystem holds state, neither needs a platform plugin, and both are
pure Dart on `package:http` and `dart:io`. That makes them easy to exercise in
isolation — which is exactly what this sample does.

---

## Quick start

Run the whole set from this folder:

```bash
cd tom_ai/basics/tom_basics_samples/tom_basics_network_sample
dart pub get
dart run example/run_all_examples.dart
```

You should see seven sections run and a final `7 passed, 0 failed`. The runner
exits non-zero if any example throws, so it doubles as a smoke test.

Run any single concept on its own:

```bash
dart run example/01_retry_with_backoff_example.dart
```

---

## The examples

Ordered from first contact to the discovery internals. Each file is a
self-contained `main()` with its expected output pasted in as a trailing
`// expected output` comment, so every snippet below is provably runnable.

| # | File | Concept |
| - | ---- | ------- |
| 1 | [`01_retry_with_backoff_example.dart`](example/01_retry_with_backoff_example.dart) | `withRetry` succeeding after transient failures, with `onRetry` logging |
| 2 | [`02_retry_exhausted_example.dart`](example/02_retry_exhausted_example.dart) | `RetryExhaustedException` when the budget runs out |
| 3 | [`03_controlling_what_retries_example.dart`](example/03_controlling_what_retries_example.dart) | The retryable-error set and the `shouldRetry` veto |
| 4 | [`04_retryable_status_codes_example.dart`](example/04_retryable_status_codes_example.dart) | `RetryableResponse.isRetryable` status-code classification |
| 5 | [`05_default_backoff_schedule_example.dart`](example/05_default_backoff_schedule_example.dart) | `kDefaultRetryDelaysMs` / `RetryConfig.defaultConfig` |
| 6 | [`06_server_discovery_example.dart`](example/06_server_discovery_example.dart) | `ServerDiscovery.discover` + `DiscoveryOptions` + `DiscoveredServer` |
| 7 | [`07_subnet_addresses_example.dart`](example/07_subnet_addresses_example.dart) | `ServerDiscovery.getSubnetAddresses` — the `/24` arithmetic |

---

## 1 · Retry with backoff

`withRetry<T>` takes an async operation and re-invokes it when it throws a
retryable error, pausing for the configured delay between attempts:

```dart
Future<T> withRetry<T>(
  Future<T> Function() operation, {
  RetryConfig config = RetryConfig.defaultConfig,
  bool Function(Object error)? shouldRetry,
});
```

The crucial design point: **`withRetry` reacts to *thrown errors*, not to HTTP
status codes.** An HTTP `503` is a perfectly successful `Response` object as
far as `package:http` is concerned — nothing throws. So the idiomatic pattern
is to *make* the retry happen: inspect the response, and if its status code is
retryable, throw. The `.isRetryable` extension (example 4) makes that one line.

In this example a flaky local server answers `503` for the first two requests
and `200` for the third. The operation turns each `503` into a thrown
`http.ClientException` (a retryable transport error), so `withRetry` waits and
tries again, and the third attempt sails through:

```dart
final body = await withRetry<String>(
  () async {
    final res = await client.get(url);
    if (res.isRetryable) {
      throw http.ClientException('HTTP ${res.statusCode}', url);
    }
    return res.body;
  },
  config: RetryConfig(
    retryDelaysMs: const [20, 40, 80],
    onRetry: (attempt, error, nextDelay) {
      print('attempt $attempt failed: $error — retrying in $nextDelay');
    },
  ),
);
```

```text
attempt 1 failed: ClientException: HTTP 503, uri=http://127.0.0.1:<port>/status — retrying in 0:00:00.020000
attempt 2 failed: ClientException: HTTP 503, uri=http://127.0.0.1:<port>/status — retrying in 0:00:00.040000
success on attempt 3: {"status":"ready"}
```

> `<port>` is an OS-assigned ephemeral port (the server binds to `:0`), so it
> changes every run. Everything else — the attempt counts, the delays, the
> final body — is stable.

Two things worth noting:

- **The delays are overridden.** The real default schedule is 2/4/8/16/32
  *seconds* (see example 5); here we pass millisecond delays so the example
  finishes instantly. `retryDelaysMs` is just a list, so you can shape the
  curve however you like — flat, linear, exponential, jittered.
- **`onRetry` is for observability, not control.** It fires *before* each wait
  with the attempt number, the error, and the upcoming delay. It cannot change
  the outcome; it is where you log, increment a metric, or surface a "still
  trying…" message.

---

## 2 · When every attempt fails

A retry budget is finite. The number of delays in `retryDelaysMs` is the number
of *retries*; add one for the initial attempt to get the total. When the
operation is still throwing a retryable error after the last delay, `withRetry`
gives up and throws `RetryExhaustedException`:

```dart
class RetryExhaustedException implements Exception {
  final Object lastError;          // the final thrown error
  final StackTrace? lastStackTrace; // its stack trace, if captured
  final int attempts;              // total attempts = initial try + retries
}
```

Here the server is always unhappy (`503` every time) and we configure two
delays, so three attempts run before exhaustion:

```dart
try {
  await withRetry<String>(
    () async {
      final res = await client.get(url);
      if (res.isRetryable) {
        throw http.ClientException('HTTP ${res.statusCode}', url);
      }
      return res.body;
    },
    config: const RetryConfig(retryDelaysMs: [10, 20]), // 2 retries => 3 tries
  );
} on RetryExhaustedException catch (e) {
  print('gave up after ${e.attempts} attempts');
  print('last error type: ${e.lastError.runtimeType}');
  print('has stack trace: ${e.lastStackTrace != null}');
}
```

```text
gave up after 3 attempts
last error type: ClientException
has stack trace: true
```

The exception carries the *last* error rather than the first — that's the one
most likely to describe why the system is still down — and the stack trace from
where it was thrown, so the failure reads cleanly in logs even ten frames away
from the original call.

---

## 3 · Controlling what gets retried

`withRetry` is deliberately conservative about what it retries. Retrying a bug
is pointless: the code will fail the same way every time, and you'll just wait
out the whole schedule before surfacing the real error. So only a fixed set of
**transport failures** is retryable:

| Error | Why it's retryable |
| ----- | ------------------ |
| `SocketException` | Connection refused / reset — the peer may recover |
| `HttpException` | Malformed or interrupted HTTP exchange |
| `TimeoutException` | The request ran out of time — a retry may be faster |
| `http.ClientException` | `package:http`'s transport-level failure |
| `OSError` | Low-level connection problem |

Anything else — a `FormatException`, an `ArgumentError`, a `StateError` — is
re-thrown on the first attempt, untouched. The optional `shouldRetry` callback
can only **narrow** this set further: it runs for an otherwise-retryable error,
and returning `false` vetoes the retry. It cannot *widen* the set (a non-
retryable error is rejected before `shouldRetry` is consulted).

This example proves both halves without any network at all — it just throws the
errors directly:

```dart
// Part A: a non-retryable error short-circuits — the operation runs once.
var runsA = 0;
try {
  await withRetry<void>(
    () async {
      runsA++;
      throw const FormatException('malformed payload');
    },
    config: const RetryConfig(retryDelaysMs: [10, 20]),
  );
} on FormatException catch (e) {
  print('A: surfaced ${e.runtimeType} after $runsA run(s)');
}

// Part B: shouldRetry vetoes an otherwise-retryable TimeoutException.
var runsB = 0;
try {
  await withRetry<void>(
    () async {
      runsB++;
      throw TimeoutException('fatal: deadline exceeded');
    },
    config: const RetryConfig(retryDelaysMs: [10, 20]),
    shouldRetry: (error) =>
        !(error is TimeoutException && error.message!.startsWith('fatal')),
  );
} on TimeoutException catch (e) {
  print('B: vetoed ${e.runtimeType} after $runsB run(s)');
}
```

```text
A: surfaced FormatException after 1 run(s)
B: vetoed TimeoutException after 1 run(s)
```

In Part A the `FormatException` is outside the retryable set, so it surfaces on
the first run — `runsA` is `1`. In Part B a `TimeoutException` *would* normally
be retried, but `shouldRetry` recognises the "fatal" marker and returns `false`,
so it surfaces immediately too. The takeaway: the built-in set is the ceiling,
and `shouldRetry` is how you carve out the cases your domain knows are hopeless.

---

## 4 · Which status codes are worth a retry

Turning a response into a retry decision is common enough that the module ships
it as an extension on `http.Response`:

```dart
extension RetryableResponse on http.Response {
  bool get isRetryable; // 5xx, or 408, or 429
}
```

`.isRetryable` is `true` for the entire `5xx` server-error range plus `408`
(Request Timeout) and `429` (Too Many Requests) — the codes where the *same*
request might succeed if you wait. Client errors (`4xx` other than 408/429) are
not retryable: the request itself is wrong, and repeating it won't help.

The example just classifies a spread of codes — pure computation, no server:

```dart
for (final code in [200, 400, 404, 408, 429, 500, 503, 599]) {
  final response = http.Response('', code);
  print('HTTP $code -> ${response.isRetryable ? 'retry' : 'fail fast'}');
}
```

```text
HTTP 200 -> fail fast
HTTP 400 -> fail fast
HTTP 404 -> fail fast
HTTP 408 -> retry
HTTP 429 -> retry
HTTP 500 -> retry
HTTP 503 -> retry
HTTP 599 -> retry
```

This is the helper that example 1 used to decide when to throw. The two pieces
fit together: `.isRetryable` answers *"should I throw?"*, and `withRetry` answers
*"now that something threw, should I wait and try again?"*.

---

## 5 · The default backoff schedule

When you pass no custom delays, `withRetry` uses `kDefaultRetryDelaysMs` —
exponential backoff capped at five retries:

```dart
const List<int> kDefaultRetryDelaysMs = [2000, 4000, 8000, 16000, 32000];
```

That's 2, 4, 8, 16, 32 seconds — roughly 62 seconds of total patience across
five retries (six attempts including the first). `RetryConfig.defaultConfig`
is exactly this schedule with no `onRetry` hook, and it's the default value of
the `config` parameter, so a bare `withRetry(op)` gets it for free.

This example just *inspects* the constants — it never actually sleeps — so you
can see the shape of the policy at a glance:

```dart
final seconds = kDefaultRetryDelaysMs.map((ms) => '${ms ~/ 1000}s').join(', ');
print('retries: ${kDefaultRetryDelaysMs.length}');
print('schedule: $seconds');
final totalMs = kDefaultRetryDelaysMs.fold<int>(0, (sum, ms) => sum + ms);
print('total wait: ${totalMs ~/ 1000}s');
```

```text
retries: 5
schedule: 2s, 4s, 8s, 16s, 32s
total wait: 62s
defaultConfig uses kDefaultRetryDelaysMs: true
```

Exponential backoff is the right default for transient failures: it backs off
fast enough to stop hammering a struggling service, but the early retries are
quick enough to recover from a momentary blip without a long stall. When your
call site has tighter latency requirements, supply your own `retryDelaysMs`
(as examples 1–3 do) — the default is a starting point, not a straitjacket.

---

## 6 · Discovering a server on the network

The second subsystem answers a different question: *"where is the service I
need to talk to?"* `ServerDiscovery.discover()` scans candidate hosts and
returns the first one that answers a `200` with a JSON status document:

```dart
static Future<DiscoveredServer?> discover([DiscoveryOptions options]);
```

The scan order is fixed: **localhost → each local IPv4 → the `/24` subnet**
(the subnet sweep only if `scanSubnet` is on). A host *qualifies* by answering
`200` with a JSON object at `<host>:<port><statusPath>` and — if you supply a
`statusValidator` — passing that check too. The first qualifier wins.

The example stands up a minimal status endpoint on loopback and discovers it.
We set `scanSubnet: false` so the scan stays local and instant, and a
`statusValidator` so only the service we actually want is accepted:

```dart
final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
server.listen((req) async {
  req.response
    ..statusCode = 200
    ..headers.contentType = ContentType.json
    ..write('{"service":"orders-api","version":"2.3.0","port":${server.port}}');
  await req.response.close();
});

final found = await ServerDiscovery.discover(
  DiscoveryOptions(
    port: server.port,
    scanSubnet: false,
    statusPath: '/status',
    statusValidator: (status) => status['service'] == 'orders-api',
  ),
);
```

```text
service: orders-api
version: 2.3.0
reported port matches: true
on loopback: true
```

The returned `DiscoveredServer` exposes the raw `status` map plus typed getters
that read the conventional fields:

| Getter | Reads | Returns |
| ------ | ----- | ------- |
| `serverUrl` | — | The base URL that answered (e.g. `http://127.0.0.1:<port>`) |
| `service` | `status['service']` | The service name |
| `version` | `status['version']` | The reported version |
| `port` | `status['port']` | The port the server claims |
| `status` | — | The full decoded JSON map |

`DiscoveryOptions` is where you tune the scan:

| Option | Default | Purpose |
| ------ | ------- | ------- |
| `port` | `19880` | Port to probe on every candidate |
| `timeout` | `500 ms` | Per-connection timeout (unreachable hosts fail fast) |
| `scanSubnet` | `true` | Whether to sweep the full `/24` |
| `maxConcurrent` | `20` | Batch size for `discoverAll` |
| `statusPath` | `/status` | The status endpoint path |
| `logger` | `null` | Progress callback (`Trying …`, `Found …`) |
| `statusValidator` | `null` | Accept/reject predicate over the JSON map |

When you need *all* the servers rather than the first, `discoverAll()` returns
a list (scanning in `maxConcurrent`-sized batches); `discoverOrThrow()` is
`discover()` that throws `DiscoveryFailedException` instead of returning `null`.

---

## 7 · The `/24` sweep, on its own

`scanSubnet: true` works by expanding each local IP into the other hosts on its
`/24`. `ServerDiscovery.getSubnetAddresses` exposes that arithmetic directly, so
you can see exactly which hosts a scan would touch — and it's pure, so no
network is involved:

```dart
static List<String> getSubnetAddresses(String ip);
```

For `192.168.1.50` it returns `.1` through `.254`, skipping the network address
(`.0`), the broadcast address (`.255`), and the machine's own IP (already probed
directly in step 1 of the scan) — 253 addresses:

```dart
final hosts = ServerDiscovery.getSubnetAddresses('192.168.1.50');
print('count: ${hosts.length}');
print('first: ${hosts.first}');
print('last: ${hosts.last}');
print('includes own ip (.50): ${hosts.contains('192.168.1.50')}');
```

```text
count: 253
first: 192.168.1.1
last: 192.168.1.254
includes own ip (.50): false
includes broadcast (.255): false
includes network (.0): false
malformed -> empty: true
```

A malformed address returns an empty list rather than throwing — discovery
treats "I can't parse this interface address" as "nothing to scan here" and
moves on, which is what you want when iterating over a machine's interfaces.

This also explains the cost model of a subnet scan: 253 hosts per local IPv4,
each tried with the per-connection `timeout`, batched `maxConcurrent` at a time.
On a machine with several interfaces that's a lot of probes — which is why
`discover()` short-circuits on the first match and why pinning `port` and a
`statusValidator` keeps real scans honest.

---

## How this sample stays offline

Both subsystems are about the network, yet the entire sample runs with no
external connectivity. The trick is the same one used throughout: each example
binds a throwaway server to the loopback interface on an OS-assigned port —

```dart
final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
```

— points the code under test at `127.0.0.1:<that port>`, and closes the server
in a `finally`. Discovery finds it because `127.0.0.1` is the very first
candidate it probes; retry exercises it because we control exactly which status
codes it returns. The classification and arithmetic examples (4, 5, 7) need no
server at all — they're pure functions over constants.

Because the servers are in-process and the retry delays are milliseconds, the
whole set finishes in well under a second.

---

## Concept reference

Everything this sample touches, in one place:

**HTTP retry**

- `withRetry<T>(operation, {config, shouldRetry})` — retry an async op
- `RetryConfig({retryDelaysMs, onRetry})` — schedule + observability hook
- `RetryConfig.defaultConfig` — the standard 2/4/8/16/32 s schedule
- `kDefaultRetryDelaysMs` — the default schedule as a raw list
- `RetryExhaustedException` — `lastError`, `lastStackTrace`, `attempts`
- `RetryableResponse.isRetryable` — status-code classifier (`5xx`, 408, 429)

**Server discovery**

- `ServerDiscovery.discover([options])` — first match, or `null`
- `ServerDiscovery.discoverOrThrow([options])` — first match, or throw
- `ServerDiscovery.discoverAll([options])` — every match
- `ServerDiscovery.getLocalIpAddresses()` — non-loopback IPv4s
- `ServerDiscovery.getSubnetAddresses(ip)` — the `/24` host list
- `DiscoveryOptions({port, timeout, scanSubnet, maxConcurrent, statusPath, logger, statusValidator})`
- `DiscoveredServer` — `serverUrl`, `service`, `version`, `port`, `status`
- `DiscoveryFailedException` — thrown by `discoverOrThrow`

---

## Where to go next

- **The module manual** — full API surface, design notes, and the test
  inventory: [`tom_basics_network/README.md`](../../tom_basics_network/README.md).
- **The samples index** — the whole learning path across the basics packages:
  [`tom_basics_samples/README.md`](../README.md).
- **The basics map** — every package under
  [`tom_ai/basics/`](../../README.md).
