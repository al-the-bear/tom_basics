import 'dart:io';

import 'package:path/path.dart' as p;

/// A fresh scratch directory under this package's gitignored `ztmp/` — never
/// the system temp directory (the workspace rule).
Directory scratchDir(String name) {
  final dir = Directory(
    p.join(Directory.current.path, 'ztmp', 'ci_test', name),
  );
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  return dir..createSync(recursive: true);
}

void writeFile(Directory root, String relative, String content) {
  File(p.join(root.path, relative))
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
}
