/// The flutter lock: one holder at a time, released on every path.
///
/// Spawns `mkdir` and one Dart child; the longest stated wait is 150 ms; the bound is for a child that hangs.
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/ci.dart';

import 'support_scratch.dart';

void main() {
  group('CI-LOCK the flutter lock', () {
    late String path;
    setUp(() => path = p.join(scratchDir('lock').path, 'flutter.lock'));

    test('CI-LOCK-1: a free lock is taken at once and released', () async {
      final lock = CiLock(path);
      await lock.acquire();
      expect(lock.held, isTrue);
      expect(Directory(path).existsSync(), isTrue);
      lock.release();
      expect(lock.held, isFalse);
      expect(Directory(path).existsSync(), isFalse);
      lock.release(); // idempotent
    });

    test('CI-LOCK-2: a second holder waits until the first releases', () async {
      final first = CiLock(path);
      await first.acquire();
      final second = CiLock(path);
      final waits = <Duration>[];
      var taken = false;
      final pending = second
          .acquire(poll: const Duration(milliseconds: 20), onWait: waits.add)
          .then((_) => taken = true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(taken, isFalse, reason: 'two holders at once is the hazard');
      expect(waits, isNotEmpty, reason: 'the wait is reported');
      first.release();
      await pending;
      expect(second.held, isTrue);
      second.release();
    });

    test(
      'CI-LOCK-3: a lock a session took with a plain mkdir is honoured',
      () async {
        Directory(path).createSync(recursive: true); // the session's mkdir
        final lock = CiLock(path);
        var taken = false;
        final pending = lock
            .acquire(poll: const Duration(milliseconds: 20))
            .then((_) => taken = true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(taken, isFalse);
        Directory(path).deleteSync(); // the session's rmdir
        await pending;
        expect(lock.held, isTrue);
        lock.release();
      },
    );

    test(
      'CI-LOCK-4: the runner releases the lock when a child fails',
      () async {
        final lock = CiLock(path);
        final runner = CiProcessRunner(lock: lock);
        final log = p.join(p.dirname(path), 'fail.log');
        final result = await runner.run([
          CiCommand(Platform.resolvedExecutable, [
            'no_such_script.dart',
          ], workingDirectory: p.dirname(path)),
        ], logPath: log);
        expect(result.ok, isFalse);
        expect(lock.held, isFalse);
        expect(Directory(path).existsSync(), isFalse);
      },
    );
  });
}
