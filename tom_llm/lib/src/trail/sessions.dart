/// Model sessions as the main isolate sees them — which session a request
/// runs in, the refusal when that session is busy, and the consolidated
/// trails of every session.
///
/// Pure Dart. The isolates that run sessions belong to a provider; what lives
/// here is what a user interface and a trail view read, so neither has to
/// name the provider that runs a session.
library;

import 'dart:async';

import 'event.dart';

/// The built-in session ordinary requests run in.
const llmDefaultSession = 'default';

/// The built-in session an agent run runs in.
const llmChatSession = 'chat';

/// The purpose of an agent run — a request that drives tools — which runs in
/// [llmChatSession]; every other purpose runs in [llmDefaultSession].
const llmAgentPurpose = 'agent';

/// The built-in session a request of [purpose] runs in: an agent run in
/// `chat`, everything else in `default`.
String llmSessionFor(String purpose) =>
    purpose == llmAgentPurpose ? llmChatSession : llmDefaultSession;

/// A request refused because its session already has a run. Never
/// queued: a queued run would start at a moment nobody chose, against a
/// document that may have changed.
class LlmSessionBusyException implements Exception {
  /// The session that is busy.
  final String sessionId;

  const LlmSessionBusyException(this.sessionId);

  /// The notice the user is shown.
  String get message => 'The $sessionId AI session is busy.';

  @override
  String toString() => 'LlmSessionBusyException($sessionId)';
}

/// The trails of every session, consolidated in the main isolate.
///
/// Each session keeps its records of its newest `maxRuns` runs (twenty by
/// default); an older run is dropped whole, and the session events from
/// before it with it. The trail view reads this, and the trail files are fed
/// from [records].
class LlmTrails {
  /// How many runs a session keeps in memory.
  final int _maxRuns;

  final DateTime Function() _clock;
  final Map<String, List<LlmTrailRecord>> _bySession = {};
  final Map<String, int> _seq = {};
  final Set<String> _running = {};
  final StreamController<LlmTrailRecord> _records =
      StreamController<LlmTrailRecord>.broadcast(sync: true);
  final StreamController<String> _changes = StreamController<String>.broadcast(
    sync: true,
  );

  LlmTrails({int maxRuns = 20, DateTime Function()? clock})
    : _maxRuns = maxRuns,
      _clock = clock ?? DateTime.now;

  /// Every record as it is made, in order.
  Stream<LlmTrailRecord> get records => _records.stream;

  /// The id of a session whose trail or running state just changed.
  Stream<String> get changes => _changes.stream;

  /// The sessions that hold a record, in the order they first did.
  List<String> get sessions => List.unmodifiable(_bySession.keys);

  /// [sessionId]'s records, oldest first.
  List<LlmTrailRecord> recordsOf(String sessionId) =>
      List.unmodifiable(_bySession[sessionId] ?? const []);

  /// Whether [sessionId] has a run in progress.
  bool isRunning(String sessionId) => _running.contains(sessionId);

  /// Records [event] in [sessionId], in the run [runId] (absent for a session
  /// event), and returns the record.
  LlmTrailRecord record(String sessionId, LlmEvent event, {String? runId}) {
    final seq = (_seq[sessionId] ?? 0) + 1;
    _seq[sessionId] = seq;
    final record = LlmTrailRecord(
      sessionId: sessionId,
      runId: runId,
      seq: seq,
      at: _clock(),
      event: event,
    );
    final list = _bySession.putIfAbsent(sessionId, () => []);
    list.add(record);
    switch (event) {
      case LlmRunStarted():
        _running.add(sessionId);
      case LlmRunEnded():
        _running.remove(sessionId);
      case LlmSessionOpened() ||
          LlmSessionClosed() ||
          LlmUserPrompt() ||
          LlmSystemInit() ||
          LlmThinkingDelta() ||
          LlmTextDelta() ||
          LlmToolCall() ||
          LlmToolResult() ||
          LlmRetry() ||
          LlmUsage() ||
          LlmStall() ||
          LlmNotice() ||
          LlmRunError():
        break;
    }
    _bound(list);
    if (!_records.isClosed) {
      _records.add(record);
      _changes.add(sessionId);
    }
    return record;
  }

