/// The report and message framework of the commands that end with one
/// report (buildkit's `:ws-*` and `:skill-*`): a command defines its
/// messages once ([MessageDefinition], gathered in a [MessageCatalog]) and
/// gets from them the text report ([RunReport.renderText]), the JSON
/// ([RunReport.toJson]), the command line to repeat for every option, and one
/// help topic per message code ([MessageCatalog.helpTopics]).
///
/// **A message block** reads: the finding, the evidence, the state it was
/// left in, every option with one or two explanation lines, then the command
/// line to repeat:
///
/// ```text
/// CONFLICT  tom_ai/core  (main)                              [ws-conflict]
///   Your 2 local commits and 3 incoming commits change the same lines:
///     lib/src/config.dart        both changed
///   Nothing was pushed for this repository.
///   Options (each acts only on the repositories you name):
///     --merge-branch core   Push your commits to ws-push/mbp/261124-1602 ...
///     --skip core           Leave the repository out of this run (exit 1).
///   Repeat with:  buildkit :ws-push --merge-branch core
/// ```
///
/// **The report:** header (command, root, host, start time, options given),
/// summary line with the exit code, then Refused, Needs you, Warnings (one
/// block per message), Done (one line per changed repository; `-v` lists the
/// rest and every file), and a footer explaining the exit code.
///
/// **Exit codes** ([ReportExitCode]): 0 nothing needs you, 1 something needs
/// you, 2 refused before anything changed (and usage errors), 3 a decision
/// about uncommitted work is open.
///
/// **Repository names** ([RepoNames]): a repository is named by its last path
/// segment when that is unique in the set, else by its path from the root;
/// an option given a list (`--skip core,basics`) acts only on the named ones.
library;

import 'dart:convert';

import '../core/help_topic.dart';

/// How serious a message is; decides where it is listed and the exit code.
enum MessageLevel {
  /// The run stopped before changing anything (exit 2).
  refusal,

  /// A repository needs you; the run goes on with the others (exit 1).
  error,

  /// Worth knowing; does not change the exit code.
  warning,

  /// Information only.
  note,
}

/// The exit codes of a run that ends with a [RunReport].
abstract final class ReportExitCode {
  /// Nothing needs you.
  static const ok = 0;

  /// A repository needs you (an error), or a repository was left out.
  static const needsYou = 1;

  /// Refused before anything changed, or a usage error.
  static const refused = 2;

  /// A decision about uncommitted work is open (the `:skill-*` commands).
  static const decision = 3;

  /// What [code] means, one line.
  static String meaning(int code) => switch (code) {
    ok => 'nothing needs you',
    needsYou => 'something needs you: see "Needs you"',
    refused => 'refused: nothing was changed',
    decision => 'a decision about uncommitted work is open',
    _ => 'exit $code',
  };
}

/// One option of a message: how it is written and what it does.
class MessageOption {
  const MessageOption(
    this.name,
    this.explanation, {
    this.repoList = true,
    this.valueName,
  });

  /// The option's name without dashes (`merge-branch`).
  final String name;

  /// What it does and what follows from it: one or two lines (`\n`).
  final String explanation;

  /// Whether it takes the repositories it acts on (`--skip core,basics`);
  /// false for a run option (`--ignore-active`) and for [valueName] options.
  final bool repoList;

  /// The value an option takes instead of repositories
  /// (`--skip-file <glob>`); the value is given when the message is raised.
  final String? valueName;

  /// `--name`.
  String get flag => '--$name';
}

/// A message, defined once per [code]: its level, the label of its block,
/// its help text and its options.
class MessageDefinition {
  const MessageDefinition({
    required this.code,
    required this.level,
    required this.label,
    required this.summary,
    required this.description,
    this.options = const [],
    this.exitCode,
  });

  /// The help topic and the JSON code (`ws-conflict`).
  final String code;

  final MessageLevel level;

  /// The block's first word (`CONFLICT`).
  final String label;

  /// One line: when it is raised (the topics list, the help page's head).
  final String summary;

  /// Why it matters and what to do, at length (the help page).
  final String description;

  /// The options that resolve it, in the order they are offered.
  final List<MessageOption> options;

