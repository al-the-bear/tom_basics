/// Platform-neutral runtime utilities for Tom framework.
///
/// This library provides an abstraction layer for platform-specific operations,
/// enabling code to run across different environments (web, mobile, desktop)
/// without direct platform dependencies.
///
/// The primary class [TomPlatformUtils] acts as a singleton that delegates
/// platform-specific operations to the appropriate implementation. Applications
/// should configure the platform implementation at startup using
/// [TomPlatformUtils.setCurrentPlatform].
///
/// ## Example
///
/// ```dart
/// // At application startup, set the platform implementation
/// TomPlatformUtils.setCurrentPlatform(MyPlatformUtils());
///
/// // Later, use platform utilities anywhere in the codebase
/// if (TomPlatformUtils.current.isMobile()) {
///   // Mobile-specific logic
/// }
/// ```
///
/// See also:
/// - [TomFallbackPlatformUtils] for a default fallback implementation
library;

// =============================================================================
// Imports
// =============================================================================

import 'package:http/http.dart';

// =============================================================================
// Platform Utilities Abstract Class
// =============================================================================

/// Abstract base class for platform-specific utility operations.
///
/// This class defines a contract for platform detection, console output,
/// HTTP client creation, and environment variable access. Concrete
/// implementations should be provided for each target platform (web, mobile,
/// desktop, server).
///
/// ## Usage
///
/// The class follows a singleton pattern with a configurable implementation:
///
/// ```dart
/// // Configure at startup
/// TomPlatformUtils.setCurrentPlatform(FlutterPlatformUtils());
///
/// // Access platform utilities
/// final platform = TomPlatformUtils.current;
/// print('Running on desktop: ${platform.isDesktop()}');
/// ```
///
/// ## Platform Detection
///
/// The platform detection methods are organized into three categories:
///
/// 1. **Environment type**: [isDesktop], [isMobile], [isWeb]
/// 2. **Desktop operating systems**: [isWindows], [isLinux], [isMacOs], [isFuchsia]
/// 3. **Mobile operating systems**: [isAndroid], [isIos]
///
/// ## Environment Variables
///
/// Environment variables can be set via [envVars] and accessed through
/// [getTomEnvVars]. This provides a platform-neutral way to manage
/// configuration across different deployment targets.
abstract class TomPlatformUtils {
  // ---------------------------------------------------------------------------
  // Static Fields
  // ---------------------------------------------------------------------------

  /// Platform-specific environment variables.
  ///
  /// This map can be populated with configuration values that should be
  /// available across the application. Use [getTomEnvVars] to retrieve
  /// these values.
  static Map<String, String> envVars = {};

  /// The current platform implementation.
  ///
  /// Defaults to [TomFallbackPlatformUtils] which throws [UnimplementedError]
  /// for most operations. Applications should set a proper implementation
  /// using [setCurrentPlatform] at startup.
  static TomPlatformUtils _current = TomFallbackPlatformUtils();

  // ---------------------------------------------------------------------------
  // Static Methods
  // ---------------------------------------------------------------------------

  /// Sets the current platform implementation.
  ///
  /// This should be called once at application startup before any platform
  /// utilities are accessed.
  ///
  /// [newCurrent] - The platform-specific implementation to use.
  ///
  /// ## Example
  ///
  /// ```dart
  /// void main() {
  ///   TomPlatformUtils.setCurrentPlatform(FlutterPlatformUtils());
  ///   runApp(MyApp());
  /// }
  /// ```
  static void setCurrentPlatform(TomPlatformUtils newCurrent) {
    _current = newCurrent;
  }

  /// Returns the current platform implementation.
  ///
  /// If no implementation has been set via [setCurrentPlatform], this returns
  /// the default [TomFallbackPlatformUtils] instance.
  static TomPlatformUtils get current => _current;

  // ---------------------------------------------------------------------------
  // Environment Type Detection
  // ---------------------------------------------------------------------------

  /// Returns `true` if running on a desktop platform.
  ///
  /// Desktop platforms include Windows, macOS, and Linux.
  bool isDesktop();

  /// Returns `true` if running on a mobile platform.
  ///
  /// Mobile platforms include Android and iOS.
  bool isMobile();

  /// Returns `true` if running in a web browser environment.
  bool isWeb();

  // ---------------------------------------------------------------------------
  // Desktop OS Detection
  // ---------------------------------------------------------------------------

  /// Returns `true` if running on Microsoft Windows.
  bool isWindows();

  /// Returns `true` if running on Linux.
  bool isLinux();

  /// Returns `true` if running on macOS.
  bool isMacOs();

