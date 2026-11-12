# Console Markdown

`TomStandalonePlatformUtils.out` and `outError` pass their text through
[`console_markdown`](https://pub.dev/packages/console_markdown) before writing
it, so Markdown-like markers in a message become ANSI styles in a terminal and
the markers themselves are consumed. This page is the vocabulary those calls
understand; the same syntax works anywhere with `.toConsole()`.

```dart
import 'package:console_markdown/console_markdown.dart';

print('Hello, **world**!'.toConsole());     // the extension method
print(ConsoleMarkdown.apply('Hello **World**!'));

print('''
  Hello **World**!
  __Looks *pretty* easy__

  <console color="red" background="black" bold> Console Markdown </console>
'''.toConsole());
```

## Symbols

| Symbol | Property | Example | Description |
|--------|----------|---------|-------------|
| `**` | bold | `**text**` | Bold text |
| `*` | italic | `*text*` | Italic text |
| `__` | underline | `__text__` | Underlined text |
| `~~` | strikethrough | `~~text~~` | Strikethrough text |
| `^` | superscript | `^text^` | Superscript |
| `~` | subscript | `~text~` | Subscript |
| `___` | double-underline | `___text___` | Double underline |
| `!!` | blink | `!!text!!` | Blinking text |
| `!!!` | rapid-blink | `!!!text!!!` | Rapid blinking |
| `\|\|` | hidden | `\|\|text\|\|` | Hidden text |
| `^^` | inverse | `^^text^^` | Inverse colors |
| `` ` `` | dim | `` `text` `` | Dimmed text |

## Tags

| Tag | Property | Example |
|-----|----------|---------|
| `<reset>` | reset | `<reset>text` |
| `<overline>` | overline | `<overline>text</overline>` |
| `<br>` | line break | `<br>` |
| `<b>` | bold | `<b>text</b>` |
| `<i>` | italic | `<i>text</i>` |
| `<u>` | underline | `<u>text</u>` |
| `<uu>` | double-underline | `<uu>text</uu>` |
| `<s>` | strikethrough | `<s>text</s>` |
| `<sup>` | superscript | `<sup>text</sup>` |
| `<sub>` | subscript | `<sub>text</sub>` |

## Colors

Color tags: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`,
`white`, `gray`. Add the `background` flag to set the background color.

| Tag | Example | Description |
|-----|---------|-------------|
| `<console>` | `<console color="red" background="#000000" bold>text</console>` | All properties can be combined |
| `<rgb(r,g,b)>` | `<rgb(255, 0, 0)>text</rgb>` | RGB color, add `background` for the background |
| `<hex(...)>` | `<hex(#ff0000)>text</hex>` | Hex color |
| `<#...>` | `<#ff0000>text</#>` | Short hex syntax |

## Faster variants

| Class | Handles |
|-------|---------|
| `ConsoleMarkdownSymbols` | Symbols only (fastest) |
| `ConsoleMarkdownBasic` | The `<console>` tag only |
| `ConsoleMarkdown` | The full syntax |
