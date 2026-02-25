/// Configuration for connecting to a chat platform.
///
/// Subclasses define platform-specific configuration options.
library;

import 'chat_api.dart';

/// Base class for chat platform configuration.
abstract class ChatConfig {
  /// Platform identifier (e.g., 'telegram', 'whatsapp').
  String get platform;

  /// Create the appropriate ChatAPI implementation for this config.
  ///
  /// This is called internally by [ChatApi.connect].
  ChatApi createApi( ChatSettings settings );

  const ChatConfig();
}
