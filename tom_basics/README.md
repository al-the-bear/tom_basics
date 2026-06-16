# tom_basics

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Basic utilities for the Tom framework including exception handling with UUID
tracking.

`tom_basics` is the **bottom of the dependency stack**. It carries the few
primitives that almost every other Tom package imports — a traceable exception
base, a configurable logger, a platform-abstraction layer, and a small runtime
environment model — while keeping its own dependency list to just three
well-known packages (`uuid`, `stack_trace`, `http`). Nothing here pulls in
Flutter, a database, or a server framework, so it is safe to import from the
most foundational corners of the codebase.

---

## Overview

A foundational library has one job: give the layers above it a vocabulary they
can share without dragging in heavy dependencies. `tom_basics` provides four
such vocabularies, each independent of the others:

- **Errors that can be traced across process boundaries.** A
  [`TomBaseException`](#exception-handling-with-uuid-tracking) stamps every
  failure with a UUID at the moment it is created. When the same error is
  logged on a server, surfaced in a client, and filed in a bug tracker, the
  UUID is the thread that ties the three sightings together. The exception also
  captures a *terse, core-folded* stack trace (via `stack_trace`) so the noise
  of the SDK internals is stripped from the report.

- **Logging you can dial up and down per class.** The global
  [`tomLog`](#logging) instance offers nine severity methods
  (`trace` → `fatal` plus `status`) and a **bitwise level model** that lets you
  compose, subtract, and match levels. You can raise the verbosity of a single
  class or method without touching the global level, and you can redirect all
  output to a destination of your choosing by swapping one field.

- **Platform detail behind a single seam.** Code that needs to know "are we on
  the web?" or "give me an HTTP client" talks to
  [`TomPlatformUtils.current`](#platform-abstraction) instead of importing
  `dart:io` or `dart:html`. The concrete implementation is injected once at
  startup, so the same library code compiles and runs on console, server,
  mobile, and web.

- **A runtime environment model for wiring.** [`TomEnvironment`,
  `TomPlatform`, and `TomRuntime`](#runtime-environments-and-platforms) describe
  *which* environment (development / test / production) and *which* platform
  (web / macos / android / …) are active, with a parent hierarchy. Higher-level
  Tom packages use this to select environment- and platform-specific
  implementations.

These four concerns share no code with each other; you can import the package
and use only the logger, only the exception base, or only the platform seam.

---

## Installation

Add the dependency with its hosted version constraint:

```yaml
dependencies:
  tom_basics: ^1.0.0
```

or from the command line:

```bash
dart pub add tom_basics
```

**SDK:** Dart `^3.10.0`. **Transitive dependencies:** `uuid`, `stack_trace`,
`http` — all pure-Dart and platform-neutral, so `tom_basics` itself adds no
native or Flutter requirement.

---

## Features

### Exception handling

| Capability | Type / member | Notes |
| ---------- | ------------- | ----- |
| UUID-stamped exception | `TomBaseException` | Auto-generates a UUIDv4 unless one is supplied. |
| Request correlation | `requestUuid` | Optional id tying an error to an inbound request. |
| Structured context | `parameters` | `Map<String, Object?>` of diagnostic values. |
| Cause chaining | `rootException` | The underlying error this one wraps. |
| Terse stack trace | `stackTrace`, `printStackTrace()` | Core frames folded out via `stack_trace`. |
| Creation timestamp | `timeStamp` | UTC `DateTime` set at construction. |

### Logging

| Capability | Type / member | Notes |
| ---------- | ------------- | ----- |
| Global logger | `tomLog` | Ready-to-use `TomLogger` singleton. |
| Severity methods | `trace` `debug` `traffic` `info` `warn` `status` `error` `severe` `fatal` | One method per level. |
| Bitwise levels | `TomLogLevel` + `-` `matches` | Compose and subtract levels. |
| Compound levels | `development` `extended` `production` `still` `silent` `off` | Named presets. |
| Per-name overrides | `addNameLevel` / `setLogLevelExceptions` | Raise verbosity for one class or method. |
| Level stack | `pushLogLevel` / `popLogLevel` | Temporary, scoped verbosity. |
| Pluggable output | `logOutput`, `TomLogOutput` | Swap in file / remote / custom sinks. |
| Custom rendering | `TomLoggable` | Control how your objects appear in logs. |

### Platform abstraction

| Capability | Type / member | Notes |
| ---------- | ------------- | ----- |
| Injectable singleton | `TomPlatformUtils.current` / `setCurrentPlatform` | One seam for all platform detail. |
| Environment type | `isDesktop` `isMobile` `isWeb` | Coarse-grained checks. |
| OS detection | `isWindows` `isLinux` `isMacOs` `isFuchsia` `isAndroid` `isIos` | Fine-grained checks. |
| Console output | `out` / `outError` | Platform-routed stdout / stderr. |
| HTTP client factory | `httpClient()` | Returns a `package:http` `Client`. |
| Env vars | `envVars` / `getTomEnvVars` | Platform-neutral configuration map. |
| Default fallback | `TomFallbackPlatformUtils` | Console output works; detection throws until configured. |

### Runtime environments and platforms

| Capability | Type / member | Notes |
| ---------- | ------------- | ----- |
| Environment model | `TomEnvironment` | Named, with optional parent + initializer. |
| Platform model | `TomPlatform` | Named target with an initializer hook. |
| Runtime registry | `TomRuntime` | Holds current env / platform + hierarchy resolution. |
| Platform constants | `platformWeb` `platformMacos` `platformWindows` `platformLinux` `platformAndroid` `platformIos` `platformFuchsia` | Predefined targets. |
| Env constants | `defaultTomEnvironment` `noTomEnvironment` | Defaults / sentinels. |

---

## Quick start

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  // The global logger is ready to use immediately.
  tomLog.setLogLevel(TomLogLevel.development);
  tomLog.info('Application starting...');

  try {
    throw TomBaseException('EXAMPLE_ERROR', 'Something went wrong');
  } on TomBaseException catch (e) {
    tomLog.error('Caught: ${e.key} - ${e.defaultUserMessage}');
    print('Exception UUID: ${e.uuid}'); // e.g. aceec92a-90ab-4f7b-896e-...
  }

  tomLog.info('Application finished.');
}
```

Running it prints (timestamps and the UUID vary per run):

```
2026-06-16 21:27:22.128328 - INFO    Application starting...   [main]
2026-06-16 21:27:22.140356 - ERROR   Caught: EXAMPLE_ERROR - Something went wrong   [main]
Exception UUID: aceec92a-90ab-4f7b-896e-595d7f1a94ca
2026-06-16 21:27:22.140927 - INFO    Application finished.   [main]
```

This is exactly [`example/tom_basics_example.dart`](example/tom_basics_example.dart) —
run it with `dart run example/tom_basics_example.dart`.

---

## Example projects

| Sample | Demonstrates |
| ------ | ------------ |
| [`example/tom_basics_example.dart`](example/tom_basics_example.dart) | The 12-line quick start above: logger + tracked exception. |
| [`tom_basics_sample`](../tom_basics_samples/tom_basics_sample/) | The full exception-handling-with-UUID-tracking model, end to end, with the logger and platform seam. *(article-grade sample, seven runnable examples)* |

---

## Usage

### Exception handling with UUID tracking

The constructor takes a **key** (a stable, machine-readable code) and a
**default user message** (human-readable), with everything else optional:

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  final ex = TomBaseException(
    'VALIDATION_ERROR',
    'The email address is not valid',
    parameters: {'field': 'email', 'value': 'not-an-email'},
  );

  print(ex.key);                  // VALIDATION_ERROR
  print(ex.defaultUserMessage);   // The email address is not valid
  print(ex.parameters?['field']); // email
  print(ex.uuid.length);          // 36  (a UUIDv4 string)
}
```

**Why a key *and* a message?** The `key` is what your code branches on and what
you grep logs for; it never changes when you reword the prose. The
`defaultUserMessage` is the fallback text shown when no localized message is
available. Keeping them separate means translators and programmers never fight
over the same string.

**Correlating an error with a request.** Pass `requestUuid` so a failure deep
in a handler can be matched back to the inbound call that triggered it:

```dart
TomBaseException(
  'DB_TIMEOUT',
  'The database did not respond in time',
  requestUuid: incomingRequestId,
  parameters: {'table': 'orders', 'timeoutMs': 5000},
);
```

**Wrapping a lower-level error.** When you catch an exception and rethrow a
domain-level one, keep the original in `rootException` and the original trace in
`stack` so nothing is lost:

```dart
try {
  await db.query(sql);
} catch (e, s) {
  throw TomBaseException(
    'ORDER_LOAD_FAILED',
    'Could not load the order',
    rootException: e,
    stack: s,
  );
}
```

**Inspecting the trace.** Each exception folds out core/SDK frames at
construction time and stores the result in `stackTrace`. Print it directly, or
use `printStackTrace()`:

```dart
try {
  throw TomBaseException('BOOM', 'demo');
} on TomBaseException catch (e) {
  e.printStackTrace();      // writes "<uuid>-<requestUuid> exception stacktrace:\n..."
  // or inspect the stored string:
  print(e.stackTrace.split('\n').first); // the first non-core frame
}
```

> **Note.** `tom_basics` deliberately stops at this minimal base class. The
> full-featured exception type with integrated logging lives in
> `tom_core_kernel` as `TomException`; reach for that when you are above the
> foundation layer.

### Logging

The global [`tomLog`](lib/src/logging/logging.dart) instance is usable without
any setup. Each severity has its own method:

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  tomLog.info('Server started on port 8080');
  tomLog.warn('Cache miss for key user:42');
  tomLog.error('Failed to connect to database');
  tomLog.debug('Request payload: {"id": 42}');
  tomLog.trace('Entering computeChecksum()');
}
```

Output lines carry the timestamp, isolate name, level, message, and the
detected origin (the `class.method` that called the logger), e.g.:

```
2026-06-16 21:27:22.140 - INFO    Server started on port 8080   [main]
```

#### Log levels are bit patterns

A [`TomLogLevel`](lib/src/logging/logging.dart) is a bit mask. Individual
levels can be **combined** with `+` and **removed** with `-`, and a logger only
emits a message when its level `matches` the message level:

```dart
// Build a custom level: info plus errors, nothing else.
var quiet = TomLogLevel.info + TomLogLevel.errors;
tomLog.setLogLevel(quiet);

tomLog.info('shown');      // matches -> printed
tomLog.debug('hidden');    // no overlap -> filtered out
tomLog.error('shown');     // matches -> printed

// Subtract a level from a preset.
var prodNoInfo = TomLogLevel.production - TomLogLevel.info;
print(prodNoInfo.matches(TomLogLevel.info)); // false
print(prodNoInfo.matches(TomLogLevel.warn)); // true
```

Named presets cover the common cases:

| Preset | Includes |
| ------ | -------- |
| `development` | everything, including `trace` |
| `extended` | production + `debug` + `traffic` |
| `production` | `info` + `warn` + errors + `status` |
| `still` | `warn` + errors + `status` |
| `silent` | errors + `status` only |
| `off` | nothing |

You can also resolve a level by name (useful for reading a level from config or
an environment variable):

```dart
tomLog.setLogLevelByName('DEVELOPMENT');          // case-insensitive
final lvl = TomLogLevel.byName('SILENT');          // or null if unknown
```

#### Temporary verbosity with a level stack

To turn the volume up around one tricky section and restore it afterwards, push
and pop:

```dart
tomLog.pushLogLevel(TomLogLevel.trace);
// ... noisy operations are fully traced here ...
tomLog.popLogLevel(); // back to whatever was active before
```

#### Per-class and per-method overrides

When stack-trace analysis is enabled (the default,
`TomLogger.globalSettingDetermineCaller == true`), the logger detects which
`class.method` emitted each message. That lets you raise verbosity for one
location only:

```dart
// Trace everything in DatabaseService, debug one method of ApiClient.
tomLog.addNameLevel('DatabaseService', TomLogLevel.trace);
tomLog.addNameLevel('ApiClient.sendRequest', TomLogLevel.debug);

// Or configure several at once from a pattern string (e.g. from config):
tomLog.setLogLevelExceptions('DatabaseService=TRACE,ApiClient=DEBUG');
```

#### Redirecting output

The logger writes through `logOutput`, a [`TomLogOutput`](lib/src/logging/logging.dart).
The default is [`TomConsoleLogOutput`](lib/src/logging/logging.dart) (errors and
status to stderr, everything else to stdout). Implement `TomLogOutput.output`
to send logs anywhere:

```dart
class CollectingLogOutput extends TomLogOutput {
  final List<String> lines = [];

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
      lines.add('$level ${convertToString(message)}');
    }
  }
}

