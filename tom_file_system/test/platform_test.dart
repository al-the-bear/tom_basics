/// The local file system's platform parts, as far as one host can run them.
///
///  (W) Watching one directory at a time — the watch on Linux, where
///      `Directory.watch(recursive: true)` is not recursive — sees an edit
///      below the root, a file in a folder created after the watch began, and
///      nothing inside a folder the walk does not enter. Run on Linux only.
///  (F) The same watch's bookkeeping, over watches the test drives, on every
///      host.
///  (T) The home trash of the freedesktop.org Trash specification, the Linux
///      fallback when neither `gio` nor `trash-put` is installed.
///
/// The same behaviours on Linux and Windows themselves are checked by
/// `tool/platform_check/run.sh`, in containers.
// Waits for filesystem events: the longest bound this file states is ten
// seconds per event.
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_file_system/io.dart';

/// Writes [write] until [changes] reports [path], so a watch that is still
/// being set up does not make the test flaky; fails after ten seconds.
Future<void> _seen(
  List<String> changes,
  String path,
  void Function() write,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!changes.contains(path)) {
    expect(
      DateTime.now().isBefore(deadline),
      isTrue,
      reason: '$path never reported; saw $changes',
    );
    write();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// Why the platform's per-directory watch is not run here, or null where it
/// is. [TomLocalFileSystem] uses it on Linux only; macOS and Windows use
/// the platform's recursive watch. On macOS a watch can also deliver nothing
/// for its whole life while the machine is busy, so a test there would
/// measure the platform's delivery, not this class. Its bookkeeping is held
/// on every host by WATCH-F1..F3 over driven watches.
final String? _platformWatchSkip = !FileSystemEntity.isWatchSupported
    ? 'this platform does not watch'
    : !Platform.isLinux
    ? 'the per-directory watch is the Linux watch; its run against the '
          'platform is measured on Linux (tool/platform_check/run.sh)'
    : null;

/// Waits, in real time, until [done] holds; false after [within].
Future<bool> _until(
  bool Function() done, {
  Duration within = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(within);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return true;
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('tom_fs_platform_'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('WATCH-W watching one directory at a time', () {
    test(
      'WATCH-W1: an edit below the root and a file in a folder made '
      'later are both reported',
      skip: _platformWatchSkip,
      () async {
        Directory(p.join(root.path, 'a', 'b')).createSync(recursive: true);
        final nested = File(p.join(root.path, 'a', 'b', 'f.txt'))
          ..writeAsStringSync('1');
        final changes = <String>[];
        final watches = TomDirectoryWatches(root.path, descend: (_) => true);
        final sub = watches.stream.listen(
          (path) => changes.add(p.relative(path, from: root.path)),
        );
        addTearDown(sub.cancel);
        // The watches start asynchronously; on a loaded machine a write made
        // before they exist is never seen.
        await watches.started;

        await _seen(
          changes,
          p.join('a', 'b', 'f.txt'),
          () => nested.writeAsStringSync('2'),
        );

        Directory(
          p.join(root.path, 'later', 'deep'),
        ).createSync(recursive: true);
        final fresh = File(p.join(root.path, 'later', 'deep', 'g.txt'));
        await _seen(
          changes,
          p.join('later', 'deep', 'g.txt'),
          () => fresh.writeAsStringSync('x'),
        );
      },
    );

    test(
      'WATCH-W2: a folder the walk does not enter is not watched, '
      'and a deleted folder\'s watches end',
      skip: _platformWatchSkip,
      () async {
        Directory(
          p.join(root.path, '.git', 'objects'),
        ).createSync(recursive: true);
        Directory(p.join(root.path, 'src', 'lib')).createSync(recursive: true);
        final watches = TomDirectoryWatches(
          root.path,
          descend: (dir) => dir != '.git',
        );
        final changes = <String>[];
        final sub = watches.stream.listen(changes.add);
        addTearDown(sub.cancel);
        await watches.started;
        final probe = File(p.join(root.path, 'src', 'lib', 'probe.txt'));
        await _seen(changes, probe.path, () => probe.writeAsStringSync('x'));
        // root, src, src/lib — not .git, not .git/objects.
        expect(watches.watchedCount, 3);

        Directory(p.join(root.path, 'src')).deleteSync(recursive: true);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (watches.watchedCount != 1) {
          expect(
            DateTime.now().isBefore(deadline),
            isTrue,
            reason: 'still watching ${watches.watchedCount} directories',
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      },
    );
  });

  group('TRASH-T the home trash', () {
    test('TRASH-T1: a file and a folder move into Trash/files with a '
        'record of where they were and when', () {
      final data = Directory(p.join(root.path, 'data'))..createSync();
      final file = File(p.join(root.path, 'my notes.md'))
        ..writeAsStringSync('n');
      final folder = Directory(p.join(root.path, 'old'))..createSync();
      File(p.join(folder.path, 'inside.txt')).writeAsStringSync('i');
      final env = {'XDG_DATA_HOME': data.path};
      final at = DateTime(2026, 10, 13, 9, 5, 7);

      expect(tomXdgTrash(file.path, environment: env, now: at), isTrue);
      expect(tomXdgTrash(folder.path, environment: env, now: at), isTrue);
      expect(file.existsSync(), isFalse);
      expect(folder.existsSync(), isFalse);

      final trash = p.join(data.path, 'Trash');
      expect(
        File(p.join(trash, 'files', 'my notes.md')).readAsStringSync(),
        'n',
      );
      expect(
        File(p.join(trash, 'files', 'old', 'inside.txt')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(trash, 'info', 'my notes.md.trashinfo')).readAsStringSync(),
        '[Trash Info]\n'
        'Path=${Uri(path: file.path)}\n'
        'DeletionDate=2026-10-13T09:05:07\n',
      );
      expect(Uri(path: file.path).toString(), contains('my%20notes.md'));
    });

    test('TRASH-T2: a second item of the same name gets its own name '
        'in the trash', () {
      final data = Directory(p.join(root.path, 'data'))..createSync();
      final env = {'XDG_DATA_HOME': data.path};
      for (final dir in ['one', 'two']) {
        final file = File(p.join(root.path, dir, 'same.txt'))
          ..createSync(recursive: true)
          ..writeAsStringSync(dir);
        expect(tomXdgTrash(file.path, environment: env), isTrue);
      }
      final files = p.join(data.path, 'Trash', 'files');
      expect(File(p.join(files, 'same.txt')).readAsStringSync(), 'one');
      expect(File(p.join(files, 'same.txt.1')).readAsStringSync(), 'two');
      expect(
        File(
          p.join(data.path, 'Trash', 'info', 'same.txt.1.trashinfo'),
        ).existsSync(),
        isTrue,
      );
    });

    test('TRASH-T3: with no home the item stays where it is', () {
      final file = File(p.join(root.path, 'kept.txt'))..writeAsStringSync('k');
      expect(tomXdgTrash(file.path, environment: const {}), isFalse);
      expect(file.existsSync(), isTrue);
    });
  });

  group('WATCH-F the per-directory watch, over watches the test drives', () {
    late Map<String, StreamController<FileSystemEvent>> driven;
    TomDirectoryWatches watches({bool Function(String)? descend}) {
      driven = {};
      return TomDirectoryWatches(
        root.path,
        descend: descend ?? (_) => true,
        watchDirectory: (dir) =>
            (driven[dir] = StreamController<FileSystemEvent>.broadcast())
                .stream,
      );
    }

    String rel(String absolute) => p.relative(absolute, from: root.path);

    test(
      'WATCH-F1: every directory is watched; a folder that appears '
      'is watched with what is in it, and its changes are reported',
      () async {
        Directory(p.join(root.path, 'a', 'b')).createSync(recursive: true);
        final w = watches();
        final changes = <String>[];
        final sub = w.stream.listen((path) => changes.add(rel(path)));
        addTearDown(sub.cancel);
        await w.started;
        expect(driven.keys.map(rel), unorderedEquals(['.', 'a', 'a/b']));

        final later = p.join(root.path, 'later');
        Directory(p.join(later, 'deep')).createSync(recursive: true);
        driven[root.path]!.add(FileSystemCreateEvent(later, true));
        expect(await _until(() => w.watchedCount == 5), isTrue);
        expect(driven.keys.map(rel), containsAll(['later', 'later/deep']));

        final file = p.join(later, 'deep', 'g.txt');
        driven[p.join(later, 'deep')]!.add(
          FileSystemModifyEvent(file, false, true),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          changes,
          containsAll(['later', p.join('later', 'deep', 'g.txt')]),
        );
      },
    );

    test('WATCH-F2: a folder the walk does not enter is not watched; a '
        'deleted folder\'s watches end, its own and those below it', () async {
      Directory(
        p.join(root.path, '.git', 'objects'),
      ).createSync(recursive: true);
      Directory(p.join(root.path, 'src', 'lib')).createSync(recursive: true);
      final w = watches(descend: (dir) => dir != '.git');
      final sub = w.stream.listen((_) {});
      addTearDown(sub.cancel);
      await w.started;
      expect(driven.keys.map(rel), unorderedEquals(['.', 'src', 'src/lib']));

      driven[root.path]!.add(
        FileSystemDeleteEvent(p.join(root.path, 'src'), true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(w.watchedCount, 1);
    });

    test('WATCH-F3: a failing folder below the root is dropped and the '
        'rest keep running; a failing root ends the stream with the error '
        '[1019]', () async {
      Directory(p.join(root.path, 'a')).createSync();
      final w = watches();
      final errors = <Object>[];
      final sub = w.stream.listen((_) {}, onError: errors.add);
      addTearDown(sub.cancel);
      await w.started;

      driven[p.join(root.path, 'a')]!.addError(
        const FileSystemException('gone'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(w.watchedCount, 1);
      expect(errors, isEmpty);

      driven[root.path]!.addError(const FileSystemException('unmounted'));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
    });
  });
}
