/// Example 06 — The message stream.
///
/// Polling with [ChatApi.getMessages] is the pull model. [ChatApi.onMessage] is
/// the push model: a [Stream] that emits each inbound message live, while the
/// transport is connected. It is a *broadcast* stream — it has no buffer, so an
/// event emitted while nobody is listening is simply dropped.
///
/// That timing detail matters and is easy to get wrong: you must subscribe
/// **before** the messages arrive. The idiom below — `onMessage.take(n).toList()`
/// — subscribes the moment it is called, returning a future that completes once
/// `n` events have been seen. We start it, *then* enqueue, *then* await.
library;

import 'package:tom_chattools/tom_chattools.dart';
import 'package:tom_chattools_sample/mock_chat.dart';

Future<void> main() async {
  final mock = MockChatApi();
  await mock.initialize();
  final from = ChatReceiver.id('42');

  // Subscribe first: take(3) attaches a listener now and resolves after three
  // events. We do NOT await it yet — we hold the future.
  final collected = mock.onMessage.take(3).toList();

  // Now produce three live events. Each enqueue, while connected, is emitted.
  mock.receiveText(from, 'event one');
  mock.receiveText(from, 'event two');
  mock.receiveText(from, 'event three');

  // Await the collector: it already has its three.
  final messages = await collected;
  print('received ${messages.length} live events:');
  for (final m in messages) {
    print('  - ${m.text}');
  }

  await mock.disconnect();

  // expected output:
  // received 3 live events:
  //   - event one
  //   - event two
  //   - event three
}
