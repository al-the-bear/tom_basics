// BK-CACHE: the build cache of `:compiler` (compile_cache.dart). The unit
// tests work on a temporary cache folder; BK-CACHE-6 runs bin/buildkit.dart on
// a fixture project under .dart_tool (rooted there with -R, so the workspace
// is never read) with TOM_BUILDKIT_CACHE_DIR pointing at a temporary folder.
@TestOn('vm')
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/incremental/compile_cache.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('compile_cache_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String keyOf(
    CompileCachePlan plan, {
    String inputs = 'i1',
    String sdk = '3.13.7',
    String target = 'darwin-arm64',
  }) => plan.key(inputsHash: inputs, dartSdk: sdk, targetPlatform: target);

  group('CompileCachePlan', () {
    test('BK-CACHE-1: cacheable only when every command is a dart compile '
        'with an output or a mkdir; the key leaves the output path out and '
        'names inputs, SDK and target [2026-11-14]', () {
      final plan = CompileCachePlan.of([
        'mkdir -p /bin/darwin-arm64',
        'dart compile exe bin/a.dart --target-os=macos -o /bin/darwin-arm64/a',
      ])!;
      expect(plan.outputs, ['/bin/darwin-arm64/a']);
      expect(
        CompileCachePlan.of([
          'dart compile exe a.dart --output="x y/a"',
        ])!.outputs,
        ['x y/a'],
      );
      for (final notCacheable in [
        ['dart compile exe a.dart -o a', 'cp a /usr/local/bin/a'],
        ['dart compile exe a.dart'],
        ['mkdir -p out'],
        ['./build.sh'],
      ]) {
        expect(
          CompileCachePlan.of(notCacheable),
          isNull,
          reason: '$notCacheable',
        );
      }

      final elsewhere = CompileCachePlan.of([
        'mkdir -p /other/darwin-arm64',
        'dart compile exe bin/a.dart --target-os=macos -o /other/darwin-arm64/a',
      ])!;
      expect(keyOf(elsewhere), keyOf(plan), reason: 'another TOM_BINARY_PATH');
      expect(keyOf(plan, sdk: '3.14.0'), isNot(keyOf(plan)));
      expect(keyOf(plan, inputs: 'i2'), isNot(keyOf(plan)));
      expect(keyOf(plan, target: 'linux-x64'), isNot(keyOf(plan)));
    });
  });

  group('CompileCache', () {
    late CompileCache cache;
    late String out;
    final plan = CompileCachePlan.of(['dart compile exe a.dart -o a'])!;

    setUp(() {
      cache = CompileCache(root: p.join(tmp.path, 'cache'), maxBytes: 1 << 20);
      out = p.join(tmp.path, 'bin', 'a');
    });

    void compiled(String text) => File(out)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);

    test('BK-CACHE-2: a stored compile is served again, executable; an '
        'unknown key misses [2026-11-14]', () {
      compiled('binary 1');
      if (!Platform.isWindows) Process.runSync('chmod', ['755', out]);
      cache.store(keyOf(plan), [out]);
      File(out).deleteSync();

      expect(cache.restore(keyOf(plan, inputs: 'other'), [out]), isFalse);
      expect(File(out).existsSync(), isFalse);
      expect(cache.restore(keyOf(plan), [out]), isTrue);
      expect(File(out).readAsStringSync(), 'binary 1');
      if (!Platform.isWindows) {
        expect(File(out).statSync().mode & 0x40, isNot(0), reason: 'u+x');
      }
    });

    test('BK-CACHE-3: another Dart SDK or another lock (inputs) misses '
        '[2026-11-14]', () {
      compiled('binary 1');
      cache.store(keyOf(plan), [out]);
      expect(cache.restore(keyOf(plan, sdk: '3.14.0'), [out]), isFalse);
      expect(
        cache.restore(keyOf(plan, inputs: 'lock changed'), [out]),
        isFalse,
      );
      expect(cache.restore(keyOf(plan), [out]), isTrue);
    });

    test('BK-CACHE-4: past the size limit the entries used longest ago are '
        'evicted [2026-11-14]', () async {
      cache = CompileCache(root: p.join(tmp.path, 'cache'), maxBytes: 250);
      final keys = [
        for (final i in [1, 2, 3]) keyOf(plan, inputs: 'i$i'),
      ];
      compiled('x' * 100);
      cache.store(keys[0], [out]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cache.store(keys[1], [out]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // Using the first makes the second the one used longest ago.
      expect(cache.restore(keys[0], [out]), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cache.store(keys[2], [out]);

      expect(cache.restore(keys[1], [out]), isFalse, reason: 'evicted');
      expect(cache.restore(keys[0], [out]), isTrue);
      expect(cache.restore(keys[2], [out]), isTrue);
    });

    test('BK-CACHE-5: the environment names folder and limit [2026-11-14]', () {
      final c = CompileCache.fromEnvironment({
        'HOME': '/h',
        'TOM_BUILDKIT_CACHE_MAX_MB': '5',
      });
      expect(c.root, p.join('/h', '.tom', 'cache', 'buildkit'));
      expect(c.maxBytes, 5 * 1024 * 1024);
      expect(
        CompileCache.fromEnvironment({
          'HOME': '/h',
          'TOM_BUILDKIT_CACHE_DIR': '/c',
        }).maxBytes,
        defaultCompileCacheMaxMb * 1024 * 1024,
      );
    });
  });

  test(
    'BK-CACHE-6: buildkit :compiler serves an unchanged compile from the '
    'cache, compiles a changed lock, and --no-cache compiles [2026-11-14]',
    () async {
      final base = Directory(p.join(Directory.current.path, '.dart_tool'))
        ..createSync(recursive: true);
      final root = base.createTempSync('compile_cache_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final cacheDir = p.join(tmp.path, 'cache');
      final project = p.join(root.path, 'app');
      final binary = p.join(root.path, 'out', 'main.dill');
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
      File(p.join(project, 'pubspec.yaml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('name: app\nenvironment:\n  sdk: ^3.0.0\n');
      File(p.join(project, 'bin', 'main.dart'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('void main() => print("hi");\n');
      File(p.join(project, 'buildkit.yaml')).writeAsStringSync(
        'compiler:\n  compiles:\n    - commandline:\n'
        '        - shell mkdir -p ../out\n'
        '        - shell dart compile kernel %{file} -o ../out/%{file.name}.dill\n'
        '      files:\n        - bin/main.dart\n',
      );
      final get = Process.runSync('dart', [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: project);
      expect(get.exitCode, 0, reason: '${get.stdout}${get.stderr}');
      final lock = File(p.join(project, 'pubspec.lock'));
      final lockText = lock.readAsStringSync();

      Future<String> compile(List<String> extra) async {
        final r = await Process.run(
          'dart',
          [
            'run',
            _buildkit,
            '-R',
            root.path,
            '-s',
            root.path,
            ':compiler',
            ...extra,
          ],
          workingDirectory: root.path,
          environment: {'TOM_BUILDKIT_CACHE_DIR': cacheDir},
        );
        final out = '${r.stdout}${r.stderr}';
        expect(r.exitCode, 0, reason: out);
        expect(File(binary).existsSync(), isTrue, reason: out);
        return out;
      }

      int entries() => Directory(cacheDir).existsSync()
          ? Directory(cacheDir).listSync().whereType<Directory>().length
          : 0;
      const hit = 'main.dart (';

      var out = await compile([]);
      expect(out, isNot(contains('from the build cache')));
      expect(entries(), 1);

      File(binary).deleteSync();
      out = await compile(['--force']);
      expect(out, contains('from the build cache'), reason: 'unchanged inputs');
      expect(out, contains(hit));

      lock.writeAsStringSync('$lockText# another resolution\n');
      out = await compile([]);
      expect(out, isNot(contains('from the build cache')), reason: 'lock');
      expect(entries(), 2);

      lock.writeAsStringSync(lockText);
      out = await compile([]);
      expect(out, contains('from the build cache'), reason: 'switched back');

      out = await compile(['--force', '--no-cache']);
      expect(out, isNot(contains('from the build cache')));
      expect(entries(), 2);
    },
  );
}
