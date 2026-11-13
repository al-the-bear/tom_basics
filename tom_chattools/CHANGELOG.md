## 2.0.0

- **No third-party dependency.** The Telegram backend calls the Bot API over
  HTTP itself (`dart:io`): long polling with `getUpdates`, `sendMessage`, the
  `sendDocument` / `sendPhoto` / `sendVideo` / `sendAudio` uploads, `getFile`.
  `televerse` is gone, and with it `freezed` 3, which held the analyzer below
  13 and kept every package taking `tom_chattools` off a current `tom_d4rt`.
- **Breaking:** `ChatMessage.rawData['telegram_message']` is the Bot API
  `Message` as JSON (a `Map`), no longer a televerse `Message` object.
- `rawData['telegram_chat_id']`: the chat a message came from (in a group not
  the sender's id).
- A message the bot sent itself is marked `isSelf` (the bot's id from `getMe`).
- `TelegramChatConfig.apiBaseUrl` and `ChatSettings.telegramApiBaseUrl`: a
  local Bot API server or a test double instead of `https://api.telegram.org`.
- A refused Bot API call throws `TelegramApiException` (`method`, `errorCode`,
  `description`).
- No more debug output on stdout for every received message.

## 1.0.2

- Moved to tom_module_basics repository (from tom_module_communication).
- Updated repository and homepage URLs in pubspec.yaml.

## 1.0.1

- Changed license from MIT to BSD-3-Clause.

## 1.0.0

- Initial public release.
- Abstract `ChatApi` interface for platform-agnostic messaging.
- `ChatMessage`, `ChatReceiver`, `ChatResponse`, `ChatSettings` data models.
- Telegram implementation via `TelegramChat` with polling-based message reception.
- Support for text messages, photos, documents, audio, video, and voice attachments.
- `ChatConfig` and `TelegramChatConfig` for platform-specific configuration.
