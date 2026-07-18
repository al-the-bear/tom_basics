// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Guards the argument-routing contract the `analyzer_cache_gc` executors rely
/// on. The v2 parser routes a *value-bearing* command option (e.g.
/// `--older-than 30`) into the per-command options map
/// (`CliArgs.commandArgs[cmd].options`), NOT the top-level
/// `CliArgs.extraOptions`; and it captures `--dry-run` as the global
/// `CliArgs.dryRun` flag. The executors read those exact locations, so if the
/// framework's routing ever changes these assertions catch it before a user
/// hits a silently-ignored `--older-than`.
library;

import 'package:tom_analyzer_shared/src/cli/analyzer_cache_gc_tool.dart';
import 'package:tom_build_base/tom_build_base_v2.dart';
import 'package:test/test.dart';

void main() {
  final parser = CliArgParser(toolDefinition: analyzerCacheGcTool);

  group('analyzer_cache_gc argument routing', () {
    test('--older-than value lands in the clean command options, not '
        'extraOptions', () {
      final args = parser.parse([':clean', '--older-than', '30']);
      expect(args.commandArgs['clean']?.options['older-than'], '30');
      expect(args.extraOptions.containsKey('older-than'), isFalse,
          reason: 'value-bearing command options are per-command, not global');
    });

    test('--older-than=<n> attached form is captured identically', () {
      final args = parser.parse([':clean', '--older-than=45']);
      expect(args.commandArgs['clean']?.options['older-than'], '45');
    });

    test('--dry-run is captured as the global dryRun flag', () {
      final args = parser.parse([':clean', '--older-than', '30', '--dry-run']);
      expect(args.dryRun, isTrue);
    });

    test('--include-current is a per-command boolean flag', () {
      final args = parser.parse([':clean', '--include-current']);
      expect(args.commandArgs['clean']?.options['include-current'], isTrue);
    });

    test('--root override is a per-command value option', () {
      final args = parser.parse([':list', '--root', '/tmp/x']);
      expect(args.commandArgs['list']?.options['root'], '/tmp/x');
    });

    test('list and clean are recognised commands (with aliases)', () {
      expect(parser.parse([':list']).commands, contains('list'));
      expect(parser.parse([':clean']).commands, contains('clean'));
      expect(parser.parse([':ls']).commands, isNotEmpty);
      expect(parser.parse([':gc']).commands, isNotEmpty);
    });
  });
}
