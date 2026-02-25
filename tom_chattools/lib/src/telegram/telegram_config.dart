/// Telegram-specific configuration for ChatAPI.
library;

import '../api/chat/chat_api.dart';
import 'chat/telegram_chat.dart';

/// Configuration for connecting to Telegram via Bot API.
///
/// To get a bot token:
/// 1. Open Telegram and search for @BotFather
/// 2. Send /newbot command
/// 3. Follow the prompts to create your bot
/// 4. Copy the API token provided
///
/// Example:
/// ```dart
/// final config = TelegramChatConfig(
///   token: 'YOUR_BOT_TOKEN',
/// );
/// final api = await ChatAPI.connect(config);
/// ```
class TelegramChatConfig extends ChatConfig {
  /// The bot token from @BotFather.
  final String token;

  /// Whether to use long polling for receiving messages.
  /// If false, you must set up webhooks separately.
  final bool usePolling;

  /// Timeout for long polling requests (in seconds).
  final int pollingTimeout;

  /// Allowed update types to receive (empty = all).
  final List<String>? allowedUpdates;

  const TelegramChatConfig({
    required this.token,
    this.usePolling = true,
    this.pollingTimeout = 2,
    this.allowedUpdates,
  });

  @override
  String get platform => 'telegram';

  @override
  ChatApi createApi( ChatSettings settings ) => TelegramChat(this)..settings = settings;
}
