import 'dart:convert';

import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

/// The report and message framework: a command defines its messages once
/// and gets the text report, the JSON, the command line to repeat for every
/// option and one help topic per code from them.
///
/// Test IDs: BB-REP-1..9.

const _conflict = MessageDefinition(
  code: 'ws-conflict',
  level: MessageLevel.error,
  label: 'CONFLICT',
  summary: 'The merge of origin/<branch> conflicts.',
  description:
      'Your local commits and the incoming ones change the same lines. '
      'Nothing is pushed for the repository until you choose.',
  options: [
    MessageOption(
      'merge-branch',
      'Push your commits to ws-push/<host>/<stamp> and leave the branch.\n'
          'Your work is on the remote at once; merge the branch later.',
    ),
    MessageOption(
      'ours',
      'Merge again; where both sides changed a line, yours wins.',
    ),
    MessageOption('skip', 'Leave the repository out of this run (exit 1).'),
  ],
);

const _active = MessageDefinition(
  code: 'ws-active',
  level: MessageLevel.refusal,
  label: 'ACTIVE',
  summary: 'A Tom AI window on this host is sending a prompt.',
  description: 'What those sessions write would be committed half done.',
  options: [
    MessageOption(
      'ignore-active',
      'Run anyway; what they wrote so far is committed with the rest.',
      repoList: false,
    ),
  ],
);

const _secret = MessageDefinition(
  code: 'ws-secret',
  level: MessageLevel.refusal,
  label: 'SECRET',
  summary: 'A file that would be committed matches the secret list.',
  description: 'Committed secrets stay in the history.',
  options: [
    MessageOption(
      'skip-file',
      'Leave it uncommitted (the run then exits 1).',
      repoList: false,
      valueName: 'glob',
    ),
  ],
);

const _binaries = MessageDefinition(
  code: 'ws-binaries',
  level: MessageLevel.warning,
  label: 'BINARIES',
  summary: 'tom_binaries has uncommitted binaries.',
  description: 'They are left for the next build.',
);

const _note = MessageDefinition(
  code: 'ws-note',
  level: MessageLevel.note,
  label: 'NOTE',
  summary: 'Something to know.',
  description: 'Information only.',
);

const _dirty = MessageDefinition(
  code: 'skill-dirty',
  level: MessageLevel.error,
  label: 'DIRTY',
  summary: 'Uncommitted work needs a decision.',
  description: 'The skill holds it until you decide.',
  exitCode: ReportExitCode.decision,
);

const _paths = [
  '',
  'tom_ai/core',
  'tom_ai/basics',
  'tom_ai/xternal/tom_dcli',
  'apps/core',
  '_ai',
];

RunReport _report({List<String> given = const []}) => RunReport(
  tool: 'buildkit',
  command: ':ws-push',
  root: '/fleet/al_the_bear',
  host: 'mbp',
  started: DateTime(2026, 11, 24, 16, 2),
  given: given,
  names: RepoNames(_paths),
);

ReportMessage _conflictIn(String repo) => _conflict.raise(
  repository: repo,
  branch: 'main',
  finding: 'Your 2 local commits and 3 incoming commits change the same lines:',
  evidence: const [
    ReportEvidence('files', [
      'lib/src/config.dart        both changed',
      'CHANGELOG.md               both changed',
    ]),
    ReportEvidence('commits', [
      'a1b2c3d ws-push on mbp at 2026-11-24T16:02',
      '9f8e7d6 Config: the retry limit',
    ], label: 'Local:'),
  ],
  state:
      'Nothing was pushed for this repository; your commits are safe on this '
      'machine.',
  explanations: const {
    'merge-branch':
        'Push your commits to ws-push/mbp/261124-1602 and leave main as it is.\n'
        'Your work is on the remote at once; merge the branch later.',
  },
);

