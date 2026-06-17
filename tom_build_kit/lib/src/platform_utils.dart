import 'dart:ffi' as ffi;

/// Platform name mappings and conversion utilities for cross-compilation.
///
/// Provides conversion between:
/// - Dart FFI Abi identifiers
/// - VS Code platform names (darwin-arm64, linux-x64, etc.)
/// - Dart compiler target format (macos-arm64, linux-x64, etc.)
class PlatformUtils {
  PlatformUtils._();

  /// Get current platform in VS Code format (e.g., darwin-arm64, linux-x64).
  static String getCurrentPlatform() {
    final abi = ffi.Abi.current();
    return abiToVSCodePlatform(abi);
  }

  /// Convert Dart FFI Abi to VS Code platform name.
  static String abiToVSCodePlatform(ffi.Abi abi) {
    switch (abi) {
      case ffi.Abi.macosArm64:
        return 'darwin-arm64';
      case ffi.Abi.macosX64:
        return 'darwin-x64';
      case ffi.Abi.linuxX64:
        return 'linux-x64';
      case ffi.Abi.linuxArm64:
        return 'linux-arm64';
      case ffi.Abi.linuxArm:
        return 'linux-armhf';
      case ffi.Abi.windowsX64:
        return 'win32-x64';
      case ffi.Abi.windowsArm64:
        return 'win32-arm64';
      default:
        throw UnsupportedError('Unsupported platform: $abi');
    }
  }

  /// Convert VS Code platform name to Dart compiler target format.
  /// (e.g., darwin-arm64 -> macos-arm64, linux-x64 -> linux-x64)
  static String vsCodeToDartTarget(String vsCodePlatform) {
    switch (vsCodePlatform) {
      case 'darwin-arm64':
        return 'macos-arm64';
      case 'darwin-x64':
        return 'macos-x64';
      case 'linux-x64':
        return 'linux-x64';
      case 'linux-arm64':
        return 'linux-arm64';
      case 'linux-armhf':
        return 'linux-arm';
      case 'win32-x64':
      case 'windows-x64':
        return 'windows-x64';
      case 'win32-arm64':
      case 'windows-arm64':
        return 'windows-arm64';
      default:
        throw ArgumentError('Unknown VS Code platform: $vsCodePlatform');
    }
  }

  /// Normalize platform name to VS Code format.
  /// Supports generic OS names (linux, macos, windows) and various formats.
  static List<String> normalizePlatform(String platform) {
    final lower = platform.toLowerCase().trim();

    // Generic OS names - return all architectures
    if (lower == 'linux') {
      return ['linux-x64', 'linux-arm64', 'linux-armhf'];
    }
    if (lower == 'macos' || lower == 'darwin') {
      return ['darwin-arm64', 'darwin-x64'];
    }
    if (lower == 'windows' || lower == 'win32') {
      return ['win32-x64', 'win32-arm64'];
    }

    // Specific platform names - normalize to VS Code format
    final normalized = lower
        .replaceAll('macos', 'darwin')
        .replaceAll('windows', 'win32')
        .replaceAll('amd64', 'x64')
        .replaceAll('x86_64', 'x64')
        .replaceAll('_', '-');

    return [normalized];
  }

  /// Check if a platform pattern matches a target platform.
  /// Supports wildcards like linux-*, darwin-*, etc.
  static bool matchesPlatform(String pattern, String targetPlatform) {
    final normalizedPattern =
        pattern.toLowerCase().trim().replaceAll('_', '-');
    final normalizedTarget =
        targetPlatform.toLowerCase().trim().replaceAll('_', '-');

    // Exact match
    if (normalizedPattern == normalizedTarget) return true;

    // Wildcard match (e.g., linux-* matches linux-x64, linux-arm64, etc.)
    if (normalizedPattern.endsWith('*')) {
      final prefix =
          normalizedPattern.substring(0, normalizedPattern.length - 1);
      return normalizedTarget.startsWith(prefix);
    }

    // Generic OS match
    final normalizedPlatforms = normalizePlatform(normalizedPattern);
    return normalizedPlatforms.contains(normalizedTarget);
  }

  /// Get OS name from VS Code platform for dart compile --target-os.
  /// Returns: linux, macos, windows (dart compile option format)
  static String getTargetOS(String platform) {
    final normalized = platform.toLowerCase().replaceAll('_', '-');
    if (normalized.startsWith('darwin-')) return 'macos';
    if (normalized.startsWith('linux-')) return 'linux';
    if (normalized.startsWith('win32-') ||
        normalized.startsWith('windows-')) {
      return 'windows';
    }
    return normalized.split('-').first;
  }

  /// Get architecture from VS Code platform for dart compile --target-arch.
  /// Returns: arm, arm64, x64 (dart compile option format)
  static String getTargetArch(String platform) {
    final normalized = platform.replaceAll('_', '-');
    final parts = normalized.split('-');
    final arch = parts.length > 1 ? parts.last : '';

    // Map to dart compile architecture names
    switch (arch) {
      case 'armhf':
        return 'arm';
      case 'arm64':
        return 'arm64';
      case 'x64':
        return 'x64';
      default:
        return arch;
    }
  }
}
