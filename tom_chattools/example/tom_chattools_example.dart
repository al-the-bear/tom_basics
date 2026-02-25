import 'package:tom_chattools/tom_chattools.dart';

void main() async {
  // Example: Connect to Telegram
  final api = await ChatApi.connect(ChatSettings.telegram(
    'YOUR_BOT_TOKEN', // Get this from @BotFather
  ));

  // Define the receiver (user/chat to communicate with)
  final receiver = ChatReceiver.id('123456789');

  // Send a message to the receiver
  await api.sendMessage(receiver, 'Hello from Tom ChatTools!');

  // Wait for and process responses from that same receiver
  final response = await api.getMessages(
    receiver,
    maxWait: Duration(seconds: 30),
    minWait: Duration(seconds: 5),
  );

  if (response.hasMessages) {
    for (final message in response.messages) {
      print('Received from ${message.sender.name}: ${message.text}');
    }
  } else {
    print('No messages received (status: ${response.status})');
  }

  await api.disconnect();
}
