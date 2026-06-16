# tom_basics_console

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Console and standalone platform utilities for Tom applications — platform
detection, console output, and HTTP client support.

`tom_basics_console` is the **standalone / server implementation** of the
platform seam declared in [`tom_basics`](../tom_basics/). Where `tom_basics`
defines the *abstract* `TomPlatformUtils` contract (and a fallback that throws
for anything it can't do without a host), this package fills that contract in
using `dart:io`: real OS detection, an IO-based HTTP client, environment
variables from the process, and console output that renders Markdown as ANSI
styling. It also **re-exports all of `tom_basics`**, so a console or server app
needs only this one import to get the logger, the exception base, the runtime
model, *and* a working platform implementation.

---

## Overview

A Dart program that runs on the command line or a server has a host it can ask
real questions: *which OS am I on? what's in the environment? give me an HTTP
client.* The Tom framework deliberately keeps those questions behind the
`TomPlatformUtils` seam so that library code stays platform-neutral and
compiles for the web too. `tom_basics_console` is the piece that answers them
for the **standalone VM** target.

It contributes exactly one class — `TomStandalonePlatformUtils` — plus a
convenience getter. That class:

- **Detects the platform for real.** `isDesktop`, `isWindows`, `isMacOs`,
  `isAndroid`, and the rest are backed by `dart:io`'s `Platform`, replacing the
  throwing stubs of `TomFallbackPlatformUtils`.
- **Renders console output as styled text.** `out` and `outError` pass their
  argument through `console_markdown`'s `.toConsole()`, so `**bold**`,
  `*italic*`, `__underline__`, and the other Markdown markers come out as ANSI
  escapes in a terminal.
- **Supplies an IO HTTP client** with a pragmatic localhost exception: bad TLS
  certificates are accepted only for `localhost` / `127.0.0.1` / `0.0.0.0`,
  which makes talking to a dev server painless without weakening production
  calls.
- **Seeds the environment map** from `Platform.environment` at construction, so
  `getTomEnvVars()` returns the real process environment.
- **Names the current isolate** via `Isolate.current.debugName`, which the
  logger uses to tag each line.

Because the library file re-exports `tom_basics`, importing
`package:tom_basics_console/tom_basics_console.dart` brings the whole foundation
layer into scope — you do not import `tom_basics` separately in a console app.

---

## Relationship to `tom_basics`

| Concern | `tom_basics` | `tom_basics_console` |
| ------- | ------------ | -------------------- |
| Platform contract | Declares the abstract `TomPlatformUtils` + a throwing fallback | Provides the concrete `TomStandalonePlatformUtils` |
| OS detection | Abstract methods (throw in the fallback) | Implemented via `dart:io` `Platform` |
| Console output | `print` (plain) in the fallback | Markdown → ANSI via `.toConsole()` |
| HTTP client | Abstract `httpClient()` (throws) | `IOClient` with localhost-cert allowance |
| Target | Any (web-safe; no `dart:io`) | Standalone VM / server only (`dart:io`) |
| Re-export | — | Re-exports all of `tom_basics` |

**Rule of thumb:** library packages that must stay web-safe depend on
`tom_basics`; the *entry-point* of a console or server app depends on
`tom_basics_console` and wires its implementation in once at startup. For a
Flutter target, the equivalent implementation lives in `tom_core_flutter`.

---

## Installation

```yaml
dependencies:
  tom_basics_console: ^1.0.0
```

```bash
dart pub add tom_basics_console
```

**SDK:** Dart `^3.10.4`. **Direct dependencies:** [`tom_basics`](../tom_basics/)
(re-exported), [`console_markdown`](https://pub.dev/packages/console_markdown)
(the `.toConsole()` extension), and `http` (the `Client` type). You do **not**
add `tom_basics` yourself — it comes transitively and is re-exported.

---

## Features

| Capability | Type / member | Notes |
| ---------- | ------------- | ----- |
| Standalone platform impl | `TomStandalonePlatformUtils` | Extends `TomFallbackPlatformUtils`; fills the whole contract. |
| Convenience getter | `standalonePlatformUtils` | Returns a fresh `TomStandalonePlatformUtils`. |
| Environment-type detection | `isDesktop` `isMobile` `isWeb` | Backed by `dart:io` `Platform`. |
| OS detection | `isWindows` `isLinux` `isMacOs` `isFuchsia` `isAndroid` `isIos` | Backed by `dart:io` `Platform`. |
| Styled console output | `out` / `outError` | Markdown rendered to ANSI via `console_markdown`. |
| HTTP client | `httpClient()` | `IOClient`; accepts bad certs for localhost only. |
| Process environment | `getTomEnvVars()` | Seeded from `Platform.environment` at construction. |
| Isolate name | `getIsolateName()` | `Isolate.current.debugName` (or `"main"`). |
| Foundation re-export | `export 'package:tom_basics/...'` | `tomLog`, `TomBaseException`, `TomRuntime`, … all in scope. |

---

## Quick start

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final platform = TomStandalonePlatformUtils();

  print('Desktop: ${platform.isDesktop()}'); // Desktop: true   (on a desktop OS)
  print('Mobile: ${platform.isMobile()}');   // Mobile: false
  print('Web: ${platform.isWeb()}');         // Web: false

  // Console-formatted output: **bold** renders as ANSI bold in a terminal.
  platform.out('**Hello** from tom_basics_console!');
}
```

This is exactly
[`example/tom_basics_console_example.dart`](example/tom_basics_console_example.dart) —
run it with `dart run example/tom_basics_console_example.dart`. On a desktop
machine it prints:

```
Desktop: true
Mobile: false
Web: false
Hello from tom_basics_console!
```

(The word *Hello* is emitted bold via ANSI escape codes; the markers
themselves never appear.)

---

## Example projects

| Sample | Demonstrates |
| ------ | ------------ |
| [`example/tom_basics_console_example.dart`](example/tom_basics_console_example.dart) | The quick start above: detection + styled output. |
| [`tom_basics_console_sample`](../tom_basics_samples/tom_basics_console_sample/) | Platform detection, console output, and the HTTP client together. *(article-grade sample; lands with the samples build-out)* |

---

## Usage

### Wiring the implementation into the seam

The whole point of the package is to make `TomPlatformUtils.current` return a
working implementation. Do this once, at startup, before any library code asks
the seam a question:

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  // Install the standalone implementation as the global platform.
  TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());

  // From here on, code anywhere can use the seam without importing dart:io.
  if (TomPlatformUtils.current.isLinux()) {
    TomPlatformUtils.current.out('*running on Linux*');
  }
}
```

`TomPlatformUtils`, like `setCurrentPlatform` and `current`, comes from the
re-exported `tom_basics` — you did not import it separately.

### Platform detection

`TomStandalonePlatformUtils` answers all the detection questions truthfully on
the VM:

```dart
final p = TomStandalonePlatformUtils();

print(p.isDesktop()); // true on Windows/macOS/Linux/Fuchsia
print(p.isMobile());  // true on Android/iOS
print(p.isWeb());     // true only when neither desktop nor mobile

print(p.isWindows()); // exactly one of these is true on a VM host
print(p.isLinux());
print(p.isMacOs());
```

`isDesktop()` is the disjunction of the four desktop OSes, `isMobile()` of the
two mobile OSes, and `isWeb()` is "neither of the above" — so on a standalone VM
it is always `false`.

### Styled console output

`out` and `outError` push their text through `console_markdown`'s `.toConsole()`
extension, so a small Markdown vocabulary becomes terminal styling:

```dart
final p = TomStandalonePlatformUtils();

p.out('**Build complete** in *2.3s*');
p.outError('**error:** could not open `config.yaml`');
```

In a terminal, `**Build complete**` is bold, `*2.3s*` is italic, and the
backtick-wrapped `config.yaml` is dimmed; the markers themselves are consumed.
See the workspace
[`console_markdown` guideline](../../../_copilot_guidelines/console_markdown.md)
for the full formatting vocabulary (colours, underline, nested tags).

Because the logger's default console sink routes through the platform seam,
installing this implementation also makes `tomLog` output Markdown-styled:

```dart
TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());
tomLog.info('**server** started on port 8080'); // "server" comes out bold
```

### HTTP client

`httpClient()` returns a `package:http` `Client` backed by `dart:io`'s
`HttpClient`. The one non-default behaviour is a deliberate convenience: invalid
TLS certificates are accepted **only** for local hosts, so a self-signed dev
server just works while remote calls stay strict.

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

Future<void> main() async {
  final client = TomStandalonePlatformUtils().httpClient();
  try {
    final res = await client.get(Uri.parse('https://localhost:8443/health'));
    print(res.statusCode); // e.g. 200 — self-signed cert accepted for localhost
  } finally {
    client.close();
  }
}
```

For any non-local host the standard certificate validation applies, exactly as
with a plain `IOClient`.

### Process environment and isolate name

The constructor copies `Platform.environment` into the seam's `envVars` map, so
configuration the program was launched with is immediately available through the
platform-neutral accessor:

```dart
final p = TomStandalonePlatformUtils();
final path = p.getTomEnvVars()['PATH'];
print(path != null); // true — the real process PATH
```

`getIsolateName()` returns `Isolate.current.debugName` (falling back to
`"main"`), which the logger uses to tag each line with the originating isolate.

### The `standalonePlatformUtils` getter

For call sites that just want an instance without naming the class, the library
exposes a getter that returns a fresh `TomStandalonePlatformUtils` typed as the
abstract `TomPlatformUtils`:

```dart
TomPlatformUtils.setCurrentPlatform(standalonePlatformUtils);
```

### Using the re-exported foundation

Because `tom_basics` is re-exported, the full foundation surface is available
from the single import — logger, exceptions, and the runtime model included:

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());
  tomLog.setLogLevel(TomLogLevel.development);

  try {
    throw TomBaseException('CONFIG_MISSING', 'config.yaml not found');
  } on TomBaseException catch (e) {
    tomLog.error('**${e.key}** — ${e.defaultUserMessage} (${e.uuid})');
  }
}
```

See the [`tom_basics` README](../tom_basics/README.md) for the full
documentation of `tomLog`, `TomBaseException`, and `TomRuntime`.

---

## Architecture

A single source file behind the barrel export
([`lib/tom_basics_console.dart`](lib/tom_basics_console.dart)):

```
        package:tom_basics_console/tom_basics_console.dart
                              │  (barrel export)
            ┌─────────────────┴──────────────────┐
            │                                     │
 ┌──────────┴───────────────┐        re-export of package:tom_basics
 │ src/runtime/             │        ┌────────────────────────────┐
 │ platform_detection_      │        │ TomPlatformUtils (abstract) │
 │ standalone.dart          │        │ TomFallbackPlatformUtils    │
 │                          │ extends│ TomLogger / tomLog          │
 │ TomStandalonePlatform    │───────▶│ TomBaseException            │
 │ Utils                    │        │ TomRuntime / TomEnvironment │
 │ standalonePlatformUtils  │        └────────────────────────────┘
 └──────────┬───────────────┘
            │ uses
   dart:io · dart:isolate · console_markdown · http/io_client
```

`TomStandalonePlatformUtils` extends `TomFallbackPlatformUtils` (from
`tom_basics`) and overrides every host-dependent method. Everything else the app
sees — the logger, the exception base, the runtime registry — flows straight
through from the re-export.

### Key types

| Type | Responsibility |
| ---- | -------------- |
| `TomStandalonePlatformUtils` | The standalone/server `TomPlatformUtils`: real OS detection, styled console output, IO HTTP client, process env, isolate name. |
| `standalonePlatformUtils` | Getter returning a fresh `TomStandalonePlatformUtils` as `TomPlatformUtils`. |

(All other public types — `TomPlatformUtils`, `TomLogger`, `TomBaseException`,
`TomRuntime`, … — are re-exported from `tom_basics`; see
[its key-types table](../tom_basics/README.md#key-types).)

---

## Ecosystem

```
        ┌───────────────────────────────┐
        │ console / server entry points │   (your `main()`)
        └───────────────┬───────────────┘
                        │ depends on
               ┌────────┴─────────┐
               │ tom_basics_      │  ← you are here
               │ console          │  (dart:io implementation)
               └───┬──────────┬───┘
        re-exports │          │ depends on
          ┌────────┴───┐  ┌───┴──────────────┐
          │ tom_basics │  │ console_markdown │
          │ (the seam) │  │ · http           │
          └────────────┘  └──────────────────┘
```

The web/Flutter counterpart is `tom_core_flutter`, which provides a
`TomPlatformUtils` implementation for those targets. Library packages that must
remain web-safe depend on `tom_basics` directly and never on this package.

See the [basics repository map](../README.md) for the full package catalogue and
the [samples learning path](../README.md#samples-learning-path).

---

## Further documentation

- [`tom_basics` README](../tom_basics/README.md) — the abstract platform seam,
  the logger, and the exception base this package implements and re-exports.
- [Basics repository README](../README.md) — the map of all ten basics packages.
- [`console_markdown` guideline](../../../_copilot_guidelines/console_markdown.md)
  — the Markdown-to-ANSI vocabulary used by `out` / `outError`.
- [`console_markdown` on pub.dev](https://pub.dev/packages/console_markdown) —
  the upstream package providing `.toConsole()`.

---

## Status

- **Version:** 1.0.0
- **SDK:** Dart `^3.10.4`
- **Tests:** none yet (the standalone implementation is exercised through
  consuming packages and the `tom_basics_console_sample`); the package ships a
  runnable `example/`.
- **Analyzer:** clean (`dart analyze` → no issues).
