## 1.0.0

- Initial release: non-destructive Markdown region merge built on
  `tom_doc_specs`' insert-marker engine.
- `MarkdownMerge.merge` refreshes `tom.managed.<key>` regions, preserves
  `tom.override.<key>` regions and all free text, and suppresses managed
  refresh when an override exists for the same key.
- Helpers: `managedKeys`, `overrideKeys`, `managedBlock`, `overrideBlock`.
