// Prints many lines inside runWithConsoleMarkdown, as a tool's output does.
// BB-PIPE-1 runs it with its stdout piped into `head -1`.
import 'dart:io';

import 'package:tom_build_base/tom_build_base.dart';

Future<void> main() => runWithConsoleMarkdown(() async {
  for (var i = 0; i < 20000; i++) {
    stdout.writeln('line $i of a long **listing**');
  }
  await stdout.flush();
});
