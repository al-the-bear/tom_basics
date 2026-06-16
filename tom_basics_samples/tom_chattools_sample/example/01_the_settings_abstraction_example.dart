/// Example 01 — The settings abstraction.
///
/// Before any messages flow, `tom_chattools` has to answer one question: *which
/// platform am I talking to?* It answers it from [ChatSettings] — a small,
/// string-keyed configuration bag. A token under `TELEGRAM_TOKEN` means
/// "Telegram"; a phone under `SIGNAL_PHONE` means "Signal"; and so on. The real
/// `ChatApi.connect` factory reads exactly this to decide which concrete
/// transport to build.
///
/// This first example stays entirely in that configuration layer — no transport,
/// no I/O. It shows what the factory dispatches on, which is also *why* a
/// token-free mock transport is possible: the contract above settings is
/// platform-agnostic.
library;

import 'package:tom_chattools/tom_chattools.dart';

void main() {
  // A settings bag is just a typed view over a string map. The named factory
  // fills in the conventional key for you.
  final telegram = ChatSettings.telegram('123:ABC-bot-token');
  print('telegram detected as: ${telegram.detectedPlatform}');
  print('  has TELEGRAM_TOKEN: ${telegram.has(ChatSettings.telegramToken)}');
  print('  token value:        ${telegram[ChatSettings.telegramToken]}');

  // The same bag recognises other platforms by their conventional keys.
  const whatsapp = ChatSettings({ChatSettings.whatsappToken: 'wa-secret'});
  print('whatsapp detected as: ${whatsapp.detectedPlatform}');

  const signal = ChatSettings({ChatSettings.signalPhone: '+15550100'});
  print('signal detected as:   ${signal.detectedPlatform}');

  // A bag with no recognised key detects nothing — the real factory would throw
  // UnsupportedError here. Our mock transport sidesteps the factory entirely and
  // is constructed directly, so it needs no recognised platform key at all.
  const mock = ChatSettings({'MOCK_TRANSPORT': 'memory'});
  print('mock detected as:     ${mock.detectedPlatform}');

  // expected output:
  // telegram detected as: telegram
  //   has TELEGRAM_TOKEN: true
  //   token value:        123:ABC-bot-token
  // whatsapp detected as: whatsapp
  // signal detected as:   signal
  // mock detected as:     null
}
