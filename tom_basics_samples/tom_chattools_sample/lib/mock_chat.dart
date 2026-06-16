/// `MockChatApi` — an in-memory implementation of `tom_chattools`' [ChatApi].
///
/// `tom_chattools` is built around one idea: **`ChatApi` is an abstract
/// contract, and a platform is just one implementation of it.** The shipped
/// implementation talks to Telegram; `ChatApi.connect` detects the platform from
/// the settings and hands you back a `ChatApi`. Your application code then talks
/// only to that interface — `sendMessage`, `getMessages`, `onMessage`,
/// `getReceiverInfo`, `disconnect` — and never names Telegram again.
///
/// That design is exactly what makes the library testable without a network or a
/// bot token: write a *second* implementation of the same contract that keeps
/// everything in memory, and any code written against `ChatApi` runs against it
/// unchanged. This file is that implementation. It is both the sample's test
/// harness and its central lesson — a worked example of implementing the
/// `ChatApi` interface.
///
/// What it models, in memory and synchronously:
///
///   * **Sending** records each outgoing message in a log ([sentMessages]) and
///     stamps it with a generated id, just as a real platform assigns one.
///   * **Receiving** is *scripted*: [enqueueIncoming] queues an inbound message
///     for a receiver, which `getMessages` then drains (honouring a
///     [ChatMessageFilter]) and `onMessage` emits live.
///   * **Auto-reply** (optional) lets the mock answer a sent message, so a
///     round-trip conversation can be exercised end to end.
///   * **Receiver info** and **attachment bytes** are served from in-memory maps
///     you populate with [setReceiverInfo] / [putAttachment].
///
/// Nothing here does I/O, sleeps, or reaches the network, so every example built
/// on it is hermetic and instant.
library;

import 'dart:async';

import 'package:tom_chattools/tom_chattools.dart';

/// An in-memory [ChatApi] for tests, samples, and local development.
///
/// Construct it directly (there is no platform to detect), optionally with an
/// [autoResponder] that turns every sent message into a scripted reply:
///
/// ```dart
/// final api = MockChatApi(autoResponder: (sent) => 'echo: ${sent.text}');
/// await api.initialize();
/// ```
class MockChatApi extends ChatApi {
  /// Creates an in-memory chat transport.
  ///
  /// [autoResponder] is called for each outgoing message; if it returns a
  /// non-null string, that string is queued as an inbound reply from the
  /// receiver (and emitted on [onMessage] while connected).
  MockChatApi({
    ChatSettings? settings,
    String? Function(ChatMessage sent)? autoResponder,
  }) : _autoResponder = autoResponder {
    this.settings = settings ?? const ChatSettings({'MOCK_TRANSPORT': 'memory'});
  }

  final String? Function(ChatMessage sent)? _autoResponder;
  final Map<ChatReceiver, List<ChatMessage>> _inbound = {};
  final List<ChatMessage> _sent = [];
  final Map<ChatReceiver, ChatReceiverInfo> _receiverInfo = {};
  final Map<String, List<int>> _attachments = {};
  final StreamController<ChatMessage> _incoming =
      StreamController<ChatMessage>.broadcast();

  bool _connected = false;
  int _idCounter = 0;

  // A deterministic monotonic clock so generated timestamps are reproducible.
  // Starts at a fixed instant and advances one second per stamp.
  DateTime _stamp() {
    _clockSeconds++;
    return DateTime.utc(2026, 1, 1).add(Duration(seconds: _clockSeconds));
  }

  int _clockSeconds = 0;

  String _nextId() => 'm${++_idCounter}';

  // ---- scripting API (not part of ChatApi) --------------------------------

  /// Every message sent through this transport, in order, for assertions.
  List<ChatMessage> get sentMessages => List.unmodifiable(_sent);

  /// Queues an inbound [message] as if [from] had sent it. While connected it is
  /// also emitted on [onMessage].
  void enqueueIncoming(ChatReceiver from, ChatMessage message) {
    (_inbound[from] ??= <ChatMessage>[]).add(message);
    if (_connected && !_incoming.isClosed) {
      _incoming.add(message);
    }
  }

