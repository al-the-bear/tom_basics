/// The build cache of `:compiler`: compiled outputs kept outside the
/// repositories, served again when the same project inputs are compiled for
/// the same target with the same Dart SDK (on a branch switched back, in a
/// second clone, after `--force`).
///
/// **What is cached.** One compile of one file for one target whose commands
/// are all `dart compile <kind> ... -o <output>` or `mkdir`: their outputs,
/// after every command ran. A pipeline with any other command (a copy, a
/// signing step, a script) may have effects the cache cannot repeat, so it
/// always runs.
///
/// **The key** ([CompileCachePlan.key]) is the hash of the project's inputs
/// ([projectInputsHash]: its files, lock, path dependencies), the Dart SDK
/// version, the target platform and the compile commands with their output
/// paths left out, so the same compile into another `TOM_BINARY_PATH` hits.
///
/// **Where.** `TOM_BUILDKIT_CACHE_DIR`, else `~/.tom/cache/buildkit/`: one
/// folder per key holding `entry.json` and the outputs (`out0`, `out1`, ...).
/// After each store the entries used longest ago are evicted until the cache
/// is at most `TOM_BUILDKIT_CACHE_MAX_MB` (default 2048) megabytes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The default size limit of the cache, in megabytes.
const int defaultCompileCacheMaxMb = 2048;

/// The compile of one file for one target, when every command of it is one
/// the cache can stand in for.
class CompileCachePlan {
  CompileCachePlan._(this.outputs, this._compileCommands);

  /// The output paths of the `dart compile` commands, as the commands name
  /// them (relative to the project, or absolute).
  final List<String> outputs;

  /// The compile commands with each output replaced by `<output n>`.
  final List<String> _compileCommands;

  static final _compile = RegExp(r'^dart\s+compile\s+\S+');
  static final _mkdir = RegExp(r'^mkdir(\s|$)');
  static final _output = RegExp(r'(\s(?:-o|--output)(?:=|\s+))("[^"]*"|\S+)');

  /// The plan for the shell command bodies [commands] (resolved, without
  /// their `shell ` prefix), or null when one of them is neither a
  /// `dart compile` with an output nor a `mkdir`, or none compiles.
  static CompileCachePlan? of(List<String> commands) {
    final outputs = <String>[];
    final compiles = <String>[];
    for (final raw in commands) {
      final command = raw.trim();
      if (_mkdir.hasMatch(command)) continue;
      if (!_compile.hasMatch(command)) return null;
      final matches = _output.allMatches(command).toList();
      if (matches.length != 1) return null;
      final token = matches.single.group(2)!;
      final out =
          token.length >= 2 && token.startsWith('"') && token.endsWith('"')
          ? token.substring(1, token.length - 1)
          : token;
      compiles.add(
        command.replaceRange(
          matches.single.start,
          matches.single.end,
          '${matches.single.group(1)}<output ${outputs.length}>',
        ),
      );
      outputs.add(out);
    }
    return outputs.isEmpty ? null : CompileCachePlan._(outputs, compiles);
  }

  /// The cache key for this compile of a project whose inputs hash to
  /// [inputsHash], with Dart SDK [dartSdk], for [targetPlatform].
  String key({
    required String inputsHash,
    required String dartSdk,
    required String targetPlatform,
  }) => sha256
      .convert(
        utf8.encode(
          [
            'inputs $inputsHash',
            'dart $dartSdk',
            'target $targetPlatform',
            ..._compileCommands,
          ].join('\n'),
        ),
      )
      .toString();
}

/// The cache folder and its size limit.
class CompileCache {
  CompileCache({required this.root, required this.maxBytes});

