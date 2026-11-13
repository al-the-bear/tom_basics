// The Telegram backend over its own Bot API client (2.0.0: no televerse), against a fake Bot API server on
// loopback that records every call and answers like Telegram.
//
//   TC-1 sendMessage: the JSON body (chat_id as a number or @username, the text, the parse mode named as the
//        Bot API spells it, none for an unknown one); the answer's message id
//   TC-2 polling: getMe, then getUpdates with the offset moving past each update; a message arrives on onMessage
//        with its text (else caption), sender, reply, type, the largest photo, and rawData with the message as
//        sent and its chat id; the bot's own message is isSelf
//   TC-3 an attachment is uploaded as multipart (sendDocument / sendPhoto ...): chat_id, caption, the file name
//        and the file's bytes
//   TC-4 downloadAttachment: getFile, then the file endpoint's bytes; a refused getFile answers null
//   TC-5 a refused call throws TelegramApiException with the method, Telegram's description and error code
//   TC-6 disconnect ends the polling: no call after it; ChatApi.connect takes the API root from the settings
//   TC-7 the package depends on nothing (no televerse)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_chattools/src/telegram/chat/telegram_chat.dart';
import 'package:tom_chattools/tom_chattools.dart';

/// A fake Bot API: answers each method from [answers] (a value or a function of the call), records the calls.
class FakeBotApi {
  late final HttpServer server;
  final calls =
      <({String method, Map<String, dynamic> json, String? multipart})>[];
  final answers = <String, Object? Function(Map<String, dynamic> body)>{};
  final files = <String, List<int>>{};
  final updates = <Map<String, Object?>>[];

  String get baseUrl => 'http://${server.address.host}:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final path = req.uri.pathSegments;
      if (path.length >= 3 && path[0] == 'file') {
        final bytes = files[path.sublist(2).join('/')];
        req.response.statusCode = bytes == null ? 404 : 200;
        if (bytes != null) req.response.add(bytes);
        await req.response.close();
        return;
      }
      final method = path.last;
      final raw = await utf8.decodeStream(req);
      final isMultipart =
          req.headers.contentType?.mimeType == 'multipart/form-data';
      final body = isMultipart || raw.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(raw) as Map<String, dynamic>;
      calls.add((
        method: method,
        json: body,
        multipart: isMultipart ? raw : null,
      ));
      Object? answer;
      if (method == 'getUpdates') {
        final offset = body['offset'] as int? ?? 0;
        final pending = updates
            .where((u) => (u['update_id'] as int) >= offset)
            .toList();
        if (pending.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        answer = {'ok': true, 'result': pending};
      } else {
        final f = answers[method];
        answer = f == null ? {'ok': true, 'result': true} : f(body);
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(answer));
      await req.response.close();
    });
  }

  Future<void> stop() => server.close(force: true);
}

Future<TelegramChat> connected(FakeBotApi api, {bool polling = false}) async {
  final config = TelegramChatConfig(
    token: 'T0K',
    usePolling: polling,
    pollingTimeout: 0,
    apiBaseUrl: api.baseUrl,
  );
  final chat = config.createApi(ChatSettings({})) as TelegramChat;
  await chat.initialize();
  return chat;
}

