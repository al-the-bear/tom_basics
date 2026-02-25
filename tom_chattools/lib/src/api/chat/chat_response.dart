/// Represents the response from getting messages.
library;

import 'chat_message.dart';

/// Encapsulates the response from [ChatAPI.getMessages].
///
/// Contains the messages received, along with status information
/// about the request and any platform-specific metadata.
class ChatResponse {
  /// The messages received.
  final List<ChatMessage> messages;

  /// Whether the operation was successful.
  final bool success;

  /// Status of the response.
  final ChatResponseStatus status;

  /// Error message if the operation failed.
  final String? error;

  /// How long the request actually waited.
  final Duration waitDuration;

  /// Whether there are potentially more messages available.
  final bool hasMore;

  /// Platform-specific metadata.
  final Map<String, dynamic>? metadata;

  const ChatResponse({
    required this.messages,
    this.success = true,
    this.status = ChatResponseStatus.ok,
    this.error,
    this.waitDuration = Duration.zero,
    this.hasMore = false,
    this.metadata,
  });

  /// Create an empty successful response.
  const ChatResponse.empty()
      : messages = const [],
        success = true,
        status = ChatResponseStatus.ok,
        error = null,
        waitDuration = Duration.zero,
        hasMore = false,
        metadata = null;

  /// Create an error response.
  factory ChatResponse.error(String message, {ChatResponseStatus? status}) {
    return ChatResponse(
      messages: const [],
      success: false,
      status: status ?? ChatResponseStatus.error,
      error: message,
    );
  }

  /// Create a timeout response.
  factory ChatResponse.timeout(Duration waitDuration) {
    return ChatResponse(
      messages: const [],
      success: true,
      status: ChatResponseStatus.timeout,
      waitDuration: waitDuration,
    );
  }

  /// Whether any messages were received.
  bool get hasMessages => messages.isNotEmpty;

  /// Number of messages received.
  int get count => messages.length;

  /// Get the first message, or null if empty.
  ChatMessage? get first => messages.isNotEmpty ? messages.first : null;

  /// Get the last message, or null if empty.
  ChatMessage? get last => messages.isNotEmpty ? messages.last : null;

  /// Filter messages by sender.
  List<ChatMessage> fromSender(String senderId) {
    return messages.where((m) => m.sender.id == senderId).toList();
  }

  /// Filter messages by type.
  List<ChatMessage> ofType(ChatMessageType type) {
    return messages.where((m) => m.type == type).toList();
  }

  /// Get only text content from all messages.
  List<String> get textContent {
    return messages
        .where((m) => m.text != null)
        .map((m) => m.text!)
        .toList();
  }

  @override
  String toString() =>
      'ChatResponse(count: $count, success: $success, status: $status)';
}

/// Status codes for chat responses.
enum ChatResponseStatus {
  /// Operation completed successfully.
  ok,

  /// Operation timed out waiting for messages.
  timeout,

  /// No new messages available.
  noMessages,

  /// Connection error occurred.
  connectionError,

  /// Authentication/authorization error.
  authError,

  /// Rate limit exceeded.
  rateLimited,

  /// Generic error.
  error,
}
