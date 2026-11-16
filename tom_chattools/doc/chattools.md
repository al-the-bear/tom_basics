# Tom Chattools — User Guide

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause, see [LICENSE](../LICENSE).

This guide describes how Tom Chattools behaves once connected: how a connection
is made, how messages come in and go out, what the Telegram backend does with
each call, and which errors and limits to plan for. The [README](../README.md)
covers installation, bot setup and the first steps.

Everything is imported from the single library:

```dart
import 'package:tom_chattools/tom_chattools.dart';
```

---

## 1. Concepts

| Concept | Type | Meaning |
| ------- | ---- | ------- |
| **Connection** | `ChatApi` | One live connection to one messenger account (for Telegram: one bot token). |
| **Settings** | `ChatSettings` | String key/value pairs plus polling options; the keys present decide the platform. |
| **Receiver** | `ChatReceiver` | Whom a call addresses: an id, a username, a phone number or a group id. |
| **Message** | `ChatMessage` | A message sent or received, with its `ChatSender`, `ChatMessageType` and `ChatAttachment`s. |
| **Response** | `ChatResponse` | What `getMessages` collected, with a `ChatResponseStatus`. |
| **Filter** | `ChatMessageFilter` | Narrows what `getMessages` collects. |

Telegram is the one backend implemented. `ChatSettings` defines keys for
WhatsApp (`whatsappToken`) and Signal (`signalPhone`), but `ChatApi.connect`
has no backend for them.

---

## 2. Connecting

### 2.1 `ChatApi.connect`

`ChatApi.connect(settings)` looks at the settings and builds the backend:

- when `settings` holds `ChatSettings.telegramToken`, it creates a Telegram
  connection, calls `initialize()` on it and returns it;
- otherwise it throws `UnsupportedError('No supported platform detected. ...')`.

`ChatSettings.detectedPlatform` answers the platform name the keys point to
(`telegram`, `whatsapp`, `signal` or `null`) without connecting.

```dart
final settings = ChatSettings.telegram(
  token,
  pollingTimeout: const Duration(seconds: 25),
);
print(settings.detectedPlatform); // telegram
final api = await ChatApi.connect(settings);
print(api.platform); // telegram
print(api.isConnected); // true
```

`connect` does not contact Telegram. A wrong token is noticed at the first
call that reaches the Bot API (for example `sendMessage`, which then throws);
the background poll keeps retrying it silently (section 3.1).

### 2.2 Settings

| Setting | Where | Default | Effect |
| ------- | ----- | ------- | ------ |
| Bot token | `ChatSettings.telegramToken` key, or `ChatSettings.telegram(token)` | — | Required for Telegram. |
| API root | `ChatSettings.telegramApiBaseUrl` key | `https://api.telegram.org` | A local Bot API server or a test double. |
| `usePolling` | constructor argument | `true` | Whether incoming messages are fetched at all (section 3). |
| `pollingTimeout` | constructor argument | `2 s` | The long-poll timeout of each `getUpdates` call, in whole seconds. |

A local Bot API server is set through the map form:

```dart
final settings = ChatSettings({
  ChatSettings.telegramToken: token,
  ChatSettings.telegramApiBaseUrl: 'http://localhost:8081',
});
```

`pollingTimeout` is passed to Telegram in whole seconds, so a value below one
second becomes `0`, which turns the long poll into short polling.

### 2.3 Building the backend from its config

`TelegramChatConfig` holds everything the Telegram backend reads, including
`allowedUpdates` (the update types `getUpdates` asks for), which `ChatSettings`
has no key for. To use it, create the connection from the config yourself; this
is what `connect` does internally:

```dart
final config = TelegramChatConfig(
  token: token,
  pollingTimeout: 25,
  allowedUpdates: const ['message'],
);
final api = config.createApi(ChatSettings.telegram(token));
await api.initialize();
```

The `ChatSettings` passed to `createApi` is stored on `api.settings`; the
backend itself reads only the config.

---

## 3. Receiving messages

### 3.1 The poll

With `usePolling: true`, `initialize()` starts a background loop that runs until
`disconnect()`:

1. Call `getMe` once, to learn the bot's own id (used for `ChatSender.isSelf`).
   A failure here is ignored.
2. Call `getUpdates` with the current offset, `timeout` = `pollingTimeout` and
   `limit` = 100.
3. For every update that carries a `message`, convert it to a `ChatMessage` and
   add it to `onMessage`. Advance the offset past every update seen, so each
   update is delivered once.
4. On any error, wait two seconds and go back to step 2.

Only the `message` field of an update is read. Edited messages, channel posts,
callback queries and the other update kinds are skipped (they still advance the
offset).

With `usePolling: false` nothing is fetched: `onMessage` never emits and
`getMessages` always ends with a timeout. Use it for a send-only connection.

