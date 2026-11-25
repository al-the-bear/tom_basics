// Copyright (c) 2026 Peter Nicolai Alexis Kyaw
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

/// What a native file is: it decides the file name on each platform and the
/// order of an application bundle's folders.
enum TomNativeFileKind {
  /// A program another process starts (`tom_office_host`,
  /// `tom_office_host.exe`). On macOS it is looked for in `Contents/MacOS/`
  /// first.
  executable,

  /// A shared library loaded into the process (`libpdfium.dylib`,
  /// `libpdfium.so`, `pdfium.dll`). On macOS it is looked for in
  /// `Contents/Frameworks/` first; on Linux in the bundle's `lib/` after the
  /// executable's folder.
  library,
}

/// Finds an external native component (a helper program or a shared library)
/// the way a Tom application ships it: first inside the running application's
/// own bundle, then in the binaries layer named by `TOM_BINARY_PATH`.
///
/// The bundle comes first because an application started from the Finder or
/// the Start menu sees no shell variable: `TOM_BINARY_PATH` exists on a
/// developer machine only. A release therefore carries what it needs inside
/// its bundle, and a development run (`flutter run`, `dart test`) falls
/// through to the binaries layer.
///
/// - **macOS:** only an executable inside `<App>.app/Contents/MacOS/` has a
///   bundle; its folders are `Contents/MacOS/` and `Contents/Frameworks/`.
/// - **Linux:** the executable's folder and its `lib/` (where a Flutter Linux
///   bundle keeps its libraries).
/// - **Windows:** the executable's folder.
/// - **No bundle:** the Dart VM (`dart`) and `flutter_tester`, i.e. `dart run`,
///   `dart test` and `flutter test`; and on macOS any executable outside an
///   `.app`.
///
/// The binaries layer is `<TOM_BINARY_PATH>/<platform folder>/<file>`, the
/// platform folder named as `tom_binaries` names it ([platformFolder]).
///
/// Every input the lookup reads from the running process (the executable,
/// the operating system, the architecture, the environment) can be given
/// instead, so tests run on fake folders.
abstract final class TomNativeBinaries {
  /// The environment variable naming the binaries layer (`tom_binaries/tom`).
  static const binaryPathVariable = 'TOM_BINARY_PATH';

  /// Executables whose folder is no application bundle: the Dart VM and the
  /// Flutter test runner.
  static const _noBundleExecutables = {
    'dart',
    'dart.exe',
    'dartaotruntime',
    'dartaotruntime.exe',
    'flutter_tester',
    'flutter_tester.exe',
  };

  /// The binaries layer's folder of a platform, as `tom_binaries` names it:
  /// `darwin-arm64`, `darwin-x64`, `linux-x64`, `linux-arm64`, `linux-armhf`,
  /// `win32-x64`, `win32-arm64` (macOS is `darwin`, Windows `win32`).
  /// [operatingSystem] is a `Platform.operatingSystem` value and [arch] one of
  /// `arm64`, `x64`, `arm`, `ia32`, `riscv64`; both default to the running
  /// process's.
  static String platformFolder({String? operatingSystem, String? arch}) {
    final os = switch (operatingSystem ?? Platform.operatingSystem) {
      'macos' => 'darwin',
      'windows' => 'win32',
      final other => other,
    };
    final cpu = switch (arch ?? currentArch()) {
      'arm' => 'armhf',
      final other => other,
    };
    return '$os-$cpu';
  }

  /// The running process's architecture, read from `Platform.version`
  /// (`... on "macos_arm64"`): `arm64`, `x64`, `arm`, `ia32`, `riscv64`.
  static String currentArch() => archOfVersion(Platform.version);

  /// The architecture a `Platform.version` string names; `x64` when it names
  /// none.
  static String archOfVersion(String version) {
    final match = RegExp(r'on "[a-z]+_([a-z0-9]+)"').firstMatch(version);
    return match?.group(1) ?? 'x64';
  }

  /// An executable's file name on [operatingSystem] (default the running
  /// one): `<name>.exe` on Windows, `<name>` elsewhere.
  static String executableFileName(String name, {String? operatingSystem}) =>
      (operatingSystem ?? Platform.operatingSystem) == 'windows'
      ? '$name.exe'
      : name;

  /// A shared library's file name on [operatingSystem] (default the running
  /// one): `lib<name>.dylib` on macOS, `<name>.dll` on Windows,
  /// `lib<name>.so` elsewhere.
  static String libraryFileName(String name, {String? operatingSystem}) =>
      switch (operatingSystem ?? Platform.operatingSystem) {
        'macos' => 'lib$name.dylib',
        'windows' => '$name.dll',
        _ => 'lib$name.so',
      };

