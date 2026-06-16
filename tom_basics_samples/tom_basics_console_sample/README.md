# tom_basics_console_sample — Platform, Console & HTTP for the Standalone VM

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](../../tom_basics_console/LICENSE).

Runnable, article-grade sample for [`tom_basics_console`](../../tom_basics_console/):
standalone platform detection, Markdown-to-ANSI console output, the IO HTTP
client (run against a local server so it works offline), and styled logging
through the platform seam.

This is sample **#2** on the [`tom_ai/basics` learning path](../#learning-path).
It follows directly from [`tom_basics_sample`](../tom_basics_sample/) (exceptions
and logging) and shows how a console or server program *grounds* the
platform-neutral foundation: it answers the host-specific questions —
*which OS am I on? what's in the environment? give me an HTTP client* — that
`tom_basics` deliberately leaves abstract.

If you want the module's full reference manual, read the
[`tom_basics_console` README](../../tom_basics_console/). If you want to *learn
it by running it*, you are in the right place.

---

## Table of contents

- [What you will learn](#what-you-will-learn)
- [The seam, and why it exists](#the-seam-and-why-it-exists)
- [The package this teaches](#the-package-this-teaches)
- [Running the samples](#running-the-samples)
- [The example files](#the-example-files)
- [Part 1 — Platform detection](#part-1--platform-detection)
  - [1.1 Detecting the platform](#11-detecting-the-platform)
  - [1.2 Wiring the implementation into the seam](#12-wiring-the-implementation-into-the-seam)
- [Part 2 — Console output](#part-2--console-output)
  - [2.1 Markdown becomes ANSI](#21-markdown-becomes-ansi)
  - [2.2 Why a seam for `print`?](#22-why-a-seam-for-print)
- [Part 3 — Environment & isolate](#part-3--environment--isolate)
- [Part 4 — The HTTP client](#part-4--the-http-client)
- [Part 5 — Styled logging through the seam](#part-5--styled-logging-through-the-seam)
- [A note on deterministic output](#a-note-on-deterministic-output)
- [Architecture](#architecture)
- [Key types](#key-types)
- [Ecosystem](#ecosystem)
- [Further documentation](#further-documentation)
- [Status](#status)

---

## What you will learn

By the end of this sample you will be able to:

- **Detect the platform** on a standalone VM — OS family and environment type —
  and recognise the invariants that hold on *any* VM host.
- **Install the standalone implementation** into the global `TomPlatformUtils`
  seam so library code can stay platform-neutral.
- **Emit styled console output**: write `**bold**` / `*italic*` / `` `code` ``
  and have it rendered as ANSI in a terminal, with the markers consumed.
- **Read the process environment** and the isolate name through the
  platform-neutral accessors.
- **Make HTTP requests** with the package's IO client, including its
  localhost-certificate convenience — demonstrated against a throwaway local
  server so it runs with no network.
- **Get styled logging for free**: see why installing the platform also makes
  `tomLog` render Markdown.

Every claim above is backed by a runnable example in [`example/`](example/)
whose run is checked by [`example/run_all_examples.dart`](example/run_all_examples.dart).

---

## The seam, and why it exists

A Dart *library* should compile for every target — web included — so it must not
import `dart:io`. But a library still occasionally needs to know the OS, read an
environment variable, or make an HTTP call. The Tom framework resolves this
tension with a **seam**: `tom_basics` declares an *abstract* `TomPlatformUtils`
with those operations, plus a `TomFallbackPlatformUtils` whose host-dependent
methods throw. The concrete answers live in target-specific packages:

| Target | Platform implementation |
| ------ | ----------------------- |
| Standalone VM / server | **`tom_basics_console`** (this sample) — `dart:io` |
| Flutter / web | `tom_core_flutter` |
| (none installed) | `TomFallbackPlatformUtils` — throws for host calls |

The entry point of a console or server app installs the standalone
implementation once at startup; from then on, library code calls
`TomPlatformUtils.current` and never touches `dart:io` itself.

---

## The package this teaches

[`tom_basics_console`](../../tom_basics_console/) contributes exactly one
class — `TomStandalonePlatformUtils` — plus a `standalonePlatformUtils` getter,
and **re-exports all of `tom_basics`**. So one import brings the logger, the
exception base, the runtime model, *and* a working platform implementation:

```dart
import 'package:tom_basics_console/tom_basics_console.dart';
// tomLog, TomBaseException, TomLogLevel, TomPlatformUtils,
// TomStandalonePlatformUtils — all in scope from this single import.
```

The sample depends on it by path (same workspace repo):

```yaml
# pubspec.yaml
dependencies:
  tom_basics_console:
    path: ../../tom_basics_console
  console_markdown: ^0.0.3   # only to *show* the Markdown→ANSI transform
```

> **Why the extra `console_markdown` dependency?** `out` / `outError` render
> Markdown internally via `console_markdown`'s `.toConsole()`, but
> `tom_basics_console` does not re-export it. The console-output example imports
> it directly so it can show the transform explicitly (markers consumed, ANSI
> added); your own app code only needs `out` and never imports it.

For the foundation vocabularies (`TomBaseException`, `tomLog`, `TomLogLevel`),
see the previous sample, [`tom_basics_sample`](../tom_basics_sample/).

---

## Running the samples

From this sample's folder:

```bash
cd tom_ai/basics/tom_basics_samples/tom_basics_console_sample
dart pub get
dart run example/run_all_examples.dart
```

The aggregator imports each example's `main()`, runs them in learning order
(awaiting the async HTTP one), catches any throw, prints a pass/fail tally, and
exits non-zero on failure:

```text
============================================================
Running all tom_basics_console_sample examples
============================================================

--- 01_platform_detection ---
not web (real host):    true
desktop xor mobile:     true
Detected OS:            Linux

… (each example in turn) …

============================================================
Results: 6 passed, 0 failed (of 6 examples)
============================================================
```

Each example is also runnable on its own:

```bash
dart run example/05_http_client_example.dart
```

This sample is one row in the
[samples-folder aggregator](../run_all_examples.dart).

---

## The example files

One concept per file, each with its expected output as an inline
`// expected output` comment.

| # | File | Concept |
| - | ---- | ------- |
| 1 | [`01_platform_detection_example.dart`](example/01_platform_detection_example.dart) | Detect OS and environment type on a standalone VM. |
| 2 | [`02_wiring_the_seam_example.dart`](example/02_wiring_the_seam_example.dart) | Install the implementation with `setCurrentPlatform`; use `current`. |
| 3 | [`03_console_output_example.dart`](example/03_console_output_example.dart) | `out` / `outError` render Markdown as ANSI. |
| 4 | [`04_environment_and_isolate_example.dart`](example/04_environment_and_isolate_example.dart) | Read the process environment and isolate name through the seam. |
| 5 | [`05_http_client_example.dart`](example/05_http_client_example.dart) | The IO HTTP client against a local server (offline). |
| 6 | [`06_styled_logging_example.dart`](example/06_styled_logging_example.dart) | `tomLog` renders Markdown once the platform is installed. |

---

## Part 1 — Platform detection

### 1.1 Detecting the platform

`TomStandalonePlatformUtils` answers every detection question truthfully on the
VM, backed by `dart:io`'s `Platform`. The OS family is host-specific, but two
facts hold on **any** standalone VM: it is never "web", and it is exactly one of
desktop or mobile.

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final p = TomStandalonePlatformUtils();

  print('not web (real host):    ${!p.isWeb()}');
  print('desktop xor mobile:     ${p.isDesktop() != p.isMobile()}');

  final os = p.isWindows()
      ? 'Windows'
      : p.isMacOs()
          ? 'macOS'
          : p.isLinux()
              ? 'Linux'
              : p.isFuchsia()
                  ? 'Fuchsia'
                  : p.isAndroid()
                      ? 'Android'
                      : p.isIos()
                          ? 'iOS'
                          : 'unknown';
  print('Detected OS:            $os');

  // expected output:
  // not web (real host):    true
  // desktop xor mobile:     true
  // Detected OS:            Linux
  //   (the "Detected OS" line varies by host: Windows / macOS / Linux / …)
}
```

The detection methods fall into three groups:

| Group | Methods | Meaning |
| ----- | ------- | ------- |
| Environment type | `isDesktop` `isMobile` `isWeb` | Where the code runs. |
| Desktop OS | `isWindows` `isLinux` `isMacOs` `isFuchsia` | Which desktop OS. |
| Mobile OS | `isAndroid` `isIos` | Which mobile OS. |

`isDesktop()` is the disjunction of the four desktop OSes, `isMobile()` of the
two mobile OSes, and `isWeb()` is "neither of the above" — so on a standalone VM
it is always `false`. That is why the example asserts `!isWeb()` and
`isDesktop() != isMobile()` rather than hard-coding an OS: those are the
host-independent truths.

### 1.2 Wiring the implementation into the seam

Detection on a hand-built instance is useful, but the *point* of the package is
to make the **global** `TomPlatformUtils.current` return a working
implementation, so platform-neutral library code can ask the seam without
importing `dart:io`. Install it once at startup:

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  // One line at startup wires the standalone (dart:io) implementation in.
  TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());

  final isStandalone = TomPlatformUtils.current is TomStandalonePlatformUtils;
  print('current is standalone:  $isStandalone');
  print('seam not web:           ${!TomPlatformUtils.current.isWeb()}');

  // The getter returns a fresh instance typed as the abstract seam.
  TomPlatformUtils.setCurrentPlatform(standalonePlatformUtils);
  print('getter also standalone: '
      '${TomPlatformUtils.current is TomStandalonePlatformUtils}');

  // expected output:
  // current is standalone:  true
  // seam not web:           true
  // getter also standalone: true
}
```

Before `setCurrentPlatform` runs, `TomPlatformUtils.current` is the throwing
`TomFallbackPlatformUtils`: calling `isDesktop()` on it raises
`UnimplementedError`. Installing the implementation is the one piece of wiring a
console/server entry point owes the rest of the program.

The `standalonePlatformUtils` getter is sugar for call sites that prefer not to
name the concrete class; it returns a fresh `TomStandalonePlatformUtils` typed
as the abstract `TomPlatformUtils`.

---

## Part 2 — Console output

### 2.1 Markdown becomes ANSI

`out` and `outError` push their text through `console_markdown`'s `.toConsole()`,
so a small Markdown vocabulary becomes terminal styling — and the markers
themselves are consumed. The example inspects the transform deterministically
(no raw escape codes in the asserts) and then emits the styled lines:

```dart
import 'package:console_markdown/console_markdown.dart';
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final p = TomStandalonePlatformUtils();

  final styled = '**Build complete** in *2.3s*'.toConsole();
  print('contains literal **:    ${styled.contains('**')}');
  print('contains ESC (ANSI):    ${styled.contains('\x1B')}');
  print('words still present:    '
      '${styled.contains('Build complete') && styled.contains('2.3s')}');

  print('--- styled line (ANSI in a terminal): ---');
  p.out('**Build complete** in *2.3s*');
  p.outError('**error:** could not open `config.yaml`');

  // expected output:
  // contains literal **:    false
  // contains ESC (ANSI):    true
  // words still present:    true
  // --- styled line (ANSI in a terminal): ---
  //   <"Build complete" bold, "2.3s" italic — rendered with ANSI escapes>
  //   <"error:" bold, "config.yaml" dimmed>
}
```

The vocabulary `out` understands: `**bold**`, `*italic*`, `__underline__`,
`` `code` `` (dimmed), plus colours and nested tags. See the workspace
[`console_markdown` guideline](../../../../_copilot_guidelines/console_markdown.md)
for the full set.

> **Marker caveat.** `console_markdown` v0.0.3 renders `*italic*` (single
> asterisks) but **not** `_italic_` (single underscores); `__underline__`
> (double underscores) *is* underline. When in doubt, use the asterisk forms.

### 2.2 Why a seam for `print`?

Routing console output through the platform rather than calling `print`
directly buys two things. First, a web/Flutter target can render the same
Markdown its own way (a styled widget, the browser console) without the calling
code changing. Second — and this is what Part 5 uses — the **logger's** console
sink writes through the same seam, so installing this implementation styles your
logs too, for free.

---

## Part 3 — Environment & isolate

The `TomStandalonePlatformUtils` constructor copies `Platform.environment` into
the seam's `envVars` map, so the real process environment is available through
the platform-neutral `getTomEnvVars()`. You can add your own entries alongside
it, and `getIsolateName()` gives the logger a tag for each line.

```dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final p = TomStandalonePlatformUtils();

  TomPlatformUtils.envVars['TOM_SAMPLE_MODE'] = 'demo';

  print('TOM_SAMPLE_MODE:        ${p.getTomEnvVars()['TOM_SAMPLE_MODE']}');
  print('PATH present:           ${p.getTomEnvVars().containsKey('PATH')}');
  print('isolate name nonempty:  ${p.getIsolateName().isNotEmpty}');

  // expected output:
  // TOM_SAMPLE_MODE:        demo
  // PATH present:           true
  // isolate name nonempty:  true
}
```

`envVars` is a single static map on `TomPlatformUtils`, so configuration you add
at startup is visible everywhere through `getTomEnvVars()` — the platform-neutral
way to thread configuration without each call site reaching for
`Platform.environment` (which would not compile for web). `getIsolateName()`
returns `Isolate.current.debugName` (or `"main"`), which the logger stamps onto
each line.

---

## Part 4 — The HTTP client

`httpClient()` returns a `package:http` `Client` backed by `dart:io`'s
`HttpClient`. Its one non-default behaviour is a deliberate convenience: invalid
TLS certificates are accepted **only** for `localhost` / `127.0.0.1` / `0.0.0.0`,
so a self-signed dev server just works while remote calls stay strict.

To keep the example hermetic — no network, runs in CI — it stands up a throwaway
local HTTP server and calls it:

```dart
import 'dart:io';

import 'package:tom_basics_console/tom_basics_console.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response
      ..statusCode = 200
      ..write('{"status":"ok"}');
    await req.response.close();
  });

  final client = TomStandalonePlatformUtils().httpClient();
  try {
    final res = await client.get(
      Uri.parse('http://localhost:${server.port}/health'),
    );
    print('status: ${res.statusCode}');
    print('body:   ${res.body}');
  } finally {
    client.close();
    await server.close();
  }

  // expected output:
  // status: 200
  // body:   {"status":"ok"}
}
```

The same client talking to `https://localhost:8443` with a self-signed
certificate would succeed where a plain `IOClient` rejects it — but for any
non-local host the standard certificate validation applies, exactly as with a
plain `IOClient`. **Always close the client** (and the server, here) when done;
the `try/finally` guarantees it even if the request throws.

For richer HTTP behaviour — retry with backoff, server discovery — see the next
sample, [`tom_basics_network_sample`](../tom_basics_network_sample/).

---

## Part 5 — Styled logging through the seam

Part 2.2 promised a payoff: the default console log sink writes via
`TomPlatformUtils.current.out` / `outError`. So once the standalone
implementation is installed, every `tomLog` line is rendered through
`console_markdown` too — `**bold**` in a log message becomes ANSI bold. The log
line also carries a timestamp/isolate/origin (host- and time-specific), so the
example asserts the deterministic rendering transform and emits one real styled
line for illustration:

```dart
import 'package:console_markdown/console_markdown.dart';
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());
  tomLog.setLogLevel(TomLogLevel.production);

  final rendered = '**server** started on port 8080'.toConsole();
  print('markers consumed: ${!rendered.contains('**')}');
  print('ANSI present:     ${rendered.contains('\x1B')}');

  print('--- a real, styled log line follows: ---');
  tomLog.info('**server** started on port 8080');

  // expected output:
  // markers consumed: true
  // ANSI present:     true
  // --- a real, styled log line follows: ---
  //   <timestamped INFO line; "server" rendered bold via ANSI>
}
```

A real emitted line looks like:

```text
2026-06-16 22:36:30.817254 main-main INFO    server started on port 8080  [main]
```

where the word *server* is bold via ANSI and the timestamp/isolate/origin are
filled in by the logger. This is the whole foundation working together: the
exception/logging vocabularies from [`tom_basics_sample`](../tom_basics_sample/)
plus the platform implementation from this package.

---

## A note on deterministic output

Three things in this sample are inherently host- or time-specific: the detected
**OS** (Part 1), the **ANSI escape bytes** of styled text (Parts 2 and 5), and
the **timestamp/isolate** of a log line (Part 5). Rather than hard-code values
that would be wrong on another machine, the examples assert the *invariants* that
hold everywhere — `!isWeb()`, "markers consumed, ANSI added", "exactly one OS" —
and clearly annotate the variable lines. That keeps the `// expected output`
comments honest on every host while still showing the real, styled result.

---

## Architecture

How the sample's pieces sit on top of the seam:

```text
tom_basics_console_sample (this package, publish_to: none)
│
├── example/01,02 ── TomStandalonePlatformUtils ..... detection + seam wiring
│                      TomPlatformUtils.setCurrentPlatform / .current
│
├── example/03 ───── out / outError .................. Markdown → ANSI
│                      (console_markdown .toConsole)
│
├── example/04 ───── getTomEnvVars / getIsolateName ... process env + isolate
│
├── example/05 ───── httpClient() .................... IO client vs local server
│
├── example/06 ───── tomLog (re-exported) ............ styled logging via seam
│
└── example/run_all_examples.dart ................... awaits each main(),
                                                      tallies, exits non-zero
        │
        └── depends on ──► package:tom_basics_console (path: ../../tom_basics_console)
                              │  extends + re-exports
                              └► package:tom_basics  (the abstract seam)
```

`TomStandalonePlatformUtils` extends `TomFallbackPlatformUtils` (from
`tom_basics`) and overrides every host-dependent method; everything else the app
sees — the logger, exceptions, the runtime model — flows through from the
re-export.

---

## Key types

| Type | Kind | First used in | Role |
| ---- | ---- | ------------- | ---- |
| `TomStandalonePlatformUtils` | class | 01 | The standalone/server `TomPlatformUtils`: OS detection, styled output, IO HTTP client, env, isolate name. |
| `standalonePlatformUtils` | getter | 02 | Fresh `TomStandalonePlatformUtils` typed as `TomPlatformUtils`. |
| `TomPlatformUtils` | abstract | 02 | The seam: `setCurrentPlatform` / `current` + the detection/output/HTTP contract. *(re-exported from `tom_basics`)* |
| `TomFallbackPlatformUtils` | class | — | The default, throwing implementation the standalone one replaces. *(re-exported)* |
| `tomLog` / `TomLogLevel` | global / class | 06 | The logger, re-exported; renders through the seam once installed. |

For the exception and logging vocabularies, see
[`tom_basics_sample`](../tom_basics_sample/) and the
[`tom_basics` manual](../../tom_basics/).

---

## Ecosystem

- **Teaches:** [`tom_basics_console`](../../tom_basics_console/) — the standalone
  platform implementation.
- **Built on:** [`tom_basics`](../../tom_basics/) — the abstract seam, logger,
  and exception base (re-exported).
- **Previous sample:** [`tom_basics_sample`](../tom_basics_sample/) — exceptions
  and structured logging.
- **Next sample:** [`tom_basics_network_sample`](../tom_basics_network_sample/) —
  HTTP retry with backoff and local server discovery.
- **Sample home:** [`tom_basics_samples`](../) — the full learning path.

The web/Flutter counterpart to `tom_basics_console` is `tom_core_flutter`, which
provides a `TomPlatformUtils` implementation for those targets. Library packages
that must remain web-safe depend on `tom_basics` directly and never on this
package.

---

## Further documentation

- [`tom_basics_console` README](../../tom_basics_console/) — the full module
  manual (the seam relationship, every member, architecture).
- [`tom_basics` README](../../tom_basics/) — the abstract seam, logger, and
  exception base this package implements and re-exports.
- [`console_markdown` guideline](../../../../_copilot_guidelines/console_markdown.md)
  — the Markdown-to-ANSI vocabulary used by `out` / `outError`.
- [`tom_basics_samples` README](../) — the samples index and learning path.

---

## Status

Ready (`1.0.0`). Six runnable examples (one async) with verified inline expected
output; [`example/run_all_examples.dart`](example/run_all_examples.dart) runs
them all and exits 0; `dart analyze` is clean. This is sample **#2** of the
`tom_ai/basics` [learning path](../#learning-path).
