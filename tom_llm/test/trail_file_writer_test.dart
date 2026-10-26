/// The trail file writer —
/// one file per session, coalesced writes, a file found continued, encrypted
/// runs kept in memory unless the session's switch is on, a failing directory
/// logged once per episode.
library;

import 'package:test/test.dart';
import 'package:tom_llm/tom_llm.dart';

/// A memory medium that counts writes and can be made to refuse them.
class _Medium implements LlmTrailMedium {
  final Map<String, String> files = {};
  final Map<String, int> writes = {};
  bool refuse = false;

  bool exists(String name) => files.containsKey(name);

  @override
  Future<String> readString(String name) async =>
      files[name] ?? (throw StateError('no file $name'));

  @override
  Future<void> writeString(String name, String text) async {
    if (refuse) throw StateError('refused');
    writes[name] = (writes[name] ?? 0) + 1;
    files[name] = text;
  }
}

/// The failure reports a writer made, as `(operation, fields)`.
typedef _Logged = ({String operation, Map<String, Object?> fields});

const _short = Duration(milliseconds: 30);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 80));

void _start(
  LlmTrails trails,
  String session,
  String run, {
  String instruction = 'Go.',
  bool encrypted = false,
}) {
  trails
    ..record(
      session,
      const LlmRunStarted(purpose: 'generate', providerId: 't'),
      runId: run,
    )
    ..record(
      session,
      LlmUserPrompt(
        instruction: instruction,
        drawsOnEncryptedDocument: encrypted,
      ),
      runId: run,
    );
}

void _end(LlmTrails trails, String session, String run) =>
    trails.record(session, const LlmRunCompleted(report: _report), runId: run);

LlmTrailFileWriter _writer(
  LlmTrails trails,
  _Medium medium, {
  List<_Logged>? log,
}) => LlmTrailFileWriter(
  trails: trails,
  medium: medium,
  directory: '/trails',
  reason: 'set in settings',
  log: log == null
      ? null
      : (operation, fields) => log.add((operation: operation, fields: fields)),
  coalesce: _short,
);