  /// Convenience: queue a plain inbound text message from [from].
  void receiveText(ChatReceiver from, String text, {String? senderName}) {
    enqueueIncoming(
      from,
      ChatMessage(
        id: _nextId(),
        text: text,
        sender: ChatSender(id: from.value, name: senderName),
        timestamp: _stamp(),
      ),
    );
  }

  /// Registers the profile returned by [getReceiverInfo] for [receiver].
  void setReceiverInfo(ChatReceiver receiver, ChatReceiverInfo info) =>
      _receiverInfo[receiver] = info;

  /// Registers attachment [bytes] served by [downloadAttachment] for [url].
  void putAttachment(String url, List<int> bytes) => _attachments[url] = bytes;

  // ---- ChatApi contract ---------------------------------------------------

  @override
  bool get isConnected => _connected;

  @override
  String get platform => 'mock';

  @override
  Future<void> initialize() async {
    _connected = true;
  }

  @override
  Future<ChatMessage> sendMessage(
    ChatReceiver receiver,
    String text, {
    String? parseMode,
  }) async {
    final message = ChatMessage(
      id: _nextId(),
      text: text,
      sender: const ChatSender.self(),
      timestamp: _stamp(),
      type: ChatMessageType.text,
      rawData: parseMode != null ? {'parseMode': parseMode} : null,
    );
    _sent.add(message);
    _maybeAutoRespond(receiver, message);
    return message;
  }

  @override
  Future<ChatMessage> send(ChatReceiver receiver, ChatMessage message) async {
    final stored = ChatMessage(
      id: _nextId(),
      text: message.text,
      sender: const ChatSender.self(),
      timestamp: _stamp(),
      type: message.type,
      attachments: message.attachments,
      rawData: message.rawData,
    );
    _sent.add(stored);
    _maybeAutoRespond(receiver, stored);
    return stored;
  }

  void _maybeAutoRespond(ChatReceiver receiver, ChatMessage sent) {
    final reply = _autoResponder?.call(sent);
    if (reply == null) return;
    enqueueIncoming(
      receiver,
      ChatMessage(
        id: _nextId(),
        text: reply,
        sender: ChatSender(id: receiver.value, name: 'Mock User'),
        timestamp: _stamp(),
      ),
    );
  }

  @override
  Future<ChatResponse> getMessages(
    ChatReceiver receiver, {
    Duration maxWait = const Duration(seconds: 30),
    Duration minWait = Duration.zero,
    Duration interval = const Duration(seconds: 2),
    ChatMessageFilter? filter,
  }) async {
    final queue = _inbound[receiver];
    if (queue == null || queue.isEmpty) {
      return const ChatResponse(
        messages: [],
        status: ChatResponseStatus.noMessages,
      );
    }

    final selected = <ChatMessage>[];
    queue.removeWhere((message) {
      if (_matches(message, filter)) {
        selected.add(message);
        return true; // consumed
      }
      return false; // left for a later, differently-filtered read
    });

    if (selected.isEmpty) {
      return const ChatResponse(
        messages: [],
        status: ChatResponseStatus.noMessages,
      );
    }
    return ChatResponse(
      messages: selected,
      status: ChatResponseStatus.ok,
      hasMore: queue.isNotEmpty,
    );
  }

  bool _matches(ChatMessage message, ChatMessageFilter? filter) {
    if (filter == null) return true;
    if (filter.types != null && !filter.types!.contains(message.type)) {
      return false;
    }
    if (filter.from != null &&
        !filter.from!.any((r) => r.value == message.sender.id)) {
      return false;
    }
    if (filter.after != null && !message.timestamp.isAfter(filter.after!)) {
      return false;
    }
    return true;
  }

  @override
  Stream<ChatMessage> get onMessage => _incoming.stream;

  @override
  Future<ChatReceiverInfo?> getReceiverInfo(ChatReceiver receiver) async =>
      _receiverInfo[receiver];

  @override
  Future<List<int>?> downloadAttachment(ChatAttachment attachment) async =>
      _attachments[attachment.url];

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _incoming.close();
  }
}
