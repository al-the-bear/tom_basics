/// the main isolate's writer of the sessions' trail files.
///
/// It follows the consolidated trails ([LlmTrails.records]) and keeps
/// one `live-trail.<session>.md` per session in the trail directory, through a
/// [TomBundleMedium] — whose writes are atomic by contract, a sibling temp
/// renamed over the file on disk — so a reader never sees half a file.
///
/// - **Coalesced.** A file is written at most once per [coalesce] while a run
///   streams, and at once when the run ends.
/// - **Continued.** A file found in the directory is read before the first
///   write and continued, so a restart keeps the earlier runs (the newest
///   five, as always).
/// - **Never in the way.** A write that fails is logged once per episode as
///   `ai.trail.write_failed` — the path and the error's type — and the trail
///   carries on in memory. Nothing here can affect a run.
/// - **Memory only for an encrypted document**. A run whose
///   `userPrompt` says it draws on an encrypted document reaches no file —
///   unless [keepOnDisk] was called for its session, which holds until the
///   writer is disposed and is never stored.
///
/// Closing a session's tab clears its in-memory trail and touches no file:
/// the writer keeps its own copy of each file's text.
///
/// **A quest session** writes into its quest folder instead, through
/// the medium [questTargetFor] gives for it: `live-trail.<session>.md` there,
/// and per finished run one entry in each of `history/<q>.<session>.prompts.md`
/// and `.answers.md`, in the VS Code extension's format
/// (`llmSummaryTrailPrepend`). The prompt entry is the user's instruction
/// and the answer entry the model's text — never the context —
/// and a run kept in memory reaches neither file.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import 'sessions.dart';
import 'live_trail.dart';
import 'summary_trail.dart';
import 'event.dart';

/// A folder the writer keeps files in: read and write a named text file.
///
/// A write must be atomic — a sibling written and renamed over the target —
/// so a reader never sees half a file. Reading a file that does not exist
/// throws.
abstract interface class LlmTrailMedium {
  Future<String> readString(String name);
  Future<void> writeString(String name, String text);
}

/// Records a write that failed: the operation, a path and the error's type.
/// Never content.
typedef LlmTrailLog =
    void Function(String operation, Map<String, Object?> fields);

/// Where a quest session writes: its quest folder, as an absolute path, and a
/// medium rooted at it.
class LlmQuestTarget {
  final String folder;
  final LlmTrailMedium medium;

  const LlmQuestTarget({required this.folder, required this.medium});
}

/// Writes the sessions' trail files.
class LlmTrailFileWriter {
  final LlmTrails trails;

  /// Where a failed write is recorded; null records nothing.
  final LlmTrailLog? log;

  /// How long a streaming run's changes wait before they are written: 250 ms
  ///, shorter only in a test.
  @visibleForTesting
  final Duration coalesce;

  /// A file's size bound, in UTF-8 bytes.
  final int maxBytes;

  LlmTrailMedium _medium;
  String _directory;
  String _reason;

  final Map<String, _SessionFile> _files = {};
  final Set<String> _persistEncrypted = {};
  final Map<String, String> _memoryOnlyRun = {};
  final Set<String> _failing = {};
  late final StreamSubscription<LlmTrailRecord> _subscription;
  Timer? _timer;
  bool _disposed = false;

  /// Writes into [medium], which is the directory [directory]; [reason] says
  /// which rule chose it.
  LlmTrailFileWriter({
    required this.trails,
    required LlmTrailMedium medium,
    required String directory,
    required String reason,
    this.log,
    this.coalesce = const Duration(milliseconds: 250),
    this.maxBytes = 1 << 20,
  }) : _medium = medium,
       _directory = directory,
       _reason = reason {
    _subscription = trails.records.listen(_onRecord);
  }

  /// The trail directory.
  String get directory => _directory;

  /// Which rule chose [directory], in the words a view shows.
  String get reason => _reason;

  /// The quest folder a session writes into, or null for a session that
  /// writes into the trail directory. Bound by the root, which knows the
  /// sessions; asked each time a file is first opened.
  LlmQuestTarget? Function(String sessionId)? questTargetFor;

