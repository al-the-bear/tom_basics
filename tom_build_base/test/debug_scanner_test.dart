import 'package:test/test.dart';
import 'package:tom_build_base/src/v2/traversal/folder_scanner.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  test('debug scanner with flutter exclusion', () async {
    // Find workspace root
    var dir = Directory.current;
    while (!File(p.join(dir.path, 'buildkit_master.yaml')).existsSync()) {
      dir = dir.parent;
      if (dir.path == dir.parent.path) fail('Could not find workspace root');
    }
    final workspaceRoot = dir.path;
    final zomTestRoot = p.join(
      workspaceRoot,
      'zom_workspaces',
      'zom_analyzer_test',
    );

    print('Workspace root: $workspaceRoot');
    print('ZomTestRoot: $zomTestRoot');

    final scanner = FolderScanner();
    final folders = await scanner.scan(
      zomTestRoot,
      recursive: true,
      recursionExclude: ['*flutter*'],
    );

    print('Found ${folders.length} folders:');
    for (final folder in folders) {
      final hasFlutter = folder.path.contains('flutter');
      print('  ${hasFlutter ? "FLUTTER: " : ""}${folder.path}');
    }

    // Count flutter folders
    final flutterFolders = folders
        .where((f) => f.path.contains('flutter'))
        .toList();
    print('\nFlutter folders found: ${flutterFolders.length}');
  });
}
