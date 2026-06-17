// Aggregator: runs every tom_chattools example and reports a pass/fail tally.
//
// Every example drives an in-memory MockChatApi — no network, no tokens, no
// sleeps — so they compose cleanly here. We call them in declaration order,
// catch any throw, and exit non-zero if any example fails: the single command
// CI needs to verify the whole sample stays green.
//
// Run with: dart run example/run_all_examples.dart
import 'dart:async';

import '01_the_settings_abstraction_example.dart' as ex01;
import '02_one_api_any_transport_example.dart' as ex02;
import '03_sending_messages_example.dart' as ex03;
import '04_receiving_messages_example.dart' as ex04;
import '05_filtering_messages_example.dart' as ex05;
import '06_the_message_stream_example.dart' as ex06;
import '07_a_full_round_trip_example.dart' as ex07;

Future<void> main() async {
  final examples = <String, FutureOr<void> Function()>{
    '01_the_settings_abstraction': ex01.main,
    '02_one_api_any_transport': ex02.main,
    '03_sending_messages': ex03.main,
    '04_receiving_messages': ex04.main,
    '05_filtering_messages': ex05.main,
    '06_the_message_stream': ex06.main,
    '07_a_full_round_trip': ex07.main,
  };

  var passed = 0;
  var failed = 0;

  for (final entry in examples.entries) {
    print('\n=== ${entry.key} ===');
    try {
      await entry.value();
      passed++;
    } catch (e, st) {
      failed++;
      print('FAILED: $e');
      print(st);
    }
  }

  print('\n----------------------------------------');
  print('$passed passed, $failed failed');
  if (failed > 0) {
    throw StateError('$failed example(s) failed');
  }
}
