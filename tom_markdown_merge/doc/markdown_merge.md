# Markdown Merge Guide

Tom Markdown Merge lets a program that generates Markdown refresh the parts of
a file it owns without disturbing the parts a person wrote. This guide explains
the concepts, the API, how each operation behaves and where its limits are.

## Concepts

### Regions and markers

A **region** is a span of lines between two HTML comment lines:

```markdown
<!--$insert:tom.managed.overview-->
The region's content, one or more lines.
<!--$end-insert-->
```

The first line is the start marker and names the region's **variable**
(`tom.managed.overview`); the second is the end marker. Markdown renderers do
not show HTML comments, so a file with markers previews the same as one
without. Everything outside a region is **free text**.

The marker grammar and its parser belong to Tom DocSpecs (`InsertMarkerParser`
and `InsertMarkerProcessor` in `tom_doc_specs`); this package adds the meaning
of the variable prefixes on top.

### The four kinds of content

| Kind | Variable | What a merge does with it |
| ---- | -------- | ------------------------- |
| Managed region | `tom.managed.<key>` | Replaces its content when the generator supplies `<key>` and no override region for `<key>` exists |
| Override region | `tom.override.<key>` | Never changes it; its presence stops the managed region of the same `<key>` from being refreshed |
| Foreign region | any other variable, e.g. `chat.lastReply` | Never changes it; it belongs to another tool |
| Free text | no marker | Keeps it byte for byte, in document order |

The **key** is the part of the variable after the prefix: `overview` in
`tom.managed.overview`. The prefixes are the top-level constants
`managedPrefix` (`'tom.managed.'`) and `overridePrefix` (`'tom.override.'`).

### Who owns what

- The **generator** owns the managed regions whose keys it supplies to a merge.
- The **author** owns the free text and the override regions. An override
  region is how an author replaces generated prose for one key: write an
  override region with the same key, and the generated text for that key is
  neither refreshed nor shown.
- A managed key the generator no longer supplies is left as it is, so dropping
  a key from a generator never deletes text from a file.

## API

Everything is on one class, `MarkdownMerge`, which holds no state and does no
I/O: it takes strings and returns strings, and reading and writing files is
the caller's job. It has a `const` constructor.

```dart
import 'package:tom_markdown_merge/tom_markdown_merge.dart';

const merge = MarkdownMerge();
```

### `merge(current, generated)`

Returns `current` with every managed region refreshed from `generated`, a map
of key to fresh content. The markers stay in the result so the file can be
merged again on the next run.

```dart
const doc = '''
# Order Service

<!--\$insert:tom.managed.overview-->
Old generated overview.
<!--\$end-insert-->

Notes written by hand.''';

final result = merge.merge(doc, {'overview': 'Fresh generated overview.'});
```

`result` is `doc` with `Old generated overview.` replaced by
`Fresh generated overview.`; the heading, the markers and the notes are
unchanged.

A region is refreshed only when all three hold: its variable starts with
`tom.managed.`, its key is in `generated`, and the document has no override
region for that key. Every other region and all free text come back unchanged.
A document without markers is returned as it is.

### `flatten(markdown)`

Returns the **display form**: the document with every marker line removed, for
showing to a reader. Where a managed region and an override region share a key,
the managed region's content is dropped as well, so superseded prose is never
shown. All other region content and all free text stay, in document order.

```dart
const current = '''
<!--\$insert:tom.managed.status-->
Generated status.
<!--\$end-insert-->
<!--\$insert:tom.override.status-->
Status written by the author.
<!--\$end-insert-->''';

merge.flatten(current); // 'Status written by the author.'
```

Keep the merged form on disk and flatten when rendering; a flattened document
has no markers left to merge into.

### `managedKeys(markdown)` and `overrideKeys(markdown)`

Return the keys of the managed and of the override regions in a document, as a
`Set<String>`. Foreign regions appear in neither.

```dart
merge.managedKeys(current); // {status}
merge.overrideKeys(current); // {status}
```

A generator can read `overrideKeys` to skip producing content the author has
replaced.

### `managedBlock(key, content)` and `overrideBlock(key, content)`

Build a new region as a string: the start marker for `tom.managed.<key>` or
`tom.override.<key>`, the content, and the end marker, joined by line breaks.
Empty content gives a region with an empty body.

```dart
merge.managedBlock('overview', 'First draft.');
// <!--$insert:tom.managed.overview-->
// First draft.
// <!--$end-insert-->

merge.managedBlock('overview', '');
// <!--$insert:tom.managed.overview-->
// <!--$end-insert-->
```

A generator writing a file for the first time places managed blocks where its
content goes; every later run calls `merge` with the same keys.

## Behaviour in detail

- **Markers are whole lines.** A start or end marker is recognised only when it
  is the only thing on its line; whitespace around it, including a trailing
  carriage return, is allowed. A marker written inside a sentence is free text.
- **Variable grammar.** A variable starts with a letter and continues with
  letters, digits, `_` and `.`. A key with any other character (a hyphen, a
  space) makes the start line unrecognisable, so the region is not a region;
  use keys such as `overview`, `api_index` or `section.intro`.
- **Every region of a key is refreshed.** When a document holds two managed
  regions with the same key, `merge` writes the generated content into both.
- **Content is inserted as given.** The generated string goes between the
  markers unchanged. A trailing line break in it leaves a blank line before the
  end marker, and an empty string leaves the region empty.
- **Merging is repeatable.** Merging the same generated content into an
  already merged document returns it unchanged.
- **Malformed documents are refused.** An unclosed region, an end marker
  without a start, or a region opened inside another region makes `merge`,
  `flatten`, `managedKeys` and `overrideKeys` throw a `FormatException` whose
  message names the marker and its line. Nothing is half-merged.

## Limits

- **No nesting.** A region cannot contain another region, so generated content
  must not contain marker lines; otherwise the next merge of the file fails.
- **No awareness of Markdown structure.** The parser reads lines, not Markdown:
  a marker line inside a fenced code block is still a marker, and so is an
  indented one. To show marker syntax in a document, put other text on the same
  line (for example a comment before it), so that the marker is not alone on
  its line.
- **No file handling.** The package neither reads nor writes files and keeps
  no record of earlier runs; a file's markers are its whole state.
- **No headline adjustment.** Shifting heading levels when documents are
  concatenated is a separate concern, handled by the workspace script
  `_bin/md_headline_indent.sh`.

## See also

- [README](../README.md) — overview, installation and the quick start.
- [`example/tom_markdown_merge_example.dart`](../example/tom_markdown_merge_example.dart)
  — a runnable program covering every operation in this guide.
- [`test/markdown_merge_test.dart`](../test/markdown_merge_test.dart) — the
  rules as tests.
