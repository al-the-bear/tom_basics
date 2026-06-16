// Process environment and isolate name through the seam.
//
// The TomStandalonePlatformUtils constructor copies Platform.environment into
// the seam's envVars map, so the real process environment is available through
// the platform-neutral getTomEnvVars(). You can also add your own entries. The
// logger uses getIsolateName() to tag each line with its originating isolate.
//
// Run with: dart run example/04_environment_and_isolate_example.dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final p = TomStandalonePlatformUtils();

  // App-supplied configuration sits alongside the inherited process env.
  TomPlatformUtils.envVars['TOM_SAMPLE_MODE'] = 'demo';

  print('TOM_SAMPLE_MODE:        ${p.getTomEnvVars()['TOM_SAMPLE_MODE']}');
  // PATH is present because the constructor seeded Platform.environment.
  print('PATH present:           ${p.getTomEnvVars().containsKey('PATH')}');
  // On the main isolate this is "main"; always non-empty on the standalone VM.
  print('isolate name nonempty:  ${p.getIsolateName().isNotEmpty}');

  // expected output:
  // TOM_SAMPLE_MODE:        demo
  // PATH present:           true
  // isolate name nonempty:  true
}