  /// The exit code it forces, when not the level's ([ReportExitCode.decision]
  /// for a decision about uncommitted work).
  final int? exitCode;

  /// The exit code a run with this message ends with (at least).
  int get effectiveExitCode =>
      exitCode ??
      switch (level) {
        MessageLevel.refusal => ReportExitCode.refused,
        MessageLevel.error => ReportExitCode.needsYou,
        _ => ReportExitCode.ok,
      };

  /// The help topic `<tool> help <code>`: the summary, the description,
  /// where it is listed and the exit code, and every option at length.
  HelpTopic get helpTopic {
    final b = StringBuffer()
      ..writeln('$label  [$code]')
      ..writeln()
      ..writeln(summary)
      ..writeln()
      ..writeln(description.trimRight())
      ..writeln()
      ..writeln(
        'Listed under "${_section(level)}"; the run ends with exit '
        '$effectiveExitCode or higher (${ReportExitCode.meaning(effectiveExitCode)}).',
      );
    if (options.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Options:');
      for (final o in options) {
        final syntax = o.valueName != null
            ? '${o.flag} <${o.valueName}>'
            : o.repoList
            ? '${o.flag} <repo>[,<repo>...]'
            : o.flag;
        b.writeln('  $syntax');
        for (final line in o.explanation.split('\n')) {
          b.writeln('      $line');
        }
      }
      if (options.any((o) => o.repoList)) {
        b
          ..writeln()
          ..writeln(
            'A repository is named by its last path segment when that is '
            'unique, else by its path from the root; an option acts only on '
            'the repositories it names.',
          );
      }
    }
    return HelpTopic(name: code, summary: summary, content: b.toString());
  }

  /// A message of this definition about [repository].
  ReportMessage raise({
    String? repository,
    String? branch,
    required String finding,
    List<ReportEvidence> evidence = const [],
    String? state,
    Map<String, String> values = const {},
    Map<String, String> explanations = const {},
    List<String>? offer,
  }) => ReportMessage(
    definition: this,
    repository: repository,
    branch: branch,
    finding: finding,
    evidence: evidence,
    state: state,
    values: values,
    explanations: explanations,
    offer: offer,
  );
}

String _section(MessageLevel level) => switch (level) {
  MessageLevel.refusal => 'Refused',
  MessageLevel.error => 'Needs you',
  MessageLevel.warning => 'Warnings',
  MessageLevel.note => 'Notes',
};

/// A command's messages, by code.
class MessageCatalog {
  MessageCatalog(List<MessageDefinition> definitions)
    : definitions = List.unmodifiable(definitions) {
    final seen = <String>{};
    for (final d in definitions) {
      if (!seen.add(d.code)) {
        throw ArgumentError.value(d.code, 'definitions', 'defined twice');
      }
    }
  }

  final List<MessageDefinition> definitions;

  /// The definition of [code]; throws for an unknown code.
  MessageDefinition operator [](String code) => definitions.firstWhere(
    (d) => d.code == code,
    orElse: () => throw ArgumentError.value(code, 'code', 'no such message'),
  );

  /// One help topic per message, for `ToolDefinition.helpTopics`.
  List<HelpTopic> get helpTopics => [for (final d in definitions) d.helpTopic];
}

/// One kind of evidence of a message: files, commits, branches, sizes,
/// windows, ... with a label and its items.
class ReportEvidence {
  const ReportEvidence(this.kind, this.items, {this.label});

  /// The JSON key (`files`, `commits`, `branches`, `sizes`, `windows`).
  final String kind;

  /// The lines, as shown.
  final List<String> items;

  /// The label before the first item in the text (`Local:`); none: the items
  /// are indented under the finding.
  final String? label;
}

/// A raised message: the definition and what this case shows.
class ReportMessage {
  const ReportMessage({
    required this.definition,
    this.repository,
    this.branch,
    required this.finding,
    this.evidence = const [],
    this.state,
    this.values = const {},
    this.explanations = const {},
    this.offer,
  });

  final MessageDefinition definition;

  /// The repository's path from the root ('' for the root); null for a
  /// message about the run.
  final String? repository;

