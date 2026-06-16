/// Example 02 — One API, any transport.
///
/// This is the central idea of `tom_chattools`: application code depends on the
/// abstract [ChatApi] contract, never on a concrete platform. Here a small
/// consumer function, [greet], is typed to `ChatApi`. It has no idea whether it
/// is driving Telegram or an in-memory mock — it just sends a message and reads
/// the assigned id back.
///
/// We hand it a [MockChatApi]. Because the mock *is-a* `ChatApi`, the consumer
/// runs unchanged. Swap in the real Telegram implementation and `greet` would
/// not change a line. That substitutability is the whole point.
library;

import 'package:tom_chattools/tom_chattools.dart';
import 'package:tom_chattools_sample/mock_chat.dart';

/// A transport-agnostic consumer. It only knows the [ChatApi] contract.
Future<String> greet(ChatApi api, ChatReceiver to) async {
  final sent = await api.sendMessage(to, 'Hello!');
  return 'sent message ${sent.id} via ${api.platform}';
}

Future<void> main() async {
  // Construct the mock directly — there is no platform to detect, so no token.
  final ChatApi api = MockChatApi();
  await api.initialize();
  print('connected: ${api.isConnected}');
  print('platform:  ${api.platform}');

  final summary = await greet(api, ChatReceiver.id('42'));
  print(summary);

  await api.disconnect();
  print('connected: ${api.isConnected}');

  // expected output:
  // connected: true
  // platform:  mock
  // sent message m1 via mock
  // connected: false
}
