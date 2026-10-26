/// A synthetic folder shaped like a quest folder tree: written to a
/// temporary directory per test, never the real workspace.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// The files of the fixture, relative to its root.
const Map<String, String> fixtureFiles = {
  'alpha/overview.alpha.md': '# Alpha\n',
  'alpha/quest-notes.alpha.md': 'notes\n',
  'alpha/progress.alpha.md': '## 2026-10-11\n',
  'alpha/todos.alpha.todo.yaml': 'todos: []\n',
  'alpha/todos-archived.alpha.todo.yaml': 'todos: []\n',
  'alpha/todos-deleted.alpha.todo.yaml': 'todos: []\n',
  'alpha/session-todo.mbp.alpha.todo.yaml': 'todos: []\n',
  'alpha/live-trail.md': '# trail\n',
  'alpha/history/history.md': 'old\n',
  'alpha/history/alpha.anthropic.prompts.md': 'p\n',
  'alpha/config.yaml': 'a: 1\n',
  'alpha/secrets.env': 'TOKEN=abc\n',
  'alpha/notes.txt': 'text\n',
  'alpha/image.png': '\u0000PNG',
  'beta/overview.beta.md': '# Beta\n',
  'beta/script.dart': 'void main() {}\n',
  'beta/build/out.txt': 'built\n',
  '.hidden/inside.md': 'hidden\n',
  '.gitignore': 'beta/build/\n*.log\n',
  'run.log': 'log\n',
  'README.md': '# Fixture\n',
};

/// Writes the fixture under a fresh temporary directory and answers its path.
/// The caller deletes it.
Directory writeFixtureTree([String prefix = 'tom_fs_']) {
  final root = Directory.systemTemp.createTempSync(prefix);
  for (final e in fixtureFiles.entries) {
    final file = File(p.joinAll([root.path, ...e.key.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(e.value);
  }
  return root;
}
