/// The rolling log file of `package:tom_basics/diagnostics_io.dart`.
///
/// Three properties are what make it a *log* rather than a file that grows:
/// it rolls, it stays structured to the last moment, and it stops rather than
/// stalling when the disk refuses it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tom_basics/diagnostics_io.dart';

/// Per the workspace rule, scratch trees go to `<ws-root>/ztmp`.
Directory scratch() {
  final marker = Directory.current;
  var dir = marker;
  while (!Directory('${dir.path}/ztmp').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      fail('no ztmp directory above ${marker.path}');
    }
    dir = parent;
  }
  final out = Directory('${dir.path}/ztmp/tom_basics_file_diagnostics')
    ..createSync(recursive: true);
  return out.createTempSync('log-');
}

TomDiagnosticEvent event(
  String operation, {
  Map<String, Object?> fields = const {},
  TomDiagnosticLevel level = TomDiagnosticLevel.info,
}) =>
    TomDiagnosticEvent(
      operation: operation,
      fields: fields,
      level: level,
    );

List<Map<String, Object?>> linesOf(String path) => [
      for (final line in File(path).readAsLinesSync())
        if (line.isNotEmpty) jsonDecode(line) as Map<String, Object?>,
    ];

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = scratch();
    path = '${dir.path}/app.log';
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // ───────────────────────────────────────────────────────────────────────
  group('R1 it writes structured lines', () {
    test('WONEPRPC109-1: one JSON object per line, with its own directory '
        '[0923]', () {
      // The directory is created rather than required: a fresh install has a
      // data directory and no `logs/` in it, and a sink that refused to write
      // until somebody made the folder would keep nothing from the one session
      // most likely to need it.
      final nested = '${dir.path}/logs/app.log';
      final sink = TomFileDiagnostics(path: nested);
      sink.log(event('script.run', fields: {'runId': 'r1', 'status': 'ok'}));
      sink.log(event('sync.commit', fields: {'documentLocator': 'a.doc'}));

      final lines = linesOf(nested);
      expect(lines, hasLength(2));
      expect(lines[0]['operation'], 'script.run');
      expect(lines[0]['runId'], 'r1');
      expect(lines[0]['level'], 'info');
      expect(DateTime.parse(lines[0]['at']! as String).isUtc, isTrue,
          reason: 'a local stamp makes two hosts\' lines uncomparable');
      expect(lines[1]['operation'], 'sync.commit');
      expect(sink.failure, isNull);
    });

    test('WONEPRPC109-2: appends across instances [0923]', () {
      // The point of a file: it outlives the object, and the process.
      TomFileDiagnostics(path: path).log(event('a'));
      TomFileDiagnostics(path: path).log(event('b'));
      expect([for (final line in linesOf(path)) line['operation']], ['a', 'b']);
    });

    test('WONEPRPC109-3: a value that is not JSON is named, never rendered '
        '[0923]', () {
      // The redaction rule is structural, and it only has teeth while the
      // payload is data. `toString()` of a token would put the token in the
      // file; naming the type keeps the finding — somebody logged the wrong
      // kind of thing — and leaks nothing.
      final sink = TomFileDiagnostics(path: path);
      sink.log(event('odd', fields: {'thing': _Secret('hunter2')}));

      final raw = File(path).readAsStringSync();
      expect(raw, isNot(contains('hunter2')));
      expect(linesOf(path).single['thing'], '<non-JSON _Secret>');
    });

    test('WONEPRPC109-4: `debug` is dropped by default, and at the sink '
        '[0923]', () {
      // Filtered here rather than at each call site: a producer that had to
      // ask the sink's level before logging would be a producer that could
      // forget to.
      final sink = TomFileDiagnostics(path: path);
      sink.log(event('seen', level: TomDiagnosticLevel.error));
      sink.log(event('seen2', level: TomDiagnosticLevel.info));
      sink.log(event('dropped', level: TomDiagnosticLevel.debug));
      expect([for (final line in linesOf(path)) line['operation']],
          ['seen', 'seen2']);

      final verbose = TomFileDiagnostics(
        path: '${dir.path}/verbose.log',
        minimumLevel: TomDiagnosticLevel.debug,
      );
      verbose.log(event('kept', level: TomDiagnosticLevel.debug));
      expect(linesOf('${dir.path}/verbose.log'), hasLength(1));
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R2 it rolls', () {
    test('WONEPRPC109-5: the live file never exceeds its ceiling [0923]', () {
      // "Rolling" with no ceiling is the unbounded growth the sink guards against
      // wearing a different name. The check is *before* the append, so the
      // ceiling is a ceiling rather than a line the file crosses and then
      // retreats from at the next write.
      final sink =
          TomFileDiagnostics(path: path, maxBytes: 400, generations: 3);
      for (var i = 0; i < 40; i++) {
        sink.log(event('op$i', fields: {'n': i}));
      }
      expect(File(path).lengthSync(), lessThanOrEqualTo(400));
      expect(File('$path.1').existsSync(), isTrue);
      expect(File('$path.2').existsSync(), isTrue);
      expect(File('$path.3').existsSync(), isFalse,
          reason: 'three generations means three files, live one included');

      // The newest lines are in the live file, the oldest are gone.
      final live = linesOf(path);
      expect(live, isNotEmpty);
      expect(live.last['operation'], 'op39');
    });

    test('WONEPRPC109-6: generations shift, and the oldest is dropped [0923]',
        () {
      final sink =
          TomFileDiagnostics(path: path, maxBytes: 120, generations: 3);
      sink.log(event('first'));
      sink.log(event('second'));
      sink.log(event('third'));
      sink.log(event('fourth'));

      // Each write over the ceiling pushes the live file down one slot, so the
      // three surviving files are the three most recent in order.
      final generations = [
        [for (final l in linesOf(path)) l['operation']],
        [for (final l in linesOf('$path.1')) l['operation']],
        [for (final l in linesOf('$path.2')) l['operation']],
      ];
      expect(generations, [
        ['fourth'],
        ['third'],
        ['second'],
      ]);
      expect(File('$path.3').existsSync(), isFalse,
          reason: '`first` was dropped rather than kept for ever');
    });

    test(
        'WONEPRPD149-1: rotation never renames onto an occupied name, so the '
        'sink keeps writing through many rotations on every platform [1001]',
        () {
      // Windows refuses a rename onto an existing file, POSIX replaces it. The
      // sink refuses on every platform, so the one ordering that keeps
      // rotation working on Windows is checked on the machines that run this
      // suite: without the oldest generation deleted first, the third rotation
      // stops the sink here too.
      final sink =
          TomFileDiagnostics(path: path, maxBytes: 120, generations: 3);
      for (var i = 0; i < 12; i++) {
        sink.log(event('op$i'));
      }
      expect(sink.failure, isNull);
      expect([for (final l in linesOf(path)) l['operation']], ['op11']);
      expect([for (final l in linesOf('$path.2')) l['operation']], ['op9']);
    });

    test('WONEPRPC109-7: one generation is a truncation, not a stray `.1` '
        '[0923]', () {
      final sink =
          TomFileDiagnostics(path: path, maxBytes: 120, generations: 1);
      sink.log(event('first'));
      sink.log(event('second'));
      expect([for (final l in linesOf(path)) l['operation']], ['second']);
      expect(File('$path.1').existsSync(), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────
  group('R3 it fails quietly and says so', () {
    test('WONEPRPC109-8: a refused write stops the sink rather than throwing '
        '[0923]', () {
      // A sink that threw would take its producer down; one that retried per
      // line would turn a full disk into a stall on every operation that logs.
      // It stops, and keeps the reason for a surface that wants to say so.
      //
      // The blocker is a **file** where the log's parent directory should be,
      // so creating the directory fails — and it can be removed, which is what
      // makes "it stopped" checkable. Asserting `failure` twice would not:
      // a sink that retried would fail again and report exactly the same thing.
      final blocker = File('${dir.path}/blocked')..writeAsStringSync('x');
      final sink = TomFileDiagnostics(path: '${blocker.path}/app.log');

      expect(() => sink.log(event('a')), returnsNormally);
      expect(sink.failure, isNotNull);
      expect(sink.failure, isA<FileSystemException>());

      // The obstruction goes away. A retrying sink would now succeed; this one
      // has given up, and stays given up until somebody repoints it.
      blocker.deleteSync();
      sink.log(event('b'));
      expect(File('${blocker.path}/app.log').existsSync(), isFalse,
          reason: 'it did not try again');
      expect(sink.failure, isNotNull);
    });

    test('WONEPRPC109-9: repointing the path gives it another chance [0923]',
        () {
      // An application keeps the location in settings, which are read after the
      // first frame — so a sink is built at a default and repointed. A sink
      // that had given up on the old path has no reason to give up on a new
      // one, and the reason it gave up may have *been* the old path.
      final sink = TomFileDiagnostics(path: '${dir.path}/nope/../');
      sink.log(event('lost'));
      expect(sink.failure, isNotNull);

      sink.path = path;
      expect(sink.failure, isNull);
      sink.log(event('kept'));
      expect([for (final l in linesOf(path)) l['operation']], ['kept'],
          reason: 'and nothing is carried across — the lost line is lost');
    });

    test('WONEPRPC109-10: repointing to the same path is not a reset [0923]',
        () {
      final sink = TomFileDiagnostics(path: '${dir.path}/nope/../');
      sink.log(event('a'));
      final failure = sink.failure;
      sink.path = '${dir.path}/nope/../';
      expect(identical(sink.failure, failure), isTrue);
    });
  });
}

/// Stands in for the typed values that must not be interpolable — a token,
/// a key, a protected value.
class _Secret {
  const _Secret(this.value);
  final String value;

  @override
  String toString() => 'Secret($value)';
}
