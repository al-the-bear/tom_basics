/// How an app started from a launcher finds Node.
///
/// A desktop app started from a launcher gets `/usr/bin:/bin:/usr/sbin:/sbin`
/// as its `PATH`, so spawning the bare name `node` finds nothing on a machine
/// with five Nodes under nvm. The search here looks where Node actually is,
/// takes the first at or above the floor **by version rather than by
/// position** — the measured machine's `/usr/local/bin/node` is a v16 that
/// sits on `PATH` ahead of everything — and records every place it looked, so
/// an availability sentence can name them.
///
/// Against a fake host throughout: the search is a function of what the
/// machine holds, and a test that depended on the machine running it would
/// pass or fail with that machine's Node.
library;

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

/// A machine described as data: the files that exist, what each answers to
/// `--version`, `PATH`, and the home directory.
class _Machine implements LlmNodeHost {
  _Machine({
    this.path = const [],
    this.home = '/Users/alexis',
    this.windows = false,
    Map<String, String?> executables = const {},
    Map<String, List<String>> directories = const {},
  }) : _executables = executables,
       _directories = directories;

  final List<String> path;
  final String? home;
  final bool windows;

  /// Path → the `--version` answer, or null for a file that cannot run.
  final Map<String, String?> _executables;
  final Map<String, List<String>> _directories;

  /// Every executable asked for its version, in order.
  final List<String> ran = [];

  @override
  List<String> get pathEntries => path;

  @override
  String? get homeDirectory => home;

  @override
  bool get isWindows => windows;

  @override
  bool fileExists(String p) => _executables.containsKey(p);

  @override
  List<String> directoryEntries(String directory) =>
      _directories[directory] ?? const [];

  @override
  Future<String?> versionOf(String executable) async {
    ran.add(executable);
    return _executables[executable];
  }
}

const _nvm = '/Users/alexis/.nvm/versions/node';

/// The measured machine (mbp, 2026-10-05): a v16 in `/usr/local/bin`, nvm
/// holding v16 through v25, no Homebrew Node, and Finder's `PATH`.
_Machine _mbp({List<String>? path}) => _Machine(
  path: path ?? const ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
  executables: {
    '/usr/local/bin/node': 'v16.17.0',
    '$_nvm/v16.17.0/bin/node': 'v16.17.0',
    '$_nvm/v20.19.6/bin/node': 'v20.19.6',
    '$_nvm/v22.22.3/bin/node': 'v22.22.3',
    '$_nvm/v25.6.1/bin/node': 'v25.6.1',
  },
  directories: {
    _nvm: ['v16.17.0', 'v22.22.3', 'v25.6.1', 'v20.19.6'],
  },
);

