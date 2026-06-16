/// Example 05 — Filtering messages.
///
/// There are two places to narrow a stream of inbound messages, and they
/// compose:
///
///   * **At the transport**, via [ChatMessageFilter] passed to
///     [ChatApi.getMessages]. The mock only *consumes* messages that match, so
///     a later, differently-filtered read still sees what an earlier read left
///     behind. This is the "give me only images" / "only from Ada" selection.
///   * **Within a batch**, via [ChatResponse] views — `fromSender`, `ofType`,
///     `textContent`. These are pure, read-only slices over a batch you already
///     have in hand.
///
/// This example does both over a small scripted feed.
library;

import 'package:tom_chattools/tom_chattools.dart';
import 'package:tom_chattools_sample/mock_chat.dart';

/// A fixed clock so the scripted timestamps are reproducible.
DateTime t(int seconds) =>
    DateTime.utc(2026, 1, 1).add(Duration(seconds: seconds));

Future<void> main() async {
  final mock = MockChatApi();
  await mock.initialize();

  final team = ChatReceiver.group('team');
  const ada = ChatSender(id: 'ada', name: 'Ada');
  const bob = ChatSender(id: 'bob', name: 'Bob');

  mock.enqueueIncoming(
      team, ChatMessage(id: 'x1', text: 'morning', sender: ada, timestamp: t(1)));
  mock.enqueueIncoming(
      team,
      ChatMessage(
          id: 'x2',
          text: 'see attached',
          sender: bob,
          timestamp: t(2),
          type: ChatMessageType.image));
  mock.enqueueIncoming(
      team, ChatMessage(id: 'x3', text: 'lunch?', sender: ada, timestamp: t(3)));

  // Transport-level filter by type: only the image is consumed.
  final images = await mock.getMessages(team,
      filter: const ChatMessageFilter(types: [ChatMessageType.image]));
  print('images:      ${images.textContent}');

  // Transport-level filter by sender: Ada's two texts remain, and now match.
  final fromAda = await mock.getMessages(team,
      filter: ChatMessageFilter(from: [ChatReceiver.id('ada')]));
  print('from ada:    ${fromAda.textContent}');

  // Batch-level views over a single unfiltered read.
  final inbox = ChatReceiver.id('inbox');
  mock.enqueueIncoming(
      inbox, ChatMessage(id: 'y1', text: 'note', sender: ada, timestamp: t(4)));
  mock.enqueueIncoming(
      inbox,
      ChatMessage(
          id: 'y2',
          text: 'photo',
          sender: bob,
          timestamp: t(5),
          type: ChatMessageType.image));
  final batch = await mock.getMessages(inbox);
  print('all:         ${batch.textContent}');
  print('fromSender:  ${batch.fromSender('ada').map((m) => m.text).toList()}');
  print('ofType img:  '
      '${batch.ofType(ChatMessageType.image).map((m) => m.text).toList()}');

  await mock.disconnect();

  // expected output:
  // images:      [see attached]
  // from ada:    [morning, lunch?]
  // all:         [note, photo]
  // fromSender:  [note]
  // ofType img:  [photo]
}
