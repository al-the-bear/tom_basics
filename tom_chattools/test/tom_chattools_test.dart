import 'package:tom_chattools/tom_chattools.dart';
import 'package:test/test.dart';

void main() {
  group('ChatReceiver', () {
    test('creates ID receiver', () {
      final receiver = ChatReceiver.id('123456');
      expect(receiver.type, equals(ChatReceiverType.id));
      expect(receiver.value, equals('123456'));
    });

    test('creates username receiver', () {
      final receiver = ChatReceiver.username('testuser');
      expect(receiver.type, equals(ChatReceiverType.username));
      expect(receiver.value, equals('testuser'));
    });
  });

  group('ChatMessage', () {
    test('creates text message', () {
      final message = ChatMessage.text('Hello');
      expect(message.text, equals('Hello'));
      expect(message.type, equals(ChatMessageType.text));
    });
  });

  group('ChatResponse', () {
    test('empty response', () {
      const response = ChatResponse.empty();
      expect(response.hasMessages, isFalse);
      expect(response.success, isTrue);
    });

    test('error response', () {
      final response = ChatResponse.error('Test error');
      expect(response.success, isFalse);
      expect(response.error, equals('Test error'));
    });
  });

  group('TelegramChatConfig', () {
    test('creates config with token', () {
      final config = TelegramChatConfig(token: 'test_token');
      expect(config.platform, equals('telegram'));
      expect(config.token, equals('test_token'));
      expect(config.usePolling, isTrue);
    });
  });
}