  /// The branch shown beside the repository.
  final String? branch;

  /// What was found and why it matters (lines with `\n`).
  final String finding;

  final List<ReportEvidence> evidence;

  /// The state it was left in.
  final String? state;

  /// The value of a [MessageOption.valueName] option (`skip-file` -> a glob).
  final Map<String, String> values;

  /// This case's explanation of an option, replacing the definition's (it
  /// can name the branch, the stamp, ...).
  final Map<String, String> explanations;

  /// The options offered, by name; null: every option of the definition.
  final List<String>? offer;

  String get code => definition.code;
  MessageLevel get level => definition.level;

  /// The options offered here, in the definition's order.
  List<MessageOption> get options => [
    for (final o in definition.options)
      if (offer == null || offer!.contains(o.name)) o,
  ];
}

/// One repository that changed: what was done (`committed 2 files`,
/// `merged 3 commits`, `pushed`) and the files.
class ReportDone {
  const ReportDone(this.repository, this.actions, {this.files = const []});

  final String repository;
  final List<String> actions;
  final List<String> files;
}

/// The names a run gives its repositories (see the library comment).
class RepoNames {
  /// [paths]: every repository of the set, by path from the root ('' for
  /// the root, named `.`).
  RepoNames(Iterable<String> paths) : paths = List.unmodifiable(paths) {
    final bySegment = <String, List<String>>{};
    for (final path in this.paths) {
      bySegment.putIfAbsent(_last(path), () => []).add(path);
    }
    _bySegment = bySegment;
  }

  final List<String> paths;
  late final Map<String, List<String>> _bySegment;

  static String _last(String path) => path.isEmpty ? '.' : path.split('/').last;

  /// The name of [path]: its last segment when unique, else the path.
  String nameOf(String path) {
    final last = _last(path);
    return _bySegment[last]!.length == 1 ? last : (path.isEmpty ? '.' : path);
  }

  /// The paths a list (`core,tom_ai/basics`) names. Throws
  /// [RepoNameException] for an unknown or ambiguous name, naming the
  /// candidates.
  List<String> resolve(String list) {
    final out = <String>[];
    for (final raw in list.split(',')) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final path = name == '.' ? '' : name;
      if (paths.contains(path)) {
        out.add(path);
        continue;
      }
      final matches = _bySegment[name] ?? const <String>[];
      if (matches.length == 1) {
        out.add(matches.single);
        continue;
      }
      if (matches.length > 1) {
        throw RepoNameException(name, ambiguous: true, candidates: matches);
      }
      final lower = name.toLowerCase();
      final near = [
        for (final p in paths)
          if (p.toLowerCase().contains(lower)) p.isEmpty ? '.' : p,
      ];
      throw RepoNameException(name, ambiguous: false, candidates: near);
    }
    return out;
  }
}

/// A repository name that is unknown or names more than one repository: a
/// usage error (exit 2).
class RepoNameException implements Exception {
  RepoNameException(
    this.name, {
    required this.ambiguous,
    required this.candidates,
  });

  final String name;
  final bool ambiguous;

  /// The repositories it could mean (ambiguous), or whose path contains it.
  final List<String> candidates;

  @override
  String toString() => ambiguous
      ? '`$name` names ${candidates.length} repositories: '
            '${candidates.join(', ')}; give the path'
      : candidates.isEmpty
      ? 'no repository is named `$name`'
      : 'no repository is named `$name`; did you mean '
            '${candidates.join(', ')}?';
}

/// The repositories each repository-list option of a run names
/// (`--skip core,basics`), resolved by [RepoNames].
class RepoSelections {
  RepoSelections(this._byOption);

  /// Reads every [optionNames] option from [args] (`--skip a,b`,
  /// `--skip=a`, repeatable) and resolves its names. Throws
  /// [RepoNameException].
  factory RepoSelections.parse(
    List<String> args,
    Iterable<String> optionNames,
    RepoNames names,
  ) {
    final wanted = optionNames.toSet();
    final by = <String, Set<String>>{};
    for (final (name, value) in _optionValues(args, wanted)) {
      by.putIfAbsent(name, () => {}).addAll(names.resolve(value));
    }
    return RepoSelections(by);
  }

