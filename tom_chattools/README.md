# Tom Chattools

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](LICENSE).

Unified chat API abstraction for Telegram, WhatsApp, Signal, and other
messaging platforms.

---

## Overview

`tom_chattools` gives you **one API** to send and receive chat messages,
regardless of the platform behind it. You describe a connection with
[`ChatSettings`](#chatsettings), call `ChatApi.connect(...)`, and from then on
the same `sendMessage` / `getMessages` / `onMessage` surface works no matter
which messenger you target.

- **Platform-agnostic core.** `ChatApi`, `ChatMessage`, `ChatReceiver`, and
  `ChatResponse` carry no platform-specific types, so application code never
  imports a Telegram (or future WhatsApp/Signal) class directly.
- **Platform auto-detection.** `ChatApi.connect` inspects the `ChatSettings` you
  pass and picks the implementation — provide a Telegram token and you get a
  Telegram connection; nothing else changes in your code.
- **Two ways to receive.** Block-and-wait with `getMessages` (with `minWait` /
  `maxWait` / `interval` tuning) or subscribe to the live `onMessage` stream.
- **Telegram today.** A complete Telegram Bot API implementation (via
  [`televerse`](https://pub.dev/packages/televerse)) ships now; WhatsApp and
  Signal are reserved in the settings model for future implementations.

Pure Dart, no Flutter dependency — works in servers, bots, and CLI tools.

---

## Installation

```yaml
dependencies:
  tom_chattools: ^1.0.2
```

or from the command line:

```bash
dart pub add tom_chattools
```

Requires the Dart SDK `^3.10.4`. Pulls in
[`televerse`](https://pub.dev/packages/televerse) for the Telegram backend. For
Telegram you also need a **bot token** from
[@BotFather](https://t.me/BotFather) — see [Telegram setup](#telegram-setup).

---

## Features

### Core abstraction

| Capability | API | Notes |
| ---------- | --- | ----- |
| Connect (auto-detect platform) | `ChatApi.connect(settings)` | Picks the impl from `ChatSettings` |
| Send text | `sendMessage(receiver, text, {parseMode})` | `parseMode`: `Markdown`/`MarkdownV2`/`HTML` |
| Send a rich message | `send(receiver, ChatMessage)` | Text + attachments + formatting |
| Pull messages | `getMessages(receiver, {minWait, maxWait, interval, filter})` | Returns a `ChatResponse` |
| Stream messages | `onMessage` | Live `Stream<ChatMessage>` |
| Look up a recipient | `getReceiverInfo(receiver)` | Returns `ChatReceiverInfo?` |
| Download an attachment | `downloadAttachment(attachment)` | Resolves platform file IDs to bytes |
| Disconnect | `disconnect()` | Closes the connection |

### Addressing & messages

| Type | Constructors / members | Notes |
| ---- | ---------------------- | ----- |
| `ChatReceiver` | `.id()`, `.username()`, `.phone()`, `.group()` | Who to send to |
| `ChatMessage` | `.text(...)`, `text`, `sender`, `type`, `attachments` | A sent/received message |
| `ChatMessageType` | `text`, `image`, `video`, `audio`, `document`, `sticker`, `location`, `contact`, `system`, `unknown` | Message kind |
| `ChatResponse` | `messages`, `hasMessages`, `count`, `ofType()`, `fromSender()`, `textContent` | Result of `getMessages` |
| `ChatMessageFilter` | `from`, `types`, `after` | Narrow what `getMessages` returns |

### Configuration

| Type | Purpose |
| ---- | ------- |
| `ChatSettings` | Platform-agnostic, auto-detected connection settings |
| `ChatSettings.telegram(token, …)` | Convenience constructor for Telegram |
| `TelegramChatConfig` | Telegram-specific config (created internally by `connect`) |

---

## Quick start

`ChatApi.connect` takes a `ChatSettings`; the convenience constructor
`ChatSettings.telegram(token)` is the shortest path to a working bot. Provide a
real token and the snippet below sends a message and waits for replies:

```dart
import 'package:tom_chattools/tom_chattools.dart';

void main() async {
  // Connect — the platform is detected from the settings.
  final api = await ChatApi.connect(ChatSettings.telegram('YOUR_BOT_TOKEN'));

  // Address the user/chat to talk to.
  final receiver = ChatReceiver.id('123456789');

  // Send a message.
  await api.sendMessage(receiver, 'Hello from Tom ChatTools!');

  // Wait up to 30s for replies (returning early once any arrive after 5s).
  final response = await api.getMessages(
    receiver,
    maxWait: const Duration(seconds: 30),
    minWait: const Duration(seconds: 5),
  );

  if (response.hasMessages) {
    for (final message in response.messages) {
      print('Received from ${message.sender.name}: ${message.text}');
    }
  } else {
    print('No messages received (status: ${response.status})');
  }

  await api.disconnect();
}
```

This mirrors the runnable [`example/tom_chattools_example.dart`](example/tom_chattools_example.dart).

---

## Example projects

| Example | What it shows |
| ------- | ------------- |
| [`tom_chattools_sample`](../tom_basics_samples/tom_chattools_sample/) | The unified chat API as an article: the `ChatApi` contract driven against an in-memory mock transport (no live tokens), covering send/receive/filtering/streaming — seven runnable, CI-safe examples. |
| [`example/tom_chattools_example.dart`](example/tom_chattools_example.dart) | Connect, send, and pull replies from Telegram |
| [Quick start](#quick-start) | Same flow, annotated |
| [Streaming updates](#streaming-updates) | The `onMessage` live stream |
| [Message types](#message-types) | Switching on `ChatMessageType` |
| [Send to different chats](#send-to-different-chats) | `ChatReceiver` variants |

---

## Telegram setup

To connect to Telegram you need a bot token from
[@BotFather](https://t.me/BotFather).

### Step 1: Create a bot

1. Open Telegram and search for **@BotFather** (the official Telegram bot).
2. Start a conversation and send `/newbot`.
3. Follow the prompts:
   - Choose a display name (e.g. "My Assistant").
   - Choose a username (must end in `bot`, e.g. `my_assistant_bot`).
4. BotFather gives you an API token like:

   ```text
   123456789:ABCdefGHIjklMNOpqrsTUVwxyz
   ```

5. **Save this token securely** — it grants full access to your bot.

### Step 2: Get your chat ID

To send/receive messages from a specific chat, you need its chat ID:

**For personal chats:**

1. Message your bot first (search for its username in Telegram).
2. Run your bot with polling enabled (see below).
3. Send a message to your bot.
4. Check `sender.id` on the received message — that is your chat ID.

**Using a helper bot:**

1. Forward any message to [@userinfobot](https://t.me/userinfobot).
2. It replies with your user ID (same as the chat ID for 1:1 chats).

**For groups:**

1. Add your bot to the group.
2. The group chat ID appears in incoming messages (usually a negative number).

### Step 3: Connect and use

```dart
import 'package:tom_chattools/tom_chattools.dart';

void main() async {
  // Settings carry just the authentication + polling preferences.
  final api = await ChatApi.connect(
    ChatSettings.telegram('YOUR_BOT_TOKEN', usePolling: true),
  );

  // Define who to communicate with.
  final receiver = ChatReceiver.id('YOUR_CHAT_ID');

  // Send a message.
  await api.sendMessage(receiver, 'Hello from Dart!');

  // Listen for incoming messages and echo them back.
  api.onMessage.listen((message) {
    print('Received: ${message.text} from ${message.sender.name}');
    api.sendMessage(ChatReceiver.id(message.sender.id), 'You said: ${message.text}');
  });
}
```

### Environment variables (recommended)

Keep your token and chat ID out of source control:

```dart
import 'dart:io';
import 'package:tom_chattools/tom_chattools.dart';

final token = Platform.environment['TELEGRAM_BOT_TOKEN']!;
final chatId = Platform.environment['TELEGRAM_CHAT_ID']!;

final api = await ChatApi.connect(ChatSettings.telegram(token, usePolling: true));
final receiver = ChatReceiver.id(chatId);
```

Set them in your shell:

```bash
export TELEGRAM_BOT_TOKEN="123456789:ABCdefGHIjklMNOpqrsTUVwxyz"
export TELEGRAM_CHAT_ID="987654321"
```

---

## Usage

### Basic send / receive

`getMessages` is the block-and-wait path. It polls the platform until either
`maxWait` elapses or messages arrive after `minWait`, then returns a
[`ChatResponse`](#chatresponse).

```dart
final api = await ChatApi.connect(ChatSettings.telegram(token, usePolling: true));
final receiver = ChatReceiver.id(chatId);

await api.sendMessage(receiver, 'Hello!');

final response = await api.getMessages(
  receiver,
  maxWait: const Duration(seconds: 10),
);
for (final msg in response.messages) {
  print('${msg.sender.name}: ${msg.text}');
}
```

`ChatResponse` carries helpers beyond `messages`: `hasMessages`, `count`,
`first`, `last`, `ofType(type)`, `fromSender(id)`, and `textContent`.

### Streaming updates

When you want push-style delivery instead of polling, subscribe to `onMessage`:

```dart
api.onMessage.listen((message) {
  print('${message.sender.name}: ${message.text}');
});
```

### Message types

Every `ChatMessage` carries a `ChatMessageType`. Switch on it to handle each
kind:

```dart
api.onMessage.listen((msg) {
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

To pull only certain kinds in a `getMessages` call, pass a `ChatMessageFilter`:

```dart
final response = await api.getMessages(
  receiver,
  filter: const ChatMessageFilter(types: [ChatMessageType.text]),
);
```

### Send to different chats

A `ChatReceiver` can address a user by ID, by username, or a whole group:

```dart
// Send to a user by ID.
await api.sendMessage(ChatReceiver.id('123456789'), 'Hello user!');

// Send to a user by username.
await api.sendMessage(ChatReceiver.username('johndoe'), 'Hi John!');

// Send to a group.
await api.sendMessage(ChatReceiver.group('-100123456789'), 'Hello group!');
```

---

## Architecture

```text
package:tom_chattools/tom_chattools.dart   (single export surface)
│
├── api/chat/                  ← platform-agnostic core
│   ├── ChatApi (abstract)         connect() factory + send/receive contract
│   ├── ChatSettings               auto-detected connection settings
│   ├── ChatConfig (abstract)      platform config → createApi()
│   ├── ChatReceiver               who to address (id/username/phone/group)
│   ├── ChatMessage / ChatSender   message + author
│   ├── ChatResponse               result of getMessages()
│   └── ChatMessageFilter          narrow getMessages results
│
└── telegram/                  ← Telegram implementation
    ├── TelegramChatConfig         token + polling options
    └── TelegramChat               ChatApi over televerse
                                   (future: WhatsApp, Signal)
```

`ChatApi.connect(settings)` reads the `ChatSettings`, builds the matching
`ChatConfig` (today: `TelegramChatConfig`), and calls its `createApi` +
`initialize`. Application code only ever touches the abstract core types.

| Type | Role |
| ---- | ---- |
| `ChatApi` | Abstract send/receive contract + `connect` factory |
| `ChatSettings` | Platform-agnostic, auto-detected connection settings |
| `ChatConfig` | Base class a platform config extends |
| `ChatReceiver` | Addresses a user, username, phone, or group |
| `ChatReceiverInfo` | Profile details for a receiver |
| `ChatMessage` | A sent or received message |
| `ChatSender` | The author of a message |
| `ChatMessageType` | Enum of message kinds |
| `ChatAttachment` / `ChatAttachmentType` | Files, images, etc. on a message |
| `ChatResponse` | Result of `getMessages`, with query helpers |
| `ChatResponseStatus` | Outcome enum (`ok`, `timeout`, `authError`, …) |
| `ChatMessageFilter` | Filter for `getMessages` |
| `TelegramChatConfig` | Telegram token + polling configuration |

---

## Troubleshooting

### "Conflict: terminated by other getUpdates request"

Only one polling connection can be active per bot token. Make sure you don't
have another instance running and that previous bot instances were stopped
cleanly.

### Bot not receiving messages

1. Message the bot first — bots cannot initiate chats.
2. Confirm polling is enabled: `ChatSettings.telegram(token, usePolling: true)`.
3. Verify the token is correct.

### Getting chat / user IDs

Print incoming message details:

```dart
api.onMessage.listen((msg) {
  print('Chat ID: ${msg.sender.id}');
  print('Message ID: ${msg.platformMessageId}');
});
```

### Bot privacy settings (groups)

By default, bots in groups only see messages that start with `/`, reply to the
bot, or mention it. To see all messages, disable privacy mode:

1. Go to [@BotFather](https://t.me/BotFather).
2. Send `/setprivacy`.
3. Choose your bot.
4. Select "Disable".

---

## Ecosystem

`tom_chattools` is one of the foundational packages under
[`tom_ai/basics/`](../). All `tom_ai/basics/` packages share a single
repository, [`tom_basics`](https://github.com/al-the-bear/tom_basics).

It underpins higher-level Tom features that talk to users over chat — for
example the **Tom Telegram** bot integration (assistant chat, reminders, and
build notifications) builds on this abstraction so the same code can target
other messengers as their implementations land.

---

## Further documentation

- [LICENSE](LICENSE) — BSD-3-Clause licence text.
- [Telegram Bot API](https://core.telegram.org/bots/api) — the underlying API.
- [`televerse`](https://pub.dev/packages/televerse) — the Telegram client library.
- [BotFather commands](https://core.telegram.org/bots#6-botfather) — bot administration.
- Source library docs — every public type in `lib/src/` carries dartdoc.

---

## Status

Stable (`1.0.2`). Telegram is fully implemented; `ChatSettings` reserves
WhatsApp and Signal slots for future backends. The public API is
platform-agnostic, so adding a backend does not change application code.
`dart analyze` is clean.
