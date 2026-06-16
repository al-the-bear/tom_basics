# Tom Basics — Samples

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

The **canonical home** for runnable, article-grade sample projects covering the
[`tom_ai/basics/`](../) packages. Each sample is a **self-contained Dart package**
in this folder with its own `pubspec.yaml`, `example/` (one-concept-per-file,
runnable examples with inline expected output), an `example/run_all_examples.dart`
smoke test, and a comprehensive README.

If you are looking for the **packages themselves**, they live one level up in
[`tom_ai/basics/`](../); each carries its own manual-style README. If you are
looking for **how to use them by example**, you are in the right place.

---

## Learning path

Ordered from first contact to advanced framework use. Each sample pairs with the
module it teaches; follow the **Pairs with** link for that module's full manual.

| # | Sample | Demonstrates | Pairs with | Status |
| - | ------ | ------------ | ---------- | ------ |
| 1 | [`tom_basics_sample`](tom_basics_sample/) | Exception handling + UUID tracking, end to end. | [`tom_basics`](../tom_basics/) | Ready |
| 2 | [`tom_basics_console_sample`](tom_basics_console_sample/) | Platform detection, console output, HTTP client. | [`tom_basics_console`](../tom_basics_console/) | Ready |
| 3 | [`tom_basics_network_sample`](tom_basics_network_sample/) | HTTP retry with backoff + local server discovery (runs offline). | [`tom_basics_network`](../tom_basics_network/) | Ready |
| 4 | [`tom_build_base_introduction_sample`](tom_build_base_introduction_sample/) | A simple single-command build tool on `tom_build_base`. | [`tom_build_base`](../tom_build_base/) | Ready |
| 5 | [`tom_build_base_advanced_sample`](tom_build_base_advanced_sample/) | A nestable, multi-command build tool with options and pipelines. | [`tom_build_base`](../tom_build_base/) | Ready |
| 6 | [`tom_build_base_advanced_analyzer_sample`](tom_build_base_advanced_analyzer_sample/) | Analyzer-summary caching with `tom_analyzer_shared` in a generator-style command. | [`tom_analyzer_shared`](../tom_analyzer_shared/) | Ready |
| 7 | [`tom_chattools_sample`](tom_chattools_sample/) | The unified chat API against a mock transport (no live tokens). | [`tom_chattools`](../tom_chattools/) | Ready |
| 8 | [`tom_crypto_sample`](tom_crypto_sample/) | JWT issue/verify, password hash/verify, RSA round trips. | [`tom_crypto`](../tom_crypto/) | Pending |

> **Forward references.** This index is the scaffold that the sample build-out
> registers into. Until a sample's own project lands, its link above is a forward
> reference and its **Status** reads *Pending*; the
> [aggregator](#running-the-whole-set) reports those samples as `PENDING` rather
> than failing. As each sample is scaffolded its status flips to *Ready* and the
> aggregator runs it automatically.

---

## Running the whole set

From this folder, run every sample's smoke test in one pass:

```bash
cd tom_ai/basics/tom_basics_samples
dart pub get
dart run run_all_examples.dart
```

The aggregator walks the learning-path samples in order, runs each scaffolded
sample's own `example/run_all_examples.dart` as a subprocess, and prints a
combined **passed / failed / pending** tally. It exits non-zero only if a
*scaffolded* sample fails — pending samples never fail the run. No edit to the
aggregator is needed as samples land: it discovers each sample's runner by
convention (`<sample>/example/run_all_examples.dart`).

Each individual sample can also be run on its own:

```bash
cd tom_ai/basics/tom_basics_samples/<sample>
dart pub get
dart run example/run_all_examples.dart
```

---

## How a sample is structured

Every sample package in this folder follows the same shape (guideline §2 + §4):

```text
<sample>/
├── pubspec.yaml                  # self-contained; depends on the module it teaches
├── analysis_options.yaml         # include: ../analysis_options.yaml
├── README.md                     # comprehensive, article-grade manual
└── example/
    ├── <concept>_example.dart    # one concept per file, runnable, inline expected output
    ├── …
    └── run_all_examples.dart     # imports each example's main(), runs all, tallies, exits non-zero on failure
```

The example files are the executable specification: each ends its meaningful work
with the result printed and the expectation as a `// expected output` comment, so
the README's pasted snippets are provably runnable.

---

## Related sample homes

These are the samples for the `tom_ai/basics/` packages specifically. Other
domains keep their own canonical sample homes — if you landed here looking for
them:

- **D4rt interpreter & bridging samples** → [`tom_ai/d4rt/tom_d4rt/example/`](../../d4rt/tom_d4rt/example/)
- **Module manuals (per package)** → each package README under [`tom_ai/basics/`](../)
- **The basics map** → [`tom_ai/basics/README.md`](../README.md)

---

## Status

Scaffold in place (`1.0.0`). The index lists all 8 planned samples and the
aggregator is wired and analyzer-clean; the individual sample packages are built
out by their own plan todos, at which point their **Status** flips from *Pending*
to *Ready*.