  /// Drops [sessionId]'s in-memory trail. Touches no file.
  void clear(String sessionId) {
    if (_bySession.remove(sessionId) != null && !_changes.isClosed) {
      _changes.add(sessionId);
    }
  }

  /// Keeps the newest `_maxRuns` runs of [list].
  void _bound(List<LlmTrailRecord> list) {
    final runs = <String>[];
    for (final record in list) {
      final runId = record.runId;
      if (runId != null && !runs.contains(runId)) runs.add(runId);
    }
    if (runs.length <= _maxRuns) return;
    final oldestKept = runs[runs.length - _maxRuns];
    final cut = list.indexWhere((r) => r.runId == oldestKept);
    list.removeRange(0, cut);
  }

  /// Closes the streams. A record made afterwards is kept and not announced.
  void dispose() {
    unawaited(_records.close());
    unawaited(_changes.close());
  }
}

/// Ids no user-created session may take: the two built-ins, and the name the
/// Tom VS Code extension writes its own trail under.
const Set<String> llmReservedSessionIds = {
  llmDefaultSession,
  llmChatSession,
  'anthropic',
};

final RegExp _sessionIdPattern = RegExp(r'^[a-z][a-z0-9-]{0,31}$');

/// Whether [id] is a well-formed session id.
bool llmIsSessionId(String id) => _sessionIdPattern.hasMatch(id);

/// One session as the app knows it: its id, its name in the trail
/// view, its kind and, for a quest session, the quest folder it is bound to.
class LlmSessionInfo {
  /// Stable and unique, `[a-z][a-z0-9-]{0,31}`; names the trail files.
  final String id;

  /// The label in the trail view.
  final String name;

  final LlmSessionKind kind;

  /// For a [LlmSessionKind.quest] session, the quest folder (absolute)
  /// it writes into; null for an internal session.
  final String? questFolder;

  const LlmSessionInfo({
    required this.id,
    required this.name,
    this.kind = LlmSessionKind.internal,
    this.questFolder,
  });

  /// Whether this is one of the two sessions every app has.
  bool get isBuiltIn => id == llmDefaultSession || id == llmChatSession;

  LlmSessionInfo renamed(String name) =>
      LlmSessionInfo(id: id, name: name, kind: kind, questFolder: questFolder);

  Map<String, Object?> encode() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    if (questFolder != null) 'folder': questFolder,
  };

  /// The stored form [value] read back, or null when it is not one.
  static LlmSessionInfo? decode(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final kind = value['kind'];
    final folder = value['folder'];
    if (id is! String || !llmIsSessionId(id)) return null;
    if (llmReservedSessionIds.contains(id)) return null;
    final sessionKind = LlmSessionKind.values
        .where((k) => k.name == kind)
        .firstOrNull;
    if (sessionKind == null) return null;
    if (sessionKind == LlmSessionKind.quest && folder is! String) {
      return null;
    }
    return LlmSessionInfo(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name : id,
      kind: sessionKind,
      questFolder: sessionKind == LlmSessionKind.quest
          ? folder as String
          : null,
    );
  }
}

/// A session operation that cannot be done, with the sentence the user is
/// shown.
class LlmSessionException implements Exception {
  final String message;

  const LlmSessionException(this.message);

  @override
  String toString() => 'LlmSessionException: $message';
}

/// The sessions of the app: the two built-ins and those the
/// user created, and which session a gesture runs in.
///
/// Pure Dart and main-isolate only. A root binds [persist] to keep the
/// user-created sessions in the device settings (`aiSessions`); [adopt] takes
/// what was read without writing it back.
class LlmSessionRegistry {
  LlmSessionRegistry();

  static const _builtIns = [
    LlmSessionInfo(id: llmDefaultSession, name: 'default'),
    LlmSessionInfo(id: llmChatSession, name: 'chat'),
  ];

  final List<LlmSessionInfo> _created = [];
  String _actionSession = llmDefaultSession;
  String _agentSession = llmChatSession;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Writes the user-created sessions, answering whether the write landed.
  /// Null keeps them for this process only.
  Future<bool> Function(List<Object?> sessions)? persist;

  /// A change to the sessions or to which one a gesture runs in.
  Stream<void> get changes => _changes.stream;

  /// Every session: the built-ins first, then the user's in creation order.
  List<LlmSessionInfo> get sessions =>
      List.unmodifiable([..._builtIns, ..._created]);