  /// Returns `true` if running on Fuchsia OS.
  bool isFuchsia();

  // ---------------------------------------------------------------------------
  // Mobile OS Detection
  // ---------------------------------------------------------------------------

  /// Returns `true` if running on Android.
  bool isAndroid();

  /// Returns `true` if running on iOS.
  bool isIos();

  // ---------------------------------------------------------------------------
  // Console Output
  // ---------------------------------------------------------------------------

  /// Outputs an error message to the console.
  ///
  /// [s] - The error message to output.
  void outError(String s);

  /// Outputs a message to the console.
  ///
  /// [s] - The message to output.
  void out(String s);

  // ---------------------------------------------------------------------------
  // HTTP & Networking
  // ---------------------------------------------------------------------------

  /// Creates and returns a platform-appropriate HTTP client.
  ///
  /// The returned client should be suitable for making HTTP requests on
  /// the current platform. For example, web platforms may return a
  /// browser-compatible client.
  ///
  /// ## Example
  ///
  /// ```dart
  /// final client = TomPlatformUtils.current.httpClient();
  /// final response = await client.get(Uri.parse('https://api.example.com'));
  /// ```
  Client httpClient();

  // ---------------------------------------------------------------------------
  // Environment & Configuration
  // ---------------------------------------------------------------------------

  /// Returns the platform-specific environment variables.
  ///
  /// These variables are stored in [envVars] and can be used for
  /// configuration that varies between deployment environments.
  Map<String, String> getTomEnvVars() {
    return envVars;
  }

  /// Returns the current browser URL location, if applicable.
  ///
  /// Returns `null` or an empty string if not running in a browser
  /// environment or if the location cannot be determined.
  String? getBrowserLocation();

  /// Returns the name of the current isolate.
  ///
  /// Useful for debugging and logging in multi-isolate applications.
  /// Returns an empty string if isolate identification is not available.
  String getIsolateName();
}

// =============================================================================
// Fallback Platform Implementation
// =============================================================================

/// A fallback implementation of [TomPlatformUtils].
///
/// This class provides default behavior when no platform-specific
/// implementation has been configured. Most methods throw
/// [UnimplementedError] to indicate that a proper implementation
/// should be provided.
///
/// The only methods with working implementations are:
/// - [out] - prints to standard output
/// - [outError] - prints to standard output
/// - [getBrowserLocation] - returns empty string
/// - [getIsolateName] - returns empty string
///
/// ## When to Use
///
/// This fallback is automatically used when the application hasn't
/// configured a platform implementation. It's primarily useful during
/// testing or when only console output functionality is needed.
///
/// ## Example
///
/// ```dart
/// // This is the default - no explicit setup needed
/// TomPlatformUtils.current.out('Hello'); // Works with fallback
///
/// // This will throw UnimplementedError with fallback
/// TomPlatformUtils.current.isDesktop(); // Throws!
/// ```
class TomFallbackPlatformUtils extends TomPlatformUtils {
  // ---------------------------------------------------------------------------
  // Browser & Isolate
  // ---------------------------------------------------------------------------

  @override
  String? getBrowserLocation() {
    return "";
  }

  @override
  String getIsolateName() {
    return "";
  }

  // ---------------------------------------------------------------------------
  // HTTP Client
  // ---------------------------------------------------------------------------

  @override
  Client httpClient() {
    throw UnimplementedError();
  }

  // ---------------------------------------------------------------------------
  // Mobile OS Detection (Unimplemented)
  // ---------------------------------------------------------------------------

  @override
  bool isAndroid() {
    throw UnimplementedError();
  }

  // ---------------------------------------------------------------------------
  // Environment Type Detection (Unimplemented)
  // ---------------------------------------------------------------------------

  @override
  bool isDesktop() {
    throw UnimplementedError();
  }

  @override
  bool isFuchsia() {
    throw UnimplementedError();
  }

  @override
  bool isIos() {
    throw UnimplementedError();
  }

  // ---------------------------------------------------------------------------
  // Desktop OS Detection (Unimplemented)
  // ---------------------------------------------------------------------------

  @override
  bool isLinux() {
    throw UnimplementedError();
  }

  @override
  bool isMacOs() {
    throw UnimplementedError();
  }

  @override
  bool isMobile() {
    throw UnimplementedError();
  }

  @override
  bool isWeb() {
    throw UnimplementedError();
  }

  @override
  bool isWindows() {
    throw UnimplementedError();
  }

  // ---------------------------------------------------------------------------
  // Console Output
  // ---------------------------------------------------------------------------

  @override
  void out(String s) {
    print(s);
  }

  @override
  void outError(String s) {
    print(s);
  }
}
