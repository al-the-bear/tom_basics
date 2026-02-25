import 'package:tom_basics/tom_basics.dart';

void main() {
  // Configure logging
  tomLog.setLogLevel(TomLogLevel.development);
  tomLog.info('Application starting...');

  try {
    throw TomBaseException('EXAMPLE_ERROR', 'Something went wrong');
  } on TomBaseException catch (e) {
    tomLog.error('Caught exception: ${e.key} - ${e.defaultUserMessage}');
    print('Exception UUID: ${e.uuid}');
  }

  tomLog.info('Application finished.');
}