void main() {
  test('BB-REP-1: a message block: label, repository, branch, code; the '
      'finding, evidence, state, every option with its explanation, the '
      'command line to repeat [2026-11-24]', () {
    final report = _report(given: ['-m', 'Evening state'])
      ..lookedAt.addAll(_paths)
      ..add(_conflictIn('tom_ai/basics'));
    final text = report.renderText(width: 80);
    final lines = text.split('\n');
    final head = lines.firstWhere((l) => l.startsWith('CONFLICT'));
    expect(head, startsWith('CONFLICT  tom_ai/basics  (main)'));
    expect(head, endsWith('[ws-conflict]'));
    expect(head.length, 80);
    expect(
      text,
      contains(
        '  Your 2 local commits and 3 incoming commits change the same lines:\n'
        '    lib/src/config.dart        both changed\n'
        '    CHANGELOG.md               both changed\n'
        '  Local:    a1b2c3d ws-push on mbp at 2026-11-24T16:02\n'
        '            9f8e7d6 Config: the retry limit\n'
        '  Nothing was pushed for this repository; your commits are safe on this machine.\n'
        '  Options (each acts only on the repositories you name):\n'
        '    --merge-branch basics Push your commits to ws-push/mbp/261124-1602 and leave main as it is.\n'
        '                          Your work is on the remote at once; merge the branch later.\n'
        '    --ours basics         Merge again; where both sides changed a line, yours wins.\n'
        '    --skip basics         Leave the repository out of this run (exit 1).\n'
        '  Repeat with:  buildkit :ws-push -m "Evening state" --merge-branch basics\n',
      ),
    );
  });

  test('BB-REP-2: the layout: header, summary with the exit code, Refused, '
      'Needs you, Warnings, Notes, Done, footer [2026-11-24]', () {
    final report = _report(given: ['-m', 'x'])
      ..lookedAt.addAll(_paths)
      ..add(
        _binaries.raise(
          repository: 'tom_ai/xternal/tom_dcli',
          finding: '3 binaries on darwin-arm64, newest 16:00.',
        ),
      )
      ..add(_conflictIn('tom_ai/core'))
      ..add(_note.raise(finding: 'Just so you know.'))
      ..changed(
        const ReportDone(
          '_ai',
          ['committed 2 files', 'pushed'],
          files: ['quests/a.md', 'quests/b.md'],
        ),
      );
    final text = report.renderText();
    expect(
      text,
      startsWith(
        'buildkit :ws-push\n'
        '  Root:     /fleet/al_the_bear\n'
        '  Host:     mbp\n'
        '  Started:  2026-11-24T16:02\n'
        '  Options:  -m x\n'
        '\n'
        '6 repositories looked at, 1 changed, 1 needs you, 1 warning: exit 1\n',
      ),
    );
    final order = [
      for (final s in [
        '\nNeeds you\n',
        '\nWarnings\n',
        '\nNotes\n',
        '\nDone\n',
      ])
        text.indexOf(s),
    ];
    expect(order.every((i) => i >= 0), isTrue, reason: text);
    expect(order, orderedEquals([...order]..sort()));
    expect(text, isNot(contains('\nRefused\n')));
    expect(
      text,
      contains('  _ai  committed 2 files, pushed\n      quests/a.md\n'),
    );
    expect(text, contains('5 repositories with nothing to do (-v lists them)'));
    expect(
      text,
      endsWith(
        'Exit 1: something needs you: see "Needs you".\n'
        'Repeat with one of the command lines above; `buildkit help <topic>` '
        'explains each message.\n',
      ),
    );
    final refused = _report()
      ..add(_active.raise(finding: 'Window build_tom is sending.'));
    final rt = refused.renderText();
    expect(rt, contains('\nRefused\n'));
    expect(rt, contains('Options:\n    --ignore-active Run anyway'));
    expect(rt, contains('Repeat with:  buildkit :ws-push --ignore-active'));
    expect(rt, contains('Exit 2: refused: nothing was changed.'));
  });

  test('BB-REP-3: Done lists the first 20 files per repository; -v lists '
      'every file and the repositories with nothing to do [2026-11-24]', () {
    final files = [for (var i = 0; i < 25; i++) 'f$i.dart'];
    final report = _report()
      ..lookedAt.addAll(_paths)
      ..changed(
        ReportDone('tom_ai/core', const ['committed 25 files'], files: files),
      );
    final short = report.renderText();
    expect(short, contains('      f19.dart\n'));
    expect(short, isNot(contains('f20.dart')));
    expect(short, contains('... 5 more (-v lists them)'));
    final long = report.renderText(verbose: true);
    expect(long, contains('      f24.dart\n'));
    expect(long, contains('  Nothing to do:\n    .\n    _ai\n'));
    expect(long, endsWith('Exit 0: nothing needs you.\n'));
  });

  test('BB-REP-4: the command line to repeat: one repository, a second one '
      'merged into an option given, a value option, a run option, quoting '
      '[2026-11-24]', () {
    const repeat = RepeatCommand(
      tool: 'buildkit',
      command: ':ws-push',
      given: ['-m', r'Say "hi" for $5', '--skip', 'basics'],
    );
    const skip = MessageOption('skip', 'x');
    expect(
      repeat.withOption(skip, repoName: 'core'),
      r'buildkit :ws-push -m "Say \"hi\" for \$5" --skip basics,core',
    );
    expect(
      repeat.withOption(skip, repoName: 'basics'),
      r'buildkit :ws-push -m "Say \"hi\" for \$5" --skip basics',
    );
    expect(
      repeat.withOption(const MessageOption('ours', 'x'), repoName: 'core'),
      r'buildkit :ws-push -m "Say \"hi\" for \$5" --skip basics --ours core',
    );
    const withEquals = RepeatCommand(
      tool: 'buildkit',
      command: ':ws-push',
      given: ['--skip=a,b'],
    );
    expect(
      withEquals.withOption(skip, repoName: 'tom_ai/core'),
      'buildkit :ws-push --skip a,b,tom_ai/core',
    );
    expect(
      const RepeatCommand(
        tool: 'buildkit',
        command: ':ws-push',
      ).withOption(_secret.options.single, value: 'secrets/*.key'),
      'buildkit :ws-push --skip-file "secrets/*.key"',
    );
    expect(
      const RepeatCommand(
        tool: 'buildkit',
        command: ':ws-push',
        given: ['--ignore-active'],
      ).withOption(_active.options.single),
      'buildkit :ws-push --ignore-active',
    );
    final report = _report(given: ['--merge-branch', 'basics'])
      ..add(_conflictIn('tom_ai/core'));
    final m = report.messages.single;
    expect(
      report.commandLine(m, _conflict.options.first),
      'buildkit :ws-push --merge-branch basics,tom_ai/core',
      reason: 'core is ambiguous (apps/core): named by its path',
    );
  });

  test('BB-REP-5: repository names: the last segment when unique, else the '
      'path; unknown and ambiguous names are usage errors naming the '
      'candidates [2026-11-24]', () {
    final names = RepoNames(_paths);
    expect(names.nameOf('tom_ai/basics'), 'basics');
    expect(names.nameOf('tom_ai/core'), 'tom_ai/core');
    expect(names.nameOf('apps/core'), 'apps/core');
    expect(names.nameOf(''), '.');
    expect(names.nameOf('_ai'), '_ai');
    expect(names.resolve('basics,tom_dcli'), [
      'tom_ai/basics',
      'tom_ai/xternal/tom_dcli',
    ]);
    expect(names.resolve('tom_ai/core,.'), ['tom_ai/core', '']);
    expect(
      () => names.resolve('core'),
      throwsA(
        isA<RepoNameException>()
            .having((e) => e.ambiguous, 'ambiguous', isTrue)
            .having((e) => e.candidates, 'candidates', [
              'tom_ai/core',
              'apps/core',
            ])
            .having((e) => '$e', 'text', contains('give the path')),
      ),
    );
    expect(
      () => names.resolve('basic'),
      throwsA(
        isA<RepoNameException>()
            .having((e) => e.ambiguous, 'ambiguous', isFalse)
            .having((e) => e.candidates, 'candidates', ['tom_ai/basics'])
            .having((e) => '$e', 'text', contains('did you mean')),
      ),
    );
    expect(
      () => names.resolve('nothing'),
      throwsA(
        isA<RepoNameException>().having(
          (e) => '$e',
          'text',
          'no repository is named `nothing`',
        ),
      ),
    );
  });

  test('BB-REP-6: an option acts only on the repositories it names '
      '[2026-11-24]', () {
    final names = RepoNames(_paths);
    final sel = RepoSelections.parse(
      ['-m', 'x', '--skip', 'basics', '--ours=tom_ai/core', '--skip', '_ai'],
      ['skip', 'ours', 'theirs'],
      names,
    );
    expect(sel.named('skip'), {'tom_ai/basics', '_ai'});
    expect(sel.applies('ours', 'tom_ai/core'), isTrue);
    expect(sel.applies('ours', 'apps/core'), isFalse);
    expect(sel.applies('theirs', 'tom_ai/core'), isFalse);
    expect(
      () => RepoSelections.parse(['--skip', 'core'], ['skip'], names),
      throwsA(isA<RepoNameException>()),
    );
  });

  test('BB-REP-7: the exit code is the highest of the messages\': 0, 1 '
      'needs you, 2 refused, 3 a decision about uncommitted work '
      '[2026-11-24]', () {
    expect(_report().exitCode, 0);
    expect((_report()..add(_binaries.raise(finding: 'w'))).exitCode, 0);
    expect((_report()..add(_note.raise(finding: 'n'))).exitCode, 0);
    expect((_report()..add(_conflictIn('tom_ai/core'))).exitCode, 1);
    expect(
      (_report()
            ..add(_conflictIn('tom_ai/core'))
            ..add(_active.raise(finding: 'r')))
          .exitCode,
      2,
    );
    final decision = _report()
      ..add(_active.raise(finding: 'r'))
      ..add(_dirty.raise(repository: '_ai', finding: 'd'));
    expect(decision.exitCode, 3);
    expect(decision.renderText(), contains('Exit 3: a decision about'));
  });

  test('BB-REP-8: --json: the same report with every message\'s fields and '
      'options [2026-11-24]', () {
    final report = _report(given: ['-m', 'x'])
      ..lookedAt.addAll(_paths)
      ..add(_conflictIn('tom_ai/basics'))
      ..add(
        _secret.raise(
          repository: '_ai',
          finding: 'secrets/a.key matches *.key',
          values: const {'skip-file': 'secrets/a.key'},
        ),
      )
      ..changed(const ReportDone('_ai', ['pushed']));
    final json = jsonDecode(report.renderJson()) as Map<String, dynamic>;
    expect(json['command'], 'buildkit :ws-push');
    expect(json['root'], '/fleet/al_the_bear');
    expect(json['host'], 'mbp');
    expect(json['options'], ['-m', 'x']);
    expect(json['exitCode'], 2);
    expect(json['summary'], {
      'repositories': 6,
      'changed': 1,
      'needsYou': 1,
      'warnings': 0,
      'refused': 1,
    });
    final conflict = (json['messages'] as List).first as Map<String, dynamic>;
    expect(conflict['code'], 'ws-conflict');
    expect(conflict['level'], 'error');
    expect(conflict['repository'], {'name': 'basics', 'path': 'tom_ai/basics'});
    expect(conflict['branch'], 'main');
    expect((conflict['evidence'] as Map).keys, ['files', 'commits']);
    expect(conflict['state'], startsWith('Nothing was pushed'));
    final options = conflict['options'] as List;
    expect(options, hasLength(3));
    expect(options.first, {
      'option': '--merge-branch basics',
      'explanation':
          'Push your commits to ws-push/mbp/261124-1602 and leave main as it is.\n'
          'Your work is on the remote at once; merge the branch later.',
      'commandLine': 'buildkit :ws-push -m x --merge-branch basics',
    });
    final secret = (json['messages'] as List)[1] as Map<String, dynamic>;
    expect((secret['options'] as List).single, {
      'option': '--skip-file secrets/a.key',
      'explanation': 'Leave it uncommitted (the run then exits 1).',
      'commandLine': 'buildkit :ws-push -m x --skip-file secrets/a.key',
    });
    expect(json['done'], [
      {
        'repository': '_ai',
        'actions': ['pushed'],
        'files': <String>[],
      },
    ]);
    expect(json['unchanged'], [
      '.',
      'apps/core',
      'tom_ai/basics',
      'tom_ai/core',
      'tom_ai/xternal/tom_dcli',
    ]);
  });

  test('BB-REP-9: one help topic per message code, from the definitions; '
      '`<tool> help <code>` shows it [2026-11-24]', () async {
    final catalog = MessageCatalog([_conflict, _active, _secret, _binaries]);
    expect(catalog.helpTopics.map((t) => t.name), [
      'ws-conflict',
      'ws-active',
      'ws-secret',
      'ws-binaries',
    ]);
    expect(catalog['ws-secret'], same(_secret));
    expect(() => catalog['nope'], throwsArgumentError);
    expect(() => MessageCatalog([_conflict, _conflict]), throwsArgumentError);
    final topic = catalog.helpTopics.first;
    expect(topic.summary, _conflict.summary);
    expect(topic.content, contains('CONFLICT  [ws-conflict]'));
    expect(
      topic.content,
      contains('Listed under "Needs you"; the run ends with exit 1'),
    );
    expect(
      topic.content,
      contains(
        '  --merge-branch <repo>[,<repo>...]\n'
        '      Push your commits to ws-push/<host>/<stamp> and leave the branch.\n'
        '      Your work is on the remote at once; merge the branch later.\n',
      ),
    );
    expect(
      catalog['ws-secret'].helpTopic.content,
      contains('  --skip-file <glob>\n'),
    );
    expect(
      catalog['ws-active'].helpTopic.content,
      contains('  --ignore-active\n'),
    );

    final tool = ToolDefinition(
      name: 'reptool',
      description: 'Tool for the report tests',
      version: '1.0.0',
      mode: ToolMode.multiCommand,
      features: NavigationFeatures.minimal,
      commands: const [
        CommandDefinition(
          name: 'push',
          description: 'Pushes',
          requiresTraversal: false,
        ),
      ],
      helpTopics: catalog.helpTopics,
    );
    final out = StringBuffer();
    final result = await ToolRunner(
      tool: tool,
      output: out,
      executors: {},
    ).run(['help', 'ws-conflict']);
    expect(result.success, isTrue, reason: '$out');
    expect('$out', contains('[ws-conflict]'));
    expect('$out', contains('--merge-branch'));
  });
}