  final Map<String, Set<String>> _byOption;

  /// Whether [option] names the repository at [path]: an option acts only
  /// on the repositories it names.
  bool applies(String option, String path) =>
      _byOption[option]?.contains(path) ?? false;

  /// The repositories [option] names.
  Set<String> named(String option) => _byOption[option] ?? const {};
}

/// Every `--name value` / `--name=value` of [args] whose name is in
/// [names], in order.
Iterable<(String, String)> _optionValues(
  List<String> args,
  Set<String> names,
) sync* {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final eq = arg.indexOf('=');
    final name = arg.substring(2, eq < 0 ? null : eq);
    if (!names.contains(name)) continue;
    if (eq >= 0) {
      yield (name, arg.substring(eq + 1));
    } else if (i + 1 < args.length) {
      yield (name, args[++i]);
    }
  }
}

/// Builds the command line to repeat: the run's arguments plus one option.
class RepeatCommand {
  /// [tool] and [command] as typed (`buildkit`, `:ws-push`); [given] the
  /// run's other arguments as typed. A chosen repository-list option merges
  /// with the same option already given (`--skip a` + `b` -> `--skip a,b`).
  const RepeatCommand({
    required this.tool,
    required this.command,
    this.given = const [],
  });

  final String tool;
  final String command;
  final List<String> given;

  /// The command line with [option] for [repoName] (a repository-list
  /// option), [value] (a value option) or alone (a run option).
  String withOption(MessageOption option, {String? repoName, String? value}) {
    final args = <String>[];
    String? merged;
    for (var i = 0; i < given.length; i++) {
      final arg = given[i];
      final isThis = arg == option.flag || arg.startsWith('${option.flag}=');
      if (!isThis) {
        args.add(arg);
        continue;
      }
      if (!option.repoList) {
        continue; // given again below
      }
      final existing = arg.contains('=')
          ? arg.substring(arg.indexOf('=') + 1)
          : (i + 1 < given.length ? given[++i] : '');
      merged = merged == null ? existing : '$merged,$existing';
    }
    if (option.repoList && repoName != null) {
      final list = <String>[
        ...?merged?.split(','),
      ].where((s) => s.isNotEmpty).toList();
      if (!list.contains(repoName)) list.add(repoName);
      args.addAll([option.flag, list.join(',')]);
    } else if (option.valueName != null) {
      args.addAll([option.flag, value ?? '<${option.valueName}>']);
    } else {
      args.add(option.flag);
    }
    return [tool, command, ...args].map(shellQuote).join(' ');
  }
}

