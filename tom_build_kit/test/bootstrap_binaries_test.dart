// BK-BOOT: bootstrap_binaries.sh puts the Tom binaries on PATH for every
// shell, non-interactive ones included.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _script = p.join(Directory.current.path, 'bootstrap_binaries.sh');

/// Sources the script in a bash whose HOME is [home] (only its functions run:
/// it returns when sourced) and runs [commands] after it.
Future<ProcessResult> _withFunctions(
  String home,
  String commands, {
  String shell = '/bin/bash',
}) => Process.run('bash', [
  '-c',
  'source "$_script" && $commands',
], environment: {'HOME': home, 'SHELL': shell, 'PATH': '/usr/bin:/bin'},
    includeParentEnvironment: false);

/// Writes the block for [binaries] / `linux-x64` into [file].
Future<void> _writeBlock(String home, String file, String binaries) async {
  final got = await _withFunctions(
    home,
    'write_shell_env_block "$file" '
    '"\$(shell_env_block "$binaries" linux-x64)"',
  );
  expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
}

/// A distribution's ~/.bashrc: it returns at once for non-interactive shells.
const _guardedBashrc = '''
case \$- in
    *i*) ;;
      *) return;;
esac
alias ll='ls -l'
''';

void main() {
  late Directory home;

  setUp(() {
    final base = Directory(p.join(Directory.current.path, '.dart_tool'))
      ..createSync(recursive: true);
    home = base.createTempSync('bootstrap_home_');
  });

  tearDown(() => home.deleteSync(recursive: true));

  test('BK-BOOT-1: zsh users get ~/.zshenv, bash users ~/.bashrc', () async {
    final zsh = await _withFunctions(
      home.path,
      'shell_env_files',
      shell: '/bin/zsh',
    );
    expect(zsh.stdout.toString().trim(), p.join(home.path, '.zshenv'));

    final bash = await _withFunctions(home.path, 'shell_env_files');
    expect(bash.stdout.toString().trim(), p.join(home.path, '.bashrc'));
  });

  test(
    'BK-BOOT-2: the block goes above the interactive guard of ~/.bashrc, '
    'and a non-interactive bash gets the binaries',
    () async {
      final bashrc = File(p.join(home.path, '.bashrc'))
        ..writeAsStringSync(_guardedBashrc);
      await _writeBlock(home.path, bashrc.path, '/opt/tom');

      expect(bashrc.readAsStringSync(), endsWith(_guardedBashrc));
      // What `ssh host 'cmd'` does: a non-interactive bash reading ~/.bashrc.
      final got = await Process.run('bash', [
        '-c',
        'source ~/.bashrc; echo "\$TOM_BINARY_PATH|\$PATH"',
      ], environment: {'HOME': home.path, 'PATH': '/usr/bin:/bin'},
          includeParentEnvironment: false);
      expect(got.stdout.toString().trim(),
          '/opt/tom|/opt/tom/linux-x64:/usr/bin:/bin');
    },
  );

  test('BK-BOOT-3: running it again replaces the block, never adds one',
      () async {
    final bashrc = File(p.join(home.path, '.bashrc'))
      ..writeAsStringSync(_guardedBashrc);
    await _writeBlock(home.path, bashrc.path, '/opt/old');
    await _writeBlock(home.path, bashrc.path, '/opt/tom');
    await _writeBlock(home.path, bashrc.path, '/opt/tom');

    final text = bashrc.readAsStringSync();
    expect('>>> tom binaries'.allMatches(text), hasLength(1));
    expect(text, isNot(contains('/opt/old')));
    expect(text, endsWith(_guardedBashrc));
  });

  test(
    'BK-BOOT-4: a non-interactive zsh gets the binaries from ~/.zshenv',
    () async {
      final zshenv = File(p.join(home.path, '.zshenv'));
      await _writeBlock(home.path, zshenv.path, '/opt/tom');

      final got = await Process.run('zsh', [
        '-c',
        'echo "\$TOM_BINARY_PATH|\$PATH"',
      ], environment: {
        'HOME': home.path,
        'ZDOTDIR': home.path,
        'PATH': '/usr/bin:/bin',
      }, includeParentEnvironment: false);
      expect(got.stdout.toString().trim(),
          '/opt/tom|/opt/tom/linux-x64:/usr/bin:/bin');
    },
    skip: File('/bin/zsh').existsSync() ? false : 'zsh is not installed',
  );
}
