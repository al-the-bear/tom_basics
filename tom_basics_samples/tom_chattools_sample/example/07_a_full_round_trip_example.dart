/// Example 07 — A full round trip.
///
/// Everything together, end to end. We address a receiver by identity
/// ([ChatReceiver] comes in `id` / `username` / `phone` / `group` flavours),
/// look up their profile with [ChatApi.getReceiverInfo], and hold a two-turn
/// conversation — each outgoing message draws a scripted reply because the mock
/// was built with an `autoResponder`.
///
/// Note that every line here talks only to the abstract [ChatApi] surface
/// (`getReceiverInfo`, `sendMessage`, `getMessages`). The auto-reply scripting
/// is a property of *this* transport; a real platform would supply the replies
/// over the network instead. The consumer code would not change.
library;

import 'package:tom_chattools/tom_chattools.dart';
import 'package:tom_chattools_sample/mock_chat.dart';

Future<void> main() async {
  // The mock answers every sent message with a scripted reply.
  final ChatApi api = MockChatApi(
    autoResponder: (sent) => 'You said: ${sent.text}',
  );
  await api.initialize();

  // Receivers are typed identities. The flavour is preserved.
  final alice = ChatReceiver.username('alice');
  print('id flavour:       ${ChatReceiver.id('42').type.name}');
  print('username flavour: ${alice.type.name} -> ${alice.value}');

  // Register and read back a profile.
  (api as MockChatApi).setReceiverInfo(
    alice,
    const ChatReceiverInfo(id: 'alice', name: 'Alice', username: 'alice'),
  );
  final info = await api.getReceiverInfo(alice);
  print('receiver:         ${info?.name} (@${info?.username})');

  // Turn one.
  await api.sendMessage(alice, 'Hello, bot');
  final reply1 = await api.getMessages(alice);
  print('turn 1 status:    ${reply1.status.name}');
  print('turn 1 reply:     ${reply1.textContent}');

  // Turn two.
  await api.sendMessage(alice, 'Ping');
  final reply2 = await api.getMessages(alice);
  print('turn 2 reply:     ${reply2.textContent}');

  await api.disconnect();

  // expected output:
  // id flavour:       id
  // username flavour: username -> alice
  // receiver:         Alice (@alice)
  // turn 1 status:    ok
  // turn 1 reply:     [You said: Hello, bot]
  // turn 2 reply:     [You said: Ping]
}
