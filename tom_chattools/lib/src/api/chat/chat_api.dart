/// ChatAPI - Abstract interface for messaging platform integrations.
///
/// This interface provides a unified API for sending and receiving messages
/// across different messaging platforms (Telegram, WhatsApp, Signal, etc.).
library;

import 'dart:async';

import 'chat_message.dart';
import 'chat_response.dart';
import 'chat_receiver.dart';
import 'chat_settings.dart';
import '../../telegram/telegram_config.dart';

export 'chat_config.dart';
export 'chat_message.dart';
export 'chat_response.dart';
export 'chat_receiver.dart';
export 'chat_settings.dart';

/// Abstract base class for chat platform integrations.
///
/// Usage:
/// ```dart
/// final settings = ChatSettings.telegram('BOT_TOKEN');
/// final api = await ChatApi.connect(settings);
/// final receiver = ChatReceiver.id('123456');
/// await api.sendMessage(receiver, 'Hello!');
/// final response = await api.getMessages(receiver, maxWait: Duration(seconds: 10));
/// ```
abstract class ChatApi {
  /// The settings used to connect to this chat platform.
  late ChatSettings settings;

  /// Whether the connection is currently active.
  bool get isConnected;

  /// Platform identifier (e.g., 'telegram', 'whatsapp', 'signal').
  String get platform;

  /// Factory constructor that creates the appropriate implementation
  /// based on the settings provided.
  ///
  /// Detects the platform from the settings and creates the appropriate
  /// implementation. For example, if [ChatSettings.telegramToken] is present,
  /// creates a Telegram connection.
  ///
  /// Throws [UnsupportedError] if no supported platform can be detected.
  static Future<ChatApi> connect(ChatSettings settings) async {
    // Detect platform and create appropriate config
    if (settings.has(ChatSettings.telegramToken)) {
      final config = TelegramChatConfig(
        token: settings[ChatSettings.telegramToken]!,
        usePolling: settings.usePolling,
        pollingTimeout: settings.pollingTimeout.inSeconds,
      );
      final api = config.createApi(settings);
      await api.initialize();
      return api;
    }

    throw UnsupportedError(
      'No supported platform detected. '
      'Provide settings for a supported platform (e.g., telegramToken).',
    );
  }

  /// Initialize the connection. Called automatically by [connect].
  Future<void> initialize();

  /// Send a text message to a receiver.
  ///
  /// The optional [parseMode] can be 'Markdown', 'MarkdownV2', or 'HTML'
  /// for platforms that support it (e.g., Telegram).
  ///
  /// Returns the sent [ChatMessage] with platform-specific metadata.
  Future<ChatMessage> sendMessage(ChatReceiver receiver, String text, {String? parseMode});

  /// Send a message with optional attachments or formatting.
  ///
  /// The [message] can include text, attachments, and formatting options.
  Future<ChatMessage> send(ChatReceiver receiver, ChatMessage message);

  /// Get messages from a specific receiver/chat.
  ///
  /// - [receiver]: The chat/user to get messages from.
  /// - [maxWait]: Maximum time to wait for messages (default: 30 seconds).
  /// - [minWait]: Minimum time to wait before returning (default: 0).
  ///   After minWait, returns immediately if messages are available.
  /// - [interval]: Polling interval to check for messages (default: 2 seconds).
  /// - [filter]: Optional filter to only return certain message types.
  ///
  /// Returns a [ChatResponse] containing messages and status information.
  Future<ChatResponse> getMessages(
    ChatReceiver receiver, {
    Duration maxWait = const Duration(seconds: 30),
    Duration minWait = Duration.zero,
    Duration interval = const Duration(seconds: 2),
    ChatMessageFilter? filter,
  });

  /// Listen to incoming messages as a stream.
  ///
  /// This provides real-time message updates. The stream will emit
  /// [ChatMessage] objects as they arrive.
  Stream<ChatMessage> get onMessage;

  /// Get the profile/info for a receiver.
  Future<ChatReceiverInfo?> getReceiverInfo(ChatReceiver receiver);

  /// Download an attachment's content.
  ///
  /// For platforms like Telegram, the [ChatAttachment.url] may contain
  /// a file ID rather than a direct URL. This method handles the
  /// platform-specific download logic.
  ///
  /// Returns the file content as bytes, or null if download fails.
  Future<List<int>?> downloadAttachment(ChatAttachment attachment);

  /// Close the connection and clean up resources.
  Future<void> disconnect();
}

/// Filter for selecting specific message types.
class ChatMessageFilter {
  /// Only include messages from these senders.
  final List<ChatReceiver>? from;

  /// Only include messages of these types.
  final List<ChatMessageType>? types;

  /// Only include messages after this timestamp.
  final DateTime? after;

  const ChatMessageFilter({
    this.from,
    this.types,
    this.after,
  });
}
