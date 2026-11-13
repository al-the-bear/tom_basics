/// Telegram implementation of the ChatAPI.
library;

import 'dart:async';
import 'dart:io';

import '../../api/chat/chat_api.dart';
import '../telegram_config.dart';
import 'telegram_bot_client.dart';

export '../telegram_config.dart';
export 'telegram_bot_client.dart' show TelegramApiException;

/// Telegram implementation of [ChatApi].
///
/// Talks to the Telegram Bot API over HTTP itself ([TelegramBotClient]):
/// long polling (`getUpdates`) for incoming messages, `sendMessage` and the
/// `send<Document|Photo|Video|Audio>` uploads for outgoing ones, `getFile` for
/// attachments.
class TelegramChat extends ChatApi {
  final TelegramChatConfig _config;
  late final TelegramBotClient _client;
  bool _connected = false;
  int _offset = 0;
  String? _botId;

  final StreamController<ChatMessage> _messageController =
      StreamController<ChatMessage>.broadcast();

  /// Internal constructor - use [ChatApi.connect] instead.
  TelegramChat(this._config);

  @override
  bool get isConnected => _connected;

  @override
  String get platform => 'telegram';

  @override
  Future<void> initialize() async {
    _client = TelegramBotClient(_config.token, baseUrl: _config.apiBaseUrl);
    _connected = true;

    // Start listening for updates if configured for polling
    if (_config.usePolling) {
      unawaited(_poll());
    }
  }

