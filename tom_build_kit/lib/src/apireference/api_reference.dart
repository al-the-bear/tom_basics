/// The combined API reference behind `buildkit :apireference`: a package's
/// hand-authored API summaries and module guides, collected in the order
/// `_copilot_guidelines/dart/api_reference_creation.md` gives and assembled
/// into one Markdown document, which tom_md2pdf renders to PDF.
///
/// **The parts:** Part I is `doc/api/api_summary_index.md`; Part II every
/// `doc/api/api_summary_<module>.md`, alphabetically, under
/// `## <Module> Reference` with its own headline dropped and its headings one
/// level deeper; Part III the guide of each module that has one,
/// `doc/<module>.md` or `doc/<module>/<module>.md`, under
/// `## <Module> Guide`. Link-only table columns are removed and links become
/// their text: a PDF reader cannot follow them.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The inputs of one package's reference, and what is missing from them.
class ApiReferenceInputs {
  /// `doc/api/api_summary_index.md`, or null when there is none.
  final String? index;

  /// `api_summary_<module>.md` by module, alphabetically.
  final Map<String, String> summaries;

  /// The guide of each module that has one.
  final Map<String, String> guides;

  /// Inputs the reference needs and does not have, each a sentence: the
  /// index, any module summary, a summary the index links to.
  final List<String> missing;

  /// Modules without a guide; Part III leaves them out.
  final List<String> withoutGuide;

  const ApiReferenceInputs({
    required this.index,
    required this.summaries,
    required this.guides,
    required this.missing,
    required this.withoutGuide,
  });

  bool get complete => missing.isEmpty;
}

/// Where the summaries and guides of a package live.
const kApiDocDir = 'doc';

/// Collects the inputs of the package at [packageDir]; null when it has no
/// `doc/api/` folder (it documents no API).
ApiReferenceInputs? collectApiReferenceInputs(String packageDir) {
  final apiDir = Directory(p.join(packageDir, kApiDocDir, 'api'));
  if (!apiDir.existsSync()) return null;
  String rel(String path) => p.relative(path, from: packageDir);

  final indexFile = File(p.join(apiDir.path, 'api_summary_index.md'));
  final summaries = <String, String>{};
  for (final f in apiDir.listSync().whereType<File>()) {
    final m = RegExp(r'^api_summary_(.+)\.md$').firstMatch(p.basename(f.path));
    if (m == null || m.group(1) == 'index') continue;
    summaries[m.group(1)!] = f.path;
  }
  final sorted = Map.fromEntries(
    summaries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  );

  final missing = <String>[];
  if (!indexFile.existsSync()) {
    missing.add('no index: ${rel(indexFile.path)}');
  } else {
    // A summary the index links to must be there.
    final linked = RegExp(
      r'\]\((?:\./)?(api_summary_[A-Za-z0-9_]+\.md)(?:#[^)]*)?\)',
    ).allMatches(indexFile.readAsStringSync()).map((m) => m.group(1)!).toSet();
    for (final name in linked.toList()..sort()) {
      if (!File(p.join(apiDir.path, name)).existsSync()) {
        missing.add(
          'the index links to ${rel(p.join(apiDir.path, name))}, '
          'which does not exist',
        );
      }
    }
  }
  if (sorted.isEmpty) {
    missing.add(
      'no module summary: ${rel(apiDir.path)}/api_summary_<module>.md',
    );
  }

  final guides = <String, String>{};
  final withoutGuide = <String>[];
  for (final module in sorted.keys) {
    final candidates = [
      p.join(packageDir, kApiDocDir, '$module.md'),
      p.join(packageDir, kApiDocDir, module, '$module.md'),
    ];
    final guide = candidates.where((c) => File(c).existsSync()).firstOrNull;
    if (guide == null) {
      withoutGuide.add(module);
    } else {
      guides[module] = guide;
    }
  }

  return ApiReferenceInputs(
    index: indexFile.existsSync() ? indexFile.path : null,
    summaries: sorted,
    guides: guides,
    missing: missing,
    withoutGuide: withoutGuide,
  );
}

