# Tom Chattools

A platform-agnostic chat API library for Dart that provides a unified interface
for sending and receiving messages across different chat platforms.

## Features

- **Abstract ChatAPI** - Platform-independent interface for chat operations
- **Telegram Support** - Full Telegram Bot API integration via televerse
- **Message Abstraction** - Unified `ChatMessage`, `ChatSender`, and `ChatResponse` classes
- **Streaming Updates** - Real-time message notifications via `onMessage` stream
- **Factory Pattern** - Create appropriate implementation via `ChatAPI.connect()`

## Getting Started

### Prerequisites

- Dart SDK 3.0 or higher
- A Telegram bot token (for Telegram integration)

### Installation

Add `tom_chattools` to your `pubspec.yaml`:

```yaml
dependencies:
  tom_chattools:
    path: ../path/to/tom_chattools  # Or use git reference
```

## Telegram Setup

To connect to Telegram, you need a bot token from [@BotFather](https://t.me/BotFather).

### Step 1: Create a Bot

1. Open Telegram and search for **@BotFather** (the official Telegram bot)
2. Start a conversation and send `/newbot`
3. Follow the prompts:
   - Choose a display name (e.g., "My Assistant")
   - Choose a username (must end in `bot`, e.g., `my_assistant_bot`)
4. BotFather will give you an API token like:
   ```
   123456789:ABCdefGHIjklMNOpqrsTUVwxyz
   ```
5. **Save this token securely** - it grants full access to your bot

### Step 2: Get Your Chat ID

To send/receive messages from a specific chat, you need the chat ID:

**For personal chats:**
1. Message your bot first (search for its username in Telegram)
2. Run your bot with polling enabled (see example below)
3. Send a message to your bot
4. Check the `sender.id` in the received message - that's your chat ID

**Using a helper bot:**
1. Forward any message to [@userinfobot](https://t.me/userinfobot)
2. It will reply with your user ID (same as chat ID for 1:1 chats)

**For groups:**
1. Add your bot to the group
2. The group chat ID will appear in incoming messages (usually a negative number)

### Step 3: Connect and Use

```dart
import 'package:tom_chattools/tom_chattools.dart';

void main() async {
  // Create configuration (just authentication)
  final config = TelegramChatConfig(
    token: 'YOUR_BOT_TOKEN',
    usePolling: true,        // Use long polling for updates
  );

  // Connect to Telegram
  final chat = await ChatAPI.connect(config);

  // Define who to communicate with
  final receiver = ChatReceiver.id('YOUR_CHAT_ID');

  // Send a message
  await chat.sendMessage(receiver, 'Hello from Dart!');

  // Listen for incoming messages
  chat.onMessage.listen((message) {
    print('Received: ${message.text} from ${message.sender.name}');
    
    // Echo back to the sender
    final sender = ChatReceiver.id(message.sender.id);
    chat.sendMessage(sender, 'You said: ${message.text}');
  });
}
```

### Environment Variables (Recommended)

Store your token and chat ID securely using environment variables:

```dart
import 'dart:io';

final token = Platform.environment['TELEGRAM_BOT_TOKEN']!;
final chatId = Platform.environment['TELEGRAM_CHAT_ID']!;

final config = TelegramChatConfig(token: token, usePolling: true);
final receiver = ChatReceiver.id(chatId);
```

Set them in your shell:
```bash
export TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
export TELEGRAM_CHAT_ID="987654321"
```

## Usage Examples

### Basic Send/Receive

```dart
final chat = await ChatAPI.connect(TelegramChatConfig(
  token: token,
  usePolling: true,
));

// Define the receiver
final receiver = ChatReceiver.id(chatId);

// Send a message to the receiver
await chat.sendMessage(receiver, 'Hello!');

// Get messages from that receiver
final response = await chat.getMessages(
  receiver,
  maxWait: Duration(seconds: 10),
);
for (final msg in response.messages) {
  print('${msg.sender.name}: ${msg.text}');
}
```

### Message Types

```dart
chat.onMessage.listen((msg) {
  switch (msg.type) {
    case ChatMessageType.text:
      print('Text: ${msg.text}');
    case ChatMessageType.image:
      print('Received an image');
    case ChatMessageType.document:
      print('Received a document');
    default:
      print('Other: ${msg.type}');
  }
});
```

### Send to Different Chats

```dart
// Send to a user by ID
await chat.sendMessage(ChatReceiver.id('123456789'), 'Hello user!');

// Send to a user by username
await chat.sendMessage(ChatReceiver.username('johndoe'), 'Hi John!');

// Send to a group
await chat.sendMessage(ChatReceiver.group('-100123456789'), 'Hello group!');
```

## API Overview

### Core Classes

| Class | Description |
|-------|-------------|
| `ChatAPI` | Abstract interface for chat operations |
| `ChatConfig` | Base configuration class |
| `ChatMessage` | Represents a chat message |
| `ChatSender` | Information about message sender |
| `ChatResponse` | Response from getMessages() |
| `ChatReceiver` | Target for sending messages |

### Telegram Classes

| Class | Description |
|-------|-------------|
| `TelegramChatConfig` | Telegram-specific configuration |
| `TelegramChat` | Telegram implementation of ChatAPI |

## Troubleshooting

### "Conflict: terminated by other getUpdates request"

Only one polling connection can be active. Make sure:
- You don't have another instance running
- You stopped previous bot instances properly

### Bot not receiving messages

1. Make sure you've messaged the bot first (bots can't initiate chats)
2. Check if polling is enabled: `usePolling: true`
3. Verify your token is correct

### Getting chat/user IDs

Print incoming message details:
```dart
chat.onMessage.listen((msg) {
  print('Chat ID: ${msg.sender.id}');
  print('Message ID: ${msg.platformMessageId}');
});
```

## Additional Information

- [Telegram Bot API Documentation](https://core.telegram.org/bots/api)
- [Televerse Package](https://pub.dev/packages/televerse) - underlying Telegram library
- [BotFather Commands](https://core.telegram.org/bots#6-botfather)

### Bot Privacy Settings

By default, bots in groups only see messages that:
- Start with `/` (commands)
- Are replies to the bot
- Mention the bot

To see all messages, disable privacy mode:
1. Go to @BotFather
2. Send `/setprivacy`
3. Choose your bot
4. Select "Disable"