  /// The session [id], or null when there is none.
  LlmSessionInfo? byId(String id) =>
      sessions.where((s) => s.id == id).firstOrNull;

  /// The session ordinary requests run in.
  String get actionSession => _actionSession;

  /// The session an agent run runs in.
  String get agentSession => _agentSession;

  /// The session a request of [purpose] runs in.
  String sessionFor(String purpose) =>
      purpose == llmAgentPurpose ? _agentSession : _actionSession;

  /// Runs ordinary requests in [id] from now on.
  void useForActions(String id) {
    _require(id);
    if (_actionSession == id) return;
    _actionSession = id;
    _changed();
  }

  /// Runs the agent in [id] from now on.
  void useForAgent(String id) {
    _require(id);
    if (_agentSession == id) return;
    _agentSession = id;
    _changed();
  }

  /// Creates a session named [name]: an internal one, or with [questFolder]
  /// a quest session writing into that folder. Its id is made from the name
  /// and is unique.
  Future<LlmSessionInfo> create(String name, {String? questFolder}) {
    final label = name.trim();
    if (label.isEmpty) {
      throw const LlmSessionException('A session needs a name.');
    }
    if (questFolder != null &&
        _created.any((s) => s.questFolder == questFolder)) {
      throw const LlmSessionException(
        'A session is already bound to that quest folder.',
      );
    }
    final session = LlmSessionInfo(
      id: llmSessionIdFor(label, taken: {for (final s in sessions) s.id}),
      name: label,
      kind: questFolder == null
          ? LlmSessionKind.internal
          : LlmSessionKind.quest,
      questFolder: questFolder,
    );
    _created.add(session);
    _changed();
    return _write().then((_) => session);
  }

  /// Gives the user's session [id] the label [name]. Its id, and so its
  /// files, stay as they are.
  Future<void> rename(String id, String name) async {
    final label = name.trim();
    final i = _created.indexWhere((s) => s.id == id);
    if (i == -1 || label.isEmpty || _created[i].name == label) return;
    _created[i] = _created[i].renamed(label);
    _changed();
    await _write();
  }

  /// Removes the user's session [id]. A built-in session cannot be removed.
  /// A gesture that ran in it runs in the built-in session again.
  Future<void> remove(String id) async {
    final i = _created.indexWhere((s) => s.id == id);
    if (i == -1) return;
    _created.removeAt(i);
    if (_actionSession == id) _actionSession = llmDefaultSession;
    if (_agentSession == id) _agentSession = llmChatSession;
    _changed();
    await _write();
  }

  /// The user-created sessions as stored.
  List<Object?> encode() => [for (final s in _created) s.encode()];

  /// Takes the sessions read from the device settings, without writing them
  /// back. Entries that are not a session are dropped.
  void adopt(List<Object?>? stored) {
    _created
      ..clear()
      ..addAll([
        for (final value in stored ?? const []) ?LlmSessionInfo.decode(value),
      ]);
    _changed();
  }

  void _require(String id) {
    if (byId(id) == null) {
      throw LlmSessionException('There is no AI session "$id".');
    }
  }

  Future<void> _write() async {
    await persist?.call(encode());
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  void dispose() => unawaited(_changes.close());
}

/// A session id made from [name]: lower case, letters, digits and
/// `-`, starting with a letter, at most 32 characters, and none of [taken]
/// or the reserved ids — a number is appended where it would be.
String llmSessionIdFor(String name, {Set<String> taken = const {}}) {
  var base = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (base.isEmpty || !RegExp(r'^[a-z]').hasMatch(base)) base = 's-$base';
  base = base.replaceAll(RegExp(r'-+$'), '');
  if (base.length > 32) {
    base = base.substring(0, 32).replaceAll(RegExp(r'-+$'), '');
  }
  bool free(String id) =>
      !taken.contains(id) && !llmReservedSessionIds.contains(id);
  if (free(base)) return base;
  for (var n = 2; ; n++) {
    final suffix = '-$n';
    final stem = base.length + suffix.length > 32
        ? base.substring(0, 32 - suffix.length).replaceAll(RegExp(r'-+$'), '')
        : base;
    final id = '$stem$suffix';
    if (free(id)) return id;
  }
}
