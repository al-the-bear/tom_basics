// Detecting the platform on a standalone VM.
//
// `tom_basics` declares the abstract TomPlatformUtils seam; `tom_basics_console`
// fills it in for the standalone/server target with TomStandalonePlatformUtils,
// backed by dart:io's Platform. The OS answers are host-specific, but two facts
// hold on *any* standalone VM: it is never "web", and it is exactly one of
// desktop or mobile.
//
// Run with: dart run example/01_platform_detection_example.dart
import 'package:tom_basics_console/tom_basics_console.dart';

void main() {
  final p = TomStandalonePlatformUtils();

  // Host-independent invariants — true on every standalone VM.
  print('not web (real host):    ${!p.isWeb()}');
  print('desktop xor mobile:     ${p.isDesktop() != p.isMobile()}');

  // The concrete OS — exactly one of these is true on a VM host.
  final os = p.isWindows()
      ? 'Windows'
      : p.isMacOs()
          ? 'macOS'
          : p.isLinux()
              ? 'Linux'
              : p.isFuchsia()
                  ? 'Fuchsia'
                  : p.isAndroid()
                      ? 'Android'
                      : p.isIos()
                          ? 'iOS'
                          : 'unknown';
  print('Detected OS:            $os');

  // expected output:
  // not web (real host):    true
  // desktop xor mobile:     true
  // Detected OS:            Linux
  //   (the "Detected OS" line varies by host: Windows / macOS / Linux / …)
}
