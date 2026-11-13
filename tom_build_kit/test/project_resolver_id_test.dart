// ProjectResolver: a bare `--project` name resolves by folder name, then by
// the project id, then by the project name of buildkit.yaml. The id is
// `project_id`; `project-id` and `short-id` are not read, and tom_project.yaml
// (retired) is not read at all.
//
// Works in a scratch workspace under testlog/ (gitignored); nothing else is
// read or written.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_build_kit/src/v2/executors/project_resolver.dart';

void main() {
  late Directory workspace;

  setUp(() {
    workspace = (Directory(
      'testlog',
    )..createSync()).createTempSync('project_resolver_id_');
    // The workspace marker stops findWorkspaceRoot at the scratch folder.
    File(
      p.join(workspace.path, 'buildkit_master.yaml'),
    ).writeAsStringSync('navigation: {}\n');
    void project(String folder, String file, String content) {
      final dir = Directory(p.join(workspace.path, 'libs', folder))
        ..createSync(recursive: true);
      File(
        p.join(dir.path, 'pubspec.yaml'),
      ).writeAsStringSync('name: $folder\nenvironment:\n  sdk: ^3.0.0\n');
      File(p.join(dir.path, file)).writeAsStringSync(content);
    }

    project('alpha_pkg', 'buildkit.yaml', 'project_id: AID\nname: alpha\n');
    project('beta_pkg', 'buildkit.yaml', 'short-id: BID\nproject-id: HID\n');
    project('gamma_pkg', 'tom_project.yaml', 'project_id: GID\nname: gamma\n');
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  Future<List<String>> resolve(String pattern) => ProjectResolver()
      .resolveProjectPatterns(pattern, basePath: workspace.path);

  String folder(String name) =>
      p.normalize(p.absolute(p.join(workspace.path, 'libs', name)));

  test('BK-RES-1: project_id selects the project (any case)', () async {
    expect(await resolve('AID'), [folder('alpha_pkg')]);
    expect(await resolve('aid'), [folder('alpha_pkg')]);
  });

  test(
    'BK-RES-2: the project name and the folder name select it too',
    () async {
      expect(await resolve('alpha'), [folder('alpha_pkg')]);
      expect(await resolve('beta_pkg'), [folder('beta_pkg')]);
    },
  );

  test('BK-RES-3: a short-id or project-id key is not an id', () async {
    expect(await resolve('BID'), isEmpty);
    expect(await resolve('HID'), isEmpty);
  });

  test('BK-RES-4: tom_project.yaml is not read [2026-11-13]', () async {
    expect(await resolve('GID'), isEmpty);
    expect(await resolve('gamma'), isEmpty);
  });
}
