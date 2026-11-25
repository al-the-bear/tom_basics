/// `buildkit :skill-build-binaries` and `:skill-build-all-binaries`
/// (buildkit_ws_commands.md § 1.6, § 1.9; decisions WSC-13, -14, -23).
///
/// Both build into tom_binaries:
///
/// 1. The generators first (tom_d4rt_generator, tom_reflection_generator:
///    `:versioner :pubget :compiler`), as `build_binaries.sh` step 2.
/// 2. `:skill-build-binaries`: the projects that compile a release
///    executable; `:skill-build-all-binaries`: every project (as
///    `build_binaries.sh` step 3) — `:versioner :pubget :d4rtgen
///    :reflectiongenerator --no-cache :compiler`, run by a buildkit
///    subprocess with `TOM_BINARY_PATH` = `tom_binaries/tom`, as every build
///    of the layer (the shared step records of `.buildkit/steps` stay where
///    the other hosts find them).
/// 3. Every binary the run wrote into `tom/<platform>/` that is no release
///    binary is moved to `all/<platform>/` (ignored by tom_binaries/.gitignore).
/// 4. buildkit itself (a project that opts out of being compiled by buildkit:
///    buildkit, findproject, wssetup) is compiled to `<name>.new` beside its
///    target, the target renamed aside to `<name>.old` (a running executable
///    can be renamed, also on Windows) and the new one given its name; the
///    `.old` files are deleted on the next run. When the running buildkit is
///    too old for this command, `bootstrap_binaries.sh` is the fallback.
/// 5. The short names: a symlink on macOS and Linux; on Windows a Git Bash
///    script and a `.cmd` (and a hard link with `windows-hard-link`).
///
/// The binaries another tool builds and the bundled ones are named and left
/// as they are. `--list` prints the set and where each entry is declared.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tom_build_base/tom_build_base_v2.dart';

import '../../platform_utils.dart';
import 'binaries_messages.dart';
import 'release_set.dart';

/// What a build step returns.
typedef BinStepResult = ({int exitCode, String output});

/// Runs buildkit with [args] in [workingDirectory] with [environment].
typedef BinBuildkitRunner =
    Future<BinStepResult> Function(
      List<String> args, {
      required Map<String, String> environment,
      required String workingDirectory,
    });

/// Compiles [dartFile] of [projectDir] to [output].
typedef BinSelfCompiler =
    Future<BinStepResult> Function(
      String projectDir,
      String dartFile,
      String output,
    );

/// The projects compiled first: the generators the others need on PATH.
const binGeneratorProjects = ['tom_d4rt_generator', 'tom_reflection_generator'];

/// The commands of the full build (`build_binaries.sh` step 3).
const binBuildCommands = [
  ':versioner',
  ':pubget',
  ':d4rtgen',
  ':reflectiongenerator',
  '--no-cache',
  ':compiler',
];

/// Whether [name] is a file a swap set aside (`<name>.old`, `<name>.old.<n>`).
bool binIsOld(String name) =>
    name.endsWith('.old') || RegExp(r'\.old\.\d+$').hasMatch(name);

/// Deletes the files a previous swap set aside in [dir]; one still in use
/// (Windows) stays for the next run.
int binDeleteOld(String dir) {
  var n = 0;
  final d = Directory(dir);
  if (!d.existsSync()) return 0;
  for (final f in d.listSync(followLinks: false)) {
    if (f is! File || !binIsOld(p.basename(f.path))) continue;
    try {
      f.deleteSync();
      n++;
    } on FileSystemException {
      // Still running: deleted next time.
    }
  }
  return n;
}

/// Puts [built] in place of [target] without overwriting it in place: an
/// existing target is renamed aside to `<target>.old` (a running executable
/// can be renamed, also on Windows; one in use cannot be deleted or
/// overwritten), then [built] gets its name.
void binSwapIn(String built, String target) {
  final type = FileSystemEntity.typeSync(target, followLinks: false);
  if (type != FileSystemEntityType.notFound) {
    var old = '$target.old';
    if (FileSystemEntity.typeSync(old, followLinks: false) !=
        FileSystemEntityType.notFound) {
      try {
        File(old).deleteSync();
      } on FileSystemException {
        old = '$target.old.${DateTime.now().microsecondsSinceEpoch}';
      }
    }
    if (type == FileSystemEntityType.link) {
      Link(target).deleteSync();
    } else {
      File(target).renameSync(old);
    }
  }
  File(built).renameSync(target);
}

