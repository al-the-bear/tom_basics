/// Represents a message in a chat conversation.
library;

/// A message sent or received through the chat API.
class ChatMessage {
  /// Unique identifier for this message (platform-specific).
  final String id;

  /// The text content of the message.
  final String? text;

  /// Sender of the message.
  final ChatSender sender;

  /// Timestamp when the message was sent.
  final DateTime timestamp;

  /// Type of the message.
  final ChatMessageType type;

  /// Platform-specific message ID (for replies, etc.).
  final String? platformMessageId;

  /// If this is a reply, the ID of the original message.
  final String? replyToMessageId;

  /// Optional attachments (files, images, etc.).
  final List<ChatAttachment> attachments;

  /// Platform-specific raw data (for advanced use cases).
  final Map<String, dynamic>? rawData;

  const ChatMessage({
    required this.id,
    this.text,
    required this.sender,
    required this.timestamp,
    this.type = ChatMessageType.text,
    this.platformMessageId,
    this.replyToMessageId,
    this.attachments = const [],
    this.rawData,
  });

  /// Create a simple text message for sending.
  factory ChatMessage.text(String text) {
    return ChatMessage(
      id: '',
      text: text,
      sender: const ChatSender.self(),
      timestamp: DateTime.now(),
      type: ChatMessageType.text,
    );
  }

  @override
  String toString() => 'ChatMessage(id: $id, text: $text, from: $sender)';
}

/// Types of chat messages.
enum ChatMessageType {
  /// Plain text message.
  text,

  /// Image/photo message.
  image,

  /// Video message.
  video,

  /// Audio/voice message.
  audio,

  /// Document/file message.
  document,

  /// Sticker message.
  sticker,

  /// Location message.
  location,

  /// Contact message.
  contact,

  /// System message (user joined, etc.).
  system,

  /// Unknown/unsupported message type.
  unknown,
}

/// Represents the sender of a message.
class ChatSender {
  /// Unique identifier for the sender.
  final String id;

  /// Display name of the sender.
  final String? name;

  /// Username/handle if available.
  final String? username;

  /// Whether this is the current user (self).
  final bool isSelf;

  const ChatSender({
    required this.id,
    this.name,
    this.username,
    this.isSelf = false,
  });

  /// Create a sender representing the current user.
  const ChatSender.self()
      : id = 'self',
        name = null,
        username = null,
        isSelf = true;

  @override
  String toString() =>
      'ChatSender(id: $id, name: $name, username: $username, isSelf: $isSelf)';
}

/// Represents an attachment in a message.
class ChatAttachment {
  /// Type of attachment.
  final ChatAttachmentType type;

  /// URL or file path to the attachment.
  final String url;

  /// MIME type if known.
  final String? mimeType;

  /// File name if available.
  final String? fileName;

  /// File size in bytes.
  final int? fileSize;

  /// Caption/description for the attachment.
  final String? caption;

  const ChatAttachment({
    required this.type,
    required this.url,
    this.mimeType,
    this.fileName,
    this.fileSize,
    this.caption,
  });
}

/// Types of attachments.
enum ChatAttachmentType {
  image,
  video,
  audio,
  document,
  sticker,
  location,
  contact,
}