void main() {
  final sink = CollectingLogOutput();
  tomLog.logOutput = sink;
  tomLog.info('captured');
  print(sink.lines); // [INFO    captured]
}
```

`convertToString` (provided by the base class) handles `String`s, lazy
`Function` messages, and `TomLoggable` objects automatically.

#### Custom log representation for your types

Implement `TomLoggable` so an object renders cleanly in logs without exposing
internals:

```dart
class User implements TomLoggable {
  User(this.id, this.name);
  final String id;
  final String name;

  @override
  String get logRepresentation => 'User($id, $name)';
}

void main() {
  tomLog.info(User('42', 'Ada')); // logs: User(42, Ada)
}
```

### Platform abstraction

Library code that must not import `dart:io` or `dart:html` directly talks to
[`TomPlatformUtils.current`](lib/src/runtime/platform_neutral.dart). The
concrete implementation is injected once at startup. Until you do that, the
default [`TomFallbackPlatformUtils`](lib/src/runtime/platform_neutral.dart)
supports console output but throws `UnimplementedError` for detection — a loud,
deliberate signal that the platform was never configured:

```dart
import 'package:tom_basics/tom_basics.dart';

// A Linux console/server implementation. Extending TomFallbackPlatformUtils
// gives working out/outError; we override every detection method so that
// TomRuntime.initializePlatform() (which probes them all) also works.
class ConsolePlatformUtils extends TomFallbackPlatformUtils {
  @override
  bool isDesktop() => true;
  @override
  bool isMobile() => false;
  @override
  bool isWeb() => false;
  @override
  bool isWindows() => false;
  @override
  bool isLinux() => true;
  @override
  bool isMacOs() => false;
  @override
  bool isFuchsia() => false;
  @override
  bool isAndroid() => false;
  @override
  bool isIos() => false;
}