void main() {
  group('the order of the search', () {
    test('PATH entries first, then nvm newest first, then '
        'Homebrew and /usr/local — and a place named twice is looked at '
        'once', () {
      final places = llmNodeSearchPlaces(
        _mbp(path: const ['/usr/local/bin', '/usr/bin']),
      );
      expect(
        [for (final (p, _) in places) p],
        [
          '/usr/local/bin/node',
          '/usr/bin/node',
          '$_nvm/v25.6.1/bin/node',
          '$_nvm/v22.22.3/bin/node',
          '$_nvm/v20.19.6/bin/node',
          '$_nvm/v16.17.0/bin/node',
          '/opt/homebrew/bin/node',
          '/usr/local/bin/node',
        ],
        reason: 'the order is stated, not inferred from which one won',
      );
      expect(
        {for (final (_, s) in places) s},
        {
          LlmNodeSource.path,
          LlmNodeSource.nvm,
          LlmNodeSource.homebrew,
          LlmNodeSource.usrLocal,
        },
      );
    });

    test('nvm versions sort numerically, not lexically', () {
      final machine = _Machine(
        directories: {
          _nvm: ['v9.11.2', 'v10.0.0', 'v22.2.0', 'v22.10.1', 'default'],
        },
      );
      final nvm = [
        for (final (p, s) in llmNodeSearchPlaces(machine))
          if (s == LlmNodeSource.nvm) p,
      ];
      expect(
        nvm,
        [
          '$_nvm/v22.10.1/bin/node',
          '$_nvm/v22.2.0/bin/node',
          '$_nvm/v10.0.0/bin/node',
          '$_nvm/v9.11.2/bin/node',
        ],
        reason:
            'v22.10 is newer than v22.2, and v10 than v9; "default" is '
            'not a version',
      );
    });

    test('Windows looks for node.exe and in Program Files', () {
      final places = llmNodeSearchPlaces(
        _Machine(windows: true, path: const [r'C:\Windows'], home: null),
      );
      expect(
        [for (final (p, _) in places) p],
        [r'C:\Windows\node.exe', r'C:\Program Files\nodejs\node.exe'],
      );
    });
  });

  group('the version floor', () {
    test('on the measured machine, the v16 on PATH is passed over '
        'by its version and nvm\'s newest is taken', () async {
      final machine = _mbp(path: const ['/usr/local/bin', '/usr/bin']);
      final found = await llmDiscoverNode(host: machine);
      expect(found.found, isTrue);
      expect(
        found.executable,
        '$_nvm/v25.6.1/bin/node',
        reason: 'THE POINT: skipped by version, not by position',
      );
      expect(found.version, 'v25.6.1');
      expect(machine.ran, [
        '/usr/local/bin/node',
        '$_nvm/v25.6.1/bin/node',
      ], reason: 'the search stops at the first acceptable Node');
      expect(found.looked.map((c) => c.outcome), [
        LlmNodeLookOutcome.tooOld,
        LlmNodeLookOutcome.absent,
        LlmNodeLookOutcome.accepted,
      ]);
    });

    test('from Finder\'s PATH the same machine finds nvm\'s Node, '
        'and the report says what PATH held', () async {
      final found = await llmDiscoverNode(host: _mbp());
      expect(found.executable, '$_nvm/v25.6.1/bin/node');
      expect(found.report, '"$_nvm/v25.6.1/bin/node" is v25.6.1');
      expect(
        found.looked.where((c) => c.source == LlmNodeSource.path).length,
        4,
        reason: 'every PATH entry was looked at and recorded',
      );
    });

    test('a Node exactly at the floor is accepted; one below is '
        'not', () async {
      final at = await llmDiscoverNode(
        host: _Machine(path: const ['/x'], executables: {'/x/node': 'v20.0.0'}),
      );
      expect(at.executable, '/x/node');
      final below = await llmDiscoverNode(
        host: _Machine(path: const ['/x'], executables: {'/x/node': 'v19.9.9'}),
      );
      expect(below.found, isFalse);
      expect(below.looked.first.outcome, LlmNodeLookOutcome.tooOld);
      expect(
        below.looked.length,
        greaterThan(1),
        reason: 'the search goes on past an old Node',
      );
    });

    test(
      'a version the search cannot read passes, as the probe\'s '
      'rule says — the floor catches a known-too-old Node, not a wrapper',
      () async {
        final found = await llmDiscoverNode(
          host: _Machine(
            path: const ['/x'],
            executables: {'/x/node': 'Dart SDK version: 3.10.8 (stable)'},
          ),
        );
        expect(found.executable, '/x/node');
        expect(found.version, 'Dart SDK version: 3.10.8 (stable)');
        expect(found.report, contains('is Dart SDK version'));
      },
    );

    test('a file that does not answer --version is not runnable, '
        'and the search goes on past it', () async {
      final found = await llmDiscoverNode(
        host: _Machine(
          path: const ['/broken', '/good'],
          executables: {'/broken/node': null, '/good/node': 'v22.22.3'},
        ),
      );
      expect(found.executable, '/good/node');
      expect(found.looked.first.outcome, LlmNodeLookOutcome.notRunnable);
    });
  });

  group('the found-nowhere report', () {
    test('names the old Node by version, that nvm holds nothing, '
        'and which PATH was searched', () async {
      final found = await llmDiscoverNode(
        host: _Machine(
          path: const ['/usr/bin', '/bin', '/usr/sbin', '/sbin'],
          executables: {'/usr/local/bin/node': 'v16.17.0'},
        ),
      );
      expect(found.found, isFalse);
      expect(found.executable, isNull);
      expect(
        found.report,
        '"/usr/local/bin/node" is v16.17.0, below 20; '
        'no node on PATH (/usr/bin:/bin:/usr/sbin:/sbin); '
        'nothing under ~/.nvm/versions/node; '
        'no /opt/homebrew/bin/node',
      );
      expect(found.looked.length, 7, reason: 'every place is recorded');
    });

    test('a machine with no Node anywhere says so for every '
        'place, with an empty PATH named as such', () async {
      final found = await llmDiscoverNode(host: _Machine());
      expect(
        found.report,
        'PATH is empty; nothing under ~/.nvm/versions/node; '
        'no /opt/homebrew/bin/node or /usr/local/bin/node',
      );
    });

    test('a machine with no home directory skips nvm rather than '
        'guessing a home', () async {
      final found = await llmDiscoverNode(
        host: _Machine(home: null, path: const ['/usr/bin']),
      );
      expect(found.report, isNot(contains('nvm')));
      expect(
        found.looked.map((c) => c.source),
        isNot(contains(LlmNodeSource.nvm)),
      );
    });
  });

  group('the setting replaces the search', () {
    test('with ai.nodePath set, only that executable is looked '
        'at, even when discovery would have found a newer one', () async {
      final machine = _mbp();
      final found = await llmDiscoverNode(
        host: machine,
        nodePath: '$_nvm/v22.22.3/bin/node',
      );
      expect(found.executable, '$_nvm/v22.22.3/bin/node');
      expect(found.version, 'v22.22.3');
      expect(found.setting, '$_nvm/v22.22.3/bin/node');
      expect(machine.ran, ['$_nvm/v22.22.3/bin/node']);
      expect(found.looked.single.source, LlmNodeSource.setting);
    });

    test('a setting naming an old Node is reported as such, '
        'never quietly passed over for a discovered one', () async {
      final machine = _mbp();
      final found = await llmDiscoverNode(
        host: machine,
        nodePath: '/usr/local/bin/node',
      );
      expect(
        found.found,
        isFalse,
        reason: 'THE POINT: the setting is a decision, not a suggestion',
      );
      expect(
        found.report,
        '"/usr/local/bin/node" is v16.17.0, below 20 '
        '(the Node.js path setting)',
      );
      expect(machine.ran, ['/usr/local/bin/node']);
    });

    test('a setting naming a file that does not exist says so, '
        'naming the setting', () async {
      final found = await llmDiscoverNode(
        host: _mbp(),
        nodePath: '/nowhere/node',
      );
      expect(found.found, isFalse);
      expect(
        found.report,
        '"/nowhere/node" does not exist (the Node.js path setting)',
      );
    });

    test('an explicit resolution vouches for its path and '
        'reports it as given', () async {
      final found = await llmNodeAt('/x/node')();
      expect(found.executable, '/x/node');
      expect(found.found, isTrue);
      expect(found.looked, isEmpty);
      expect(found.report, '"/x/node", as given');
    });
  });

  group('the version parser', () {
    test('the version parser reads Node\'s shape and nothing '
        'else', () {
      expect(llmParseNodeVersion('v22.22.3\n'), (
        version: 'v22.22.3',
        major: 22,
      ));
      expect(llmParseNodeVersion('20.1.0'), (version: 'v20.1.0', major: 20));
      expect(llmParseNodeVersion('Dart SDK version: 3.10.8'), isNull);
      expect(llmRequiredNodeMajorVersion, 20);
    });
  });
}
