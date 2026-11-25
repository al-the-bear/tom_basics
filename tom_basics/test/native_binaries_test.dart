/// `package:tom_basics/native_binaries.dart`: a native component is looked
/// for in the running application's bundle first, then in the binaries
/// layer, on fake folders.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_basics/native_binaries.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('tom_native_'));
  tearDown(() => root.deleteSync(recursive: true));

  File touch(String relative) =>
      File('${root.path}/$relative')..createSync(recursive: true);

  group('NATIVE-P platform folders and file names', () {
    test('NATIVE-P1: the binaries layer names each platform as tom_binaries '
        'does', () {
      String folder(String os, String arch) =>
          TomNativeBinaries.platformFolder(operatingSystem: os, arch: arch);
      expect(folder('macos', 'arm64'), 'darwin-arm64');
      expect(folder('macos', 'x64'), 'darwin-x64');
      expect(folder('linux', 'x64'), 'linux-x64');
      expect(folder('linux', 'arm64'), 'linux-arm64');
      expect(folder('linux', 'arm'), 'linux-armhf');
      expect(folder('windows', 'x64'), 'win32-x64');
      expect(folder('windows', 'arm64'), 'win32-arm64');
    });

    test('NATIVE-P2: the architecture is read from Platform.version', () {
      expect(
        TomNativeBinaries.archOfVersion('3.13.7 (stable) on "macos_arm64"'),
        'arm64',
      );
      expect(
        TomNativeBinaries.archOfVersion('3.13.7 (stable) on "linux_x64"'),
        'x64',
      );
      expect(
        TomNativeBinaries.archOfVersion('3.13.7 (stable) on "windows_arm64"'),
        'arm64',
      );
      expect(TomNativeBinaries.archOfVersion('unknown'), 'x64');
    });

    test('NATIVE-P3: executable and library file names per platform', () {
      expect(
        TomNativeBinaries.executableFileName('tool', operatingSystem: 'macos'),
        'tool',
      );
      expect(
        TomNativeBinaries.executableFileName('tool', operatingSystem: 'linux'),
        'tool',
      );
      expect(
        TomNativeBinaries.executableFileName(
          'tool',
          operatingSystem: 'windows',
        ),
        'tool.exe',
      );
      expect(
        TomNativeBinaries.libraryFileName('pdfium', operatingSystem: 'macos'),
        'libpdfium.dylib',
      );
      expect(
        TomNativeBinaries.libraryFileName('pdfium', operatingSystem: 'linux'),
        'libpdfium.so',
      );
      expect(
        TomNativeBinaries.libraryFileName('pdfium', operatingSystem: 'windows'),
        'pdfium.dll',
      );
    });
  });

  group('NATIVE-B the application bundle', () {
    test('NATIVE-B1: macOS — Contents/MacOS then Contents/Frameworks for an '
        'executable, the other way round for a library', () {
      const exe = '/Applications/Forge.app/Contents/MacOS/Forge';
      expect(
        TomNativeBinaries.bundleFolders(
          executable: exe,
          operatingSystem: 'macos',
        ),
        [
          '/Applications/Forge.app/Contents/MacOS',
          '/Applications/Forge.app/Contents/Frameworks',
        ],
      );
      expect(
        TomNativeBinaries.bundleFolders(
          kind: TomNativeFileKind.library,
          executable: exe,
          operatingSystem: 'macos',
        ),
        [
          '/Applications/Forge.app/Contents/Frameworks',
          '/Applications/Forge.app/Contents/MacOS',
        ],
      );
    });

    test('NATIVE-B2: macOS — an executable outside an .app has no bundle', () {
      for (final exe in [
        '/usr/local/bin/forge',
        '/opt/Forge/Contents/MacOS/Forge',
        '/Applications/Forge.app/Contents/Resources/Forge',
      ]) {
        expect(
          TomNativeBinaries.bundleFolders(
            executable: exe,
            operatingSystem: 'macos',
          ),
          isEmpty,
          reason: exe,
        );
      }
    });

    test('NATIVE-B3: Linux — the executable\'s folder, and its lib/ for a '
        'library', () {
      const exe = '/opt/forge/bundle/forge';
      expect(
        TomNativeBinaries.bundleFolders(
          executable: exe,
          operatingSystem: 'linux',
        ),
        ['/opt/forge/bundle'],
      );
      expect(
        TomNativeBinaries.bundleFolders(
          kind: TomNativeFileKind.library,
          executable: exe,
          operatingSystem: 'linux',
        ),
        ['/opt/forge/bundle', '/opt/forge/bundle/lib'],
      );
    });

    test('NATIVE-B4: Windows — the executable\'s folder, drive kept', () {
      expect(
        TomNativeBinaries.bundleFolders(
          kind: TomNativeFileKind.library,
          executable: r'C:\Program Files\Forge\forge.exe',
          operatingSystem: 'windows',
        ),
        [r'C:\Program Files\Forge'],
      );
    });

    test('NATIVE-B5: the Dart VM and flutter_tester are no bundle', () {
      for (final (exe, os) in [
        ('/sdk/bin/dart', 'linux'),
        (r'C:\sdk\bin\dart.exe', 'windows'),
        (
          '/flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester',
          'linux',
        ),
        ('/sdk/bin/dart', 'macos'),
      ]) {
        expect(
          TomNativeBinaries.bundleFolders(executable: exe, operatingSystem: os),
          isEmpty,
          reason: exe,
        );
      }
    });

    test('NATIVE-B6: this test run has no bundle, so it falls through to the '
        'binaries layer', () {
      expect(TomNativeBinaries.bundleFolders(), isEmpty);
    });
  });

  group('NATIVE-F the lookup order', () {
    test('NATIVE-F1: found in the bundle before the binaries layer', () {
      final inBundle = touch('Forge.app/Contents/MacOS/tool');
      touch('layer/darwin-arm64/tool');
      expect(
        TomNativeBinaries.find(
          'tool',
          executable: '${root.path}/Forge.app/Contents/MacOS/Forge',
          operatingSystem: 'macos',
          arch: 'arm64',
          environment: {'TOM_BINARY_PATH': '${root.path}/layer'},
        ),
        inBundle.path,
      );
    });

    test('NATIVE-F2: a library in Contents/Frameworks', () {
      final lib = touch('Forge.app/Contents/Frameworks/libx.dylib');
      expect(
        TomNativeBinaries.find(
          'libx.dylib',
          kind: TomNativeFileKind.library,
          executable: '${root.path}/Forge.app/Contents/MacOS/Forge',
          operatingSystem: 'macos',
          environment: const {},
        ),
        lib.path,
      );
    });

    test('NATIVE-F3: a library in a Linux bundle\'s lib/', () {
      final lib = touch('bundle/lib/libx.so');
      expect(
        TomNativeBinaries.find(
          'libx.so',
          kind: TomNativeFileKind.library,
          executable: '${root.path}/bundle/forge',
          operatingSystem: 'linux',
          environment: const {},
        ),
        lib.path,
      );
    });

    test('NATIVE-F4: not in the bundle — the binaries layer, from '
        'TOM_BINARY_PATH or an explicit binaryPath', () {
      Directory(
        '${root.path}/Forge.app/Contents/MacOS',
      ).createSync(recursive: true);
      final inLayer = touch('layer/darwin-arm64/tool');
      final exe = '${root.path}/Forge.app/Contents/MacOS/Forge';
      expect(
        TomNativeBinaries.find(
          'tool',
          executable: exe,
          operatingSystem: 'macos',
          arch: 'arm64',
          environment: {'TOM_BINARY_PATH': '${root.path}/layer'},
        ),
        inLayer.path,
      );
      expect(
        TomNativeBinaries.find(
          'tool',
          executable: exe,
          operatingSystem: 'macos',
          arch: 'arm64',
          binaryPath: '${root.path}/layer',
          environment: const {},
        ),
        inLayer.path,
      );
    });

    test('NATIVE-F5: neither — null; an empty TOM_BINARY_PATH is none', () {
      expect(
        TomNativeBinaries.find(
          'tool',
          bundleFolders: ['${root.path}/bundle'],
          environment: {'TOM_BINARY_PATH': '${root.path}/layer'},
        ),
        isNull,
      );
      expect(
        TomNativeBinaries.find(
          'tool',
          bundleFolders: const [],
          environment: const {'TOM_BINARY_PATH': ''},
        ),
        isNull,
      );
    });

    test('NATIVE-F6: explicit bundle folders replace the running '
        'application\'s, in order', () {
      final second = touch('b/tool');
      expect(
        TomNativeBinaries.find(
          'tool',
          bundleFolders: ['${root.path}/a', '${root.path}/b'],
          environment: const {},
        ),
        second.path,
      );
      expect(
        TomNativeBinaries.findInBundle(
          'tool',
          bundleFolders: ['${root.path}/a', '${root.path}/b'],
        ),
        second.path,
      );
      expect(
        TomNativeBinaries.findInBundle('tool', bundleFolders: const []),
        isNull,
      );
    });

    test('NATIVE-F7: candidates lists the bundle paths, then the layer', () {
      expect(
        TomNativeBinaries.candidates(
          'tool.exe',
          executable: r'C:\Forge\forge.exe',
          operatingSystem: 'windows',
          arch: 'x64',
          binaryPath: r'D:\tom_binaries\tom',
        ),
        [r'C:\Forge\tool.exe', r'D:\tom_binaries\tom\win32-x64\tool.exe'],
      );
    });

    test('NATIVE-F8: the binaries repository is the layer\'s parent', () {
      expect(
        TomNativeBinaries.binariesRepository(
          environment: {'TOM_BINARY_PATH': '${root.path}/tom'},
        ),
        root.path,
      );
      expect(
        TomNativeBinaries.binariesRepository(environment: const {}),
        isNull,
      );
    });
  });
}
