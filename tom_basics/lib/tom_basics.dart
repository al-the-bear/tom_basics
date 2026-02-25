/// Basic utilities for the TOM framework.
///
/// This library provides foundational utilities that have minimal dependencies
/// and can be used by other TOM framework packages:
///
/// - [TomBaseException] - Base exception class with UUID tracking
/// - [TomLogger] - Lightweight logging with configurable outputs
/// - [TomPlatformUtils] - Cross-platform utility abstractions
/// - [TomEnvironment] - Runtime environment configuration
///
/// ## Usage
///
/// ```dart
/// import 'package:tom_basics/tom_basics.dart';
///
/// throw TomBaseException('ERROR_CODE', 'Something went wrong');
/// tomLog.info('Application started');
/// ```
library;

export 'src/exceptions/exception_base.dart';
export 'src/logging/logging.dart';
export 'src/runtime/platform_neutral.dart';
export 'src/runtime/platform_environment_runtime.dart';
