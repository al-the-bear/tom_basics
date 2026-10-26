/// The file-system entry points keep what they promise, executed rather than
/// asserted.
///
/// 1. A walk of `tom_file_system.dart`'s import closure inside this package: nothing
///    reachable from it imports `dart:io`, `dart:ffi` or Flutter. `dart
///    compile js` *accepts* `dart:io` (the SDK ships a throwing stub), so only
///    the walk catches it before a browser build does.
/// 2. A real dart2js compile of a program over `tom_file_system.dart`.
///
/// Each guard has a negative control, so a guard that stopped looking fails
/// rather than passes: `io.dart` must reach `dart:io`, the walk must find the
/// file-system libraries, and dart2js must refuse a program that does not
/// compile.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_file_system/tom_file_system.dart';

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// Library → the external URIs it imports, over the libraries reachable from
/// [entry] inside this package.
Map<String, Set<String>> _closureOf(String entry) {
  final closure = <String, Set<String>>{};
  final queue = [File(entry).absolute.path];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (closure.containsKey(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    final external = <String>{};
    for (final line in file.readAsLinesSync()) {
      final uri = _directive.firstMatch(line)?.group(1);
      if (uri == null) continue;
      if (uri.startsWith('package:tom_file_system/')) {
        queue.add(
          '${Directory.current.absolute.path}/lib/'
          '${uri.substring('package:tom_file_system/'.length)}',
        );
      } else if (uri.contains(':')) {
        external.add(uri);
      } else {
        queue.add(File('${file.parent.path}/$uri').absolute.path);
      }
    }
    closure[path] = external;
  }
  return closure;
}

Set<String> _reached(String entry) =>
    _closureOf(entry).values.expand((uris) => uris).toSet();

/// Compiles [program]; the result, and the size of the JavaScript written.
Future<(ProcessResult, int)> _compileJs(String name, String program) async {
  final dart = Platform.resolvedExecutable;
  expect(
    dart.endsWith('dart') || dart.endsWith('dart.exe'),
    isTrue,
    reason:
        'run this suite with `dart test`; under another runner there '
        'is no Dart CLI to compile with',
  );
  final tmp = Directory('.dart_tool/entry_points')..createSync(recursive: true);
  final dir = tmp.createTempSync('$name-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final entry = File('${dir.path}/main.dart')..writeAsStringSync(program);
  final result = await Process.run(dart, [
    'compile',
    'js',
    '--no-source-maps',
    '--packages=${Directory.current.absolute.path}/.dart_tool/package_config.json',
    '-o',
    '${dir.path}/out.js',
    entry.path,
  ]);
  final out = File('${dir.path}/out.js');
  return (result, out.existsSync() ? out.lengthSync() : 0);
}

void main() {
  group('FILES-WEB tom_file_system.dart links everywhere', () {
    test('FILES-WEB-1: no dart:io, dart:ffi or Flutter reachable from '
        'tom_file_system.dart', () {
      final closure = _closureOf('lib/tom_file_system.dart');
      expect(
        closure.keys.where((p) => p.contains('/src/')).length,
        greaterThanOrEqualTo(4),
        reason: 'the walk found almost nothing, so it proved nothing',
      );
      final uris = _reached('lib/tom_file_system.dart');
      expect(uris, isNot(contains('dart:io')));
      expect(uris, isNot(contains('dart:ffi')));
      expect(uris.where((u) => u.startsWith('package:flutter/')), isEmpty);
    });

    test('FILES-WEB-2: io.dart is where dart:io and dart:ffi live', () {
      final uris = _reached('lib/io.dart');
      expect(uris, contains('dart:io'));
      expect(uris, contains('dart:ffi'));
    });

    test(
      'FILES-WEB-3: a program over tom_file_system.dart compiles under dart2js',
      () async {
        final (result, size) = await _compileJs('files', '''
import 'dart:convert';
import 'dart:typed_data';

import 'package:tom_file_system/tom_file_system.dart';

Future<void> main() async {
  final fs = TomMemoryFileSystem(seed: {'/a.txt': 'a'});
  print((await fs.list(fs.root)).length);
  await fs.write(fs.uriOf('b.txt'), Uint8List.fromList(utf8.encode('b')));
  print(await fs.readText(fs.uriOf('b.txt')));
  print(tomLooksLikeText(utf8.encode('text')));
}
''');
        expect(
          result.exitCode,
          0,
          reason: 'dart2js rejected it:\n${result.stdout}\n${result.stderr}',
        );
        expect(size, greaterThan(10000), reason: 'no program was written');
      },
    );

    test('FILES-WEB-4: dart2js refuses a program that does not compile, so '
        'FILES-WEB-3 is a compile and not a no-op', () async {
      final (result, size) = await _compileJs('broken', '''
import 'package:tom_file_system/tom_file_system.dart';

void main() => TomMemoryFileSystem().noSuchMember();
''');
      expect(result.exitCode, isNot(0));
      expect(size, 0);
    });
  });

  group('FILES-REDACT what a failure says', () {
    test('FILES-REDACT-1: a conflict and a missing file name the file, never '
        'its content', () async {
      final fs = TomMemoryFileSystem(seed: {'/k.env': 'TOKEN=hunter2\n'});
      final uri = fs.uriOf('k.env');
      final stale = (await fs.read(uri)).revision;
      await fs.writeText(uri, 'TOKEN=other\n');
      final conflict = await fs
          .writeText(uri, 'TOKEN=mine\n', expected: stale)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(conflict, isA<TomFileConflict>());
      expect('$conflict', isNot(contains('hunter2')));
      expect('$conflict', isNot(contains('other')));
      final missing = await fs
          .read(fs.uriOf('nope.env'))
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect('$missing', contains('nope.env'));
    });
  });
}
