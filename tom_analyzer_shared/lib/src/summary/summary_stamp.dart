// Copyright (c) 2026. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// What wrote a summary, kept beside it: its toolchain and whether it holds
/// Flutter's `dart:ui`.
library;

import 'dart:io';

import 'analyzer_version.dart';

/// What a summary file was written by, recorded in a stamp file beside it
/// (`<summary>.stamp`): the toolchain ([currentToolchainKey]: the Dart SDK and
/// the analyzer data version, the exact key of the summary format) and whether
/// it was built with Flutter's embedder (`dart:ui`). The embedder is recorded
/// by its presence, not its path: the Dart SDK version in the toolchain already
/// names the Flutter release it ships with, and a path would make the stamp —
/// committed beside a shipped summary — true on one machine only.
///
/// A tool that keeps a summary between runs keeps it only while its stamp is
/// the one it would write now ([isCurrentFor]): a summary another analyzer
/// wrote cannot be read by this one, and one built without (or with) `dart:ui`
/// describes another SDK. A summary without a stamp counts as stale.
final class SummaryStamp {
  const SummaryStamp({required this.toolchain, this.dartUi = false});

  /// The stamp of a summary the running toolchain writes now, with the
  /// embedder at [embedderYamlPath] (null: the plain SDK).
  factory SummaryStamp.current({String? embedderYamlPath}) => SummaryStamp(
    toolchain: currentToolchainKey(),
    dartUi: embedderYamlPath != null,
  );

  /// `<dart-sdk-version>+d<analyzer-data-version>`.
  final String toolchain;

  /// Whether the summary was built with Flutter's embedder (`dart:ui`).
  final bool dartUi;

  /// The stamp file of the summary at [summaryPath].
  static File fileFor(String summaryPath) => File('$summaryPath.stamp');

  /// The stamp's text.
  String encode() =>
      '# Written with the summary beside it; it is rebuilt when this differs.\n'
      'toolchain: $toolchain\n'
      'dart-ui: ${dartUi ? 'yes' : 'no'}\n';

  /// The stamp in [text], or null when it is not one.
  static SummaryStamp? decode(String text) {
    String? field(String name) {
      final match = RegExp('^$name: (.*)\$', multiLine: true).firstMatch(text);
      return match?.group(1)?.trim();
    }

    final toolchain = field('toolchain');
    final dartUi = field('dart-ui');
    if (toolchain == null ||
        toolchain.isEmpty ||
        (dartUi != 'yes' && dartUi != 'no')) {
      return null;
    }
    return SummaryStamp(toolchain: toolchain, dartUi: dartUi == 'yes');
  }

  /// The stamp beside the summary at [summaryPath], or null when there is
  /// none or it cannot be read.
  static SummaryStamp? readFor(String summaryPath) {
    final file = fileFor(summaryPath);
    if (!file.existsSync()) return null;
    try {
      return decode(file.readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  /// Whether the summary at [summaryPath] exists and was written as this
  /// stamp says.
  bool isCurrentFor(String summaryPath) =>
      File(summaryPath).existsSync() && readFor(summaryPath) == this;

  /// Writes this stamp beside the summary at [summaryPath].
  void writeFor(String summaryPath) =>
      fileFor(summaryPath).writeAsStringSync(encode());

  @override
  bool operator ==(Object other) =>
      other is SummaryStamp &&
      other.toolchain == toolchain &&
      other.dartUi == dartUi;

  @override
  int get hashCode => Object.hash(toolchain, dartUi);

  @override
  String toString() => 'SummaryStamp($toolchain, dart:ui: $dartUi)';
}