void main() {
  TomPlatformUtils.setCurrentPlatform(ConsolePlatformUtils());

  final p = TomPlatformUtils.current;
  print(p.isDesktop()); // true
  print(p.isLinux());   // true
  p.out('hello from the platform seam'); // prints to stdout
}
```

A stub that overrides only `isDesktop`/`isMobile`/`isWeb` is enough for those
three checks, but `TomRuntime.initializePlatform()` (below) probes the full set
of OS methods — so a complete implementation like the one above is what makes
detection work end to end. In real apps you don't write this yourself:
`tom_basics_console` ships the desktop/server implementation and
`tom_core_flutter` ships the Flutter one. The seam is what lets the same
upstream code run on both.

The same singleton also hands out an HTTP client and a configuration map:

```dart
// Configuration that travels with the platform, not the call site.
TomPlatformUtils.envVars['API_BASE'] = 'https://api.example.com';
print(TomPlatformUtils.current.getTomEnvVars()['API_BASE']);
// https://api.example.com

// A platform-appropriate http client (once a real platform is configured):
// final client = TomPlatformUtils.current.httpClient();
// final res = await client.get(Uri.parse('https://api.example.com/health'));
```

### Runtime environments and platforms

The runtime model answers "which environment and platform are active, and what
is the chain of fallbacks?" Register environments, pick the current one, and
walk the hierarchy:

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  final prod = TomRuntime.addEnvironment(const TomEnvironment('production'));
  TomRuntime.addEnvironment(
    TomEnvironment('staging', parent: prod),
  );

  TomRuntime.setCurrentEnvironment('staging');
  print(TomRuntime.getCurrentEnvironment().env); // staging

  // Root-to-current chain, used by higher layers to resolve fallbacks.
  final chain = TomRuntime.getEnvironmentHierarchy().map((e) => e.env).toList();
  print(chain); // [production, staging]
}
```

