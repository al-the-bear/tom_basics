/// Example 03 — Sending messages.
///
/// The contract offers two ways out: [ChatApi.sendMessage] for the common case
/// (plain text plus an optional `parseMode`), and [ChatApi.send] for a fully
/// built [ChatMessage] when you need to control type, attachments, or raw
/// platform data. Both return the *stored* message — the transport stamps it
/// with an id and marks the sender as self, exactly as a real platform does.
///
/// The mock records every outgoing message in [MockChatApi.sentMessages], which
/// is the natural assertion surface in a test.
library;

import 'package:tom_chattools/tom_chattools.dart';
import 'package:tom_chattools_sample/mock_chat.dart';

Future<void> main() async {
  final mock = MockChatApi();
  await mock.initialize();
  final to = ChatReceiver.id('42');

  // sendMessage: the simple path. parseMode rides along in rawData.
  final a = await mock.sendMessage(to, 'plain hello', parseMode: 'Markdown');
  print('a.id=${a.id} self=${a.sender.isSelf} type=${a.type.name} '
      'parseMode=${a.rawData?['parseMode']}');

  // send: hand over a pre-built message. ChatMessage.text is the quick builder;
  // the transport re-stamps id/sender/timestamp on the stored copy.
  final b = await mock.send(to, ChatMessage.text('built elsewhere'));
  print('b.id=${b.id} self=${b.sender.isSelf} text=${b.text}');

  // Everything sent is recorded, in order, for assertions.
  print('sent count: ${mock.sentMessages.length}');
  print('sent texts: ${mock.sentMessages.map((m) => m.text).toList()}');

  await mock.disconnect();

  // expected output:
  // a.id=m1 self=true type=text parseMode=Markdown
  // b.id=m2 self=true text=built elsewhere
  // sent count: 2
  // sent texts: [plain hello, built elsewhere]
}