/// The tom_binaries clone: [given], else the `kind: binaries` entry of the
/// repos.yaml above [root] for this host, else `<root>/tom_binaries`.
String binTomBinaries(String root, {String? given}) {
  if (given != null) return p.normalize(p.absolute(given));
  try {
    final set = RepoSet.discover(root);
    if (set != null) {
      for (final e in set.manifest.entries) {
        if (e.kind == RepoKind.binaries && e.isForHost(set.host)) {
          return p.join(set.root, p.joinAll(e.path.split('/')));
        }
      }
    }
  } on Object {
    // No or an unreadable repos.yaml: the default below.
  }
  return p.join(root, 'tom_binaries');
}

/// Runs this buildkit again as a subprocess (the compiled binary, or the Dart
/// script it was started from), output streamed to [progress].
BinBuildkitRunner binDefaultBuildkit(StringSink progress) =>
    (args, {required environment, required workingDirectory}) async {
      final exe = Platform.resolvedExecutable;
      final viaDart =
          p.basenameWithoutExtension(exe) == 'dart' &&
          Platform.script.scheme == 'file' &&
          Platform.script.path.endsWith('.dart');
      final command = viaDart
          ? [exe, Platform.script.toFilePath(), ...args]
          : [exe, ...args];
      return binRunStreamed(command, environment, workingDirectory, progress);
    };

/// `dart pub get` once per project, then `dart compile exe`.
BinSelfCompiler binDefaultSelfCompiler(StringSink progress) {
  final got = <String>{};
  return (projectDir, dartFile, output) async {
    if (got.add(projectDir)) {
      final r = await binRunStreamed(
        ['dart', 'pub', 'get'],
        Platform.environment,
        projectDir,
        progress,
      );
      if (r.exitCode != 0) return r;
    }
    return binRunStreamed(
      ['dart', 'compile', 'exe', dartFile, '-o', output],
      Platform.environment,
      projectDir,
      progress,
    );
  };
}