  /// The running application's bundle folders a [kind] of file is looked
  /// for in, in order; empty when the process runs from no bundle (see the
  /// class comment). [executable] defaults to `Platform.resolvedExecutable`,
  /// [operatingSystem] to the running one.
  static List<String> bundleFolders({
    TomNativeFileKind kind = TomNativeFileKind.executable,
    String? executable,
    String? operatingSystem,
  }) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final exe = executable ?? Platform.resolvedExecutable;
    final sep = os == 'windows' ? r'\' : '/';
    final parts = _split(exe);
    if (parts.length < 2) return const [];
    if (_noBundleExecutables.contains(parts.last.toLowerCase())) {
      return const [];
    }
    final folder = _join(parts.sublist(0, parts.length - 1), sep, exe);
    switch (os) {
      case 'macos':
        // <App>.app/Contents/MacOS/<executable>
        if (parts.length < 4 ||
            parts[parts.length - 2] != 'MacOS' ||
            parts[parts.length - 3] != 'Contents' ||
            !parts[parts.length - 4].endsWith('.app')) {
          return const [];
        }
        final contents = _join(parts.sublist(0, parts.length - 2), sep, exe);
        final frameworks = '$contents${sep}Frameworks';
        return kind == TomNativeFileKind.library
            ? [frameworks, folder]
            : [folder, frameworks];
      case 'linux':
        return kind == TomNativeFileKind.library
            ? [folder, '$folder${sep}lib']
            : [folder];
      default:
        return [folder];
    }
  }

  /// The binaries layer's root (`tom_binaries/tom`): [binaryPath], else
  /// `TOM_BINARY_PATH` from [environment] (default `Platform.environment`);
  /// `null` when neither is set.
  static String? binariesLayer({
    String? binaryPath,
    Map<String, String>? environment,
  }) {
    final root =
        binaryPath ?? (environment ?? Platform.environment)[binaryPathVariable];
    return root == null || root.isEmpty ? null : root;
  }

  /// The binaries repository's root (`tom_binaries`, the parent of the
  /// layer): where components with a folder of their own live
  /// (`tom_binaries/pdfium/<platform>/`). `null` without a layer.
  static String? binariesRepository({
    String? binaryPath,
    Map<String, String>? environment,
  }) {
    final layer = binariesLayer(
      binaryPath: binaryPath,
      environment: environment,
    );
    return layer == null ? null : Directory(layer).parent.path;
  }

  /// Every path [find] would try for [fileName], in order: the bundle
  /// folders ([bundleFolders] overrides them), then
  /// `<binaries layer>/<platform folder>/<fileName>` when a layer is known.
  static List<String> candidates(
    String fileName, {
    TomNativeFileKind kind = TomNativeFileKind.executable,
    List<String>? bundleFolders,
    String? binaryPath,
    Map<String, String>? environment,
    String? executable,
    String? operatingSystem,
    String? arch,
  }) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final sep = os == 'windows' ? r'\' : '/';
    final folders =
        bundleFolders ??
        TomNativeBinaries.bundleFolders(
          kind: kind,
          executable: executable,
          operatingSystem: os,
        );
    final layer = binariesLayer(
      binaryPath: binaryPath,
      environment: environment,
    );
    return [
      for (final folder in folders) '$folder$sep$fileName',
      if (layer != null)
        '$layer$sep${platformFolder(operatingSystem: os, arch: arch)}'
            '$sep$fileName',
    ];
  }

  /// The first of [candidates] that exists as a file, or `null`.
  static String? find(
    String fileName, {
    TomNativeFileKind kind = TomNativeFileKind.executable,
    List<String>? bundleFolders,
    String? binaryPath,
    Map<String, String>? environment,
    String? executable,
    String? operatingSystem,
    String? arch,
  }) {
    for (final path in candidates(
      fileName,
      kind: kind,
      bundleFolders: bundleFolders,
      binaryPath: binaryPath,
      environment: environment,
      executable: executable,
      operatingSystem: operatingSystem,
      arch: arch,
    )) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  /// The first bundle folder (of [bundleFolders], default the running
  /// application's) holding [fileName], as a path; `null` when none does.
  static String? findInBundle(
    String fileName, {
    TomNativeFileKind kind = TomNativeFileKind.executable,
    List<String>? bundleFolders,
    String? executable,
    String? operatingSystem,
  }) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final sep = os == 'windows' ? r'\' : '/';
    for (final folder
        in bundleFolders ??
            TomNativeBinaries.bundleFolders(
              kind: kind,
              executable: executable,
              operatingSystem: os,
            )) {
      final path = '$folder$sep$fileName';
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static List<String> _split(String path) =>
      path.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();

  /// Joins [parts] back with [sep], keeping the original's leading root
  /// (`/`, `\\`, or a drive letter, which is the first part).
  static String _join(List<String> parts, String sep, String original) {
    final joined = parts.join(sep);
    if (original.startsWith('/') || original.startsWith(r'\')) {
      return original.startsWith(r'\\') ? '$sep$sep$joined' : '$sep$joined';
    }
    return joined;
  }
}
