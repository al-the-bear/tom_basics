/// Run by tool/test_without_git.sh, which strips every git* executable from
/// PATH: there, git cannot be started at all — so everything else that ran
/// green in that run needed no git binary.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'GIT-NOBIN-1: git cannot be started in the stripped run',
    () async {
      await expectLater(
        Process.run('git', ['--version']),
        throwsA(isA<ProcessException>()),
      );
    },
    skip: Platform.environment['TOM_GIT_NO_BINARY'] == '1'
        ? false
        : 'runs under tool/test_without_git.sh',
  );
}
