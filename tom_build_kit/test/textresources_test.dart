// BK-TXTRES: `buildkit :textresources` — an application's text resource
// files assembled from its packages' lib/resources/<package>_<language>.json
// files, each package under the scope the application mounts it with (the
// workspace guideline _agent_guidelines/i18n.md, section 8). 1..13 call the
// assembly on fixture packages written under .dart_tool; 14..16 run the real
// executable, rooted there (-R), so the workspace is never read.
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/textresources/text_resources.dart';

final _buildkit = p.join(Directory.current.path, 'bin', 'buildkit.dart');

/// The rename dialog's texts (the guideline's worked example).
const _rename = {
  'rename': {
    'renameDialog': {'title': 'Rename file'},
    'nameField': {'label': 'Name', 'hint': 'e.g. notes.txt'},
    'cancelButton': {'label': 'Cancel'},
  },
};

/// The application's own texts.
const _app = {
  'main': {
    'mainPage': {'title': 'My app'},
  },
};

void main() {
  late Directory root;
  late String app;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    root = base.createTempSync('textresources_test_');
    app = p.join(root.path, 'my_app');
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A package [name] beside the application with [files] by language.
  void package(String name, Map<String, Map<String, Object?>> files) {
    final dir = Directory(p.join(root.path, name))..createSync();
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('name: $name\n');
    for (final entry in files.entries) {
      File(p.join(dir.path, 'lib', 'resources', '${name}_${entry.key}.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({name: entry.value}));
    }
  }

  /// The application with its own texts, its `text-resources:` section and
  /// a package configuration naming [packages] (and itself).
  void application(String section, {List<String> packages = const []}) {
    package('my_app', {'en': _app});
    File(
      p.join(app, 'buildkit.yaml'),
    ).writeAsStringSync('text-resources:\n$section');
    File(p.join(app, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {'name': 'my_app', 'rootUri': '../', 'packageUri': 'lib/'},
            for (final name in packages)
              {'name': name, 'rootUri': '../../$name', 'packageUri': 'lib/'},
          ],
        }),
      );
  }

  Map<String, Object?> read(String relative) =>
      jsonDecode(File(p.join(app, relative)).readAsStringSync())
          as Map<String, Object?>;

  Matcher fails(String text) => throwsA(
    isA<TextResourcesException>().having(
      (e) => e.message,
      'message',
      contains(text),
    ),
  );

  test('BK-TXTRES-1: the packages under their scopes, the application\'s own '
      'too; written to the default output in the mounts\' order', () {
    package('rename_demo', {'en': _rename});
    application(
      '''
  mounts:
    - scope: app
      package: my_app
    - scope: files
      package: rename_demo
''',
      packages: ['rename_demo'],
    );
    final run = runTextResources(app)!;
    expect(run.written, ['assets/resources/my_app_en.json']);
    final texts = read('assets/resources/my_app_en.json');
    expect(texts.keys, ['app', 'files']);
    expect(texts['app'], _app);
    expect(texts['files'], _rename);
    expect((texts['files']! as Map).keys, [
      'rename',
    ], reason: 'each block in its file\'s order');
  });

  test('BK-TXTRES-2: a package under two scopes appears twice; a nested '
      'scope nests one level deeper', () {
    package('rename_demo', {'en': _rename});
    application(
      '''
  mounts:
    - scope: files
      package: rename_demo
    - scope: workbench.explorer
      package: rename_demo
''',
      packages: ['rename_demo'],
    );
    runTextResources(app);
    expect(read('assets/resources/my_app_en.json'), {
      'files': _rename,
      'workbench': {'explorer': _rename},
    });
  });

  test('BK-TXTRES-3: an unchanged input gives an unchanged file; --check '
      'reports a file that differs and writes nothing', () {
    package('rename_demo', {'en': _rename});
    application(
      '''
  mounts:
    - scope: files
      package: rename_demo
''',
      packages: ['rename_demo'],
    );
    runTextResources(app);
    final file = File(p.join(app, 'assets/resources/my_app_en.json'));
    final first = file.readAsStringSync();
    final again = runTextResources(app)!;
    expect(again.written, isEmpty);
    expect(again.unchanged, ['assets/resources/my_app_en.json']);
    expect(file.readAsStringSync(), first);
    expect(runTextResources(app, check: true)!.differing, isEmpty);

    file.writeAsStringSync('{}\n');
    final checked = runTextResources(app, check: true)!;
    expect(checked.differing, ['assets/resources/my_app_en.json']);
    expect(file.readAsStringSync(), '{}\n', reason: '--check writes nothing');
  });

  test('BK-TXTRES-4: the overrides file is laid over the result; Tom Core\'s '
      'global captions are added', () {
    package('rename_demo', {'en': _rename});
    application(
      '''
  overrides: lib/resources/overrides_{language}.json
  mounts:
    - scope: files
      package: rename_demo
''',
      packages: ['rename_demo'],
    );
    File(p.join(app, 'lib/resources/overrides_en.json')).writeAsStringSync(
      jsonEncode({
        'files': {
          'rename': {
            'renameDialog': {'title': 'Rename this file'},
          },
        },
        'form': {'cancel': 'Abort'},
      }),
    );
    runTextResources(app);
    final texts = read('assets/resources/my_app_en.json');
    expect(((texts['files']! as Map)['rename'] as Map)['renameDialog'], {
      'title': 'Rename this file',
    });
    expect(texts['form'], {'cancel': 'Abort'});
  });

  test('BK-TXTRES-5: a language a package lacks is filled from the reference '
      'language, a missing entry too, each with a warning', () {
    package('rename_demo', {
      'en': _rename,
      'de': {
        'rename': {
          'renameDialog': {'title': 'Datei umbenennen'},
        },
      },
    });
    package('other_demo', {
      'en': {
        'other': {
          'okButton': {'label': 'OK'},
        },
      },
    });
    application(
      '''
  languages: [en, de]
  mounts:
    - scope: files
      package: rename_demo
    - scope: other
      package: other_demo
''',
      packages: ['rename_demo', 'other_demo'],
    );
    final run = runTextResources(app)!;
    expect(run.written, [
      'assets/resources/my_app_en.json',
      'assets/resources/my_app_de.json',
    ]);
    final de = read('assets/resources/my_app_de.json');
    final rename = (de['files']! as Map)['rename'] as Map;
    expect(rename['renameDialog'], {'title': 'Datei umbenennen'});
    expect(rename['nameField'], {'label': 'Name', 'hint': 'e.g. notes.txt'});
    expect(rename.keys, ['renameDialog', 'nameField', 'cancelButton']);
    expect(de['other'], {
      'other': {
        'okButton': {'label': 'OK'},
      },
    });
    expect(run.warnings, hasLength(2));
    expect(run.warnings[0], contains('rename_demo_de.json lacks 2 entries'));
    expect(run.warnings[0], contains('rename.nameField'));
    expect(run.warnings[1], contains('other_demo has no other_demo_de.json'));
  });

  test('BK-TXTRES-6: the Dart source holds every language\'s map', () {
    package('rename_demo', {'en': _rename});
    application(
      r'''
  languages: [en]
  dart: lib/generated/{app}_texts.g.dart
  mounts:
    - scope: files
      package: rename_demo
''',
      packages: ['rename_demo'],
    );
    final run = runTextResources(app)!;
    expect(run.written, contains('lib/generated/my_app_texts.g.dart'));
    final source = File(
      p.join(app, 'lib/generated/my_app_texts.g.dart'),
    ).readAsStringSync();
    expect(
      source,
      contains(
        'const Map<String, Map<String, Object?>> '
        'textResources = <String, Object?>{',
      ),
    );
    expect(source, contains("'en': <String, Object?>{"));
    expect(source, contains("'title': 'Rename file',"));
  });

  test(
    'BK-TXTRES-7: the Dart source escapes quotes, dollars and line breaks',
    () {
      final source = dartTextResources({
        'en': {
          'a': {'text': "it's \$5\nnow"},
        },
      }, app: 'x');
      expect(source, contains(r"'text': 'it\'s \$5\nnow',"));
    },
  );

  group('the reports', () {
    test('BK-TXTRES-8: a mounted package without a file for the reference '
        'language', () {
      package('rename_demo', {'de': _rename});
      application(
        '''
  mounts:
    - scope: files
      package: rename_demo
''',
        packages: ['rename_demo'],
      );
      expect(
        () => runTextResources(app),
        fails(
          'the package rename_demo (mounted at "files") has no '
          'rename_demo_en.json',
        ),
      );
    });

    test('BK-TXTRES-9: two mounts at the same scope', () {
      package('rename_demo', {'en': _rename});
      package('other_demo', {'en': _rename});
      application(
        '''
  mounts:
    - scope: files
      package: rename_demo
    - scope: files
      package: other_demo
''',
        packages: ['rename_demo', 'other_demo'],
      );
      expect(
        () => runTextResources(app),
        fails(
          'the mount of other_demo at "files" would overwrite the mount '
          'of rename_demo at the same scope',
        ),
      );
    });

    test('BK-TXTRES-10: a scope that is an entry of a package mounted above '
        'it, in either order', () {
      package('rename_demo', {'en': _rename});
      application(
        '''
  mounts:
    - scope: app
      package: my_app
    - scope: app.main
      package: rename_demo
''',
        packages: ['rename_demo'],
      );
      expect(
        () => runTextResources(app),
        fails(
          'the mount of rename_demo at "app.main" would overwrite the '
          'entry "app.main" of my_app (mounted at "app")',
        ),
      );
      application(
        '''
  mounts:
    - scope: app.main
      package: rename_demo
    - scope: app
      package: my_app
''',
        packages: ['rename_demo'],
      );
      expect(
        () => runTextResources(app),
        fails('both place the entry "app.main"'),
      );
    });

    test('BK-TXTRES-11: a package mounted inside another\'s block where the '
        'block has no such entry is no conflict', () {
      package('rename_demo', {'en': _rename});
      application(
        '''
  mounts:
    - scope: app
      package: my_app
    - scope: app.files
      package: rename_demo
''',
        packages: ['rename_demo'],
      );
      runTextResources(app);
      expect((read('assets/resources/my_app_en.json')['app']! as Map).keys, [
        'main',
        'files',
      ]);
    });

    test('BK-TXTRES-12: an override for an entry that does not exist', () {
      package('rename_demo', {'en': _rename});
      application(
        '''
  overrides: lib/resources/overrides_{language}.json
  mounts:
    - scope: files
      package: rename_demo
''',
        packages: ['rename_demo'],
      );
      File(p.join(app, 'lib/resources/overrides_en.json')).writeAsStringSync(
        jsonEncode({
          'files': {
            'rename': {
              'deleteButton': {'label': 'Delete'},
            },
          },
        }),
      );
      expect(
        () => runTextResources(app),
        fails(
          'the overrides for en name "files.rename.deleteButton", which '
          'the assembled file does not have',
        ),
      );
    });

    test('BK-TXTRES-13: a scope Tom Core refuses, a package the application '
        'does not depend on, a section without mounts', () {
      for (final scope in ['a..b', '.a', 'a.', 'a-b']) {
        expect(
          () => TextResourcesConfig.parse({
            'mounts': [
              {'scope': scope, 'package': 'x'},
            ],
          }),
          fails('the scope "$scope" of the mount of x'),
        );
      }
      expect(
        () => TextResourcesConfig.parse({'mounts': []}),
        fails('mounts must be a non-empty list'),
      );
      expect(
        () => TextResourcesConfig.parse({
          'langs': ['en'],
          'mounts': [
            {'scope': 'a', 'package': 'x'},
          ],
        }),
        fails('unknown key "langs"'),
      );
      application('''
  mounts:
    - scope: files
      package: missing_demo
''');
      expect(
        () => runTextResources(app),
        fails(
          'the package missing_demo is mounted but not among the '
          'application\'s dependencies',
        ),
      );
    });
  });

  group('the command', () {
    setUp(() {
      File(p.join(root.path, 'buildkit_master.yaml')).writeAsStringSync('');
    });

    Future<ProcessResult> buildkit(List<String> args) => Process.run('dart', [
      'run',
      _buildkit,
      '-R',
      root.path,
      '-s',
      root.path,
      ...args,
    ], workingDirectory: root.path);

    String out(ProcessResult r) => '${r.stdout}${r.stderr}';

    void appWithRename() {
      package('rename_demo', {'en': _rename});
      application(
        '''
  mounts:
    - scope: files
      package: rename_demo
''',
        packages: ['rename_demo'],
      );
    }

    test('BK-TXTRES-14: :textresources writes the file; --check then passes, '
        'and fails once the file is changed', () async {
      appWithRename();
      var r = await buildkit(['-p', 'my_app', ':textresources']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('wrote assets/resources/my_app_en.json'));
      expect(read('assets/resources/my_app_en.json')['files'], _rename);

      r = await buildkit(['-p', 'my_app', ':textresources', '--check']);
      expect(r.exitCode, 0, reason: out(r));

      File(
        p.join(app, 'assets/resources/my_app_en.json'),
      ).writeAsStringSync('{}\n');
      r = await buildkit(['-p', 'my_app', ':textresources', '--check']);
      expect(r.exitCode, 1, reason: out(r));
      expect(
        out(r),
        contains(
          'differs from a fresh assembly: '
          'assets/resources/my_app_en.json',
        ),
      );
    });

    test('BK-TXTRES-15: a report fails the command with its message', () async {
      appWithRename();
      File(
        p.join(root.path, 'rename_demo/lib/resources/rename_demo_en.json'),
      ).deleteSync();
      final r = await buildkit(['-p', 'my_app', ':textresources']);
      expect(r.exitCode, 1, reason: out(r));
      expect(out(r), contains('has no rename_demo_en.json'));
    });

    test('BK-TXTRES-16: :build assembles the text resources before its '
        'build step', () async {
      appWithRename();
      File(p.join(app, 'buildkit.yaml')).writeAsStringSync(
        '${File(p.join(app, 'buildkit.yaml')).readAsStringSync()}'
        'build: test -f assets/resources/my_app_en.json\n',
      );
      final r = await buildkit(['-p', 'my_app', ':build']);
      expect(r.exitCode, 0, reason: out(r));
      expect(out(r), contains('wrote assets/resources/my_app_en.json'));
    });
  });
}