void main() {
  test('two concurrent sessions write their own files; a '
      'streaming run is coalesced and written at once when it ends', () async {
    final trails = LlmTrails();
    final medium = _Medium();
    final writer = _writer(trails, medium);
    addTearDown(writer.dispose);

    _start(trails, 'default', 'a', instruction: 'Summarize.');
    _start(trails, 'chat', 'b', instruction: 'Tidy.');
    for (var i = 0; i < 50; i++) {
      trails
        ..record('default', LlmTextDelta('d$i '), runId: 'a')
        ..record('chat', LlmTextDelta('c$i '), runId: 'b');
    }
    await _settle();
    expect(medium.writes['live-trail.default.md'], 1);
    expect(medium.writes['live-trail.chat.md'], 1);

    _end(trails, 'default', 'a');
    _end(trails, 'chat', 'b');
    await _settle();
    final defaultText = await medium.readString('live-trail.default.md');
    final chatText = await medium.readString('live-trail.chat.md');
    expect(defaultText, contains('> User: Summarize.'));
    expect(defaultText, contains('d49'));
    expect(defaultText, isNot(contains('c0')));
    expect(chatText, contains('> User: Tidy.'));
    expect(chatText, isNot(contains('d0')));
    expect(defaultText, contains('### ✅ DONE'));
    expect(writer.fileFor('chat'), '/trails/live-trail.chat.md');
  });

  test('a file found in the directory is continued, and '
      'closing a tab leaves the file alone', () async {
    final medium = _Medium();
    final earlier = LlmLiveTrailSession();
    for (final r in [
      const LlmRunStarted(purpose: 'generate', providerId: 't'),
      const LlmUserPrompt(instruction: 'From before.'),
      const LlmRunCompleted(report: _report),
    ]) {
      earlier.apply(
        LlmTrailRecord(
          sessionId: 'default',
          runId: 'old',
          seq: 1,
          at: DateTime.utc(2026, 10, 11),
          event: r,
        ),
      );
    }
    await medium.writeString('live-trail.default.md', earlier.text);

    final trails = LlmTrails();
    final writer = _writer(trails, medium);
    addTearDown(writer.dispose);
    _start(trails, 'default', 'n', instruction: 'Now.');
    _end(trails, 'default', 'n');
    await _settle();
    var text = await medium.readString('live-trail.default.md');
    expect(text, contains('> User: From before.'));
    expect(text, contains('> User: Now.'));

    trails.clear('default');
    _start(trails, 'default', 'm', instruction: 'Later.');
    _end(trails, 'default', 'm');
    await _settle();
    text = await medium.readString('live-trail.default.md');
    expect(text, contains('> User: From before.'));
    expect(text, contains('> User: Later.'));
  });

  test('a run that draws on an encrypted document reaches no '
      'file until the session is switched to keep it', () async {
    final trails = LlmTrails();
    final medium = _Medium();
    final writer = _writer(trails, medium);
    addTearDown(writer.dispose);

    _start(trails, 'chat', 'e', instruction: 'Secret plan.', encrypted: true);
    trails.record('chat', const LlmTextDelta('Vault answer.'), runId: 'e');
    _end(trails, 'chat', 'e');
    await _settle();
    expect(medium.exists('live-trail.chat.md'), isFalse);
    expect(writer.isMemoryOnly('chat'), isTrue);

    // A plaintext run in the same session is written; the session is not
    // memory-only any more.
    _start(trails, 'chat', 'p', instruction: 'Plain.');
    _end(trails, 'chat', 'p');
    await _settle();
    var text = await medium.readString('live-trail.chat.md');
    expect(text, contains('> User: Plain.'));
    expect(text, isNot(contains('Secret plan.')));
    expect(writer.isMemoryOnly('chat'), isFalse);

    // The switch: the run on screen is written, and later encrypted runs too.
    _start(
      trails,
      'chat',
      'e2',
      instruction: 'Second secret.',
      encrypted: true,
    );
    _end(trails, 'chat', 'e2');
    await _settle();
    expect(writer.isMemoryOnly('chat'), isTrue);
    await writer.keepOnDisk('chat');
    expect(writer.isMemoryOnly('chat'), isFalse);
    text = await medium.readString('live-trail.chat.md');
    expect(text, contains('> User: Second secret.'));
    expect(text, isNot(contains('Secret plan.')));
    _start(trails, 'chat', 'e3', instruction: 'Third secret.', encrypted: true);
    _end(trails, 'chat', 'e3');
    await _settle();
    expect(
      await medium.readString('live-trail.chat.md'),
      contains('> User: Third secret.'),
    );
    // Never stored: a new writer starts with the switch off.
    expect(_writer(LlmTrails(), medium).isMemoryOnly('chat'), isFalse);
  });

  test('a refused write is logged once per episode, never '
      'reaches the run, and the next success ends the episode', () async {
    final trails = LlmTrails();
    final medium = _Medium()..refuse = true;
    final log = <_Logged>[];
    final writer = _writer(trails, medium, log: log);
    addTearDown(writer.dispose);

    for (final run in ['a', 'b', 'c']) {
      _start(trails, 'default', run);
      _end(trails, 'default', run);
    }
    await _settle();
    final failures = log.where((e) => e.operation == 'ai.trail.write_failed');
    expect(failures, hasLength(1));
    expect(failures.single.fields, {
      'path': '/trails/live-trail.default.md',
      'error': 'StateError',
    });

    medium.refuse = false;
    _start(trails, 'default', 'd');
    _end(trails, 'default', 'd');
    await _settle();
    expect(
      await medium.readString('live-trail.default.md'),
      contains('### ✅ DONE'),
    );
    medium.refuse = true;
    _start(trails, 'default', 'e');
    _end(trails, 'default', 'e');
    await _settle();
    expect(
      log.where((e) => e.operation == 'ai.trail.write_failed'),
      hasLength(2),
    );
  });

  test('retargeting writes to the new directory from then on ', () async {
    final trails = LlmTrails();
    final first = _Medium();
    final second = _Medium();
    final writer = _writer(trails, first);
    addTearDown(writer.dispose);
    _start(trails, 'default', 'a');
    _end(trails, 'default', 'a');
    await _settle();
    await writer.retarget(
      medium: second,
      directory: '/quest',
      reason: 'from the command line',
    );
    expect(writer.directory, '/quest');
    expect(writer.reason, 'from the command line');
    _start(trails, 'default', 'b', instruction: 'Moved.');
    _end(trails, 'default', 'b');
    await _settle();
    expect(
      await second.readString('live-trail.default.md'),
      contains('> User: Moved.'),
    );
    expect(
      await first.readString('live-trail.default.md'),
      isNot(contains('Moved.')),
    );
  });
}

const _report = LlmCallReport(
  providerId: 'fake',
  modelId: '',
  anchorHash: '',
  promptHash: '',
  tokensIn: 0,
  tokensOut: 0,
  retries: 0,
  wallClockMs: 0,
);
