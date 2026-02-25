/// Platform-agnostic settings for chat connections.
library;

/// Settings for connecting to chat platforms.
///
/// This class provides a unified way to configure chat connections
/// without depending on platform-specific configuration classes.
/// The platform is automatically detected based on which settings
/// are provided.
///
/// Example:
/// ```dart
/// final settings = ChatSettings({
///   ChatSettings.telegramToken: 'YOUR_BOT_TOKEN',
/// });
/// final api = await ChatAPI.connect(settings);
/// ```
class ChatSettings {
  // ============ Telegram Settings ============

  /// Telegram bot token from @BotFather.
  static const String telegramToken = 'TELEGRAM_TOKEN';

  // ============ Future Platform Settings ============

  /// WhatsApp Business API token (future).
  static const String whatsappToken = 'WHATSAPP_TOKEN';

  /// Signal phone number (future).
  static const String signalPhone = 'SIGNAL_PHONE';

  // ============ Instance Fields ============

  /// Platform-specific settings as key-value pairs.
  final Map<String, String> settings;

  /// Timeout for polling requests.
  final Duration pollingTimeout;

  /// Whether to use polling for receiving messages.
  final bool usePolling;

  /// Creates chat settings.
  ///
  /// The [settings] map should contain platform-specific keys
  /// (e.g., [telegramToken] for Telegram).
  const ChatSettings(
    this.settings, {
    this.pollingTimeout = const Duration(seconds: 2),
    this.usePolling = true,
  });

  /// Convenience constructor for Telegram.
  factory ChatSettings.telegram(
    String token, {
    Duration pollingTimeout = const Duration(seconds: 2),
    bool usePolling = true,
  }) {
    return ChatSettings(
      {telegramToken: token},
      pollingTimeout: pollingTimeout,
      usePolling: usePolling,
    );
  }

  /// Get a setting value by key.
  String? operator [](String key) => settings[key];

  /// Check if a setting is present.
  bool has(String key) => settings.containsKey(key) && settings[key] != null;

  /// Detected platform based on settings.
  ///
  /// Returns the first platform for which required settings are present.
  String? get detectedPlatform {
    if (has(telegramToken)) return 'telegram';
    if (has(whatsappToken)) return 'whatsapp';
    if (has(signalPhone)) return 'signal';
    return null;
  }
}
