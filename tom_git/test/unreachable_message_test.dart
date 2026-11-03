/// The sentence a request that got no answer produces, in a page and outside
/// one.
library;

import 'package:test/test.dart';
import 'package:tom_git/tom_git.dart';

void main() {
  test('UNREACH-1: outside a page, the server could not be reached', () {
    expect(
      gitUnreachableMessage(
        'git.example.org',
        'Connection refused',
        inPage: false,
      ),
      'git.example.org could not be reached: Connection refused',
    );
  });

  test('UNREACH-2: in a page, the sentence names both causes the browser '
      'reports alike', () {
    final sentence = gitUnreachableMessage(
      '127.0.0.1',
      'Failed to fetch',
      inPage: true,
    );
    expect(
      sentence,
      startsWith('127.0.0.1 could not be reached from this page'),
    );
    expect(sentence, contains('Failed to fetch'));
    expect(sentence, contains('not answering'));
    expect(sentence, contains('does not allow requests from a web page'));
    expect(sentence, contains('CORS'));
  });

  test(
    'UNREACH-3: a server that does not answer is reported in those words',
    () async {
      final remote = GitHttpRemote(Uri.parse('http://127.0.0.1:9/r.git'));
      addTearDown(remote.close);
      await expectLater(
        remote.listRefs(),
        throwsA(
          isA<GitUnreachableException>().having(
            (e) => e.message,
            'message',
            startsWith('127.0.0.1 could not be reached: '),
          ),
        ),
      );
    },
  );
}
