# tom_chattools — Unified Chat API Sample

> Part of the **Tom framework** by al-the-bear.
> © 2024–2026 Peter Nicolai Alexis Kyaw — BSD-3-Clause.

A runnable, article-grade walkthrough of [`tom_chattools`](../../tom_chattools/),
the library that lets application code send and receive chat messages **without
naming a platform**. The library ships a Telegram transport, but the lesson here
is the abstraction *above* it: your code depends only on the `ChatApi` contract,
and a platform is just one implementation of that contract.

To prove the point — and to run in CI with **no live tokens and no network** —
this sample implements a *second* `ChatApi`: an in-memory
[`MockChatApi`](lib/mock_chat.dart). Every example drives that mock, so the whole
send/receive abstraction runs **offline and instantly**. Swap the mock for the
real Telegram transport and not one line of the example consumer code would
change. That substitutability is the entire point.

> **Read the `tom_chattools` module manual first.** This README assumes you have
> skimmed [`tom_ai/basics/tom_chattools/README.md`](../../tom_chattools/README.md),
> which documents the platform transports, the settings keys, and the message
> model in full. Here we re-derive only what the examples need, and we spend our
> words on the *abstraction* rather than on any one platform.

> **Pairs with** the other `tom_basics_samples` walkthroughs. If you have not
> read one before, the
> [samples index](../README.md) lists them; each follows the same shape — a
> handful of one-concept example files plus a single aggregator that runs them
> all.

---

## The problem: a chat API that does not name a platform

Suppose you are writing a notification service. It needs to send a build report
to whoever asked for it and read back any replies. You could reach for the
Telegram Bot API directly — `televerse`, a bot token, long-polling, the works —
and most of your service would end up *being* Telegram glue. The day you add
WhatsApp, you rewrite it.

`tom_chattools` refuses that coupling. It defines one abstract contract,
`ChatApi`, with a small, platform-neutral surface:

```dart
abstract class ChatApi {
  late ChatSettings settings;
  bool get isConnected;
  String get platform;

  Future<void> initialize();
  Future<ChatMessage> sendMessage(ChatReceiver receiver, String text,
      {String? parseMode});
  Future<ChatMessage> send(ChatReceiver receiver, ChatMessage message);
  Future<ChatResponse> getMessages(ChatReceiver receiver,
      {Duration maxWait, Duration minWait, Duration interval,
       ChatMessageFilter? filter});
  Stream<ChatMessage> get onMessage;
  Future<ChatReceiverInfo?> getReceiverInfo(ChatReceiver receiver);
  Future<List<int>?> downloadAttachment(ChatAttachment attachment);
  Future<void> disconnect();
}
```

