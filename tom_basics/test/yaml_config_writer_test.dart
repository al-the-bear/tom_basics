// Tests for the AST-preserving config writer.
//
// `TomYamlConfigWriter` is the single sanctioned path for mutating YAML config
// text. It wraps `package:yaml_edit`, so a surgical `set`/`remove` rewrites
// only the targeted node and leaves every comment, key order, and byte of
// surrounding formatting untouched — the property a naive
// `load → mutate map → re-serialize` round-trip destroys.
//
// What this file pins:
//   1. Editing a value preserves comments, key order, and untouched lines.
//   2. Removing a key leaves its neighbours (and their comments) intact.
//   3. A hand-formatted fixture round-trips through a write with only the
//      intended line changed (byte-level diff of every other line).
//   4. Nested-path and list-index addressing work.

import 'package:tom_basics/utilities.dart';
import 'package:test/test.dart';

/// A hand-formatted, commented, ordered fixture — the kind of config a human
/// maintains and whose layout a write must respect.
const _fixture = '''
# Substrate configuration.
# Edit with care — order and comments are meaningful.

substrate:
  # Primary chat endpoint (oMLX over the fleet VPN).
  baseUrl: http://10.8.0.7:8000/v1/
  model: gemma-4-26b-a4b-it-4bit
  timeoutMs: 30000   # generous, the Mac is slow to first token

  embedding:
    model: nomic-embed-text   # 768 dims
    dims: 768

  providers:
    - id: omlx
      weight: 1
    - id: ollama
      weight: 2
''';

void main() {
  group('TomYamlConfigWriter.set', () {
    test('editing a scalar preserves comments, order, and other lines', () {
      final w = TomYamlConfigWriter(_fixture);
      w.set(['substrate', 'model'], 'gemma-4-26b-new');
      final out = w.toString();

      // The new value is present; the old is gone.
      expect(out, contains('model: gemma-4-26b-new'));
      expect(out, isNot(contains('gemma-4-26b-a4b-it-4bit')));

      // Every comment in the document survives.
      expect(out, contains('# Substrate configuration.'));
      expect(out, contains('# Edit with care'));
      expect(out, contains('# Primary chat endpoint'));
      expect(out, contains('# generous, the Mac is slow to first token'));
      expect(out, contains('# 768 dims'));

      // Key order is preserved: baseUrl precedes model precedes timeoutMs.
      final iBase = out.indexOf('baseUrl:');
      final iModel = out.indexOf('model: gemma-4-26b-new');
      final iTimeout = out.indexOf('timeoutMs:');
      expect(iBase, lessThan(iModel));
      expect(iModel, lessThan(iTimeout));
    });

    test('editing a nested scalar changes only the targeted line', () {
      final w = TomYamlConfigWriter(_fixture);
      w.set(['substrate', 'embedding', 'dims'], 1024);
      final out = w.toString();

      // Line-by-line diff: every line is identical except the dims line.
      final before = _fixture.split('\n');
      final after = out.split('\n');
      expect(
        after.length,
        before.length,
        reason: 'no lines added or removed by a scalar edit',
      );
      for (var i = 0; i < before.length; i++) {
        if (before[i].trimLeft().startsWith('dims:')) {
          expect(after[i], '    dims: 1024');
        } else {
          expect(after[i], before[i], reason: 'line $i must be byte-identical');
        }
      }
    });

    test('addressing a list element by index works', () {
      final w = TomYamlConfigWriter(_fixture);
      w.set(['substrate', 'providers', 1, 'weight'], 5);
      final out = w.toString();
      // The second provider's weight changed; the first is untouched.
      expect(out, contains('weight: 5'));
      expect(out, contains('id: omlx'));
      expect(out, contains('id: ollama'));
      // Order preserved: omlx still before ollama.
      expect(out.indexOf('id: omlx'), lessThan(out.indexOf('id: ollama')));
    });
  });

  group('TomYamlConfigWriter.remove', () {
    test('removing a key leaves neighbours and their comments intact', () {
      final w = TomYamlConfigWriter(_fixture);
      w.remove(['substrate', 'timeoutMs']);
      final out = w.toString();

      // The key and its inline comment are gone.
      expect(out, isNot(contains('timeoutMs:')));
      expect(out, isNot(contains('generous, the Mac is slow')));

      // Neighbours survive, with their own comments and order.
      expect(out, contains('baseUrl: http://10.8.0.7:8000/v1/'));
      expect(out, contains('model: gemma-4-26b-a4b-it-4bit'));
      expect(out, contains('# Primary chat endpoint'));
      expect(out, contains('embedding:'));
      expect(out, contains('# 768 dims'));
      expect(out.indexOf('baseUrl:'), lessThan(out.indexOf('embedding:')));
    });

    test('removing a list element preserves the surrounding list', () {
      final w = TomYamlConfigWriter(_fixture);
      w.remove(['substrate', 'providers', 0]);
      final out = w.toString();
      expect(out, isNot(contains('id: omlx')));
      expect(out, contains('id: ollama'));
      expect(out, contains('weight: 2'));
    });
  });

  group('TomYamlConfigWriter — round-trip', () {
    test('source getter mirrors toString()', () {
      final w = TomYamlConfigWriter(_fixture)
        ..set([
          'substrate',
          'dims',
        ], 1); // harmless top-level add under substrate
      expect(w.source, w.toString());
    });

    test('an untouched writer returns the original source verbatim', () {
      final w = TomYamlConfigWriter(_fixture);
      expect(w.toString(), _fixture);
    });
  });
}