/// `tom_core_message_bus` → `Tom Core Message Bus`.
String titleCase(String snake) => snake
    .split('_')
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
    .join(' ');

/// The combined document of [inputs] for the package [packageName], dated
/// [now].
String assembleApiReference(
  ApiReferenceInputs inputs,
  String packageName, {
  required DateTime now,
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final out = StringBuffer()
    ..writeln('# ${titleCase(packageName)} API Reference')
    ..writeln()
    ..writeln(
      'Created on ${two(now.day)}.${two(now.month)}.${now.year} at '
      '${two(now.hour)}:${two(now.minute)}',
    )
    ..writeln()
    ..writeln('# Part I: API Summary Index')
    ..writeln()
    ..writeln(_plain(_withoutHeadline(File(inputs.index!).readAsStringSync())))
    ..writeln()
    ..writeln('# Part II: Module API References');
  for (final entry in inputs.summaries.entries) {
    out
      ..writeln()
      ..writeln('## ${titleCase(entry.key)} Reference')
      ..writeln()
      ..writeln(
        _deeper(_plain(_withoutHeadline(File(entry.value).readAsStringSync()))),
      );
  }
  if (inputs.guides.isNotEmpty) {
    out
      ..writeln()
      ..writeln('# Part III: Module Guides');
    for (final entry in inputs.guides.entries) {
      out
        ..writeln()
        ..writeln('## ${titleCase(entry.key)} Guide')
        ..writeln()
        ..writeln(
          _deeper(
            _plain(_withoutHeadline(File(entry.value).readAsStringSync())),
          ),
        );
    }
  }
  return out.toString();
}

/// [text] without its first line when that is a level-1 headline.
String _withoutHeadline(String text) {
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.first.startsWith('# ')) lines.removeAt(0);
  return lines.join('\n').trim();
}

/// Headings one level deeper, so a document nests under its `##` heading;
/// fenced code is left alone.
String _deeper(String text) {
  var fence = false;
  return [
    for (final line in text.split('\n'))
      if (line.trimLeft().startsWith('```'))
        (() {
          fence = !fence;
          return line;
        })()
      else if (!fence && RegExp(r'^#{1,5} ').hasMatch(line))
        '#$line'
      else
        line,
  ].join('\n');
}

/// Links as their text, and table columns holding only links (a `Link`
/// column of `[→](...)` cells) removed.
String _plain(String text) {
  final lines = text.split('\n');
  final out = <String>[];
  var fence = false;
  List<int>? dropColumns; // in the table being read
  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) fence = !fence;
    if (fence || !line.trimLeft().startsWith('|')) {
      dropColumns = null;
      out.add(fence ? line : _unlink(line));
      continue;
    }
    final cells = _cells(line);
    // A header row: drop the columns headed `Link` (or `→`, `Guide`).
    dropColumns ??= [
      for (var i = 0; i < cells.length; i++)
        if (RegExp(
          r'^(link|links|→|guide)$',
          caseSensitive: false,
        ).hasMatch(cells[i].trim()))
          i,
    ];
    final kept = [
      for (var i = 0; i < cells.length; i++)
        if (!dropColumns.contains(i)) _unlink(cells[i]),
    ];
    out.add('|${kept.join('|')}|');
  }
  return out.join('\n');
}

List<String> _cells(String row) {
  var r = row.trim();
  if (r.startsWith('|')) r = r.substring(1);
  if (r.endsWith('|')) r = r.substring(0, r.length - 1);
  // `\|` inside a cell is text, not a column.
  return r.split(RegExp(r'(?<!\\)\|'));
}

/// `[text](url)` → `text`; images are left as they are.
String _unlink(String text) =>
    text.replaceAllMapped(RegExp(r'(?<!!)\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!);
