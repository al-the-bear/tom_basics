# Tom Markdown Merge

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Non-destructive Markdown region merge (managed / override / preserved
free-text) built on `tom_doc_specs`' insert-marker engine. Lets a generator
refresh designated regions of a Markdown file without clobbering hand-authored
prose.

---

## Overview

When a code generator writes Markdown — a README, a status page, an API index —
it faces a recurring problem: **how do you refresh the generated parts without
destroying the parts a human edited?** Regenerating the whole file throws away
hand-written prose; never regenerating leaves the file stale.

`tom_markdown_merge` solves this with **marked regions**. The generator wraps
the content it owns in an *insert marker* (an HTML comment, invisible in any
Markdown preview); on the next run it refreshes only those regions and preserves
everything else verbatim — in document order. A single class,
[`MarkdownMerge`](#markdownmerge), gives you:

- **`merge`** — refresh the regions a generator currently owns, leaving author
  text, override regions, and foreign markers untouched.
- **`flatten`** — strip the marker comments to produce the *display form* a
  reader should see.
- **Region inspection and block builders** — discover the keys in a document
  and emit fresh marker blocks.

The four content categories the merge distinguishes:

| Category | Marker | On `merge` |
| -------- | ------ | ---------- |
| **Managed** | `<!--$insert:tom.managed.<key>-->` | Refreshed when the generator owns `<key>` |
| **Override** | `<!--$insert:tom.override.<key>-->` | Never touched; **wins** over a managed region of the same key |
| **Foreign** | `<!--$insert:<other>-->` | Left untouched (belongs to a different tool) |
| **Free text** | _(no marker)_ | Preserved verbatim, in order |

The merge is built on `tom_doc_specs`' `InsertMarkerParser`/`InsertMarkerProcessor`
rather than a hand-written Markdown parser, so marker grammar and edge cases
(nested/unclosed markers) are handled by the shared engine.

> **Marker spelling.** The behaviour (managed-refresh / override-replace /
> free-text-preserve) is encoded in the `tom.managed.` / `tom.override.`
> *variable prefix* on the existing insert-marker grammar
> (`<!--$insert:VAR-->` / `<!--$end-insert-->`, variable `[a-zA-Z0-9_.]`). This
> is the reconciled form of the `@tom:managed` / `@tom:override` concept from
> the website spec §6.2: the shared engine could not parse the `@tom:` spelling,
> so the variable prefix carries the same intent.

> **Region-aware, not headline-aware.** This package merges *marked regions*. If
> you need to shift Markdown *headline levels* when concatenating documents,
> that is a separate concern — see [Related tooling](#related-tooling).

---

## Installation

This is a **workspace-internal** package (`publish_to: none`); it is consumed by
path, not from pub.dev:

```yaml
dependencies:
  tom_markdown_merge:
    path: ../../basics/tom_markdown_merge
```

It depends (by path) on
[`tom_doc_specs`](../../ai_build/tom_doc_specs/), which provides the
insert-marker engine. Requires the Dart SDK `^3.10.4`. Pure Dart — no Flutter,
no I/O of its own (you read and write the files).

---

## Features

| Capability | API | Notes |
| ---------- | --- | ----- |
| Refresh managed regions | `merge(current, generated)` | `generated` is `key → fresh prose` |
| Produce display form | `flatten(markdown)` | Strips marker comments; override wins |
| List managed keys | `managedKeys(markdown)` | `Set<String>` of owned keys |
| List override keys | `overrideKeys(markdown)` | Generator should suppress output for these |
| Build a managed block | `managedBlock(key, content)` | Emits a fresh `tom.managed.<key>` region |
| Build an override block | `overrideBlock(key, content)` | Emits a fresh `tom.override.<key>` region |
| Marker prefixes | `managedPrefix`, `overridePrefix` | `tom.managed.` / `tom.override.` constants |

---

## Quick start

Refresh a generated region while keeping the author's notes:

```dart
import 'package:tom_markdown_merge/tom_markdown_merge.dart';

void main() {
  const merge = MarkdownMerge();

  const doc = '''
# My Component

<!--\$insert:tom.managed.overview-->
Old generated overview.
<!--\$end-insert-->

Hand-written notes I never want a generator to touch.''';

  // The generator owns the `overview` key and supplies fresh prose for it.
  final result = merge.merge(doc, {'overview': 'Fresh generated overview.'});
  print(result);
}
```

Output — the managed region is refreshed, everything else is byte-identical:

```markdown
# My Component

<!--$insert:tom.managed.overview-->
Fresh generated overview.
<!--$end-insert-->

Hand-written notes I never want a generator to touch.
```

The markers stay in the file so it can be re-merged next run. To render it for a
reader, [`flatten`](#flatten--display-form) strips them.

---

## Example projects

| Example | What it shows |
| ------- | ------------- |
| [Quick start](#quick-start) | Refresh one managed region |
| [The merge contract](#the-merge-contract) | All four region categories |
| [flatten — display form](#flatten--display-form) | Strip markers for rendering |
| [Override wins](#override-wins) | Author content supersedes generated |
| [Inspecting & building regions](#inspecting--building-regions) | Keys + block builders |
| [`test/markdown_merge_test.dart`](test/markdown_merge_test.dart) | 19 worked cases covering every rule |

> This package has no standalone `example/` program — it is a library consumed
> by generators. The runnable test suite is the executable reference for every
> rule below.

---

## Usage

### The merge contract

`merge(current, generated)` walks the document and applies exactly these rules
(spec §6.2):

- A **managed region** whose key is in `generated` and is *not* overridden →
  content replaced with the generated prose.
- A managed key **absent** from `generated` → left as-is (the generator no
  longer owns it).
- An **override region** → never touched, and it removes its key from the set
  the generator may refresh.
- **Free text** and **foreign `$insert:` regions** → preserved verbatim, in
  document order.
- A document with **no markers** → returned unchanged.
- A **malformed** document (nested or unclosed markers) → throws
  `FormatException` (from the underlying parser). Merges fail loud rather than
  silently corrupt.

```dart
// Generator no longer owns 'overview' → region preserved unchanged.
merge.merge(doc, {'summary': 'unrelated'}); // == doc

// Foreign region (different tool's namespace) → untouched.
const foreign = '<!--\$insert:chat.lastReply-->\nnot ours\n<!--\$end-insert-->';
merge.merge(foreign, {'lastReply': 'nope'}); // == foreign
```

Two grammar constraints, enforced by the underlying parser: marker keys must
match the insert-marker variable grammar (`[a-zA-Z0-9_.]`), and region content
must not itself contain insert markers (nesting is rejected).

### `flatten` — display form

`flatten(markdown)` is the read-side companion to `merge`: it removes the
`<!--$insert:…-->` / `<!--$end-insert-->` comment lines so only live content and
free text remain. `merge` keeps markers (so the file can be re-merged);
`flatten` strips them (so the content can be rendered).

```dart
final display = merge.flatten(result);
print(display);
```

Output:

```markdown
# My Component

Fresh generated overview.

Hand-written notes I never want a generator to touch.
```

### Override wins

When both a managed and an override region exist for the same key, the
**override wins** — `merge` refreshes neither, and `flatten` drops the managed
body so superseded prose is never shown.

```dart
const current = '''
<!--\$insert:tom.managed.overview-->
generated
<!--\$end-insert-->
<!--\$insert:tom.override.overview-->
author-owned
<!--\$end-insert-->''';

merge.merge(current, {'overview': 'new'}); // == current (neither refreshed)

merge.flatten(current); // → 'author-owned' only; 'generated' is dropped
```

### Inspecting & building regions

Discover what a document declares, and emit fresh marker blocks:

```dart
merge.managedKeys(mixed);  // {a}
merge.overrideKeys(mixed); // {b}   (foreign regions report under neither)

merge.managedBlock('overview', 'first draft');
```

`managedBlock` output:

```markdown
<!--$insert:tom.managed.overview-->
first draft
<!--$end-insert-->
```

`overrideBlock('body', 'mine')` produces the same shape with the
`tom.override.body` variable. Empty content yields an empty body —
`managedBlock('overview', '')` is exactly:

```markdown
<!--$insert:tom.managed.overview-->
<!--$end-insert-->
```

A `managedBlock` round-trips through `merge`: build it once, then refresh its key
on every later run.

---

## Architecture

```text
package:tom_markdown_merge/tom_markdown_merge.dart
│
└── MarkdownMerge                         (the entire public surface)
    ├── merge(current, generated)         refresh owned managed regions
    ├── flatten(markdown)                 strip markers → display form
    ├── managedKeys / overrideKeys        region inspection
    ├── managedBlock / overrideBlock      emit fresh marker blocks
    └── managedPrefix / overridePrefix    'tom.managed.' / 'tom.override.'
            │
            └── delegates marker parsing/processing to
                package:tom_doc_specs
                ├── InsertMarkerParser     tokenises $insert: regions
                ├── InsertMarkerProcessor  rewrites region bodies
                └── InsertMarker           start/end line + variable
```

| Type / member | Role |
| ------------- | ---- |
| `MarkdownMerge` | The whole API — a small, stateless, `const`-constructible value |
| `merge` | Non-destructive refresh of managed regions |
| `flatten` | Marker-stripping display projection |
| `managedKeys` / `overrideKeys` | Report a document's declared region keys |
| `managedBlock` / `overrideBlock` | Construct fresh marker blocks |
| `managedPrefix` / `overridePrefix` | The `tom.managed.` / `tom.override.` variable prefixes |

`MarkdownMerge` holds no state and does no I/O: you pass strings and get strings
back. Reading and writing the files is the caller's concern.

---

## Related tooling

- **[`tom_doc_specs`](../../ai_build/tom_doc_specs/)** — the insert-marker engine
  (`InsertMarkerParser` / `InsertMarkerProcessor`) this package builds on, plus
  the wider DocSpecs document-schema toolkit. Reach for it directly when you need
  raw marker processing without the managed/override merge semantics.
- **`_bin/md_headline_indent.sh`** (workspace root) — a *different* Markdown
  concern: it shifts headline levels (`#` → `##`, …) when **concatenating**
  documents. Use it when you assemble several Markdown files into one and need to
  re-nest their headings; use `tom_markdown_merge` when you need to **refresh
  regions in place** without disturbing author text. They compose cleanly — merge
  the regions first, concatenate-and-indent second.

---

## Ecosystem

`tom_markdown_merge` is one of the foundational packages under
[`tom_ai/basics/`](../). All `tom_ai/basics/` packages share a single
repository, [`tom_basics`](https://github.com/al-the-bear/tom_basics). This
package is consumed by Tom's documentation generators, which own the managed
regions of the READMEs and doc pages they produce.

---

## Further documentation

- [LICENSE](LICENSE) — BSD-3-Clause licence text.
- [`test/markdown_merge_test.dart`](test/markdown_merge_test.dart) — 19 worked
  cases that double as the executable specification.
- [`tom_doc_specs`](../../ai_build/tom_doc_specs/) — the insert-marker engine and
  DocSpecs specification.
- Source library docs — `MarkdownMerge` and the prefix constants carry dartdoc
  with the full rule set.

---

## Status

Stable (`1.0.0`). The public surface is a single stateless class; all 19 tests
pass and `dart analyze` is clean. Workspace-internal (`publish_to: none`),
consumed by path.