Telegram allows one `getUpdates` consumer per bot token. Two processes polling
the same token take updates from each other; see the README's
*Troubleshooting*.

### 3.2 `onMessage`

`onMessage` is a broadcast stream. A message is delivered to the listeners that
are subscribed when it arrives; there is no buffer, so a message that arrives
while nobody listens is gone. Subscribe before you send something you expect an
answer to. `disconnect()` closes the stream, which ends every subscription.

### 3.3 `getMessages`

`getMessages(receiver, {maxWait, minWait, interval, filter})` subscribes to
`onMessage` for the duration of the call and collects matching messages:

- it returns as soon as at least one message was collected **and** `minWait`
  has passed;
- it returns at `maxWait` at the latest;
- `interval` is how often it checks those two conditions; it does not change
  how often Telegram is polled.

Only messages that arrive during the call are seen. The Telegram backend keeps
a message when its **sender** matches the receiver:

| Receiver | Kept when |
| -------- | --------- |
| `ChatReceiver.id(x)` | `message.sender.id == x` |
| `ChatReceiver.username(u)` | `message.sender.username == u` (a leading `@` is ignored) |
| `ChatReceiver.group(g)` | `message.sender.id == g` |
| `ChatReceiver.phone(p)` | never |

In a 1:1 chat the user id and the chat id are the same, so `ChatReceiver.id`
works for both sending and receiving. In a group the sender is a user, not the
group, so `ChatReceiver.group` collects nothing; listen to `onMessage` and
compare `message.rawData?['telegram_chat_id']` with the group id instead.

The filter then applies, all given conditions together:

| `ChatMessageFilter` field | Kept when |
| ------------------------- | --------- |
| `from` | some receiver in the list has `value == message.sender.id` |
| `types` | `message.type` is in the list |
| `after` | `message.timestamp` is not before it |

The result:

| Outcome | `status` | `success` | `messages` |
| ------- | -------- | --------- | ---------- |
| Messages collected | `ok` | `true` | the messages, in arrival order |
| Nothing by `maxWait` | `timeout` | `true` | empty |

`waitDuration` says how long the call waited. The other statuses of
`ChatResponseStatus` (`noMessages`, `connectionError`, `authError`,
`rateLimited`, `error`) and `ChatResponse.error(...)` exist for backends to use;
the Telegram backend does not return them.

```dart
final response = await api.getMessages(
  ChatReceiver.id(chatId),
  maxWait: const Duration(seconds: 60),
  filter: const ChatMessageFilter(types: [ChatMessageType.text]),
);
switch (response.status) {
  case ChatResponseStatus.ok:
    print(response.textContent.join('\n'));
  case ChatResponseStatus.timeout:
    print('no answer within ${response.waitDuration.inSeconds} s');
  default:
    print('failed: ${response.error}');
}
```

### 3.4 What a received message holds

| Field | Telegram source |
| ----- | --------------- |
| `id`, `platformMessageId` | `message_id`, as text |
| `text` | `text`, else `caption` (a message with an attachment) |
| `sender.id`, `sender.username` | `from.id`, `from.username` (`unknown` id when there is no `from`) |
| `sender.name` | `from.first_name` and `from.last_name`, joined by a space |
| `sender.isSelf` | true for a message from this bot itself |
| `timestamp` | `date` (Unix seconds), as a local `DateTime` |
| `replyToMessageId` | `reply_to_message.message_id` |
| `type` | the first of photo, video, audio, voice, document, sticker, location, contact, text present; else `unknown` |
| `attachments` | photo (largest size), document, video, audio, voice |
| `rawData['telegram_message']` | the Bot API `Message` as received |
| `rawData['telegram_chat_id']` | `chat.id`, as text |

Voice notes have type `audio`. Stickers, locations and contacts set the type
but carry no attachment; their data is in `rawData['telegram_message']`.

An attachment's `url` holds the Telegram **file id**, not a URL.

### 3.5 Downloading an attachment

`downloadAttachment(attachment)` calls `getFile` for the file id and downloads
the bytes from the file endpoint. It answers `null` when the file id is empty,
when Telegram refuses the call, or on an I/O error. The Bot API limits
downloads to files of up to 20 MB (on `api.telegram.org`).

```dart
api.onMessage.listen((message) async {
  for (final attachment in message.attachments) {
    final bytes = await api.downloadAttachment(attachment);
    print('${attachment.fileName}: ${bytes?.length ?? 'not available'}');
  }
});
```

---

## 4. Sending messages

### 4.1 Addressing

The Telegram backend turns a receiver into the Bot API's `chat_id`:

| Receiver | `chat_id` sent | Failure |
| -------- | -------------- | ------- |
| `ChatReceiver.id('123')` | the number `123` | `FormatException` when the value is not an integer |
| `ChatReceiver.group('-100…')` | the number | as above |
| `ChatReceiver.username('name')` | `@name` (an `@` is added when missing) | — |
| `ChatReceiver.phone(...)` | — | `UnsupportedError`: the Bot API cannot send by phone number |