  /// The cache the environment names: `TOM_BUILDKIT_CACHE_DIR` (else
  /// `~/.tom/cache/buildkit`) and `TOM_BUILDKIT_CACHE_MAX_MB`.
  factory CompileCache.fromEnvironment([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final root =
        env['TOM_BUILDKIT_CACHE_DIR'] ??
        p.join(home, '.tom', 'cache', 'buildkit');
    final mb =
        int.tryParse(env['TOM_BUILDKIT_CACHE_MAX_MB'] ?? '') ??
        defaultCompileCacheMaxMb;
    return CompileCache(root: root, maxBytes: mb * 1024 * 1024);
  }

  /// The folder holding the entries.
  final String root;

  /// The size the cache is evicted down to after a store.
  final int maxBytes;

  Directory _entry(String key) => Directory(p.join(root, key));

  /// Copies the entry [key]'s outputs to [outputs] (absolute paths, in the
  /// plan's order) and marks it used. False, with nothing copied, when there
  /// is no complete entry.
  bool restore(String key, List<String> outputs) {
    final dir = _entry(key);
    final info = _readInfo(dir);
    if (info == null) return false;
    final stored = (info['outputs'] as List?)?.length ?? -1;
    if (stored != outputs.length) return false;
    for (var i = 0; i < outputs.length; i++) {
      if (!File(p.join(dir.path, 'out$i')).existsSync()) return false;
    }
    for (var i = 0; i < outputs.length; i++) {
      final target = File(outputs[i]);
      target.parent.createSync(recursive: true);
      // Deleted first, so the copy takes the cached file's mode (executable).
      if (target.existsSync()) target.deleteSync();
      File(p.join(dir.path, 'out$i')).copySync(target.path);
    }
    info['used'] = DateTime.now().toUtc().toIso8601String();
    _writeInfo(dir, info);
    return true;
  }

  /// Stores [outputs] (absolute paths) under [key] with [description]
  /// (project, file, target), then evicts down to [maxBytes]. A missing
  /// output stores nothing.
  void store(
    String key,
    List<String> outputs, {
    Map<String, Object?> description = const {},
  }) {
    if (outputs.any((o) => !File(o).existsSync())) return;
    Directory(root).createSync(recursive: true);
    // Written beside the entry and renamed into place, so a concurrent run
    // never reads a half-written entry.
    final temp = Directory(root).createTempSync('.store-');
    try {
      var size = 0;
      for (var i = 0; i < outputs.length; i++) {
        final copy = File(outputs[i]).copySync(p.join(temp.path, 'out$i'));
        size += copy.lengthSync();
      }
      final now = DateTime.now().toUtc().toIso8601String();
      _writeInfo(temp, {
        ...description,
        'outputs': [for (final o in outputs) p.basename(o)],
        'size': size,
        'created': now,
        'used': now,
      });
      final entry = _entry(key);
      if (entry.existsSync()) entry.deleteSync(recursive: true);
      temp.renameSync(entry.path);
    } finally {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    }
    evict();
  }

  /// Deletes the entries used longest ago until the cache holds at most
  /// [maxBytes]; answers the keys deleted.
  List<String> evict() {
    final dir = Directory(root);
    if (!dir.existsSync()) return const [];
    final entries = <({String key, int size, String used})>[];
    for (final child in dir.listSync().whereType<Directory>()) {
      // `.store-*` folders are entries still being written.
      if (p.basename(child.path).startsWith('.')) continue;
      final info = _readInfo(child);
      if (info == null) continue;
      entries.add((
        key: p.basename(child.path),
        size: (info['size'] as num?)?.toInt() ?? 0,
        used: info['used']?.toString() ?? '',
      ));
    }
    var total = entries.fold<int>(0, (sum, e) => sum + e.size);
    entries.sort((a, b) => a.used.compareTo(b.used));
    final evicted = <String>[];
    for (final e in entries) {
      if (total <= maxBytes) break;
      _entry(e.key).deleteSync(recursive: true);
      total -= e.size;
      evicted.add(e.key);
    }
    return evicted;
  }

  Map<String, dynamic>? _readInfo(Directory dir) {
    final file = File(p.join(dir.path, 'entry.json'));
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  void _writeInfo(Directory dir, Map<String, Object?> info) => File(
    p.join(dir.path, 'entry.json'),
  ).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(info)}\n');
}

/// Whether `:compiler`'s options turn the cache off (`--no-cache`).
bool compileCacheDisabled(Map<String, dynamic> options) =>
    options['no-cache'] == true;
