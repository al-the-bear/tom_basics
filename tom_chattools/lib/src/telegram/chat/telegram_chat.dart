/// Telegram implementation of the ChatAPI.
library;

import 'dart:async';
import 'dart:io';

import 'package:televerse/telegram.dart' as tg_models;
import 'package:televerse/televerse.dart' as tg;

import '../../api/chat/chat_api.dart';
import '../telegram_config.dart';

export '../telegram_config.dart';

/// Telegram implementation of [ChatApi].
///
/// Uses the Televerse library to communicate with Telegram Bot API.
class TelegramChat extends ChatApi {
  final TelegramChatConfig _config;
  late final tg.Bot _bot;
  bool _connected = false;

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
    _bot = tg.Bot(_config.token);
    _connected = true;

    // Start listening for updates if configured for polling
    if (_config.usePolling) {
      _startPolling();
    }
  }

  void _startPolling() {
    _bot.onMessage((ctx) {
      final message = _convertMessage(ctx.message);
      if (message != null) {
        _messageController.add(message);
      }
    });

    // Start the bot with configured polling timeout
    final fetcher = tg.LongPollingFetcher(
      _bot.api,
      config: tg.LongPollingConfig(
        timeout: _config.pollingTimeout,
        limit: 100,
      ),
    );
    _bot.start(fetcher);
  }

  ChatMessage? _convertMessage(tg_models.Message? msg) {
    if (msg == null) return null;

    final from = msg.from;
    
    // Debug logging for text vs caption
    print('[TelegramChat] Message received:');
    print('  msg.text: ${msg.text == null ? "null" : (msg.text!.isEmpty ? "empty" : "\"${msg.text}\"")}');
    print('  msg.caption: ${msg.caption == null ? "null" : (msg.caption!.isEmpty ? "empty" : "\"${msg.caption}\"")}');
    print('  hasPhoto: ${msg.photo != null}');
    print('  hasDocument: ${msg.document != null}');
    print('  hasVideo: ${msg.video != null}');
    print('  hasAudio: ${msg.audio != null}');
    
    // Use text if available, otherwise use caption (for messages with attachments)
    final messageText = msg.text ?? msg.caption;
    print('  → Using messageText: ${messageText == null ? "null" : "\"$messageText\""}');
    
    // Extract attachments from the message
    final attachments = _extractAttachments(msg);
    print('  → Extracted ${attachments.length} attachment(s)');
    
    return ChatMessage(
      id: msg.messageId.toString(),
      text: messageText,
      sender: ChatSender(
        id: from?.id.toString() ?? 'unknown',
        name: _buildName(from?.firstName, from?.lastName),
        username: from?.username,
        isSelf: from?.isBot == true && from?.id.toString() == _getBotId(),
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(msg.date * 1000),
      type: _getMessageType(msg),
      platformMessageId: msg.messageId.toString(),
      replyToMessageId: msg.replyToMessage?.messageId.toString(),
      attachments: attachments,
      rawData: {'telegram_message': msg},
    );
  }
  
  /// Extract attachments from a Telegram message.
  List<ChatAttachment> _extractAttachments(tg_models.Message msg) {
    final attachments = <ChatAttachment>[];
    
    // Photo - Telegram sends multiple sizes, get the largest
    if (msg.photo != null && msg.photo!.isNotEmpty) {
      final largest = msg.photo!.reduce((a, b) => 
          a.width * a.height > b.width * b.height ? a : b);
      attachments.add(ChatAttachment(
        type: ChatAttachmentType.image,
        url: largest.fileId,  // File ID for downloading
        fileName: 'photo.jpg',
        mimeType: 'image/jpeg',
      ));
    }
    
    // Document
    if (msg.document != null) {
      attachments.add(ChatAttachment(
        type: ChatAttachmentType.document,
        url: msg.document!.fileId,
        fileName: msg.document!.fileName ?? 'document',
        mimeType: msg.document!.mimeType,
      ));
    }
    
    // Video
    if (msg.video != null) {
      attachments.add(ChatAttachment(
        type: ChatAttachmentType.video,
        url: msg.video!.fileId,
        fileName: msg.video!.fileName ?? 'video.mp4',
        mimeType: msg.video!.mimeType,
      ));
    }
    
    // Audio
    if (msg.audio != null) {
      attachments.add(ChatAttachment(
        type: ChatAttachmentType.audio,
        url: msg.audio!.fileId,
        fileName: msg.audio!.fileName ?? 'audio.mp3',
        mimeType: msg.audio!.mimeType,
      ));
    }
    
    // Voice message
    if (msg.voice != null) {
      attachments.add(ChatAttachment(
        type: ChatAttachmentType.audio,
        url: msg.voice!.fileId,
        fileName: 'voice.ogg',
        mimeType: msg.voice!.mimeType,
      ));
    }
    
    return attachments;
  }

  String? _buildName(String? firstName, String? lastName) {
    if (firstName == null && lastName == null) return null;
    return [firstName, lastName].where((s) => s != null).join(' ');
  }

  String? _getBotId() {
    // Will be populated after getMe is called
    return null; // TODO: cache bot info
  }

  ChatMessageType _getMessageType(tg_models.Message msg) {
    if (msg.photo != null) return ChatMessageType.image;
    if (msg.video != null) return ChatMessageType.video;
    if (msg.audio != null) return ChatMessageType.audio;
    if (msg.voice != null) return ChatMessageType.audio;
    if (msg.document != null) return ChatMessageType.document;
    if (msg.sticker != null) return ChatMessageType.sticker;
    if (msg.location != null) return ChatMessageType.location;
    if (msg.contact != null) return ChatMessageType.contact;
    if (msg.text != null) return ChatMessageType.text;
    return ChatMessageType.unknown;
  }

  @override
  Future<ChatMessage> sendMessage(ChatReceiver receiver, String text, {String? parseMode}) async {
    final chatId = await _resolveChatId(receiver);
    final tgParseMode = _toTelegramParseMode(parseMode);
    final result = await _bot.api.sendMessage(chatId, text, parseMode: tgParseMode);

    return ChatMessage(
      id: result.messageId.toString(),
      text: text,
      sender: const ChatSender.self(),
      timestamp: DateTime.now(),
      type: ChatMessageType.text,
      platformMessageId: result.messageId.toString(),
    );
  }
  
  /// Convert string parse mode to Telegram ParseMode enum.
  tg_models.ParseMode? _toTelegramParseMode(String? parseMode) {
    if (parseMode == null) return null;
    switch (parseMode.toLowerCase()) {
      case 'markdown':
        return tg_models.ParseMode.markdown;
      case 'markdownv2':
        return tg_models.ParseMode.markdownV2;
      case 'html':
        return tg_models.ParseMode.html;
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
  Future<void> _sendAttachment(tg.ID chatId, ChatAttachment attachment, String? caption) async {
    final file = tg.InputFile.fromFile(File(attachment.url), name: attachment.fileName);
    
    switch (attachment.type) {
      case ChatAttachmentType.document:
        await _bot.api.sendDocument(chatId, file, caption: caption);
        break;
      case ChatAttachmentType.image:
        await _bot.api.sendPhoto(chatId, file, caption: caption);
        break;
      case ChatAttachmentType.video:
        await _bot.api.sendVideo(chatId, file, caption: caption);
        break;
      case ChatAttachmentType.audio:
        await _bot.api.sendAudio(chatId, file, caption: caption);
        break;
      default:
        // Default to document for unknown types
        await _bot.api.sendDocument(chatId, file, caption: caption);
    }
  }

  Future<tg.ID> _resolveChatId(ChatReceiver receiver) async {
    switch (receiver.type) {
      case ChatReceiverType.id:
        return tg.ID.create(int.parse(receiver.value));
      case ChatReceiverType.username:
        // Telegram requires @ prefix for usernames in some contexts
        final username = receiver.value.startsWith('@')
            ? receiver.value
            : '@${receiver.value}';
        return tg.ID.create(username);
      case ChatReceiverType.group:
        return tg.ID.create(int.parse(receiver.value));
      case ChatReceiverType.phone:
        throw UnsupportedError(
            'Telegram Bot API does not support sending by phone number');
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
      // Get the file info from Telegram
      final file = await _bot.api.getFile(fileId);
      final filePath = file.filePath;
      if (filePath == null) {
        print('[TelegramChat] getFile returned no filePath for $fileId');
        return null;
      }
      
      // Construct the download URL
      final downloadUrl = 'https://api.telegram.org/file/bot${_config.token}/$filePath';
      print('[TelegramChat] Downloading: $downloadUrl');
      
      // Download the file
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(Uri.parse(downloadUrl));
        final response = await request.close();
        if (response.statusCode == 200) {
          final bytes = <int>[];
          await for (final chunk in response) {
            bytes.addAll(chunk);
          }
          print('[TelegramChat] Downloaded ${bytes.length} bytes');
          return bytes;
        } else {
          print('[TelegramChat] Download failed: HTTP ${response.statusCode}');
        }
      } finally {
        httpClient.close();
      }
    } catch (e, stack) {
      print('[TelegramChat] Failed to download attachment: $e');
      print(stack);
    }
    return null;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _messageController.close();
    // Stop the bot polling and close connections
    await _bot.stop();
  }
}