Telegram accepts `@username` only for public channels and groups; a private
user is addressed by id. A bot can only write to a user who has started a chat
with it.

### 4.2 `sendMessage`

`sendMessage(receiver, text, {parseMode})` calls `sendMessage` and answers a
`ChatMessage` with the new message id, `sender` = `ChatSender.self()` and the
local time as `timestamp`. `parseMode` is matched without regard to case:
`markdown`, `markdownv2` and `html` become Telegram's `Markdown`, `MarkdownV2`
and `HTML`; any other value sends the text unformatted.

```dart
await api.sendMessage(
  ChatReceiver.id(chatId),
  '<b>Build 412</b> passed',
  parseMode: 'html',
);
```

Text with `MarkdownV2` must escape Telegram's reserved characters; an unescaped
one makes Telegram refuse the call.

### 4.3 `send` with attachments

`send(receiver, message)` sends a `ChatMessage` you build:

- without attachments, it sends `message.text` through `sendMessage` (no parse
  mode);
- with attachments, it uploads each one as its own Telegram message, in order,
  each with `message.text` as caption, and answers a `ChatMessage` of type
  `document` whose `id` is the local time in milliseconds;
- with neither text nor attachments, it throws `UnsupportedError`.

For an outgoing attachment, `url` is the **path of a local file**. The type
picks the upload method:

| `ChatAttachmentType` | Bot API method |
| -------------------- | -------------- |
| `image` | `sendPhoto` |
| `video` | `sendVideo` |
| `audio` | `sendAudio` |
| any other | `sendDocument` |

`fileName` is the name Telegram shows; it defaults to the file's own name.

```dart
await api.send(
  ChatReceiver.id(chatId),
  ChatMessage(
    id: '',
    text: 'Nightly report',
    sender: const ChatSender.self(),
    timestamp: DateTime.now(),
    attachments: const [
      ChatAttachment(
        type: ChatAttachmentType.document,
        url: 'build/report.pdf',
        fileName: 'report.pdf',
      ),
    ],
  ),
);
```

`ChatMessage.text('...')` is the short form for a text-only message.

---

## 5. Errors

| Situation | What happens |
| --------- | ------------ |
| No supported platform in the settings | `connect` throws `UnsupportedError` |
| Telegram refuses a call (`ok: false`) or answers something that is not a Bot API answer | `sendMessage` / `send` throw `TelegramApiException` |
| Network failure while sending | the `dart:io` error (`SocketException`, ...) propagates |
| Non-numeric id or group receiver | `FormatException` |
| Phone receiver | `UnsupportedError` |
| Error while polling | swallowed; the poll retries after two seconds |
| Failed attachment download | `downloadAttachment` answers `null` |

`TelegramApiException` carries `method` (for example `sendMessage`),
`errorCode` (Telegram's `error_code`, else the HTTP status) and `description`
(Telegram's text). Its type is declared in
`package:tom_chattools/src/telegram/chat/telegram_bot_client.dart`; the public
library does not export it, so code that catches it by type imports that file
(which the `implementation_imports` lint reports in another package):

```dart
import 'package:tom_chattools/src/telegram/chat/telegram_bot_client.dart'
    show TelegramApiException;

try {
  await api.sendMessage(ChatReceiver.id(chatId), text);
} on TelegramApiException catch (e) {
  if (e.errorCode == 429) {
    // Rate limited: Telegram's description says how long to wait.
  }
  print('${e.method} refused: ${e.description}');
}
```

Telegram's own rate limits apply (roughly one message per second per chat and
20 per minute per group); the backend does not throttle or retry sends.

---

## 6. Other calls

- `getReceiverInfo(receiver)` answers `null` on Telegram: the backend does not
  look up profiles.
- `disconnect()` stops the poll, closes `onMessage` and closes the HTTP
  connections; a long poll in flight ends at once. Afterwards `isConnected` is
  `false`. Create a new connection to continue.

---

## 7. Writing another backend

A backend is a `ChatConfig` subclass whose `createApi(settings)` returns a
`ChatApi` subclass implementing the abstract members (`isConnected`,
`platform`, `initialize`, `sendMessage`, `send`, `getMessages`, `onMessage`,
`getReceiverInfo`, `downloadAttachment`, `disconnect`). `ChatApi.connect` knows
only the Telegram backend, so a separate backend is created through its config
as in section 2.3: `config.createApi(settings)`, then `initialize()`.

---

## 8. See also

- [README](../README.md) — installation, bot setup, quick start,
  troubleshooting.
- [`example/tom_chattools_example.dart`](../example/tom_chattools_example.dart)
  — connect, send, and wait for replies.
- [Telegram Bot API](https://core.telegram.org/bots/api) — the API the backend
  calls.
- [CHANGELOG](../CHANGELOG.md).
