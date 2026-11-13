// The natures of the SOM runtime languages other than Dart (build_tom
// build_cleanup6). Every fixture copies the shape of the corresponding
// tom_ai/ai_build/tom_som_<lang>_runtime: its project file, identity and
// source layout.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';

const _pyproject = '''
[build-system]
requires = ["setuptools>=77"]
build-backend = "setuptools.build_meta"

[project]
name = "tom_som_python_runtime"
# Version tracks the TomSpecs model version.
version = "1.9.0"
requires-python = ">=3.9"
''';

const _pom = '''
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.example</groupId>
    <artifactId>parent_pom</artifactId>
    <version>9.9.9</version>
  </parent>
  <groupId>ai.tom</groupId>
  <artifactId>tom_som_java_runtime</artifactId>
  <!-- <version>0.0.0</version> in a comment is not the version -->
  <version>1.9.0</version>
  <dependencies>
    <dependency>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
    </dependency>
  </dependencies>
</project>
''';

const _cargo = '''
# tom_som_rust_runtime
[package]
name = "tom_som_rust_runtime"
version = "1.9.0"
edition = "2021"

[dependencies]
serde = { version = "1.0" }
''';

const _packageJson = '''
{
  "name": "tom_som_javascript_runtime",
  "version": "1.9.0",
  "type": "commonjs",
  "scripts": {
    "test": "node --test tests/"
  },
  "devDependencies": {
    "some-lib": { "version": "2.0.0" }
  }
}
''';

