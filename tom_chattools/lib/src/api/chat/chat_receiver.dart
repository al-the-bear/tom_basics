/// Represents a message receiver (user, group, channel).
library;

/// Identifies a recipient for sending messages.
///
/// A receiver can be identified by:
/// - Platform-specific numeric ID
/// - Username/handle
/// - Phone number (for platforms that support it)
class ChatReceiver {
  /// The type of receiver identifier.
  final ChatReceiverType type;

  /// The identifier value.
  final String value;

  const ChatReceiver._(this.type, this.value);

  /// Create a receiver from a platform-specific ID.
  const ChatReceiver.id(String id) : this._(ChatReceiverType.id, id);

  /// Create a receiver from a username/handle.
  const ChatReceiver.username(String username)
      : this._(ChatReceiverType.username, username);

  /// Create a receiver from a phone number.
  const ChatReceiver.phone(String phone) : this._(ChatReceiverType.phone, phone);

  /// Create a receiver for a group/channel by ID.
  const ChatReceiver.group(String groupId)
      : this._(ChatReceiverType.group, groupId);

  @override
  String toString() => 'ChatReceiver($type: $value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatReceiver && type == other.type && value == other.value;

  @override
  int get hashCode => type.hashCode ^ value.hashCode;
}

/// Types of receiver identifiers.
enum ChatReceiverType {
  /// Platform-specific numeric or string ID.
  id,

  /// Username or handle (e.g., @username).
  username,

  /// Phone number.
  phone,

  /// Group or channel ID.
  group,
}

/// Additional information about a receiver.
class ChatReceiverInfo {
  /// Platform-specific ID.
  final String id;

  /// Display name.
  final String? name;

  /// First name (if available).
  final String? firstName;

  /// Last name (if available).
  final String? lastName;

  /// Username/handle.
  final String? username;

  /// Phone number (if available).
  final String? phone;

  /// Profile photo URL.
  final String? photoUrl;

  /// Whether this is a bot/automated account.
  final bool isBot;

  /// Platform-specific additional data.
  final Map<String, dynamic>? rawData;

  const ChatReceiverInfo({
    required this.id,
    this.name,
    this.firstName,
    this.lastName,
    this.username,
    this.phone,
    this.photoUrl,
    this.isBot = false,
    this.rawData,
  });

  @override
  String toString() => 'ChatReceiverInfo(id: $id, name: $name)';
}