  /// Long polling: `getUpdates` in a loop, each message onto [onMessage],
  /// until [disconnect]. A failed call is retried after a short pause.
  Future<void> _poll() async {
    try {
      final me = await _client.call('getMe');
      if (me is Map) {
        _botId = me['id']?.toString();
      }
    } catch (_) {
      // Without getMe the bot's own messages are not marked isSelf; polling goes on.
    }
    while (_connected) {
      try {
        final updates = await _client.call('getUpdates', {
          'offset': _offset,
          'timeout': _config.pollingTimeout,
          'limit': 100,
          if (_config.allowedUpdates != null)
            'allowed_updates': _config.allowedUpdates,
        });
        if (updates is! List) {
          continue;
        }
        for (final update in updates) {
          if (update is! Map) {
            continue;
          }
          final id = update['update_id'];
          if (id is int && id >= _offset) {
            _offset = id + 1;
          }
          final msg = update['message'];
          if (msg is Map) {
            final message = _convertMessage(Map<String, dynamic>.from(msg));
            if (_connected && !_messageController.isClosed) {
              _messageController.add(message);
            }
          }
        }
      } catch (_) {
        if (!_connected) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  /// A Bot API `Message` (JSON) as a [ChatMessage]: the text or caption, the
  /// sender, the attachments; `rawData` holds the message as Telegram sent it
  /// (`telegram_message`) and its chat id (`telegram_chat_id`).
  ChatMessage _convertMessage(Map<String, dynamic> msg) {
    final from = msg['from'] is Map
        ? Map<String, dynamic>.from(msg['from'] as Map)
        : null;
    final chat = msg['chat'] is Map
        ? Map<String, dynamic>.from(msg['chat'] as Map)
        : null;
    final reply = msg['reply_to_message'] is Map
        ? msg['reply_to_message'] as Map
        : null;
    final messageId = msg['message_id']?.toString() ?? '';
    final date = msg['date'] is int ? msg['date'] as int : 0;
    final fromId = from?['id']?.toString();
    return ChatMessage(
      id: messageId,
      // Text, else the caption (a message with an attachment).
      text: (msg['text'] ?? msg['caption']) as String?,
      sender: ChatSender(
        id: fromId ?? 'unknown',
        name: _buildName(
          from?['first_name'] as String?,
          from?['last_name'] as String?,
        ),
        username: from?['username'] as String?,
        isSelf: from?['is_bot'] == true && fromId != null && fromId == _botId,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(date * 1000),
      type: _getMessageType(msg),
      platformMessageId: messageId,
      replyToMessageId: reply?['message_id']?.toString(),
      attachments: _extractAttachments(msg),
      rawData: {
        'telegram_message': msg,
        if (chat?['id'] != null) 'telegram_chat_id': chat!['id'].toString(),
      },
    );
  }

  /// Extract attachments from a Telegram message.
  List<ChatAttachment> _extractAttachments(Map<String, dynamic> msg) {
    final attachments = <ChatAttachment>[];
    Map<String, dynamic>? part(String key) =>
        msg[key] is Map ? Map<String, dynamic>.from(msg[key] as Map) : null;

    // Photo - Telegram sends multiple sizes, get the largest
    final photos = msg['photo'];
    if (photos is List && photos.isNotEmpty) {
      final sizes = photos.whereType<Map>().toList();
      if (sizes.isNotEmpty) {
        int area(Map p) =>
            ((p['width'] as int?) ?? 0) * ((p['height'] as int?) ?? 0);
        final largest = sizes.reduce((a, b) => area(a) > area(b) ? a : b);
        attachments.add(
          ChatAttachment(
            type: ChatAttachmentType.image,
            url:
                largest['file_id']?.toString() ?? '', // File ID for downloading
            fileName: 'photo.jpg',
            mimeType: 'image/jpeg',
            fileSize: largest['file_size'] as int?,
          ),
        );
      }
    }

    final document = part('document');
    if (document != null) {
      attachments.add(
        ChatAttachment(
          type: ChatAttachmentType.document,
          url: document['file_id']?.toString() ?? '',
          fileName: document['file_name'] as String? ?? 'document',
          mimeType: document['mime_type'] as String?,
          fileSize: document['file_size'] as int?,
        ),
      );
    }

    final video = part('video');
    if (video != null) {
      attachments.add(
        ChatAttachment(
          type: ChatAttachmentType.video,
          url: video['file_id']?.toString() ?? '',
          fileName: video['file_name'] as String? ?? 'video.mp4',
          mimeType: video['mime_type'] as String?,
          fileSize: video['file_size'] as int?,
        ),
      );
    }

    final audio = part('audio');
    if (audio != null) {
      attachments.add(
        ChatAttachment(
          type: ChatAttachmentType.audio,
          url: audio['file_id']?.toString() ?? '',
          fileName: audio['file_name'] as String? ?? 'audio.mp3',
          mimeType: audio['mime_type'] as String?,
          fileSize: audio['file_size'] as int?,
        ),
      );
    }

    // Voice message
    final voice = part('voice');
    if (voice != null) {
      attachments.add(
        ChatAttachment(
          type: ChatAttachmentType.audio,
          url: voice['file_id']?.toString() ?? '',
          fileName: 'voice.ogg',
          mimeType: voice['mime_type'] as String?,
          fileSize: voice['file_size'] as int?,
        ),
      );
    }

    return attachments;
  }

  String? _buildName(String? firstName, String? lastName) {
    if (firstName == null && lastName == null) return null;
    return [firstName, lastName].where((s) => s != null).join(' ');
  }

  ChatMessageType _getMessageType(Map<String, dynamic> msg) {
    if (msg['photo'] != null) return ChatMessageType.image;
    if (msg['video'] != null) return ChatMessageType.video;
    if (msg['audio'] != null) return ChatMessageType.audio;
    if (msg['voice'] != null) return ChatMessageType.audio;
    if (msg['document'] != null) return ChatMessageType.document;
    if (msg['sticker'] != null) return ChatMessageType.sticker;
    if (msg['location'] != null) return ChatMessageType.location;
    if (msg['contact'] != null) return ChatMessageType.contact;
    if (msg['text'] != null) return ChatMessageType.text;
    return ChatMessageType.unknown;
  }

  @override
  Future<ChatMessage> sendMessage(
    ChatReceiver receiver,
    String text, {
    String? parseMode,
  }) async {
    final chatId = await _resolveChatId(receiver);
    final result = await _client.call('sendMessage', {
      'chat_id': chatId,
      'text': text,
      'parse_mode': _toTelegramParseMode(parseMode),
    });
    final messageId = result is Map
        ? result['message_id']?.toString() ?? ''
        : '';

    return ChatMessage(
      id: messageId,
      text: text,
      sender: const ChatSender.self(),
      timestamp: DateTime.now(),
      type: ChatMessageType.text,
      platformMessageId: messageId,
    );
  }

  /// The Bot API's `parse_mode` for a parse mode name (any case); null when unknown.
  String? _toTelegramParseMode(String? parseMode) {
    if (parseMode == null) return null;
    switch (parseMode.toLowerCase()) {
      case 'markdown':
        return 'Markdown';
      case 'markdownv2':
        return 'MarkdownV2';
      case 'html':
        return 'HTML';
      default:
        return null;
    }
  }

  @override
  Future<ChatMessage> send(ChatReceiver receiver, ChatMessage message) async {
    final chatId = await _resolveChatId(receiver);

    // Handle attachments first
    if (message.attachments.isNotEmpty) {
      for (final attachment in message.attachments) {
        await _sendAttachment(chatId, attachment, message.text);
      }
      // If we sent attachments, create a response message
      return ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: message.text,
        sender: const ChatSender.self(),
        timestamp: DateTime.now(),
        type: ChatMessageType.document,
        attachments: message.attachments,
      );
    }

    // For text-only messages
    if (message.text != null) {
      return sendMessage(receiver, message.text!);
    }
    throw UnsupportedError('Message must have text or attachments');
  }

  /// Send a file attachment via Telegram.
  /// Send a file attachment via Telegram (`url` is the local file's path).
  Future<void> _sendAttachment(
    Object chatId,
    ChatAttachment attachment,
    String? caption,
  ) async {
    // The upload method and its file field; unknown types go as a document.
    final (method, field) = switch (attachment.type) {
      ChatAttachmentType.image => ('sendPhoto', 'photo'),
      ChatAttachmentType.video => ('sendVideo', 'video'),
      ChatAttachmentType.audio => ('sendAudio', 'audio'),
      _ => ('sendDocument', 'document'),
    };
    await _client.upload(
      method,
      {'chat_id': chatId, 'caption': caption},
      field,
      File(attachment.url),
      fileName: attachment.fileName,
    );
  }

  /// The Bot API's `chat_id`: a number, or `@username`.
  Future<Object> _resolveChatId(ChatReceiver receiver) async {
    switch (receiver.type) {
      case ChatReceiverType.id:
        return int.parse(receiver.value);
      case ChatReceiverType.username:
        // Telegram requires @ prefix for usernames in some contexts
        return receiver.value.startsWith('@')
            ? receiver.value
            : '@${receiver.value}';
      case ChatReceiverType.group:
        return int.parse(receiver.value);
      case ChatReceiverType.phone:
        throw UnsupportedError(
          'Telegram Bot API does not support sending by phone number',
        );
    }
  }

  @override
  Future<ChatResponse> getMessages(
    ChatReceiver receiver, {
    Duration maxWait = const Duration(seconds: 30),
    Duration minWait = Duration.zero,
    Duration interval = const Duration(seconds: 2),
    ChatMessageFilter? filter,
  }) async {
    final startTime = DateTime.now();
    final messages = <ChatMessage>[];

    // Subscribe to message stream, filtering by receiver
    late StreamSubscription<ChatMessage> subscription;
    subscription = onMessage.listen((message) {
      // Filter by receiver - check if sender matches the requested receiver
      if (!_matchesReceiver(message.sender, receiver)) return;
      if (_matchesFilter(message, filter)) {
        messages.add(message);
      }
    });

    // Poll at intervals until maxWait is reached
    while (true) {
      final elapsed = DateTime.now().difference(startTime);

      // If minWait has passed and we have messages, return immediately
      if (elapsed >= minWait && messages.isNotEmpty) {
        break;
      }

      // If maxWait has passed, stop waiting
      if (elapsed >= maxWait) {
        break;
      }

      // Wait for the interval (or remaining time if less)
      final remaining = maxWait - elapsed;
      final waitTime = remaining < interval ? remaining : interval;
      await Future.delayed(waitTime);
    }

    await subscription.cancel();

    final waitDuration = DateTime.now().difference(startTime);

    if (messages.isEmpty) {
      return ChatResponse.timeout(waitDuration);
    }

    return ChatResponse(
      messages: messages,
      success: true,
      status: ChatResponseStatus.ok,
      waitDuration: waitDuration,
    );
  }

  /// Check if a sender matches the expected receiver.
  bool _matchesReceiver(ChatSender sender, ChatReceiver receiver) {
    switch (receiver.type) {
      case ChatReceiverType.id:
        return sender.id == receiver.value;
      case ChatReceiverType.username:
        final expectedUsername = receiver.value.startsWith('@')
            ? receiver.value.substring(1)
            : receiver.value;
        return sender.username == expectedUsername;
      case ChatReceiverType.group:
        // For groups, the sender.id would be the group chat ID
        return sender.id == receiver.value;
      case ChatReceiverType.phone:
        // Phone matching not typically available in Telegram
        return false;
    }
  }

  bool _matchesFilter(ChatMessage message, ChatMessageFilter? filter) {
    if (filter == null) return true;

    if (filter.from != null) {
      final senderMatch = filter.from!.any((r) => r.value == message.sender.id);
      if (!senderMatch) return false;
    }

    if (filter.types != null) {
      if (!filter.types!.contains(message.type)) return false;
    }

    if (filter.after != null) {
      if (message.timestamp.isBefore(filter.after!)) return false;
    }

    return true;
  }

  @override
  Stream<ChatMessage> get onMessage => _messageController.stream;

  @override
  Future<ChatReceiverInfo?> getReceiverInfo(ChatReceiver receiver) async {
    // For Telegram, we need to have interacted with the user before
    // we can get their info via the Bot API
    // This is a limitation of the Bot API
    return null; // TODO: implement caching of known users
  }

  @override
  Future<List<int>?> downloadAttachment(ChatAttachment attachment) async {
    // Telegram attachments use file IDs, not URLs
    // We need to call getFile to get the file path, then download it
    final fileId = attachment.url;
    if (fileId.isEmpty) return null;

    try {
      // getFile answers the file's path; the bytes come from the file endpoint.
      final file = await _client.call('getFile', {'file_id': fileId});
      final filePath = file is Map ? file['file_path'] as String? : null;
      if (filePath == null) return null;
      return await _client.download(filePath);
    } on TelegramApiException {
      return null;
    } on IOException {
      return null;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _messageController.close();
    // Ends a long poll in flight and closes the connections.
    _client.close();
  }
}