void main() {
  late Directory tmp;
  final detector = NatureDetector();

  setUp(() => tmp = Directory.systemTemp.createTempSync('bb_lang_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String project(String name, Map<String, String> files) {
    final dir = p.join(tmp.path, name);
    files.forEach((rel, text) {
      File(p.join(dir, rel))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(text);
    });
    return dir;
  }

  List<RunFolder> natures(String dir) =>
      detector.detectNatures(FsFolder(path: dir));

  T single<T extends RunFolder>(String dir) =>
      natures(dir).whereType<T>().single;

  group('detection and identity', () {
    test('BB-LNG-1: JavaScript: package.json without tsconfig.json', () {
      final dir = project('js', {
        'package.json': _packageJson,
        'tom_som_runtime/index.js': '',
      });
      final js = single<JavaScriptFolder>(dir);
      expect(js.projectName, 'tom_som_javascript_runtime');
      expect(js.version, '1.9.0');
      expect(js.scripts['test'], 'node --test tests/');
      expect(js.language, 'javascript');
      expect(natures(dir).whereType<TypeScriptFolder>(), isEmpty);
    });

    test('BB-LNG-2: TypeScript: tsconfig.json; a TypeScript project is no '
        'JavaScript project, and is a language project', () {
      final dir = project('ts', {
        'package.json': _packageJson.replaceAll('javascript', 'typescript'),
        'tsconfig.json': '{}',
      });
      final ts = single<TypeScriptFolder>(dir);
      expect(ts.projectName, 'tom_som_typescript_runtime');
      expect(ts.version, '1.9.0');
      expect(ts, isA<LanguageProjectFolder>());
      expect(ts.language, 'typescript');
      expect(natures(dir).whereType<JavaScriptFolder>(), isEmpty);
    });

    test('BB-LNG-3: Python: pyproject.toml [project]; setup.py / setup.cfg '
        'without identity', () {
      final py = single<PythonFolder>(
        project('py', {'pyproject.toml': _pyproject, 'tests/test_x.py': ''}),
      );
      expect(py.projectName, 'tom_som_python_runtime');
      expect(py.version, '1.9.0');
      expect(py.projectFile, 'pyproject.toml');
      expect(
        single<PythonFolder>(project('py2', {'setup.py': ''})).projectFile,
        'setup.py',
      );
      expect(
        single<PythonFolder>(project('py3', {'setup.cfg': ''})).version,
        isNull,
      );
    });

    test('BB-LNG-4: Java: pom.xml (the project\'s own artifactId and version, '
        'not the parent\'s, a comment\'s or a dependency\'s); Gradle', () {
      final java = single<JavaFolder>(project('java', {'pom.xml': _pom}));
      expect(java.buildTool, JavaBuildTool.maven);
      expect(java.projectName, 'tom_som_java_runtime');
      expect(java.version, '1.9.0');
      final gradle = single<JavaFolder>(
        project('gradle', {'build.gradle.kts': ''}),
      );
      expect(gradle.buildTool, JavaBuildTool.gradle);
      expect(gradle.projectFile, 'build.gradle.kts');
    });

    test('BB-LNG-5: Go: go.mod; the module path names it', () {
      final go = single<GoFolder>(
        project('go', {
          'go.mod':
              'module github.com/al-the-bear/tom_ai_build/tom_som_go_runtime\n'
              '\ngo 1.21\n',
          'som_facade.go': '',
        }),
      );
      expect(
        go.modulePath,
        'github.com/al-the-bear/tom_ai_build/tom_som_go_runtime',
      );
      expect(go.projectName, 'tom_som_go_runtime');
      expect(go.version, isNull);
    });

    test('BB-LNG-6: Rust: Cargo.toml [package], not [dependencies]', () {
      final rust = single<RustFolder>(
        project('rust', {'Cargo.toml': _cargo, 'src/lib.rs': ''}),
      );
      expect(rust.projectName, 'tom_som_rust_runtime');
      expect(rust.version, '1.9.0');
    });

    test('BB-LNG-7: C and C++: a Makefile, the language decided by the '
        'sources; CMake too', () {
      final c = natures(
        project('c', {
          'Makefile': 'all:\n',
          'src/som_facade.c': '',
          'include/som.h': '',
        }),
      );
      expect(c.whereType<CFolder>().single.buildSystem, NativeBuildSystem.make);
      expect(c.whereType<CppFolder>(), isEmpty);

      final cpp = natures(
        project('cpp', {
          'Makefile': 'all:\n',
          'src/som_facade.cpp': '',
          'src/legacy_shim.c': '',
        }),
      );
      expect(cpp.whereType<CppFolder>().single.language, 'cpp');
      expect(cpp.whereType<CFolder>(), isEmpty, reason: 'any C++ makes C++');

      final cmake = single<CppFolder>(
        project('cmake', {'CMakeLists.txt': '', 'lib/a.cc': ''}),
      );
      expect(cmake.buildSystem, NativeBuildSystem.cmake);
    });

    test('BB-LNG-8: a Makefile without sources (docs) is no project', () {
      final docs = natures(
        project('docs', {'Makefile': 'html:\n', 'index.rst': '', 'a.h': ''}),
      );
      expect(docs.whereType<LanguageProjectFolder>(), isEmpty);
    });

    test('BB-LNG-9: a Dart project gets no language nature', () {
      final dart = natures(
        project('dart', {'pubspec.yaml': 'name: x\n', 'lib/x.dart': ''}),
      );
      expect(dart.whereType<LanguageProjectFolder>(), isEmpty);
    });
  });

  group('selection', () {
    test('BB-LNG-10: LanguageProjectFolder and NativeProjectFolder select '
        'their subtypes; Dart natures select no language project', () async {
      for (final (name, files) in [
        ('a_js', {'package.json': _packageJson}),
        ('b_py', {'pyproject.toml': _pyproject}),
        ('c_go', {'go.mod': 'module x/y\n'}),
        ('d_c', {'Makefile': 'all:\n', 'x.c': ''}),
        ('e_dart', {'pubspec.yaml': 'name: e_dart\n'}),
      ]) {
        project(name, files);
      }
      Future<List<String>> run(Set<Type> works) async {
        final names = <String>[];
        await BuildBase.traverse(
          info: ProjectTraversalInfo(executionRoot: tmp.path, scan: tmp.path),
          worksWithNatures: works,
          run: (ctx) async {
            names.add(ctx.name);
            return true;
          },
        );
        return names..sort();
      }

      expect(await run({LanguageProjectFolder}), [
        'a_js',
        'b_py',
        'c_go',
        'd_c',
      ]);
      expect(await run({NativeProjectFolder}), ['d_c']);
      expect(await run({GoFolder}), ['c_go']);
      expect(await run({DartProjectFolder}), ['e_dart']);
    });

    test('BB-LNG-11: the YAML tool definition names every nature', () {
      final tool = ToolDefinitionSerializer.fromYamlMap({
        'name': 't',
        'description': 't',
        'works_with_natures': [
          'JavaScriptFolder',
          'PythonFolder',
          'JavaFolder',
          'GoFolder',
          'RustFolder',
          'CFolder',
          'CppFolder',
          'TypeScriptFolder',
          'LanguageProjectFolder',
          'NativeProjectFolder',
        ],
      });
      expect(tool.worksWithNatures, {
        JavaScriptFolder,
        PythonFolder,
        JavaFolder,
        GoFolder,
        RustFolder,
        CFolder,
        CppFolder,
        TypeScriptFolder,
        LanguageProjectFolder,
        NativeProjectFolder,
      });
    });

    test('BB-LNG-12: %{<lang>.exists} and %{language}', () {
      final dir = project('rust', {'Cargo.toml': _cargo});
      final ctx = ExecutePlaceholderContext(
        rootPath: tmp.path,
        folder: FsFolder(path: dir)..natures.addAll(natures(dir)),
      );
      expect(
        ExecutePlaceholderResolver.resolvePlaceholder('rust.exists', ctx),
        'true',
      );
      expect(
        ExecutePlaceholderResolver.resolvePlaceholder('go.exists', ctx),
        'false',
      );
      expect(
        ExecutePlaceholderResolver.resolvePlaceholder('language', ctx),
        'rust',
      );
    });

    test('BB-LNG-13: a language project is not descended into without -r, '
        'like a Dart project', () async {
      project('ts_rt', {
        'package.json': _packageJson,
        'tsconfig.json': '{}',
        'tests/fixtures/sample/package.json': '{"name": "fixture"}',
      });
      final shallow = await FolderScanner().scan(tmp.path);
      final deep = await FolderScanner().scan(tmp.path, recursive: true);
      bool hasFixture(List<FsFolder> f) =>
          f.any((x) => x.path.endsWith(p.join('fixtures', 'sample')));
      expect(hasFixture(shallow), isFalse);
      expect(hasFixture(deep), isTrue);
    });
  });

  group('version files', () {
    test('BB-LNG-14: read and write the version in each format, the rest '
        'of the file kept', () {
      final cases = {
        'pubspec.yaml': 'name: x\nversion: 1.9.0\n',
        'package.json': _packageJson,
        'pyproject.toml': _pyproject,
        'Cargo.toml': _cargo,
        'pom.xml': _pom,
      };
      cases.forEach((file, text) {
        final dir = project('v_$file', {file: text});
        final vf = ProjectVersionFile.of(dir)!;
        expect(vf.fileName, file);
        expect(vf.read(text), '1.9.0', reason: file);
        final written = vf.write(text, '1.10.0');
        expect(vf.read(written), '1.10.0', reason: file);
        expect(
          written.replaceFirst('1.10.0', '1.9.0'),
          text,
          reason: '$file: only the version changed',
        );
      });
    });

    test('BB-LNG-15: Go and C state no version in their project file', () {
      expect(
        ProjectVersionFile.of(project('g', {'go.mod': 'module a\n'})),
        isNull,
      );
      expect(
        ProjectVersionFile.of(project('m', {'Makefile': '', 'a.c': ''})),
        isNull,
      );
    });
  });
}
