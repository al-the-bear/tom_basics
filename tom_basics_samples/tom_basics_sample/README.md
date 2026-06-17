# tom_basics_sample — Exceptions & UUID Tracking, End to End

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](../../tom_basics/LICENSE).

Runnable, article-grade sample for [`tom_basics`](../../tom_basics/): exception
handling and UUID tracking end to end, plus structured logging with bitwise log
levels.

This is the **first stop** on the
[`tom_ai/basics` learning path](../#learning-path). It teaches the two
vocabularies of `tom_basics` you reach for in *every* application — a
self-identifying exception type and a configurable logger — by building them up
one concept at a time, each as a small, runnable program with its expected
output printed inline.

If you want the module's full reference manual, read the
[`tom_basics` README](../../tom_basics/). If you want to *learn it by running
it*, you are in the right place.

---

## Table of contents

- [What you will learn](#what-you-will-learn)
- [The package this teaches](#the-package-this-teaches)
- [Running the samples](#running-the-samples)
- [The example files](#the-example-files)
- [Part 1 — The exception model](#part-1--the-exception-model)
  - [1.1 Throwing and catching](#11-throwing-and-catching)
  - [1.2 The anatomy of a TomBaseException](#12-the-anatomy-of-a-tombaseexception)
  - [1.3 Correlating failures with requestUuid](#13-correlating-failures-with-requestuuid)
  - [1.4 Structured parameters](#14-structured-parameters)
  - [1.5 Wrapping a root cause](#15-wrapping-a-root-cause)
  - [1.6 Stack traces](#16-stack-traces)
- [Part 2 — Structured logging](#part-2--structured-logging)
  - [2.1 The global logger](#21-the-global-logger)
  - [2.2 Log levels are bit patterns](#22-log-levels-are-bit-patterns)
  - [2.3 Filtering by level](#23-filtering-by-level)
  - [2.4 Custom output destinations](#24-custom-output-destinations)
  - [2.5 TomLoggable — curated log forms](#25-tomloggable--curated-log-forms)
- [Part 3 — Putting it together](#part-3--putting-it-together)
- [Architecture](#architecture)
- [Key types](#key-types)
- [Ecosystem](#ecosystem)
- [Further documentation](#further-documentation)
- [Status](#status)

---

## What you will learn

By the end of this sample you will be able to:

- **Raise a domain failure** that carries a stable, machine-readable key, a
  safe user-facing message, and a UUID you can quote and grep for.
- **Correlate** every failure raised while handling one request, without losing
  the ability to tell individual failures apart.
- **Attach structured context** (order ids, amounts, raw inputs) to an error
  without leaking it into the user-facing message.
- **Wrap a low-level cause** (a `FormatException`, an IO error) in a domain
  exception while preserving the original for diagnosis.
- **Configure the logger**: set a level, compose levels with bitwise operators,
  filter noisy output, swap the output destination, and give your own objects a
  deliberate log representation.

Every claim above is backed by a runnable example in [`example/`](example/)
whose output is checked by [`example/run_all_examples.dart`](example/run_all_examples.dart).

---

## The package this teaches

[`tom_basics`](../../tom_basics/) is the foundation package of the Tom
framework. It bundles four small, independent vocabularies; this sample covers
the first two:

| Vocabulary | Type(s) | Covered here |
| ---------- | ------- | ------------ |
| **Exceptions** | `TomBaseException` | ✅ Part 1 |
| **Logging** | `TomLogger` / `tomLog`, `TomLogLevel`, `TomLogOutput`, `TomLoggable` | ✅ Part 2 |
| Platform seam | `TomPlatformUtils` | See [`tom_basics_console_sample`](../tom_basics_console_sample/) |
| Runtime | `TomEnvironment` | See [`tom_basics_console_sample`](../tom_basics_console_sample/) |

The sample depends on `tom_basics` by path, since both live in the same
workspace repo:

```yaml
# pubspec.yaml
dependencies:
  tom_basics:
    path: ../../tom_basics
```

For the package's own grouped feature tables, architecture diagram, and the
platform/runtime vocabularies this sample does not cover, see the
[`tom_basics` manual](../../tom_basics/).

---

## Running the samples

From this sample's folder, run the whole set as a smoke test:

```bash
cd tom_ai/basics/tom_basics_samples/tom_basics_sample
dart pub get
dart run example/run_all_examples.dart
```

The aggregator imports each example's `main()`, runs them in learning order,
catches any throw, prints a pass/fail tally, and exits non-zero if anything
fails:

```text
============================================================
Running all tom_basics_sample examples
============================================================

--- 01_throw_and_catch ---
key: ORDER_NOT_FOUND
message: We could not find your order.
uuid length: 36
runtimeType: TomBaseException

… (each example in turn) …

============================================================
Results: 7 passed, 0 failed (of 7 examples)
============================================================
```

Each example is also runnable on its own:

```bash
dart run example/01_throw_and_catch_example.dart
```

This sample is itself one row in the
[samples-folder aggregator](../run_all_examples.dart); running that walks every
`tom_ai/basics` sample in learning order.

---

## The example files

One concept per file, each with its expected output as an inline
`// expected output` comment so the snippets below are provably runnable.

| # | File | Concept |
| - | ---- | ------- |
| 1 | [`01_throw_and_catch_example.dart`](example/01_throw_and_catch_example.dart) | Raise and catch a `TomBaseException`; read its key, message, UUID. |
| 2 | [`02_request_correlation_example.dart`](example/02_request_correlation_example.dart) | Share a `requestUuid` across failures while keeping per-failure UUIDs. |
| 3 | [`03_parameters_example.dart`](example/03_parameters_example.dart) | Attach a structured `parameters` map. |
| 4 | [`04_wrapping_root_exception_example.dart`](example/04_wrapping_root_exception_example.dart) | Wrap a low-level cause in `rootException`. |
| 5 | [`05_logging_with_levels_example.dart`](example/05_logging_with_levels_example.dart) | Log through a custom output; filter by `TomLogLevel`. |
| 6 | [`06_bitwise_levels_example.dart`](example/06_bitwise_levels_example.dart) | Compose levels with `+`, `-`, `matches`, `byName`. |
| 7 | [`07_loggable_example.dart`](example/07_loggable_example.dart) | Give a domain object a curated log form with `TomLoggable`. |

---

## Part 1 — The exception model

### 1.1 Throwing and catching

The whole point of `TomBaseException` is that *every error is identifiable*.
You raise it with two positional arguments — a **key** (a stable,
machine-readable identifier you switch on and grep for) and a
**`defaultUserMessage`** (text safe to show a user) — and it generates a random
UUIDv4 for you.

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  try {
    throw TomBaseException('ORDER_NOT_FOUND', 'We could not find your order.');
  } on TomBaseException catch (e) {
    print('key: ${e.key}');
    print('message: ${e.defaultUserMessage}');
    print('uuid length: ${e.uuid.length}');
    print('runtimeType: ${e.runtimeType}');
  }

  // expected output:
  // key: ORDER_NOT_FOUND
  // message: We could not find your order.
  // uuid length: 36
  // runtimeType: TomBaseException
}
```

The UUID is a standard 36-character v4 (`8-4-4-4-12`), random per instance — so
the literal value differs each run, but its **length is always 36**. Quote that
UUID to the user ("please mention reference `…` when you contact support") and
log it on the server: the two now join up.

> **Why a key *and* a message?** The key is for your code and your dashboards —
> it never changes, so you can switch on it, count it, and alert on it. The
> message is for humans — you can reword it freely without breaking any logic.
> Keeping them separate is the single most useful habit this type encourages.

### 1.2 The anatomy of a TomBaseException

A `TomBaseException` carries more than the two required fields. The full set:

| Field | Type | Set by | Purpose |
| ----- | ---- | ------ | ------- |
| `key` | `String` | required arg | Stable, machine-readable failure identifier. |
| `defaultUserMessage` | `String` | required arg | Human-readable, user-safe message. |
| `uuid` | `String` | auto (v4) | Unique id of *this* exception instance. |
| `requestUuid` | `String?` | named arg | Correlation id shared across one request. |
| `timeStamp` | `DateTime` | auto | `DateTime.timestamp()` (UTC) at construction. |
| `parameters` | `Map<String, Object?>?` | named arg | Structured context for logs/reports. |
| `rootException` | `Object?` | named arg | The original lower-level cause, if any. |
| `stack` | `Object?` | named arg | Caller-supplied stack object, if any. |
| `stackTrace` | `String` | auto | Terse, folded stack captured at construction. |

You can also pass an explicit `uuid:` if you are reconstructing an exception
(e.g. deserialising one received over the wire) and want to keep its identity.

The `toString()` form stitches the headline fields together:

```text
<uuid>-<requestUuid>, <runtimeType>: <key>, <defaultUserMessage>, <parameters>, <rootException>
```

so a single log line tells you *which* instance, *which* request, *what*
category, *what* the user saw, *what* the context was, and *what* caused it.

### 1.3 Correlating failures with requestUuid

Each exception has its own `uuid`. But a single inbound request can produce
several failures (a validation error *and* a downstream timeout). Stamp them all
with the same `requestUuid` and you can pull the whole story out of an
aggregated log — while still telling the individual failures apart by `uuid`.

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  const requestUuid = 'req-7f3a'; // normally taken from the inbound request

  final validation = TomBaseException(
    'VALIDATION',
    'Bad input',
    requestUuid: requestUuid,
  );
  final dbTimeout = TomBaseException(
    'DB_TIMEOUT',
    'Slow store',
    requestUuid: requestUuid,
  );

  print('first.requestUuid:  ${validation.requestUuid}');
  print('second.requestUuid: ${dbTimeout.requestUuid}');
  print('same request:  ${validation.requestUuid == dbTimeout.requestUuid}');
  print('distinct uuid: ${validation.uuid != dbTimeout.uuid}');

  // expected output:
  // first.requestUuid:  req-7f3a
  // second.requestUuid: req-7f3a
  // same request:  true
  // distinct uuid: true
}
```

The pattern in production: generate one `requestUuid` at your request boundary
(an HTTP middleware, a message handler), thread it through your call stack, and
pass it to every `TomBaseException` you raise. Your log aggregator can then
group by `requestUuid` to reconstruct exactly what happened to one request.

### 1.4 Structured parameters

The `parameters` map is for the structured context you want in a log or an
error report but would *never* concatenate into a user-facing string. Keys are
arbitrary; values are any `Object?`.

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  final declined = TomBaseException(
    'PAYMENT_DECLINED',
    'Your card was declined.',
    parameters: {'orderId': 42, 'amount': 19.99, 'currency': 'EUR'},
  );

  print('parameters: ${declined.parameters}');
  print('orderId: ${declined.parameters?['orderId']}');

  // expected output:
  // parameters: {orderId: 42, amount: 19.99, currency: EUR}
  // orderId: 42
}
```

Keep the *user message* generic ("Your card was declined.") and push the
specifics (`orderId`, `amount`) into `parameters`. The user sees a clean
sentence; your on-call engineer sees the numbers.

### 1.5 Wrapping a root cause

When a low-level failure bubbles up — a `FormatException` from a parse, an IO
error from a read — translate it into a domain `TomBaseException` that callers
above you can reason about, while keeping the original in `rootException` for
whoever has to debug it.

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  try {
    try {
      int.parse('not-a-number'); // throws FormatException
    } on FormatException catch (cause) {
      throw TomBaseException(
        'PRICE_PARSE_FAILED',
        'The price could not be read.',
        rootException: cause,
        parameters: {'raw': 'not-a-number'},
      );
    }
  } on TomBaseException catch (e) {
    print('key: ${e.key}');
    print('rootException is FormatException: ${e.rootException is FormatException}');
    print('raw: ${e.parameters?['raw']}');
  }

  // expected output:
  // key: PRICE_PARSE_FAILED
  // rootException is FormatException: true
  // raw: not-a-number
}
```

This is the boundary-translation pattern from the workspace architecture rules:
an exception thrown ten frames deep should surface a message that identifies the
*operation* that failed, not just the line. Wrapping gives the caller a stable
domain key (`PRICE_PARSE_FAILED`) while `rootException` preserves the forensic
detail (`FormatException`).

### 1.6 Stack traces

A `TomBaseException` captures a **terse, folded** stack trace at construction
(core and framework frames collapsed) into its `stackTrace` field, and exposes
`printStackTrace([int depth = -1])` to print it — `-1` prints all frames, a
positive number limits the depth. Because the captured trace is environment- and
line-number-specific, this sample does not assert on its exact text; in a real
app you log `stackTrace` alongside the `uuid` so a support reference leads
straight to the failing frames.

```dart
try {
  throw TomBaseException('IMPORT_FAILED', 'Could not import the file.');
} on TomBaseException catch (e) {
  e.printStackTrace(5); // first five (folded) frames
}
```

---

## Part 2 — Structured logging

### 2.1 The global logger

`tom_basics` exposes a ready-to-use global logger, `tomLog`, with one method per
level:

```dart
tomLog.trace('finest detail');
tomLog.debug('developer detail');
tomLog.traffic('a network call');
tomLog.info('something happened');
tomLog.warn('something looks off');
tomLog.status('an always-visible status line');
tomLog.error('a recoverable error');
tomLog.severe('a serious error');
tomLog.fatal('about to terminate');
```

Each method forwards to a [`TomLogOutput`](#24-custom-output-destinations). The
default `TomConsoleLogOutput` stamps every line with a timestamp, isolate name,
level, and the originating `class.method` — excellent for a running service, but
non-deterministic, so the examples in this sample install a tiny deterministic
output to keep their printed output stable.

### 2.2 Log levels are bit patterns

A `TomLogLevel` is a bit pattern. Individual levels are powers of two; the named
**compound** levels are unions of them. You compose levels with `+` (union),
strip a level with `-`, and test membership with `matches`.

| Level | Bit | In `production`? | In `development`? |
| ----- | --- | ---------------- | ----------------- |
| `trace` | 1 | — | ✅ |
| `debug` | 2 | — | ✅ |
| `traffic` | 4 | — | ✅ |
| `info` | 8 | ✅ | ✅ |
| `warn` | 16 | ✅ | ✅ |
| `status` | 256 | ✅ | ✅ |
| `error` | 512 | ✅ | ✅ |
| `severe` | 1024 | ✅ | ✅ |
| `fatal` | 2048 | ✅ | ✅ |

Compound levels: `errors` = error+severe+fatal · `production` =
info+warn+errors+status · `extended` = production+debug+traffic ·
`development` = extended+trace · `still` = warn+errors+status · `silent` =
errors+status · `off`/`none` = nothing.

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  final combined = TomLogLevel.info + TomLogLevel.error;
  print('info matches combined:  ${combined.matches(TomLogLevel.info)}');
  print('warn matches combined:  ${combined.matches(TomLogLevel.warn)}');

  final quieter = TomLogLevel.production - TomLogLevel.info;
  print('info after removal:     ${quieter.matches(TomLogLevel.info)}');
  print('warn after removal:     ${quieter.matches(TomLogLevel.warn)}');

  print('byName(development): ${TomLogLevel.byName('development')}');
  print('byName(bogus):       ${TomLogLevel.byName('bogus')}');

  // expected output:
  // info matches combined:  true
  // warn matches combined:  false
  // info after removal:     false
  // warn after removal:     true
  // byName(development): TomLogLevel 3871
  // byName(bogus):       null
}
```

`byName` is case-insensitive and returns `null` for an unknown name — ideal for
turning a `LOG_LEVEL` environment variable straight into a level (`3871` is the
bit pattern for `development`: trace+debug+traffic+info+warn+status+errors).

### 2.3 Filtering by level

The logger only emits a message whose level `matches` the active logger level.
Set the level with `setLogLevel`; raise verbosity temporarily with
`pushLogLevel` / `popLogLevel`; override per class or method with `addNameLevel`.

At `production`, a `debug` message is dropped; raise to `development` and it
appears:

```dart
tomLog.setLogLevel(TomLogLevel.production);
tomLog.debug('this debug is filtered at production'); // not emitted
tomLog.info('order received');                         // emitted

tomLog.setLogLevel(TomLogLevel.development);
tomLog.debug('now visible');                           // emitted
```

### 2.4 Custom output destinations

To send logs somewhere else — a file, a remote sink, or (here) a deterministic
console line — extend `TomLogOutput` and assign it to `tomLog.logOutput`. The
base class gives you `convertToString`, which already knows how to render
`String`, `Function` (called lazily), and [`TomLoggable`](#25-tomloggable--curated-log-forms)
messages.

```dart
import 'package:tom_basics/tom_basics.dart';

/// Emits `LEVEL: message` with no timestamp — deterministic for examples/tests.
class SimpleLogOutput extends TomLogOutput {
  @override
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp,
    String? origin,
  ) {
    if (logLevel.matches(loggerLevel)) {
      print('${level.trim()}: ${convertToString(message)}');
    }
  }
}

void main() {
  tomLog.logOutput = SimpleLogOutput();

  tomLog.setLogLevel(TomLogLevel.production);
  tomLog.debug('this debug is filtered at production');
  tomLog.info('order received');
  tomLog.warn('inventory low');
  tomLog.error('checkout failed');

  print('--- raise to development ---');
  tomLog.setLogLevel(TomLogLevel.development);
  tomLog.debug('now visible');

  // expected output:
  // INFO: order received
  // WARN: inventory low
  // ERROR: checkout failed
  // --- raise to development ---
  // DEBUG: now visible
}
```

The guard `if (logLevel.matches(loggerLevel))` is what makes the level filter
work — the default `TomConsoleLogOutput` does exactly the same check before it
writes to stdout/stderr.

### 2.5 TomLoggable — curated log forms

When you log an object, `convertToString` falls back to its `toString()` — but
if the object implements `TomLoggable`, the logger uses its `logRepresentation`
instead. That lets a domain object decide *exactly* what lands in a log (and,
crucially, what does **not** — passwords, tokens, PII).

```dart
import 'package:tom_basics/tom_basics.dart';

class Order implements TomLoggable {
  Order(this.id, this.customer);
  final int id;
  final String customer;

  @override
  String get logRepresentation => 'Order(#$id for $customer)';
}

class SimpleLogOutput extends TomLogOutput {
  @override
  void output(
    TomLogLevel loggerLevel,
    TomLogLevel logLevel,
    String level,
    Object message,
    String isolateName,
    DateTime timeStamp,
    String? origin,
  ) {
    if (logLevel.matches(loggerLevel)) {
      print('${level.trim()}: ${convertToString(message)}');
    }
  }
}

void main() {
  tomLog.logOutput = SimpleLogOutput();
  tomLog.setLogLevel(TomLogLevel.production);

  tomLog.info(Order(42, 'Ada'));

  // expected output:
  // INFO: Order(#42 for Ada)
}
```

---

## Part 3 — Putting it together

The two vocabularies are designed to be used as a pair: when you catch a
`TomBaseException`, you log it — and because the logger honours `TomLoggable`,
you can route the exception's most useful fields into a single, scannable line.
A realistic request handler combines everything from Parts 1 and 2:

```dart
import 'package:tom_basics/tom_basics.dart';

/// Renders a TomBaseException as one curated, user-safe-then-diagnostic line.
extension on TomBaseException {
  String get logLine =>
      '[$requestUuid] $key — $defaultUserMessage (ref $uuid) $parameters';
}

void handleCheckout(String requestUuid) {
  try {
    // … domain work that may raise …
    throw TomBaseException(
      'PAYMENT_DECLINED',
      'Your card was declined.',
      requestUuid: requestUuid,
      parameters: {'orderId': 42, 'amount': 19.99},
    );
  } on TomBaseException catch (e) {
    // One correlated, structured line — request id, key, message, ref, context.
    tomLog.error(e.logLine);
    // Surface only the safe message + a reference id to the caller/user.
    // respondToUser(e.defaultUserMessage, reference: e.uuid);
  }
}

void main() {
  tomLog.setLogLevel(TomLogLevel.production);
  handleCheckout('req-7f3a');
}
```

The takeaways that carry into real services:

1. **Generate one `requestUuid` at the boundary** and thread it through.
2. **Raise `TomBaseException` with a stable key**, a safe message, the
   `requestUuid`, and structured `parameters`.
3. **Wrap low-level causes** in `rootException` instead of letting them escape.
4. **Log the exception once, near the boundary**, with all correlation fields
   on one line; show the user only `defaultUserMessage` and the `uuid`.
5. **Pick a level per environment** (`production` in prod, `development`
   locally) and override noisy components with `addNameLevel`.

---

## Architecture

How the sample's pieces sit on top of `tom_basics`:

```text
tom_basics_sample (this package, publish_to: none)
│
├── example/01..04 ── TomBaseException ............ exception model
│                       key · message · uuid · requestUuid
│                       parameters · rootException · stackTrace
│
├── example/05,06 ─── tomLog (TomLogger) ........... structured logging
│                       └── TomLogLevel (bit patterns)
│                       └── TomLogOutput (SimpleLogOutput here)
│
├── example/07 ────── TomLoggable .................. curated log forms
│
└── example/run_all_examples.dart .................. imports each main(),
                                                     tallies, exits non-zero
                                                     on failure
        │
        └── depends on ──► package:tom_basics (path: ../../tom_basics)
```

The examples touch only the public surface re-exported from
[`tom_basics.dart`](../../tom_basics/lib/tom_basics.dart); nothing reaches into
`src/`.

---

## Key types

The `tom_basics` types this sample exercises, and where each first appears:

| Type | Kind | First used in | Role |
| ---- | ---- | ------------- | ---- |
| `TomBaseException` | class | 01 | Self-identifying domain exception (key + message + UUID). |
| `TomLogger` / `tomLog` | class / global | 05 | The logger; one method per level. |
| `TomLogLevel` | class | 05 | Bit-pattern log level; `+`, `-`, `matches`, `byName`. |
| `TomLogOutput` | abstract | 05 | Output seam; `convertToString` + `output`. |
| `TomConsoleLogOutput` | class | — (default) | Built-in stdout/stderr output (timestamped). |
| `TomLoggable` | abstract | 07 | Lets an object define its own `logRepresentation`. |

For the platform (`TomPlatformUtils`) and runtime (`TomEnvironment`) types that
`tom_basics` also provides, see the
[`tom_basics_console_sample`](../tom_basics_console_sample/) (next on the
learning path) and the [`tom_basics` manual](../../tom_basics/).

---

## Ecosystem

- **Teaches:** [`tom_basics`](../../tom_basics/) — the foundation package.
- **Sample home:** [`tom_basics_samples`](../) — the canonical home for all
  `tom_ai/basics` samples, with the full learning path.
- **Next sample:** [`tom_basics_console_sample`](../tom_basics_console_sample/)
  — platform detection, console output, and the HTTP client.
- **The basics map:** [`tom_ai/basics`](../../) — every basics package at a
  glance.

`tom_basics` is depended on, directly or transitively, by nearly every other Tom
package: its exception and logging vocabularies are the lingua franca the rest
of the framework speaks.

---

## Further documentation

- [`tom_basics` README](../../tom_basics/) — the full module manual (all four
  vocabularies, grouped feature tables, architecture).
- [`tom_basics` source](../../tom_basics/lib/tom_basics.dart) — the single
  public export surface.
- [`tom_basics_samples` README](../) — the samples index and learning path.
- [`component_module_readme_example.md`](../../../../_copilot_guidelines/component_module_readme_example.md)
  — the guideline this sample's shape follows.

---

## Status

Ready (`1.0.0`). Seven runnable examples, each with verified inline expected
output; [`example/run_all_examples.dart`](example/run_all_examples.dart) runs
them all and exits 0; `dart analyze` is clean. This is sample **#1** of the
`tom_ai/basics` [learning path](../#learning-path).
