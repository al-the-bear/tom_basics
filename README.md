# Tom Basics — the foundation layer of the Tom framework

> Tom Basics is part of the **Tom framework** by al-the-bear.
> Distributed under the terms in each package's own license — see
> [LICENSE.md](LICENSE.md).

A small family of focused, dependency-light Dart packages that every other
Tom component builds on: exception handling with traceable IDs, platform and
console utilities, networking, the unified **CLI / build framework**
(`tom_build_base`), cryptography, a unified messaging API, and a handful of
documentation / workspace tools.

**This document is the map.** It orients you to the whole `tom_ai/basics`
repository and routes you to the one package you actually need — each package
carries its own README with the full manual, and the runnable samples live in
[`tom_basics_samples/`](tom_basics_samples/). Depth lives downstream; this page
is just the index.

---

## New here?

Start with the **[`tom_basics_sample`](tom_basics_samples/tom_basics_sample/)**
project — it walks the exception-handling-with-UUID-tracking model end to end
and is the gentlest on-ramp into the ecosystem. From there, the
[samples learning path](#samples-learning-path) takes you category by category.

---

## What you can do with Tom Basics

- **Track every failure to its source** — wrap and rethrow exceptions carrying
  a stable UUID so a log line on one machine maps to a stack frame on another.
- **Write code that runs the same on console and in the browser** — platform
  detection, console output, and an HTTP client that abstract the host away.
- **Talk to flaky networks reliably** — HTTP retry with backoff and local
  server discovery.
- **Build your own CLI tools in minutes** — declare a tool, its commands and
  options once and get argument parsing, help, workspace traversal, pipelines
  and config for free (`tom_build_base`).
- **Secure your data** — issue and verify JWTs, hash and check passwords, and
  do RSA round trips.
- **Send a message anywhere** — one chat API over Telegram, WhatsApp, Signal
  and more.
- **Keep generated docs and workspace metadata honest** — non-destructive
  Markdown merges, workspace package scanning, and key generation.

---

## How the packages fit together

Tom Basics splits into five concern areas. Read this framing before the
component tables so the inventory makes sense:

- **Core utilities** — the universally-imported primitives: error model,
  platform/console helpers, networking. Almost everything depends on these.
- **Build framework** — `tom_build_base` is the shared engine behind every Tom
  CLI tool (`buildkit`, `testkit`, `issuekit`, …); `tom_analyzer_shared` is the
  analyzer-summary cache that code generators sit on.
- **Crypto** — security primitives, isolated so non-security code never pulls
  in the crypto dependency tree.
- **Messaging** — a transport-agnostic chat abstraction.
- **Doc / workspace tooling** — utilities that operate on the workspace itself:
  Markdown merge, package scanning, key generation.

```
                       ┌─────────────────────────────┐
                       │        Core utilities       │
                       │  tom_basics                 │
                       │  tom_basics_console         │
                       │  tom_basics_network         │
                       └──────────────┬──────────────┘
                                      │ used by everything
        ┌───────────────┬─────────────┼──────────────┬──────────────┐
        │               │             │              │              │
 ┌──────┴──────┐ ┌──────┴──────┐ ┌────┴─────┐ ┌──────┴──────┐ ┌─────┴───────┐
 │ Build       │ │ Crypto      │ │ Messaging│ │ Doc / WS    │ │ (downstream │
 │ framework   │ │ tom_crypto  │ │ tom_     │ │ tooling     │ │  Tom repos: │
 │ tom_build_  │ │             │ │ chattools│ │ tom_md_merge│ │  d4rt,      │
 │  base       │ │             │ │          │ │ tom_pkg_scan│ │  devops,    │
 │ tom_analyzer│ │             │ │          │ │ tom_tools   │ │  vscode …)  │
 │  _shared    │ │             │ │          │ │             │ │             │
 └─────────────┘ └─────────────┘ └──────────┘ └─────────────┘ └─────────────┘
```

---

## Components

Every package appears in exactly one row below, linked to its own README.
There are no standalone binaries in this repository — each package is a library
(`tom_build_base` and `tom_tools` ship their executables through the consuming
CLI tools, not from here), so the **Binary** column is `—` throughout.

### Core utilities

| Package | What it is | Binary |
| ------- | ---------- | ------ |
| [`tom_basics`](tom_basics/) | Basic utilities including exception handling with UUID tracking. | — |
| [`tom_basics_console`](tom_basics_console/) | Console / standalone platform utilities — platform detection, console output, HTTP client. | — |
| [`tom_basics_network`](tom_basics_network/) | Network utilities — HTTP retry and server discovery. | — |

### Build framework

| Package | What it is | Binary |
| ------- | ---------- | ------ |
| [`tom_build_base`](tom_build_base/) | Unified CLI framework: workspace traversal, tool definition, pipeline execution, build configuration. | — |
| [`tom_analyzer_shared`](tom_analyzer_shared/) | Shared analyzer-summary caching reused by Tom code generators (reflection, d4rt bridges). | — |

### Crypto

| Package | What it is | Binary |
| ------- | ---------- | ------ |
| [`tom_crypto`](tom_crypto/) | Cryptographic utilities — JWT tokens, password hashing, RSA encryption. | — |

### Messaging

| Package | What it is | Binary |
| ------- | ---------- | ------ |
| [`tom_chattools`](tom_chattools/) | Unified chat API for Telegram, WhatsApp, Signal and other messaging platforms. | — |

### Doc / workspace tooling

| Package | What it is | Binary |
| ------- | ---------- | ------ |
| [`tom_markdown_merge`](tom_markdown_merge/) | Non-destructive, headline-aware Markdown region merge (managed / override / preserved). | — |
| [`tom_package_scanner`](tom_package_scanner/) | Scans workspace repos and derives each Dart package's publication status, license, version and links. | — |
| [`tom_tools`](tom_tools/) | Key-generator CLI built on `tom_crypto`. | — |

---

## Getting started

Add the package you need with its hosted version constraint (never a path
override):

```yaml
dependencies:
  tom_basics: ^1.0.0
```

```bash
dart pub add tom_basics
```

A minimal taste — wrap a failure with a traceable ID:

```dart
import 'package:tom_basics/tom_basics.dart';

void main() {
  try {
    throw StateError('disk full');
  } catch (e, s) {
    final tracked = TomException.wrap(e, s);
    print(tracked.id); // e.g. 3f2a9c41-... (stable UUID for cross-host tracing)
  }
}
```

Each package README opens with its own runnable quick-start — follow the link
from the component tables above.

---

## Samples learning path

Runnable, article-grade sample projects live in
[`tom_basics_samples/`](tom_basics_samples/), one self-contained Dart package
each. Ordered from first contact to advanced framework use:

| # | Sample | Demonstrates |
| - | ------ | ------------ |
| 1 | [`tom_basics_sample`](tom_basics_samples/tom_basics_sample/) | Exception handling + UUID tracking, end to end. |
| 2 | [`tom_basics_console_sample`](tom_basics_samples/tom_basics_console_sample/) | Platform detection, console output, HTTP client. |
| 3 | [`tom_basics_network_sample`](tom_basics_samples/tom_basics_network_sample/) | HTTP retry with backoff + local server discovery. |
| 4 | [`tom_build_base_introduction_sample`](tom_basics_samples/tom_build_base_introduction_sample/) | A simple single-command build tool on `tom_build_base`. |
| 5 | [`tom_build_base_advanced_sample`](tom_basics_samples/tom_build_base_advanced_sample/) | A nestable, multi-command build tool with options and pipelines. |
| 6 | [`tom_build_base_advanced_analyzer_sample`](tom_basics_samples/tom_build_base_advanced_analyzer_sample/) | Analyzer-summary caching with `tom_analyzer_shared` in a generator-style command. |
| 7 | [`tom_chattools_sample`](tom_basics_samples/tom_chattools_sample/) | The unified chat API against a mock transport. |
| 8 | [`tom_crypto_sample`](tom_basics_samples/tom_crypto_sample/) | JWT issue/verify, password hash/verify, RSA round trips. |

> Samples are written before some of their packages' deep-dive docs; until each
> sample project lands, its link is a forward reference resolved by the samples
> build-out.

---

## Documentation index

In-package guides beyond the package READMEs:

| Topic | Document |
| ----- | -------- |
| CLI framework — user guide | [`tom_build_base/doc/build_base_user_guide.md`](tom_build_base/doc/build_base_user_guide.md) |
| CLI tools — navigation model | [`tom_build_base/doc/cli_tools_navigation.md`](tom_build_base/doc/cli_tools_navigation.md) |
| Modes and placeholders | [`tom_build_base/doc/modes_and_placeholders.md`](tom_build_base/doc/modes_and_placeholders.md) |
| Multi-workspace pipelines, macros, defines | [`tom_build_base/doc/multiws_pipelines_macros_defines.md`](tom_build_base/doc/multiws_pipelines_macros_defines.md) |
| Tool inheritance and nesting | [`tom_build_base/doc/tool_inheritance_and_nesting.md`](tom_build_base/doc/tool_inheritance_and_nesting.md) |
| Test coverage | [`tom_build_base/doc/test_coverage.md`](tom_build_base/doc/test_coverage.md) |
| Cryptography reference | [`tom_crypto/doc/crypto.md`](tom_crypto/doc/crypto.md) |

---

## Repository layout

```
tom_ai/basics/
├── README.md                 # this map
├── LICENSE.md                # per-package licensing note
├── analysis_options.yaml     # shared analyzer settings
│
├── tom_basics/               # error model + UUID tracking (core)
├── tom_basics_console/       # platform detection, console output, HTTP (core)
├── tom_basics_network/       # HTTP retry + server discovery (core)
│
├── tom_build_base/           # unified CLI / build framework
│   └── doc/                  # framework user guides
├── tom_analyzer_shared/      # analyzer-summary caching for code generators
│
├── tom_crypto/               # JWT, password hashing, RSA
│   └── doc/                  # crypto reference
│
├── tom_chattools/            # unified chat API (Telegram/WhatsApp/Signal/…)
│
├── tom_markdown_merge/       # non-destructive Markdown region merge
├── tom_package_scanner/      # workspace package publication scanner
├── tom_tools/                # key-generator CLI
│
└── tom_basics_samples/       # runnable, article-grade sample projects
```

---

## License

See [LICENSE.md](LICENSE.md); each package carries its own license terms.