An environment may carry an initializer that runs when it is activated:

```dart
final dev = TomEnvironment(
  'development',
  isDevelopment: true,
  initializer: (env) => tomLog.info('Activated ${env.env}'),
);
dev.initialize(); // logs: Activated development
```

Platform detection ties the platform seam to the runtime registry. Once a real
`TomPlatformUtils` is configured, `initializePlatform()` detects and records the
current platform:

```dart
TomPlatformUtils.setCurrentPlatform(ConsolePlatformUtils());
TomRuntime.setCurrentEnvironment('production');
TomRuntime.initializePlatform();
print(TomRuntime.printReport());
// TomRuntime: Platform TomPlatform: linux Root Environment ... Current Environment ...
```

---

## Architecture

`tom_basics` is four small, independent modules behind a single barrel export
([`lib/tom_basics.dart`](lib/tom_basics.dart)):

```
                       package:tom_basics/tom_basics.dart
                                     │  (barrel export)
        ┌──────────────┬─────────────┼──────────────────┐
        │              │             │                  │
 ┌──────┴──────┐ ┌─────┴──────┐ ┌────┴─────────┐ ┌──────┴────────────┐
 │ exceptions/ │ │ logging/   │ │ runtime/     │ │ runtime/          │
 │ exception_  │ │ logging.   │ │ platform_    │ │ platform_         │
 │ base.dart   │ │ dart       │ │ neutral.dart │ │ environment_      │
 │             │ │            │ │              │ │ runtime.dart      │
 │ TomBase     │ │ TomLogger  │ │ TomPlatform  │ │ TomEnvironment    │
 │ Exception   │ │ TomLogLevel│ │ Utils        │ │ TomPlatform       │
 │             │ │ TomLogOut  │ │ (+ fallback) │ │ TomRuntime        │
 └─────────────┘ └─────┬──────┘ └──────┬───────┘ └───────────────────┘
   uuid,                │  uses         │ uses
   stack_trace          └───────────────┘
                     (logging routes its console
                      output through the platform seam)
```

