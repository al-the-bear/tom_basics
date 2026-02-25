/// Example demonstrating tom_basics_console platform detection.
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final platform = TomStandalonePlatformUtils();

  print('Desktop: ${platform.isDesktop()}');
  print('Mobile: ${platform.isMobile()}');
  print('Web: ${platform.isWeb()}');

  // Console-formatted output
  platform.out('**Hello** from tom_basics_console!');
}
