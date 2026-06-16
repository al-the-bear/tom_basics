/// Example 04 — Receiving messages.
///
/// Inbound traffic arrives through [ChatApi.getMessages], which returns a
/// [ChatResponse]: a batch of messages plus a [ChatResponseStatus] describing
/// *why* the batch looks the way it does. A non-empty batch is `ok`; an empty
/// poll is `noMessages` (a real platform would have waited and timed out — the
/// mock reports the honest "nothing queued" status).
///
/// We script inbound traffic with the mock's [MockChatApi.receiveText] helper,
/// then drain it. `ChatResponse` exposes convenience views — `count`,
/// `textContent` — so consumers rarely touch the raw list.
library;

import 'package:tom_chattools/tom_chattools.dart';
import 'package:tom_chattools_sample/mock_chat.dart';

Future<void> main() async {
  final mock = MockChatApi();
  await mock.initialize();
  final from = ChatReceiver.id('42');

  // Script two inbound messages, as if the receiver had sent them.
  mock.receiveText(from, 'hi there', senderName: 'Ada');
  mock.receiveText(from, 'are you receiving?', senderName: 'Ada');

  final response = await mock.getMessages(from);
  print('status:   ${response.status.name}');
  print('count:    ${response.count}');
  print('texts:    ${response.textContent}');
  print('hasMore:  ${response.hasMore}');

  // Draining again finds nothing left: an honest noMessages.
  final empty = await mock.getMessages(from);
  print('2nd poll: ${empty.status.name} (count ${empty.count})');

  await mock.disconnect();

  // expected output:
  // status:   ok
  // count:    2
  // texts:    [hi there, are you receiving?]
  // hasMore:  false
  // 2nd poll: noMessages (count 0)
}