/// [arg] as a POSIX shell reads it back: plain when it holds only safe
/// characters, else in double quotes with `"`, `\`, `$` and `` ` `` escaped.
String shellQuote(String arg) {
  if (arg.isNotEmpty && RegExp(r'^[A-Za-z0-9_./:@%+=,<>-]+$').hasMatch(arg)) {
    return arg;
  }
  return '"${arg.replaceAllMapped(RegExp(r'["\\$`]'), (m) => '\\${m[0]}')}"';
}

/// The one report a run ends with (see the library comment).
class RunReport {
  RunReport({
    required this.tool,
    required this.command,
    required this.root,
    required this.host,
    required this.started,
    this.given = const [],
    required this.names,
    this.helpCommand,
  });

  /// `buildkit`, and the command as typed (`:ws-push`).
  final String tool;
  final String command;

  /// The folder holding `repos.yaml`, and the host's fleet id.
  final String root;
  final String host;
  final DateTime started;

  /// The run's arguments other than the command, as typed.
  final List<String> given;

  /// The names of the run's repositories.
  final RepoNames names;

  /// How the footer names the help (`buildkit help <topic>`); default
  /// `<tool> help <topic>`.
  final String? helpCommand;

  /// Every repository looked at (by path), for the summary and `-v`.
  final Set<String> lookedAt = {};

  final List<ReportMessage> messages = [];
  final List<ReportDone> done = [];

  /// Adds [message] (raise it with [MessageDefinition.raise]).
  void add(ReportMessage message) => messages.add(message);

  /// Records what changed in [repository].
  void changed(ReportDone entry) => done.add(entry);

  RepeatCommand get _repeat =>
      RepeatCommand(tool: tool, command: command, given: given);

  /// The exit code the run ends with: the highest of its messages'.
  int get exitCode => messages.fold(
    ReportExitCode.ok,
    (code, m) => m.definition.effectiveExitCode > code
        ? m.definition.effectiveExitCode
        : code,
  );

  Iterable<ReportMessage> _at(MessageLevel level) =>
      messages.where((m) => m.level == level);

  /// The command line that repeats the run with [option] for [message].
  String commandLine(ReportMessage message, MessageOption option) =>
      _repeat.withOption(
        option,
        repoName: option.repoList && message.repository != null
            ? names.nameOf(message.repository!)
            : null,
        value: message.values[option.name],
      );

  String _optionToken(ReportMessage message, MessageOption option) {
    if (option.valueName != null) {
      return '${option.flag} ${message.values[option.name] ?? '<${option.valueName}>'}';
    }
    if (option.repoList && message.repository != null) {
      return '${option.flag} ${names.nameOf(message.repository!)}';
    }
    return option.flag;
  }

  String _repoLabel(String? path) =>
      path == null ? '' : (path.isEmpty ? '.' : path);

  /// The report as text; [verbose] lists the repositories with nothing to
  /// do and every changed file (else the first 20 per repository); [width]
  /// aligns the codes on the right.
  String renderText({bool verbose = false, int width = 100}) {
    final b = StringBuffer();
    final changedPaths = {for (final d in done) d.repository};
    final unchanged = (lookedAt.toList()..sort())
        .where((p) => !changedPaths.contains(p))
        .toList();
    final errors = _at(MessageLevel.error).toList();
    final warnings = _at(MessageLevel.warning).toList();
    final refusals = _at(MessageLevel.refusal).toList();
    final notes = _at(MessageLevel.note).toList();

    b
      ..writeln('$tool $command')
      ..writeln('  Root:     $root')
      ..writeln('  Host:     $host')
      ..writeln('  Started:  ${_stamp(started)}')
      ..writeln(
        '  Options:  ${given.isEmpty ? '(none)' : given.map(shellQuote).join(' ')}',
      )
      ..writeln()
      ..writeln(
        '${lookedAt.length} repositories looked at, ${done.length} changed, '
        '${errors.length} need${errors.length == 1 ? 's' : ''} you, '
        '${warnings.length} warning${warnings.length == 1 ? '' : 's'}: '
        'exit $exitCode',
      );

    void section(String title, List<ReportMessage> list) {
      if (list.isEmpty) return;
      b
        ..writeln()
        ..writeln(title);
      for (final m in list) {
        b
          ..writeln()
          ..write(_block(m, width));
      }
    }

    section('Refused', refusals);
    section('Needs you', errors);
    section('Warnings', warnings);
    section('Notes', notes);

    if (done.isNotEmpty || unchanged.isNotEmpty) {
      b
        ..writeln()
        ..writeln('Done');
      final pad = done.fold(
        0,
        (w, d) => _repoLabel(d.repository).length > w
            ? _repoLabel(d.repository).length
            : w,
      );
      for (final d in done) {
        b.writeln(
          '  ${_repoLabel(d.repository).padRight(pad)}  ${d.actions.join(', ')}',
        );
        final shown = verbose ? d.files : d.files.take(20);
        for (final f in shown) {
          b.writeln('      $f');
        }
        if (!verbose && d.files.length > 20) {
          b.writeln('      ... ${d.files.length - 20} more (-v lists them)');
        }
      }
      if (unchanged.isNotEmpty) {
        if (verbose) {
          b.writeln('  Nothing to do:');
          for (final p in unchanged) {
            b.writeln('    ${_repoLabel(p)}');
          }
        } else {
          b.writeln(
            '  ${unchanged.length} '
            '${unchanged.length == 1 ? 'repository' : 'repositories'} with '
            'nothing to do (-v lists them)',
          );
        }
      }
    }

    final help = helpCommand ?? '$tool help <topic>';
    b
      ..writeln()
      ..writeln('Exit $exitCode: ${ReportExitCode.meaning(exitCode)}.');
    if (refusals.isNotEmpty ||
        errors.isNotEmpty ||
        exitCode == ReportExitCode.decision) {
      b.writeln(
        'Repeat with one of the command lines above; `$help` explains each '
        'message.',
      );
    }
    return b.toString();
  }

  String _block(ReportMessage m, int width) {
    final b = StringBuffer();
    final head = StringBuffer('${m.definition.label}  ');
    if (m.repository != null) head.write(_repoLabel(m.repository));
    if (m.branch != null) head.write('  (${m.branch})');
    final code = '[${m.code}]';
    final gap = width - head.length - code.length;
    b.writeln('$head${' ' * (gap < 2 ? 2 : gap)}$code');
    for (final line in m.finding.trimRight().split('\n')) {
      b.writeln('  $line');
    }
    for (final e in m.evidence) {
      if (e.label == null) {
        for (final item in e.items) {
          b.writeln('    $item');
        }
      } else {
        final label = '${e.label} ';
        for (var i = 0; i < e.items.length; i++) {
          b.writeln(
            '  ${i == 0 ? label.padRight(10) : ' ' * label.padRight(10).length}${e.items[i]}',
          );
        }
      }
    }
    if (m.state != null) {
      for (final line in m.state!.trimRight().split('\n')) {
        b.writeln('  $line');
      }
    }
    final options = m.options;
    if (options.isNotEmpty) {
      final anyRepo = options.any((o) => o.repoList);
      b.writeln(
        anyRepo
            ? '  Options (each acts only on the repositories you name):'
            : '  Options:',
      );
      final tokens = [for (final o in options) _optionToken(m, o)];
      final pad = tokens.fold(0, (w, t) => t.length > w ? t.length : w);
      for (var i = 0; i < options.length; i++) {
        final lines =
            (m.explanations[options[i].name] ?? options[i].explanation)
                .trimRight()
                .split('\n');
        for (var j = 0; j < lines.length; j++) {
          b.writeln(
            '    ${(j == 0 ? tokens[i] : '').padRight(pad)} ${lines[j]}',
          );
        }
      }
      b.writeln('  Repeat with:  ${commandLine(m, options.first)}');
    }
    return b.toString();
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}';
  }

  /// The report as JSON: the header, the summary, every message with its
  /// code, level, repository, evidence and options
  /// (`{option, explanation, commandLine}`), and what was done.
  Map<String, Object?> toJson() {
    final changedPaths = {for (final d in done) d.repository};
    return {
      'command': '$tool $command',
      'root': root,
      'host': host,
      'started': started.toIso8601String(),
      'options': given,
      'exitCode': exitCode,
      'summary': {
        'repositories': lookedAt.length,
        'changed': done.length,
        'needsYou': _at(MessageLevel.error).length,
        'warnings': _at(MessageLevel.warning).length,
        'refused': _at(MessageLevel.refusal).length,
      },
      'messages': [
        for (final m in messages)
          {
            'code': m.code,
            'level': m.level.name,
            'repository': m.repository == null
                ? null
                : {
                    'name': names.nameOf(m.repository!),
                    'path': _repoLabel(m.repository),
                  },
            'branch': m.branch,
            'finding': m.finding,
            'evidence': {for (final e in m.evidence) e.kind: e.items},
            'state': m.state,
            'options': [
              for (final o in m.options)
                {
                  'option': _optionToken(m, o),
                  'explanation': m.explanations[o.name] ?? o.explanation,
                  'commandLine': commandLine(m, o),
                },
            ],
          },
      ],
      'done': [
        for (final d in done)
          {
            'repository': _repoLabel(d.repository),
            'actions': d.actions,
            'files': d.files,
          },
      ],
      'unchanged': [
        for (final p in (lookedAt.toList()..sort()))
          if (!changedPaths.contains(p)) _repoLabel(p),
      ],
    };
  }

  /// [toJson] as indented text.
  String renderJson() => const JsonEncoder.withIndent('  ').convert(toJson());
}