  /// The path of [sessionId]'s trail file.
  String fileFor(String sessionId) => p.join(
    questTargetFor?.call(sessionId)?.folder ?? _directory,
    llmLiveTrailFileName(sessionId),
  );

  LlmTrailMedium _mediumFor(String sessionId) =>
      questTargetFor?.call(sessionId)?.medium ?? _medium;

  /// Whether [sessionId]'s latest run draws on an encrypted document and is
  /// therefore kept in memory only.
  bool isMemoryOnly(String sessionId) =>
      _memoryOnlyRun.containsKey(sessionId) &&
      !_persistEncrypted.contains(sessionId);

  /// Moves the trail files to [directory] for every write from now on. A
  /// file already in the new directory is continued.
  Future<void> retarget({
    required LlmTrailMedium medium,
    required String directory,
    required String reason,
  }) async {
    await flush();
    _medium = medium;
    _directory = directory;
    _reason = reason;
    _files.clear();
    _failing.clear();
  }

  /// The memory-only switch: [sessionId]'s runs are written even when they
  /// draw on an encrypted document, until the writer is disposed. The run
  /// the session is showing is written now.
  Future<void> keepOnDisk(String sessionId) async {
    if (!_persistEncrypted.add(sessionId)) return;
    final runId = _memoryOnlyRun.remove(sessionId);
    if (runId == null) return;
    final file = _fileOf(sessionId);
    var ended = false;
    for (final record in trails.recordsOf(sessionId)) {
      if (record.runId != runId) continue;
      file.apply(record);
      if (record.event is LlmRunEnded) ended = true;
    }
    await _write(sessionId);
    if (ended) await _writeHistory(sessionId, runId);
  }

  void _onRecord(LlmTrailRecord record) {
    if (_disposed) return;
    final session = record.sessionId;
    final runId = record.runId;
    if (record.event case LlmUserPrompt(
      :final drawsOnEncryptedDocument,
    ) when runId != null) {
      if (drawsOnEncryptedDocument) {
        _memoryOnlyRun[session] = runId;
      } else {
        _memoryOnlyRun.remove(session);
      }
    }
    // The run's start precedes its prompt, so it is held back until the
    // prompt says whether the run may be written.
    final file = _fileOf(session);
    if (record.event is LlmRunStarted) {
      file.held = record;
      return;
    }
    if (runId != null &&
        _memoryOnlyRun[session] == runId &&
        !_persistEncrypted.contains(session)) {
      file.held = null;
      return;
    }
    final held = file.held;
    if (held != null && held.runId == runId) {
      file.held = null;
      file.apply(held);
    }
    if (!file.apply(record)) return;
    if (record.event is LlmRunEnded) {
      unawaited(_write(session));
      if (runId != null) unawaited(_writeHistory(session, runId));
    } else {
      _timer ??= Timer(coalesce, () {
        _timer = null;
        unawaited(flush());
      });
    }
  }

  _SessionFile _fileOf(String sessionId) => _files.putIfAbsent(
    sessionId,
    () => _SessionFile(
      _mediumFor(sessionId).readString(llmLiveTrailFileName(sessionId)),
      maxBytes,
    ),
  );

  final Map<String, Future<void>> _historyQueues = {};

