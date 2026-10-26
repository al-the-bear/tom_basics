/// The entry point stays platform-neutral, executed rather than asserted.
///
/// Two guards, because they catch disjoint failures:
///
/// 1. A walk of the import closure inside this package: no library reachable
///    from `tom_llm.dart` imports `dart:io`, a browser API, Flutter or
///    a process API — the Node search's machine half is behind `io.dart`. `dart compile js` *accepts*
///    `dart:io` (the SDK ships a throwing stub), so only a walk catches it
///    before a web build does.
/// 2. A real dart2js compile of a program using the package, which catches
///    codegen-level problems the VM never sees.
@Timeout(Duration(minutes: 4))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/scratch.dart';

final _directive = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''');

/// The external URIs reachable from [entry] inside this package.
Set<String> reached(String entry, {Set<String>? visited}) {
  final seen = visited ?? <String>{};
  final external = <String>{};
  final queue = [File(entry).absolute.path];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    for (final line in file.readAsLinesSync()) {
      final uri = _directive.firstMatch(line)?.group(1);
      if (uri == null) continue;
      if (uri.startsWith('package:tom_llm/')) {
        queue.add(
          '${Directory.current.absolute.path}/lib/'
          '${uri.substring('package:tom_llm/'.length)}',
        );
      } else if (uri.contains(':')) {
        external.add(uri);
      } else {
        queue.add(File('${file.parent.path}/$uri').absolute.path);
      }
    }
  }
  return external;
}

void main() {
  test('nothing reachable from tom_llm.dart is platform-bound', () {
    final visited = <String>{};
    final uris = reached('lib/tom_llm.dart', visited: visited);
    expect(
      visited.length,
      greaterThan(10),
      reason: 'the walk found almost nothing, so it proved nothing',
    );
    for (final banned in [
      'dart:io',
      'dart:ui',
      'dart:isolate',
      'package:web/',
      'package:flutter/',
      'package:tom_llm/io.dart',
    ]) {
      expect(uris.where((u) => u.startsWith(banned)), isEmpty, reason: banned);
    }
  });

  test('a program over the package compiles under dart2js', () async {
    final dart = Platform.resolvedExecutable;
    expect(
      dart.endsWith('dart') || dart.endsWith('dart.exe'),
      isTrue,
      reason:
          'run this suite with `dart test`; under another runner there is no '
          'Dart CLI to compile with',
    );
    final tmp = scratchDirectory('web_safe').createTempSync('sync-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final entry = File('${tmp.path}/main.dart')
      ..writeAsStringSync('''
import 'package:tom_llm/tom_llm.dart';

class Echo extends LlmProvider {
  @override
  String get id => 'echo';

  @override
  Stream<LlmEvent> run(LlmRequest request) async* {
    final account = LlmRunAccount.of(request.prompt, providerId: id);
    for (final event in llmRunPrelude(request, providerId: id)) {
      account.observe(event);
      yield event;
    }
    yield LlmTextDelta(request.prompt.combined);
    yield account.end(LlmRunOutcome.completed, duration: Duration.zero);
  }
}

Future<void> main() async {
  const request = LlmRequest(
    prompt: WirePrompt(system: 'S', user: 'U', anchorHash: 'a', roleId: 'r'),
  );
  final report = await Echo().complete(request);
  final trails = LlmTrails();
  trails.record(llmDefaultSession, LlmRunStarted(providerId: report.providerId));
  print([
    report.providerId,
    llmTrailEntries(trails.recordsOf(llmDefaultSession)).length,
  ]);
  trails.dispose();
}
''');
    final result = await Process.run(dart, [
      'compile',
      'js',
      '--no-source-maps',
      '--packages=${Directory.current.absolute.path}/.dart_tool/package_config.json',
      '-o',
      '${tmp.path}/out.js',
      entry.path,
    ]);
    expect(
      result.exitCode,
      0,
      reason: 'dart2js rejected it:\n${result.stdout}\n${result.stderr}',
    );
  });
}