/// Runs [command], every line of its output written to [progress]; answers
/// the exit code and the last 40 lines.
Future<BinStepResult> binRunStreamed(
  List<String> command,
  Map<String, String> environment,
  String workingDirectory,
  StringSink progress,
) async {
  final tail = <String>[];
  void line(String l) {
    progress.writeln(l);
    tail.add(l);
    if (tail.length > 40) tail.removeAt(0);
  }

  final Process proc;
  try {
    proc = await Process.start(
      command.first,
      command.skip(1).toList(),
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (e) {
    return (exitCode: 127, output: '$e');
  }
  final a = proc.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(line)
      .asFuture<void>();
  final b = proc.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(line)
      .asFuture<void>();
  final code = await proc.exitCode;
  await Future.wait([a, b]);
  return (exitCode: code, output: tail.join('\n'));
}

/// One build of the release binaries ([all]: the full build).
class SkillBinariesBuild {
  SkillBinariesBuild({
    required this.set,
    required this.binaries,
    required this.all,
    String? platform,
    this.dryRun = false,
    DateTime? now,
    BinBuildkitRunner? buildkit,
    BinSelfCompiler? compileSelf,
    StringSink? progress,
  }) : platform = platform ?? PlatformUtils.getCurrentPlatform(),
       now = now ?? DateTime.now(),
       _progress = progress ?? stderr {
    _buildkit = buildkit ?? binDefaultBuildkit(_progress);
    _compileSelf = compileSelf ?? binDefaultSelfCompiler(_progress);
  }

  final ReleaseSet set;

  /// The tom_binaries clone.
  final String binaries;
  final bool all;
  final String platform;
  final bool dryRun;
  final DateTime now;
  final StringSink _progress;
  late final BinBuildkitRunner _buildkit;
  late final BinSelfCompiler _compileSelf;

  late final RunReport report;
  late final DateTime _started;

  /// The commands run (or, with -n, that would run).
  final planned = <String>[];

  String get command =>
      all ? ':skill-build-all-binaries' : ':skill-build-binaries';
  String get _tom => p.join(binaries, 'tom', platform);
  String get _all => p.join(binaries, 'all', platform);
  bool get _win => platform.startsWith('win32');

  Future<RunReport> run() async {
    // Whole seconds: file times may be stored without the fraction.
    _started = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    report = RunReport(
      tool: 'buildkit',
      command: command,
      root: set.root,
      host: Platform.localHostname,
      started: now,
      given: const [],
      names: RepoNames(const []),
    );
    if (!_refused()) await _build();
    return report;
  }

  bool _refused() {
    if (set.problems.isNotEmpty) {
      report.add(
        binSet.raise(
          finding: '${set.problems.length} problem(s):',
          evidence: [ReportEvidence('problems', set.problems)],
          state: 'Nothing was built.',
        ),
      );
      return true;
    }
    if (!Directory(p.join(binaries, '.git')).existsSync() &&
        !File(p.join(binaries, '.git')).existsSync()) {
      report.add(
        binNoClone.raise(
          finding: 'No clone at $binaries.',
          state: 'Nothing was built.',
        ),
      );
      return true;
    }
    final ignored = Process.runSync('git', [
      'check-ignore',
      '-q',
      'all/$platform/probe',
    ], workingDirectory: binaries);
    if (ignored.exitCode != 0) {
      report.add(
        binNotIgnored.raise(
          finding: 'git check-ignore all/$platform/ in $binaries: not ignored.',
          state: 'Nothing was built; add /all/ to tom_binaries/.gitignore.',
        ),
      );
      return true;
    }
    return false;
  }

  Map<String, String> get _environment {
    final sep = _win ? ';' : ':';
    return {
      ...Platform.environment,
      'TOM_BINARY_PATH': p.join(binaries, 'tom'),
      'PATH': '$_tom$sep${Platform.environment['PATH'] ?? ''}',
    };
  }

  Future<bool> _step(String label, List<String> args) async {
    planned.add('buildkit ${args.join(' ')}');
    if (dryRun) return true;
    _progress.writeln('=== $label: buildkit ${args.join(' ')}');
    final r = await _buildkit(
      args,
      environment: _environment,
      workingDirectory: set.root,
    );
    if (r.exitCode == 0) return true;
    report.add(
      binBuildFailed.raise(
        finding:
            '$label failed (exit ${r.exitCode}): buildkit ${args.join(' ')}',
        evidence: [
          ReportEvidence('output', r.output.split('\n'), label: 'Output:'),
        ],
        state: 'The steps after it ran; what was built is in place.',
      ),
    );
    return false;
  }

  Future<void> _build() async {
    final release = set.forPlatform(platform);
    final compiled = [
      for (final b in release)
        if (b.kind == ReleaseKind.compiled) b,
    ];
    final selfBuilt = [
      for (final b in compiled)
        if (b.selfBuilt) b,
    ];
    final others = [
      for (final b in compiled)
        if (!b.selfBuilt) b,
    ];
    report.lookedAt.addAll([
      for (final b in compiled) 'tom/$platform/${b.fileName(platform)}',
    ]);
    if (!dryRun) {
      Directory(_all).createSync(recursive: true);
      Directory(_tom).createSync(recursive: true);
      final removed = binDeleteOld(_tom);
      if (removed > 0) {
        report.changed(
          ReportDone('tom/$platform', [
            'deleted $removed file(s) set aside last time (*.old)',
          ]),
        );
      }
    }

    // 1. The generators.
    final generators = [
      for (final g in binGeneratorProjects)
        if (releaseProjects(set.root).any((d) => p.basename(d) == g)) g,
    ];
    if (generators.isNotEmpty) {
      await _step('the generators', [
        for (final g in generators) ...['-p', g],
        ':versioner',
        ':pubget',
        ':compiler',
      ]);
    }

    // 2. The release projects, or every project.
    if (all) {
      await _step('the full build', binBuildCommands);
    } else {
      final projects = <String>{
        for (final b in others) p.basename(b.projectDir!),
      }..removeAll(generators);
      if (projects.isNotEmpty) {
        await _step('the release projects', [
          for (final x in projects.toList()..sort()) ...['-p', x],
          ...binBuildCommands,
        ]);
      }
    }

    // 3. Every binary this run wrote that is no release binary goes to
    // all/<platform>/; the release ones stay where the compiler wrote them.
    final keep = <String>{
      for (final b in release) ...[
        b.name,
        ...b.builtFiles(platform),
        ...b.shortFiles(platform),
        for (final n in {b.name, b.fileName(platform)}) ...[
          '$n.buildkit.json',
          '$n.build.json',
        ],
      ],
    };
    if (!dryRun) {
      final moved = <String>[];
      for (final f in Directory(_tom).listSync(followLinks: false)) {
        final name = p.basename(f.path);
        if (f is! File ||
            name.startsWith('.') ||
            binIsOld(name) ||
            keep.contains(name)) {
          continue;
        }
        // Only what this run wrote: anything older was there before it.
        // (Links and folders stay: a short name, an application bundle.)
        if (f.statSync().modified.isBefore(_started)) continue;
        final to = p.join(_all, name);
        if (FileSystemEntity.isLinkSync(to)) {
          Link(to).deleteSync();
        } else if (File(to).existsSync()) {
          File(to).deleteSync();
        }
        f.renameSync(to);
        moved.add(name);
      }
      if (moved.isNotEmpty) {
        report.changed(
          ReportDone('all/$platform', [
            'moved ${moved.length} file(s) that are no release binaries out of tom/$platform/',
          ], files: moved..sort()),
        );
      }
    }
    for (final b in others) {
      final main = p.join(_tom, b.fileName(platform));
      if (dryRun) {
        report.changed(
          ReportDone('tom/$platform/${b.fileName(platform)}', [
            'would be built by its project\'s :compiler',
          ]),
        );
        continue;
      }
      if (!File(main).existsSync()) {
        report.add(
          binMissing.raise(
            finding:
                '${b.fileName(platform)} (${b.project}) was not written to '
                'tom/$platform/.',
            state: 'The other release binaries are in place.',
          ),
        );
        continue;
      }
      final fresh = !File(main).statSync().modified.isBefore(_started);
      report.changed(
        ReportDone('tom/$platform/${b.fileName(platform)}', [
          fresh
              ? 'built (${b.project})'
              : 'up to date (${b.project}: its :compiler had nothing to do)',
        ]),
      );
    }

    // 4. buildkit itself: its version stamp first (:versioner :pubget, as
    // every other project), then compiled beside the target and swapped in.
    final selfProjects = <String>{
      for (final b in selfBuilt) p.basename(b.projectDir!),
    };
    if (selfProjects.isNotEmpty) {
      await _step('buildkit itself (version stamp)', [
        for (final x in selfProjects.toList()..sort()) ...['-p', x],
        ':versioner',
        ':pubget',
      ]);
    }
    for (final b in selfBuilt) {
      final target = p.join(_tom, b.fileName(platform));
      final built = '$target.new';
      final source = 'bin/${b.name}.dart';
      planned.add(
        'dart compile exe $source -o $built (${b.project}), swapped in',
      );
      if (dryRun) {
        report.changed(
          ReportDone('tom/$platform/${b.fileName(platform)}', [
            'would be compiled beside it and swapped in',
          ]),
        );
        continue;
      }
      final r = await _compileSelf(b.projectDir!, source, built);
      if (r.exitCode != 0 || !File(built).existsSync()) {
        report.add(
          binBuildFailed.raise(
            finding:
                'Compiling ${b.name} (${b.project}) failed (exit ${r.exitCode}).',
            evidence: [
              ReportEvidence('output', r.output.split('\n'), label: 'Output:'),
            ],
            state: 'The ${b.fileName(platform)} there stays.',
          ),
        );
        continue;
      }
      binSwapIn(built, target);
      report.changed(
        ReportDone('tom/$platform/${b.fileName(platform)}', [
          'built (${b.project}) and swapped in; the old one is '
              '${b.fileName(platform)}.old until the next run',
        ]),
      );
    }

    // 5. The short names.
    for (final b in release) {
      for (final s in b.shortNames) {
        _short(b, s);
      }
    }

    // 6. What is not built here.
    final notHere = [
      for (final b in release)
        if (b.kind != ReleaseKind.compiled) b,
    ];
    if (notHere.isNotEmpty) {
      report.add(
        binNotBuilt.raise(
          finding:
              '${notHere.length} release binaries are not built by buildkit:',
          evidence: [
            ReportEvidence('binaries', [
              for (final b in notHere)
                '${b.name}: ${b.kind == ReleaseKind.bundled ? 'bundled' : 'built by ${b.builtBy}'}'
                    '${_exists(b) ? '' : ' (missing on $platform)'}',
            ]),
          ],
          state: 'Left as they are.',
        ),
      );
    }

    if (all && !dryRun) {
      final rest = Directory(_all).existsSync()
          ? Directory(_all)
                .listSync(followLinks: false)
                .where((f) => !p.basename(f.path).endsWith('.buildkit.json'))
                .length
          : 0;
      report.changed(
        ReportDone('all/$platform', [
          '$rest other binaries (no release binary; ignored by git)',
        ]),
      );
    }
  }

  /// Whether [b] is there: its file in its folder, or for an entry with a
  /// `path:` of its own (pdfium, sqlite_vec) that folder.
  bool _exists(ReleaseBinary b) =>
      FileSystemEntity.typeSync(
        b.path != null
            ? b.folder(binaries, platform)
            : p.join(b.folder(binaries, platform), b.name),
        followLinks: false,
      ) !=
      FileSystemEntityType.notFound;

  /// Creates a short name of [b] (a symlink; on Windows a Git Bash script, a
  /// `.cmd` and, with `windows-hard-link`, a hard link).
  void _short(ReleaseBinary b, ReleaseShortName s) {
    final folder = b.folder(binaries, platform);
    final target = s.target ?? b.fileName(platform);
    final rel = 'tom/$platform/${s.name}';
    if (!File(p.join(folder, target)).existsSync() &&
        !Link(p.join(folder, target)).existsSync()) {
      return; // Nothing to point to on this platform.
    }
    if (dryRun) {
      report.changed(ReportDone(rel, ['would point to $target']));
      return;
    }
    if (!_win) {
      final link = Link(p.join(folder, s.name));
      if (link.existsSync() && link.targetSync() == target) return;
      if (FileSystemEntity.typeSync(link.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        FileSystemEntity.isLinkSync(link.path)
            ? link.deleteSync()
            : File(link.path).deleteSync();
      }
      link.createSync(target);
      report.changed(ReportDone(rel, ['-> $target']));
      return;
    }
    final changed = <String>[];
    void write(String file, String text) {
      final f = File(p.join(folder, file));
      if (f.existsSync() && f.readAsStringSync() == text) return;
      f.writeAsStringSync(text);
      changed.add(file);
    }

    write(
      s.name,
      '#!/bin/sh\n'
      '# Alias for $target in Git Bash (git symlinks are off on Windows checkouts).\n'
      'exec "\$(dirname "\$0")/$target" "\$@"\n',
    );
    write('${s.name}.cmd', '@"%~dp0$target" %*\r\n');
    if (b.windowsHardLink) {
      final link = p.join(folder, '${s.name}.exe');
      if (File(link).existsSync()) {
        final aside = '$link.old';
        try {
          if (File(aside).existsSync()) File(aside).deleteSync();
          File(link).renameSync(aside);
        } on FileSystemException {
          File(
            link,
          ).renameSync('$link.old.${DateTime.now().microsecondsSinceEpoch}');
        }
      }
      try {
        final r = Process.runSync('cmd', [
          '/c',
          'mklink',
          '/H',
          link,
          p.join(folder, target),
        ]);
        if (r.exitCode == 0) changed.add('${s.name}.exe');
      } on ProcessException {
        // No cmd (a Windows layout written on another platform): no link.
      }
    }
    if (changed.isNotEmpty) {
      report.changed(ReportDone(rel, ['-> $target'], files: changed));
    }
  }

  Map<String, Object?> toJson() => {
    'platform': platform,
    'binaries': binaries,
    'all': all,
    'commands': planned,
  };
}

/// The `--list` of the release set, as text.
String binListText(ReleaseSet set, String platform) {
  final b = StringBuffer()
    ..writeln(
      'The release binaries (${set.binaries.length}; on $platform: '
      '${set.forPlatform(platform).length}):',
    )
    ..writeln();
  for (final x in set.binaries) {
    final how = switch (x.kind) {
      ReleaseKind.compiled =>
        'compiled by ${x.project}${x.selfBuilt ? ' (swapped in)' : ''}',
      ReleaseKind.external => 'built by ${x.builtBy}',
      ReleaseKind.bundled => 'bundled',
    };
    b.writeln('  ${x.name}${x.path != null ? '  (${x.path}/)' : ''}');
    b.writeln('      $how');
    if (x.files.isNotEmpty) b.writeln('      files: ${x.files.join(', ')}');
    if (x.shortNames.isNotEmpty) {
      b.writeln(
        '      short: ${[for (final s in x.shortNames) s.target == null ? s.name : '${s.name} -> ${s.target}'].join(', ')}'
        '${x.windowsHardLink ? ' (hard link on Windows)' : ''}',
      );
    }
    if (x.platforms != null) {
      b.writeln('      platforms: ${x.platforms!.join(', ')}');
    }
    b.writeln('      declared in: ${x.declaredIn.join(', ')}');
  }
  if (set.problems.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Problems:');
    for (final x in set.problems) {
      b.writeln('  $x');
    }
  }
  return '$b';
}