  /// Adds run [runId]'s prompt and answer to a quest session's history pair
  ///. Nothing for an internal session.
  Future<void> _writeHistory(String sessionId, String runId) {
    final target = questTargetFor?.call(sessionId);
    if (target == null) return Future.value();
    final records = [
      for (final r in trails.recordsOf(sessionId))
        if (r.runId == runId) r,
    ];
    final prompt = records
        .map((r) => r.event)
        .whereType<LlmUserPrompt>()
        .firstOrNull;
    if (prompt == null) return Future.value();
    final at = records.first.at;
    final answer = StringBuffer();
    String? failure;
    LlmRunOutcome? outcome;
    for (final record in records) {
      switch (record.event) {
        case LlmTextDelta(:final text):
          answer.write(text);
        case LlmRunError(:final message):
          failure = message;
        case LlmRunEnded(outcome: final o):
          outcome = o;
        default:
          break;
      }
    }
    final ending = switch (outcome) {
      LlmRunOutcome.completed || null => null,
      LlmRunOutcome.cancelled => 'The run was cancelled.',
      LlmRunOutcome.timeout => 'The run stopped: the model went silent.',
      LlmRunOutcome.failed => failure ?? 'The run failed.',
    };
    final body = [
      if (answer.toString().trim().isNotEmpty) answer.toString().trim(),
      ?ending,
    ].join('\n\n');
    final quest = p.basename(target.folder);
    final medium = target.medium;
    String nameOf(LlmSummaryTrailKind kind) => p.posix.join(
      'history',
      llmSummaryTrailFileName(quest, sessionId, kind),
    );
    final previous = _historyQueues[sessionId] ?? Future.value();
    return _historyQueues[sessionId] = previous.then((_) async {
      try {
        for (final (kind, text) in [
          (LlmSummaryTrailKind.prompt, prompt.instruction),
          (LlmSummaryTrailKind.answer, body),
        ]) {
          final name = nameOf(kind);
          String existing;
          try {
            existing = await medium.readString(name);
          } on Object {
            existing = '';
          }
          await medium.writeString(
            name,
            llmSummaryTrailPrepend(
              existing,
              kind: kind,
              requestId: runId,
              at: at,
              body: text,
            ),
          );
        }
        _failing.remove('$sessionId/history');
      } on Object catch (error) {
        if (_failing.add('$sessionId/history')) {
          log?.call('ai.trail.write_failed', {
            'path': p.join(target.folder, 'history'),
            'error': error.runtimeType.toString(),
          });
        }
      }
    });
  }

  /// Writes every file with changes now, and waits for the history entries
  /// of runs that have ended.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    await Future.wait([
      for (final entry in _files.entries)
        if (entry.value.dirty) _write(entry.key),
    ]);
    await Future.wait(_historyQueues.values);
  }

  /// Writes [sessionId]'s file, after any write of it still in flight.
  Future<void> _write(String sessionId) {
    final file = _files[sessionId];
    if (file == null) return Future.value();
    final medium = _mediumFor(sessionId);
    final path = fileFor(sessionId);
    return file.queue = file.queue.then((_) async {
      final text = await file.text;
      if (text == null) return;
      try {
        await medium.writeString(llmLiveTrailFileName(sessionId), text);
        _failing.remove(sessionId);
      } on Object catch (error) {
        // Once per episode: a directory that cannot be written refuses every
        // write, and a line per write would bury everything else in the log.
        if (_failing.add(sessionId)) {
          log?.call('ai.trail.write_failed', {
            'path': path,
            'error': error.runtimeType.toString(),
          });
        }
      }
    });
  }

  /// Writes what is pending and stops following the trails.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // Not awaited: a cancel takes effect when it is called.
    unawaited(_subscription.cancel());
    await flush();
  }
}

/// One session's file: the text as it was found, with the records applied
/// since. Records that arrive while the found file is still being read wait
/// for it, in order.
class _SessionFile {
  _SessionFile(Future<String> existing, int maxBytes) {
    _loaded = existing.then((text) => text, onError: (_) => '').then((text) {
      _session = LlmLiveTrailSession(existing: text, maxBytes: maxBytes);
      for (final record in _pending) {
        if (_session!.apply(record)) dirty = true;
      }
      _pending.clear();
    });
  }

  late final Future<void> _loaded;
  LlmLiveTrailSession? _session;
  final List<LlmTrailRecord> _pending = [];

  /// A run's start, held until its prompt says whether it may be written.
  LlmTrailRecord? held;

  /// Whether the text has changes not yet written.
  bool dirty = false;

  /// The writes of this file, one after another.
  Future<void> queue = Future.value();

  /// Applies [record]; answers whether anything will need writing.
  bool apply(LlmTrailRecord record) {
    final session = _session;
    if (session == null) {
      _pending.add(record);
      dirty = true;
      return true;
    }
    final changed = session.apply(record);
    if (changed) dirty = true;
    return changed;
  }

  /// The text to write, once the found file is read; null when nothing
  /// changed since the last write.
  Future<String?> get text async {
    await _loaded;
    if (!dirty) return null;
    dirty = false;
    return _session!.text;
  }
}
