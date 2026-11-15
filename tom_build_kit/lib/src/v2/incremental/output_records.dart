/// The record `:compiler` writes beside each binary it builds,
/// `<binary>.buildkit.json`, and the check that the binary is still the one
/// the record describes.
///
/// **What a record holds**: the format and its version, the project that
/// built the binary, the buildkit version, the step fingerprint of the run
/// that wrote it ([stepFingerprint]), when, and the binary's size and sha256.
/// It is committed with the binary (the binaries layer commits what is in
/// it), so it says where a published binary came from.
///
/// **The check** ([staleOutputReason]): a project whose inputs did not
/// change is still compiled again when one of the binaries its last run wrote
/// is missing, has no record, has a record naming another fingerprint (a
/// build of another project, of other inputs, or on another machine), or
/// differs in size or content from its record (written by something that
/// left the record alone).
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The `format` of a record.
const String outputRecordFormat = 'buildkit-output';

/// The `formatVersion` of a record; raised only for a change an older reader
/// cannot read.
const int outputRecordFormatVersion = 1;

/// The record file of [binary].
String outputRecordPath(String binary) => '$binary.buildkit.json';

/// Writes the record of [binary], built in [project] by buildkit
/// [buildkitVersion] in the run whose fingerprint is [fingerprint].
void writeOutputRecord({
  required String binary,
  required String project,
  required String buildkitVersion,
  required String fingerprint,
  DateTime? builtAt,
}) {
  final file = File(binary);
  final record = {
    'format': outputRecordFormat,
    'formatVersion': outputRecordFormatVersion,
    'project': project,
    'buildkit': buildkitVersion,
    'fingerprint': fingerprint,
    'builtAt': (builtAt ?? DateTime.now()).toUtc().toIso8601String(),
    'size': file.lengthSync(),
    'sha256': _sha256(file),
  };
  File(outputRecordPath(binary)).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(record)}\n',
  );
}

/// Why [binary] is not the one a run with [fingerprint] wrote, or null when
/// it is.
String? staleOutputReason(String binary, String fingerprint) {
  final file = File(binary);
  if (!file.existsSync()) return '${p.basename(binary)} is missing';
  final recordFile = File(outputRecordPath(binary));
  if (!recordFile.existsSync()) {
    return '${p.basename(binary)} has no ${p.basename(recordFile.path)}';
  }
  Map<String, dynamic> record;
  try {
    final decoded = jsonDecode(recordFile.readAsStringSync());
    if (decoded is! Map<String, dynamic>) throw const FormatException();
    record = decoded;
  } on FormatException {
    return '${p.basename(recordFile.path)} cannot be read';
  }
  if (record['fingerprint'] != fingerprint) {
    return '${p.basename(binary)} was written by another build';
  }
  if (record['size'] != file.lengthSync() ||
      record['sha256'] != _sha256(file)) {
    return '${p.basename(binary)} was replaced after its record was written';
  }
  return null;
}

/// The output paths of the `dart compile` commands among the shell command
/// bodies [commands] (resolved, without their `shell ` prefix), as the
/// commands name them: relative to the directory they run in, or absolute.
List<String> compileOutputPaths(Iterable<String> commands) => [
  for (final command in commands)
    if (_compile.hasMatch(command.trim()))
      for (final m in _output.allMatches(command)) _unquote(m.group(2)!),
];

final _compile = RegExp(r'^dart\s+compile\s+\S+');
final _output = RegExp(r'(\s(?:-o|--output)(?:=|\s+))("[^"]*"|\S+)');

String _unquote(String token) =>
    token.length >= 2 && token.startsWith('"') && token.endsWith('"')
    ? token.substring(1, token.length - 1)
    : token;

String _sha256(File file) => sha256.convert(file.readAsBytesSync()).toString();