The only internal coupling is that `logging` writes through the platform seam
(`TomConsoleLogOutput` calls `TomPlatformUtils.current.out/outError`) and reads
the isolate name from it. Exceptions and the environment model stand alone.

### Key types

| Type | Responsibility |
| ---- | -------------- |
| `TomBaseException` | Minimal exception base with UUID, timestamp, params, cause, and folded stack trace. |
| `TomLogger` | The logger: severity methods, level + per-name configuration, output dispatch. |
| `tomLog` | The global `TomLogger` instance. |
| `TomLogLevel` | Bitwise log-level value with `+`, `-`, `matches`, and named presets. |
| `TomLogOutput` | Abstract log sink; `TomConsoleLogOutput` is the default stdout/stderr impl. |
| `TomLoggable` | Interface for objects that supply their own `logRepresentation`. |
| `TomPlatformUtils` | Injectable platform seam: detection, console output, HTTP client, env vars. |
| `TomFallbackPlatformUtils` | Default impl: console output works, detection throws until configured. |
| `TomEnvironment` | A named runtime environment with optional parent + initializer. |
| `TomPlatform` | A named target platform with an initializer hook. |
| `TomRuntime` | Registry of current environment/platform and hierarchy resolution. |

---

## Ecosystem

`tom_basics` sits at the root of the basics layer; the rest of the framework
imports it, never the other way around.

```
                      ┌───────────────────────────┐
                      │  tom_core_kernel / server  │   higher-level Tom packages
                      │  tom_core_flutter, d4rt …  │   (TomException, DI, …)
                      └─────────────┬──────────────┘
                                    │ depends on
        ┌────────────────┬──────────┼───────────────┐
        │                │          │               │
 ┌──────┴──────┐  ┌──────┴──────┐   │        ┌───────┴────────┐
 │ tom_basics_ │  │ tom_basics_ │   │        │  tom_crypto     │
 │ console     │  │ network     │   │        │  (uses logging) │
 │ (platform   │  │             │   │        └────────────────┘
 │  impl)      │  │             │   │
 └──────┬──────┘  └──────┬──────┘   │
        └────────────────┴──────────┘
                         │ all depend on
                  ┌──────┴───────┐
                  │  tom_basics  │  ← you are here
                  └──────────────┘
            (uuid · stack_trace · http only)
```

See the [basics repository map](../README.md) for the full package catalogue
and the [samples learning path](../README.md#samples-learning-path).

---

## Further documentation

- [Basics repository README](../README.md) — the map of all ten basics packages.
- [`tom_basics_console`](../tom_basics_console/) — supplies the desktop/server
  `TomPlatformUtils` implementation that backs the platform seam.
- [`tom_crypto`](../tom_crypto/) — a downstream consumer that logs through
  `tomLog`.
- `tom_core_kernel` (separate repo) — provides `TomException`, the
  full-featured exception type that builds on this base.

---

## Status

- **Version:** 1.0.0
- **SDK:** Dart `^3.10.0`
- **Tests:** 6 passing (`TomBaseException` group — construction, parameters,
  custom UUID, cause capture, `toString`, stack-trace capture). Run with
  `dart test` or `testkit :test`.
- **Analyzer:** clean (`dart analyze` → no issues).
