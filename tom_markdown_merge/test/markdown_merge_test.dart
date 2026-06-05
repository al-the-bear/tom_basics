import 'package:tom_markdown_merge/tom_markdown_merge.dart';
import 'package:test/test.dart';

void main() {
  const merge = MarkdownMerge();

  group('managed regions', () {
    test('refreshes a managed region whose key the generator owns', () {
      const current = '''
<!--\$insert:tom.managed.overview-->
old prose
<!--\$end-insert-->''';

      final result = merge.merge(current, {'overview': 'new prose'});

      expect(result, '''
<!--\$insert:tom.managed.overview-->
new prose
<!--\$end-insert-->''');
    });

    test('leaves a managed region untouched when the generator no longer owns its key', () {
      const current = '''
<!--\$insert:tom.managed.overview-->
old prose
<!--\$end-insert-->''';

      // 'overview' not in the generated map → region preserved verbatim.
      final result = merge.merge(current, {'summary': 'unrelated'});

      expect(result, current);
    });

    test('refreshes multiple managed regions independently', () {
      const current = '''
<!--\$insert:tom.managed.a-->
old a
<!--\$end-insert-->
<!--\$insert:tom.managed.b-->
old b
<!--\$end-insert-->''';

      final result = merge.merge(current, {'a': 'new a', 'b': 'new b'});

      expect(result, contains('new a'));
      expect(result, contains('new b'));
      expect(result, isNot(contains('old a')));
      expect(result, isNot(contains('old b')));
    });
  });

  group('override regions', () {
    test('override region is never rewritten', () {
      const current = '''
<!--\$insert:tom.override.overview-->
author prose
<!--\$end-insert-->''';

      final result = merge.merge(current, {'overview': 'generated prose'});

      expect(result, current);
      expect(result, isNot(contains('generated prose')));
    });

    test('override suppresses refresh of a managed region for the same key', () {
      const current = '''
<!--\$insert:tom.override.overview-->
author prose
<!--\$end-insert-->
<!--\$insert:tom.managed.overview-->
old generated
<!--\$end-insert-->''';

      final result = merge.merge(current, {'overview': 'new generated'});

      // Override wins: neither region is refreshed.
      expect(result, current);
      expect(result, isNot(contains('new generated')));
    });
  });

  group('free text and foreign regions', () {
    test('prepended and appended free text survives a refresh', () {
      const current = '''
Intro I wrote before the block.

<!--\$insert:tom.managed.overview-->
old prose
<!--\$end-insert-->

Closing note I wrote after the block.''';

      final result = merge.merge(current, {'overview': 'new prose'});

      expect(result, contains('Intro I wrote before the block.'));
      expect(result, contains('Closing note I wrote after the block.'));
      expect(result, contains('new prose'));
      expect(result, isNot(contains('old prose')));
    });

    test('foreign \$insert: regions are left untouched', () {
      const current = '''
<!--\$insert:chat.lastReply-->
not ours
<!--\$end-insert-->''';

      final result = merge.merge(current, {'lastReply': 'should not apply'});

      expect(result, current);
    });

    test('a document with no markers is returned unchanged', () {
      const current = 'Just prose, no markers at all.';
      expect(merge.merge(current, {'overview': 'x'}), current);
    });
  });

  group('key inspection', () {
    test('managedKeys and overrideKeys report the right keys', () {
      const md = '''
<!--\$insert:tom.managed.a-->
a
<!--\$end-insert-->
<!--\$insert:tom.override.b-->
b
<!--\$end-insert-->
<!--\$insert:foreign.c-->
c
<!--\$end-insert-->''';

      expect(merge.managedKeys(md), {'a'});
      expect(merge.overrideKeys(md), {'b'});
    });
  });

  group('block builders', () {
    test('managedBlock round-trips through a merge', () {
      final block = merge.managedBlock('overview', 'first draft');
      expect(merge.managedKeys(block), {'overview'});

      final refreshed = merge.merge(block, {'overview': 'second draft'});
      expect(refreshed, contains('second draft'));
      expect(refreshed, isNot(contains('first draft')));
    });

    test('overrideBlock is recognised as an override', () {
      final block = merge.overrideBlock('overview', 'mine');
      expect(merge.overrideKeys(block), {'overview'});
      expect(merge.merge(block, {'overview': 'theirs'}), block);
    });

    test('empty content produces an empty body', () {
      expect(
        merge.managedBlock('overview', ''),
        '<!--\$insert:tom.managed.overview-->\n<!--\$end-insert-->',
      );
    });
  });

  group('malformed input', () {
    test('throws FormatException on an unclosed marker', () {
      const current = '<!--\$insert:tom.managed.overview-->\nno end';
      expect(() => merge.merge(current, {'overview': 'x'}),
          throwsA(isA<FormatException>()));
    });
  });
}
