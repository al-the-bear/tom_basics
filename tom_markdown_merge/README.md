# tom_markdown_merge

Non-destructive **Markdown region merge**: let a generator refresh designated
regions of a Markdown file on every run *without clobbering hand-authored
prose*. Built on `tom_doc_specs`' insert-marker engine
(`InsertMarkerParser`/`InsertMarkerProcessor`) rather than a hand-written
parser, so parsing stays AST-based and is shared with the rest of the Tom
toolchain.

## The model

A Markdown document is tokenised into **insert-marker regions** delimited by
HTML comments (invisible in any Markdown preview). Each region carries a
*variable*; this package gives the variable a meaning via a prefix:

| Region | Marker | Behaviour on merge |
| ------ | ------ | ------------------ |
| **Managed** | `<!--$insert:tom.managed.<key>-->` … `<!--$end-insert-->` | The generator **may refresh** the content when it owns `<key>`. |
| **Override** | `<!--$insert:tom.override.<key>-->` … `<!--$end-insert-->` | Author-owned. **Never rewritten**; also *suppresses* a managed region for the same key. |
| Free text | (anything outside a region) | **Preserved verbatim**, in document order — prepend or append freely. |
| Foreign | any other `$insert:` variable | Left untouched (not owned by this merge). |

> **Marker syntax note.** These markers reuse the existing
> `tom_doc_specs` insert-marker grammar (`<!--$insert:VAR-->` /
> `<!--$end-insert-->`, variable `[a-zA-Z][a-zA-Z0-9_.]+`). The behaviour
> (managed-refresh / override-replace / free-text-preserve) is encoded in the
> `tom.managed.` / `tom.override.` variable prefix. This is the reconciled form
> of the `@tom:managed` / `@tom:override` concept from the website spec §6.2:
> the engine could not parse the `@tom:` spelling, so the variable prefix
> carries the same intent.

## Usage

```dart
import 'package:tom_markdown_merge/tom_markdown_merge.dart';

const merge = MarkdownMerge();

// Refresh managed regions the generator currently owns:
final updated = merge.merge(currentMarkdown, {
  'overview': 'freshly generated overview prose',
  'summary': 'freshly generated summary',
});

// Inspect which keys a document declares:
final managed = merge.managedKeys(currentMarkdown);   // Set<String>
final overridden = merge.overrideKeys(currentMarkdown); // a generator should
                                                        // skip these keys

// Emit a fresh block (e.g. on first generation):
final block = merge.managedBlock('overview', 'first draft');
```

### Rules in detail

- A **managed** region whose key is in the `generated` map **and is not
  overridden** has its content replaced.
- An **override** region is never touched. If both an override and a managed
  region exist for the same key, the override wins and the managed region is
  left as-is (not refreshed).
- A managed key **absent** from the `generated` map is left as-is (the
  generator no longer owns it).
- All free text and foreign `$insert:` regions are preserved verbatim.
- Malformed markers (nested or unclosed) raise `FormatException` (propagated
  from the underlying parser) — merges fail loud rather than silently corrupt.

### Constraints

- Marker keys must match the insert-marker variable grammar (`[a-zA-Z0-9_.]`).
- Region content must not itself contain insert markers (nesting is rejected).

## Testing

```bash
dart test
```