Your service talks only to those members. Telegram is one concrete subclass; the
shipped factory `ChatApi.connect(settings)` reads the [settings](#example-1--the-settings-abstraction),
sees a `TELEGRAM_TOKEN`, and hands you the Telegram implementation. Nothing in
your service names Telegram again.

### Why a mock — and why it is the lesson, not a shortcut

`ChatApi.connect` only knows how to build Telegram, and Telegram needs a real
bot token and a network. That makes it useless in CI and awkward in a tutorial.

But the contract does not care *how* a `ChatApi` is implemented. So instead of
mocking the network underneath Telegram, we write a whole new `ChatApi` that
keeps everything in memory:

```dart
class MockChatApi extends ChatApi { /* ... */ }
```

Any code typed to `ChatApi` runs against it unchanged. This is not a test
shortcut bolted onto the side — **it is a direct demonstration of what the
abstraction buys you.** If a second implementation of the contract is this easy
to write and substitute, then a third (WhatsApp, Signal, …) is a known quantity.
The mock is therefore both this sample's test harness and its central worked
example. It is documented in full under
[The mock transport, explained](#the-mock-transport-explained).

---

## What you will learn

Each example isolates one concept of the `tom_chattools` contract:

| # | Example | Concept |
|---|---------|---------|
| 1 | [`01_the_settings_abstraction`](example/01_the_settings_abstraction_example.dart) | `ChatSettings`: how a platform is *detected*, not hard-coded |
| 2 | [`02_one_api_any_transport`](example/02_one_api_any_transport_example.dart) | Consumer code typed to abstract `ChatApi`; connect / `platform` / disconnect |
| 3 | [`03_sending_messages`](example/03_sending_messages_example.dart) | `sendMessage` vs `send`; the stored `ChatMessage`; `parseMode` |
| 4 | [`04_receiving_messages`](example/04_receiving_messages_example.dart) | `getMessages` → `ChatResponse`; `count`, `textContent`, status |
| 5 | [`05_filtering_messages`](example/05_filtering_messages_example.dart) | `ChatMessageFilter` at the transport; `fromSender` / `ofType` in a batch |
| 6 | [`06_the_message_stream`](example/06_the_message_stream_example.dart) | `onMessage` push stream; subscribe-before-emit timing |
| 7 | [`07_a_full_round_trip`](example/07_a_full_round_trip_example.dart) | `ChatReceiver` identities, `getReceiverInfo`, a scripted conversation |

---

## Quick start

```bash
cd tom_ai/basics/tom_basics_samples/tom_chattools_sample
dart pub get

# Run a single concept:
dart run example/02_one_api_any_transport_example.dart

# Run all seven in order, with a pass/fail tally:
dart run example/run_all_examples.dart
```

The aggregator prints each example's output under a header and ends with a
tally; it exits non-zero if any example throws, which is the single command CI
needs:

```text
----------------------------------------
7 passed, 0 failed
```

---

## Layout

| Path | What it is |
|------|------------|
| [`lib/mock_chat.dart`](lib/mock_chat.dart) | `MockChatApi` — the in-memory `ChatApi` every example drives |
| [`example/01..07_*.dart`](example/) | One concept per file, each ending in a verbatim `// expected output` block |
| [`example/run_all_examples.dart`](example/run_all_examples.dart) | Aggregator: runs all seven, tallies, throws on failure |
| [`pubspec.yaml`](pubspec.yaml) | `publish_to: none`; path dependency on `../../tom_chattools` |

---

## The mock transport, explained

[`lib/mock_chat.dart`](lib/mock_chat.dart) is the heart of the sample — a
complete, in-memory implementation of `ChatApi`. It is worth reading in full,
because it shows exactly how much (little) a transport must do to satisfy the
contract. Three design choices make it a good worked example:

**1. It is constructed directly — there is no platform to detect.**

```dart
MockChatApi({
  ChatSettings? settings,
  String? Function(ChatMessage sent)? autoResponder,
}) : _autoResponder = autoResponder {
  this.settings = settings ?? const ChatSettings({'MOCK_TRANSPORT': 'memory'});
}
```

The real factory dispatches on settings keys; the mock skips the factory and is
`new`-ed up, so it needs no recognised platform token. The optional
`autoResponder` turns each sent message into a scripted reply, which is what lets
[example 7](#example-7--a-full-round-trip) hold a conversation.

**2. Every contract method is in-memory and synchronous.** Outgoing messages go
into a list; incoming messages are queued per receiver and drained on
`getMessages`; the live stream is a broadcast `StreamController`. Nothing sleeps
or reaches the network:

```dart
@override
Future<ChatMessage> sendMessage(ChatReceiver receiver, String text,
    {String? parseMode}) async {
  final message = ChatMessage(
    id: _nextId(),
    text: text,
    sender: const ChatSender.self(),
    timestamp: _stamp(),
    type: ChatMessageType.text,
    rawData: parseMode != null ? {'parseMode': parseMode} : null,
  );
  _sent.add(message);
  _maybeAutoRespond(receiver, message);
  return message;
}
```

**3. It is deterministic.** Generated ids are `m1`, `m2`, … and timestamps come
from a fixed monotonic clock (`DateTime.utc(2026, 1, 1)` plus one second per
stamp). That is why every `// expected output` block below can be checked
literally — there is nothing varying to print.

Alongside the contract, the mock exposes a small **scripting API** that is *not*
part of `ChatApi` — `sentMessages` (for assertions), `enqueueIncoming` /
`receiveText` (to script inbound traffic), `setReceiverInfo`, and
`putAttachment`. These are the test-harness affordances; the examples use them to
set up a scenario, then exercise the *contract* against it.

---

## Walkthrough

### Example 1 — The settings abstraction

Before any message flows, `tom_chattools` has to decide which platform it is
talking to. It decides from [`ChatSettings`](../../tom_chattools/lib/src/api/chat/chat_settings.dart) —
a string-keyed bag with conventional keys (`TELEGRAM_TOKEN`, `WHATSAPP_TOKEN`,
`SIGNAL_PHONE`). The `detectedPlatform` getter is exactly what the real factory
reads.

```dart
final telegram = ChatSettings.telegram('123:ABC-bot-token');
print('telegram detected as: ${telegram.detectedPlatform}');

const whatsapp = ChatSettings({ChatSettings.whatsappToken: 'wa-secret'});
print('whatsapp detected as: ${whatsapp.detectedPlatform}');

const mock = ChatSettings({'MOCK_TRANSPORT': 'memory'});
print('mock detected as:     ${mock.detectedPlatform}');
```

```text
telegram detected as: telegram
  has TELEGRAM_TOKEN: true
  token value:        123:ABC-bot-token
whatsapp detected as: whatsapp
signal detected as:   signal
mock detected as:     null
```

The last line is the hinge: a bag with no recognised key detects nothing, and
the real factory would throw `UnsupportedError`. Our mock sidesteps the factory
entirely, which is precisely why it needs no platform key — the contract above
settings is platform-agnostic.

### Example 2 — One API, any transport

The central idea, in code. A consumer function is typed to the abstract
`ChatApi`; it does not know or care which transport it drives:

```dart
Future<String> greet(ChatApi api, ChatReceiver to) async {
  final sent = await api.sendMessage(to, 'Hello!');
  return 'sent message ${sent.id} via ${api.platform}';
}
```

We hand it a `MockChatApi`. Because the mock *is-a* `ChatApi`, `greet` runs
unchanged:

```dart
final ChatApi api = MockChatApi();
await api.initialize();
final summary = await greet(api, ChatReceiver.id('42'));
print(summary);
await api.disconnect();
```

```text
connected: true
platform:  mock
sent message m1 via mock
connected: false
```

Replace `MockChatApi()` with `await ChatApi.connect(telegramSettings)` and
`greet` is still correct — only the construction line changed. That is the whole
return on the abstraction.

### Example 3 — Sending messages

The contract offers two ways out. [`sendMessage`](../../tom_chattools/lib/src/api/chat/chat_api.dart)
is the common path (plain text plus an optional `parseMode`);
[`send`](../../tom_chattools/lib/src/api/chat/chat_api.dart) takes a fully built
`ChatMessage` when you need control over type, attachments, or raw platform data.
Both return the *stored* message — the transport stamps it with an id and marks
the sender as self, just as a real platform does.

```dart
final a = await mock.sendMessage(to, 'plain hello', parseMode: 'Markdown');
final b = await mock.send(to, ChatMessage.text('built elsewhere'));
print('sent texts: ${mock.sentMessages.map((m) => m.text).toList()}');
```

```text
a.id=m1 self=true type=text parseMode=Markdown
b.id=m2 self=true text=built elsewhere
sent count: 2
sent texts: [plain hello, built elsewhere]
```

`parseMode` rides along in `rawData` — the contract has one neutral escape hatch
for per-platform options, and each transport interprets it. `sentMessages` is the
mock's recording surface; in a test it is where your assertions land.

### Example 4 — Receiving messages

Inbound traffic arrives through `getMessages`, which returns a
[`ChatResponse`](../../tom_chattools/lib/src/api/chat/chat_response.dart): a batch
of messages plus a `ChatResponseStatus` explaining *why* the batch looks the way
it does. A non-empty batch is `ok`; an empty poll is `noMessages`.

```dart
mock.receiveText(from, 'hi there', senderName: 'Ada');
mock.receiveText(from, 'are you receiving?', senderName: 'Ada');

final response = await mock.getMessages(from);
print('texts: ${response.textContent}');

final empty = await mock.getMessages(from);
print('2nd poll: ${empty.status.name} (count ${empty.count})');
```

```text
status:   ok
count:    2
texts:    [hi there, are you receiving?]
hasMore:  false
2nd poll: noMessages (count 0)
```

A real transport would *wait* up to `maxWait` for traffic and report `timeout`
on an empty poll; the mock has nothing to wait for, so it reports the honest
`noMessages`. `textContent` is a convenience view — the list of message texts —
so consumers rarely touch the raw messages.

### Example 5 — Filtering messages

There are two places to narrow inbound traffic, and they compose. **At the
transport**, a [`ChatMessageFilter`](../../tom_chattools/lib/src/api/chat/chat_api.dart)
passed to `getMessages` selects which messages are consumed — so a later,
differently-filtered read still sees what an earlier read left behind:

```dart
final images = await mock.getMessages(team,
    filter: const ChatMessageFilter(types: [ChatMessageType.image]));
final fromAda = await mock.getMessages(team,
    filter: ChatMessageFilter(from: [ChatReceiver.id('ada')]));
```

**Within a batch**, `ChatResponse` exposes pure read-only slices — `fromSender`,
`ofType`, `textContent` — over messages you already hold:

```dart
final batch = await mock.getMessages(inbox);
print('fromSender:  ${batch.fromSender('ada').map((m) => m.text).toList()}');
print('ofType img:  ${batch.ofType(ChatMessageType.image).map((m) => m.text).toList()}');
```

```text
images:      [see attached]
from ada:    [morning, lunch?]
all:         [note, photo]
fromSender:  [note]
ofType img:  [photo]
```

Transport-level filtering decides what leaves the queue; batch-level views slice
what you already received. Use the first to keep unrelated traffic queued, the
second to read one batch several ways.

### Example 6 — The message stream

`getMessages` is the pull model. [`onMessage`](../../tom_chattools/lib/src/api/chat/chat_api.dart)
is the push model: a `Stream` that emits each inbound message live. It is a
*broadcast* stream — it has no buffer, so an event emitted while nobody is
listening is dropped.

That timing detail is the lesson. You must subscribe **before** the messages
arrive. The `take(n).toList()` idiom subscribes the instant it is called and
returns a future that completes after `n` events:

```dart
final collected = mock.onMessage.take(3).toList(); // subscribe now
mock.receiveText(from, 'event one');               // then emit
mock.receiveText(from, 'event two');
mock.receiveText(from, 'event three');
final messages = await collected;                  // already has its three
```

```text
received 3 live events:
  - event one
  - event two
  - event three
```

Get the order wrong — enqueue first, subscribe second — and the events are gone.
The same rule applies to the real transports, which is why the mock reproduces it
faithfully rather than buffering.

### Example 7 — A full round trip

Everything together. We address a receiver by identity (`ChatReceiver` comes in
`id` / `username` / `phone` / `group` flavours), read their profile with
`getReceiverInfo`, and hold a two-turn conversation. Each outgoing message draws
a scripted reply because the mock was built with an `autoResponder`:

```dart
final ChatApi api = MockChatApi(
  autoResponder: (sent) => 'You said: ${sent.text}',
);
await api.initialize();

await api.sendMessage(alice, 'Hello, bot');
final reply1 = await api.getMessages(alice);
print('turn 1 reply: ${reply1.textContent}');
```

```text
id flavour:       id
username flavour: username -> alice
receiver:         Alice (@alice)
turn 1 status:    ok
turn 1 reply:     [You said: Hello, bot]
turn 2 reply:     [You said: Ping]
```

Every line talks only to the abstract `ChatApi` surface. The auto-reply is a
property of *this* transport; a real platform would deliver the replies over the
network instead — and the consumer code would not change.

---

## How this sample stays offline / CI-safe

The library's shipped factory needs a Telegram bot token and a live connection.
This sample never touches it. Instead:

- **A second `ChatApi` implementation.** `MockChatApi` satisfies the whole
  contract in memory. Consumer code typed to `ChatApi` cannot tell the
  difference, which is the abstraction working as designed.
- **No network, no sleeps.** Every method completes synchronously over in-memory
  collections; there is no polling delay and no socket.
- **Deterministic ids and clock.** Ids are `m1`, `m2`, …; timestamps advance one
  second from a fixed instant. Output is reproducible, so every
  `// expected output` block is checked literally and the aggregator's tally is
  stable across machines and CI.

The result: `dart run example/run_all_examples.dart` is hermetic and instant, and
its non-zero-on-failure exit is all CI needs.

---

## Concept reference

| API | Role | Seen in |
|-----|------|---------|
| `ChatApi` | The abstract transport contract | all |
| `ChatApi.connect` | Telegram-only factory (settings → transport) | discussed in 1–2 |
| `MockChatApi` | In-memory `ChatApi` implementation | all |
| `ChatSettings` | Platform detection from string keys | 1 |
| `ChatReceiver` | Typed recipient identity (id/username/phone/group) | 2, 5, 7 |
| `ChatMessage` / `ChatMessage.text` | A message; quick text builder | 3 |
| `ChatSender` / `ChatSender.self` | Who sent a message | 3 |
| `ChatMessageType` | text / image / … message kinds | 3, 5 |
| `ChatResponse` | A batch + status + convenience views | 4, 5, 7 |
| `ChatResponseStatus` | `ok` / `noMessages` / `timeout` / … | 4, 7 |
| `ChatMessageFilter` | Transport-level selection by type/sender/time | 5 |
| `onMessage` | Live broadcast stream of inbound messages | 6 |
| `getReceiverInfo` / `ChatReceiverInfo` | Profile lookup | 7 |
| `downloadAttachment` / `ChatAttachment` | Attachment bytes by url | mock |

---

## Where to go next

- Read [`tom_ai/basics/tom_chattools/README.md`](../../tom_chattools/README.md)
  for the real transports (Telegram today, more planned), the full settings keys,
  and the complete message and attachment model.
- Study [`lib/mock_chat.dart`](lib/mock_chat.dart) as a template: writing a new
  transport (a second or third platform) is the same exercise as writing the
  mock — implement the contract, nothing more.
- Browse the [samples index](../README.md) for the other `tom_basics` libraries,
  each with a walkthrough in this same shape.
