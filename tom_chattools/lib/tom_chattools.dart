/// Tom ChatTools - Unified chat API abstraction for messaging platforms.
///
/// This library provides a platform-agnostic API for integrating with
/// various messaging platforms like Telegram, WhatsApp, Signal, etc.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:tom_chattools/tom_chattools.dart';
///
/// void main() async {
///   // Connect to Telegram
///   final api = await ChatAPI.connect(TelegramChatConfig(
///     token: 'YOUR_BOT_TOKEN',
///   ));
///
///   // Send a message
///   await api.sendMessage(ChatReceiver.id('123456789'), 'Hello!');
///
///   // Wait for response
///   final response = await api.getMessages(
///     maxWait: Duration(seconds: 30),
///     minWait: Duration(seconds: 5),
///   );
///
///   for (final message in response.messages) {
///     print('Received: ${message.text}');
///   }
///
///   await api.disconnect();
/// }
/// ```
///
/// ## Supported Platforms
///
/// - **Telegram** - Full support via Bot API
/// - More platforms coming soon (WhatsApp, Signal, etc.)
library;

// Core API
export 'src/api/chat/chat_api.dart';
export 'src/api/chat/chat_config.dart';
export 'src/api/chat/chat_message.dart';
export 'src/api/chat/chat_receiver.dart';
export 'src/api/chat/chat_response.dart';

// Telegram implementation
export 'src/telegram/telegram_config.dart';