void main() {
  late FakeBotApi api;
  setUp(() async {
    api = FakeBotApi();
    await api.start();
  });
  tearDown(() => api.stop());

  test('TC-1: sendMessage', () async {
    api.answers['sendMessage'] = (b) => {
      'ok': true,
      'result': {'message_id': 77},
    };
    final chat = await connected(api);
    final sent = await chat.sendMessage(
      ChatReceiver.id('1234'),
      'Hello *you*',
      parseMode: 'markdownV2',
    );
    expect(sent.id, '77');
    expect(sent.sender.isSelf, isTrue);
    expect(api.calls.single.json, {
      'chat_id': 1234,
      'text': 'Hello *you*',
      'parse_mode': 'MarkdownV2',
    });
    await chat.sendMessage(
      ChatReceiver.username('someone'),
      'x',
      parseMode: 'html',
    );
    expect(api.calls.last.json, {
      'chat_id': '@someone',
      'text': 'x',
      'parse_mode': 'HTML',
    });
    await chat.sendMessage(ChatReceiver.id('5'), 'y', parseMode: 'bbcode');
    expect(
      api.calls.last.json.containsKey('parse_mode'),
      isFalse,
      reason: 'an unknown parse mode is left out',
    );
    await chat.disconnect();
  });

  test('TC-2: polling', () async {
    api.answers['getMe'] = (b) => {
      'ok': true,
      'result': {'id': 999, 'is_bot': true, 'first_name': 'Tom'},
    };
    api.updates.addAll([
      {
        'update_id': 10,
        'message': {
          'message_id': 1,
          'date': 1700000000,
          'text': 'hi',
          'from': {
            'id': 42,
            'is_bot': false,
            'first_name': 'Ada',
            'last_name': 'L',
            'username': 'ada',
          },
          'chat': {'id': 42, 'type': 'private'},
          'reply_to_message': {
            'message_id': 0,
            'date': 1699999999,
            'chat': {'id': 42, 'type': 'private'},
          },
        },
      },
      {
        'update_id': 11,
        'message': {
          'message_id': 2,
          'date': 1700000001,
          'caption': 'look',
          'from': {'id': 999, 'is_bot': true, 'first_name': 'Tom'},
          'chat': {'id': -100, 'type': 'group'},
          'photo': [
            {'file_id': 'small', 'width': 90, 'height': 60, 'file_size': 1000},
            {
              'file_id': 'big',
              'width': 1280,
              'height': 853,
              'file_size': 90000,
            },
          ],
        },
      },
    ]);
    final chat = await connected(api, polling: true);
    final received = await chat.onMessage
        .take(2)
        .toList()
        .timeout(const Duration(seconds: 10));
    final first = received[0];
    expect(first.text, 'hi');
    expect(first.sender.id, '42');
    expect(first.sender.name, 'Ada L');
    expect(first.sender.username, 'ada');
    expect(first.sender.isSelf, isFalse);
    expect(first.replyToMessageId, '0');
    expect(first.type, ChatMessageType.text);
    expect(
      first.timestamp,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    expect(first.rawData!['telegram_chat_id'], '42');
    expect((first.rawData!['telegram_message'] as Map)['text'], 'hi');
    final second = received[1];
    expect(second.text, 'look', reason: 'the caption when there is no text');
    expect(second.type, ChatMessageType.image);
    expect(second.sender.isSelf, isTrue, reason: 'getMe named the bot');
    expect(second.attachments.single.url, 'big', reason: 'the largest photo');
    expect(second.attachments.single.fileSize, 90000);
    expect(second.rawData!['telegram_chat_id'], '-100');
    // The offset moved past what was delivered.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final polls = api.calls.where((c) => c.method == 'getUpdates').toList();
    expect(polls.first.json['offset'], 0);
    expect(polls.last.json['offset'], 12);
    expect(polls.first.json['limit'], 100);
    expect(api.calls.first.method, 'getMe');
    await chat.disconnect();
  });

  test('TC-3: an attachment is uploaded', () async {
    final dir = await Directory.systemTemp.createTemp('tom_chattools_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/report.txt')
      ..writeAsStringSync('the report body');
    final chat = await connected(api);
    await chat.send(
      ChatReceiver.id('7'),
      ChatMessage(
        id: 'x',
        text: 'see attached',
        sender: const ChatSender.self(),
        timestamp: DateTime.now(),
        type: ChatMessageType.document,
        attachments: [
          ChatAttachment(
            type: ChatAttachmentType.document,
            url: file.path,
            fileName: 'report.txt',
          ),
        ],
      ),
    );
    final call = api.calls.single;
    expect(call.method, 'sendDocument');
    final body = call.multipart!;
    expect(body, contains('name="chat_id"\r\n\r\n7\r\n'));
    expect(body, contains('name="caption"\r\n\r\nsee attached\r\n'));
    expect(body, contains('name="document"; filename="report.txt"'));
    expect(body, contains('the report body'));
    await chat.send(
      ChatReceiver.id('7'),
      ChatMessage(
        id: 'y',
        sender: const ChatSender.self(),
        timestamp: DateTime.now(),
        type: ChatMessageType.image,
        attachments: [
          ChatAttachment(
            type: ChatAttachmentType.image,
            url: file.path,
            fileName: 'p.jpg',
          ),
        ],
      ),
    );
    expect(api.calls.last.method, 'sendPhoto');
    expect(
      api.calls.last.multipart,
      contains('name="photo"; filename="p.jpg"'),
    );
    await chat.disconnect();
  });

  test('TC-4: downloadAttachment', () async {
    api.answers['getFile'] = (b) => b['file_id'] == 'big'
        ? {
            'ok': true,
            'result': {'file_id': 'big', 'file_path': 'photos/file_1.jpg'},
          }
        : {
            'ok': false,
            'error_code': 400,
            'description': 'Bad Request: invalid file_id',
          };
    api.files['photos/file_1.jpg'] = [1, 2, 3, 4];
    final chat = await connected(api);
    final bytes = await chat.downloadAttachment(
      const ChatAttachment(type: ChatAttachmentType.image, url: 'big'),
    );
    expect(bytes, [1, 2, 3, 4]);
    expect(api.calls.single.json, {'file_id': 'big'});
    expect(
      await chat.downloadAttachment(
        const ChatAttachment(type: ChatAttachmentType.image, url: 'nope'),
      ),
      isNull,
    );
    expect(
      await chat.downloadAttachment(
        const ChatAttachment(type: ChatAttachmentType.image, url: ''),
      ),
      isNull,
    );
    await chat.disconnect();
  });

  test('TC-5: a refused call', () async {
    api.answers['sendMessage'] = (b) => {
      'ok': false,
      'error_code': 403,
      'description': 'Forbidden: bot was blocked by the user',
    };
    final chat = await connected(api);
    await expectLater(
      chat.sendMessage(ChatReceiver.id('1'), 'x'),
      throwsA(
        isA<TelegramApiException>()
            .having((e) => e.method, 'method', 'sendMessage')
            .having((e) => e.errorCode, 'errorCode', 403)
            .having((e) => e.description, 'description', contains('blocked')),
      ),
    );
    await chat.disconnect();
  });

  test(
    'TC-6: disconnect ends the polling; connect takes the API root',
    () async {
      final api2 = await ChatApi.connect(
        ChatSettings(
          {
            ChatSettings.telegramToken: 'T0K',
            ChatSettings.telegramApiBaseUrl: api.baseUrl,
          },
          usePolling: true,
          pollingTimeout: Duration.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(
        api.calls.any((c) => c.method == 'getUpdates'),
        isTrue,
        reason: 'polling at the given root',
      );
      await api2.disconnect();
      expect(api2.isConnected, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final after = api.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(api.calls.length, after, reason: 'no call after disconnect');
    },
  );

  test('TC-7: no third-party dependency', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('televerse')));
    expect(
      RegExp(r'^dependencies: \{\}$', multiLine: true).hasMatch(pubspec),
      isTrue,
    );
  });
}
