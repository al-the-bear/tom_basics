// Installing the standalone implementation into the global seam.
//
// Library code stays platform-neutral by asking TomPlatformUtils.current rather
// than touching dart:io. The app entry point installs a concrete implementation
// once at startup with setCurrentPlatform; from then on any code — including the
// logger — can use the seam without importing dart:io.
//
// Run with: dart run example/02_wiring_the_seam_example.dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  // One line at startup wires the standalone (dart:io) implementation in.
  TomPlatformUtils.setCurrentPlatform(TomStandalonePlatformUtils());

  // Anywhere downstream, library code uses the seam — no dart:io import needed.
  final isStandalone =
      TomPlatformUtils.current is TomStandalonePlatformUtils;
  print('current is standalone:  $isStandalone');
  print('seam not web:           ${!TomPlatformUtils.current.isWeb()}');

  // The `standalonePlatformUtils` getter returns a fresh instance typed as the
  // abstract seam, for call sites that prefer not to name the class.
  TomPlatformUtils.setCurrentPlatform(standalonePlatformUtils);
  print('getter also standalone: '
      '${TomPlatformUtils.current is TomStandalonePlatformUtils}');

  // expected output:
  // current is standalone:  true
  // seam not web:           true
  // getter also standalone: true
}
