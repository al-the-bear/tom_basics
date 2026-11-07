/// A grouped bundle of Flutter packages is linked against the SDK with
/// Flutter's embedder, so the `dart:ui` types Flutter re-exports resolve to
/// code read against the bundle and an SDK summary built with the same
/// embedder.
///
/// The fixture is a miniature Flutter: a `sky_engine` package whose
/// `_embedder.yaml` adds a `dart:ui` with `TextDirection` and `Color`, and a
/// `flutter` package whose `painting.dart` re-exports them, as Flutter's
/// does.
@Timeout(Duration(minutes: 3))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/sdk/build_sdk_summary.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/src/context/packages.dart';
import 'package:analyzer/src/analysis_options/analysis_options.dart';
import 'package:analyzer/src/dart/analysis/analysis_options_map.dart';
import 'package:analyzer/src/dart/analysis/byte_store.dart';
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/performance_logger.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer/src/file_system/file_system.dart'
    show ResourceUriResolver;
import 'package:analyzer/src/generated/source.dart'
    show DartUriResolver, SourceFactory;
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/summary/summary_sdk.dart';
import 'package:analyzer/src/summary2/package_bundle_format.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_analyzer_shared/tom_analyzer_shared.dart';

/// The diagnostics of [code], analysed against [sdkSummary] and
/// [packageSummary] alone — no sources on disk, as an embedded editor reads
/// them.
Future<List<Diagnostic>> _errorsOf(
  String code, {
  required Uint8List sdkSummary,
  required Uint8List packageSummary,
}) async {
  final sdkBundle = PackageBundleReader(sdkSummary);
  final packageBundle = PackageBundleReader(packageSummary);
  final store = SummaryDataStore()
    ..addBundle('sdk', sdkBundle)
    ..addBundle('packages', packageBundle);
  for (final library in packageBundle.libraries) {
    store.uriToSummaryPath.putIfAbsent(library.uriStr, () => 'packages');
  }
  final provider = MemoryResourceProvider();
  final file = provider.newFile('/app/lib/main.dart', code);
  final logger = PerformanceLog(null);
  final scheduler = AnalysisDriverScheduler(logger)..start();
  final driver = AnalysisDriver(
    scheduler: scheduler,
    logger: logger,
    resourceProvider: provider,
    byteStore: MemoryByteStore(),
    sourceFactory: SourceFactory([
      DartUriResolver(SummaryBasedDartSdk.forBundle(sdkBundle)),
      InSummaryUriResolver(store),
      ResourceUriResolver(provider),
    ]),
    analysisOptionsMap: AnalysisOptionsMap.forSharedOptions(
      AnalysisOptionsImpl(),
    ),
    externalSummaries: store,
    packages: Packages.empty,
    withFineDependencies: false,
  );
  final result = await driver.getErrors(file.path) as ErrorsResult;
  await driver.dispose2();
  return [
    for (final d in result.diagnostics)
      if (d.severity == Severity.error) d,
  ];
}

void main() {
  late Directory work;
  late String consumer;
  late String embedder;
  late String sdkPath;

  void write(String path, String text) => (File(
    p.join(work.path, path),
  )..createSync(recursive: true)).writeAsStringSync(text);

  setUpAll(() {
    sdkPath =
        resolveDartSdkPath() ??
        p.dirname(p.dirname(Platform.resolvedExecutable));
    work = Directory(
      p.join(
        Directory.current.path,
        'ztmp',
        'grouped_dart_ui_${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    write('sky_engine/lib/_embedder.yaml', '''
embedded_libs:
  "dart:ui": "ui/ui.dart"
''');
    write('sky_engine/lib/ui/ui.dart', '''
library dart.ui;

enum TextDirection { rtl, ltr }

class Color {
  const Color(this.value);
  final int value;
}
''');
    write('flutter/lib/painting.dart', '''
export 'dart:ui' show Color, TextDirection;

class TextSpan {
  const TextSpan({this.textDirection});
  final TextDirection? textDirection;
}
''');
    write('consumer/.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    { "name": "sky_engine", "rootUri": "../../sky_engine", "packageUri": "lib/" },
    { "name": "flutter", "rootUri": "../../flutter", "packageUri": "lib/" }
  ]
}
''');
    consumer = p.join(work.path, 'consumer');
    embedder = p.normalize(p.join(work.path, 'sky_engine/lib/_embedder.yaml'));
  });

  tearDownAll(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  const code = '''
import 'package:flutter/painting.dart';

const span = TextSpan(textDirection: TextDirection.ltr);
const red = Color(0xFFFF0000);
''';

  test('GDU-1: the embedder is found from the packages\' sky_engine, and '
      'the bundle links against it: dart:ui types re-exported by Flutter '
      'resolve against the bundle and an SDK summary with the same '
      'embedder', () async {
    expect(
      flutterEmbedderYamlInPackageRoots(mergePackageRootsForDirs([consumer])),
      embedder,
    );
    final bundle = await GroupedPackageBundleBuilder().buildFromDirs([
      consumer,
    ], sdkPath: sdkPath);
    expect(bundle.embedderYamlPath, embedder);

    final sdkSummary = await buildSdkSummary(
      resourceProvider: PhysicalResourceProvider.INSTANCE,
      sdkPath: sdkPath,
      embedderYamlPath: bundle.embedderYamlPath,
    );
    final errors = await _errorsOf(
      code,
      sdkSummary: sdkSummary,
      packageSummary: bundle.bytes,
    );
    expect(errors, isEmpty, reason: errors.map((e) => e.message).join('\n'));
    expect(summaryLibraryUris(sdkSummary), contains('dart:ui'));
    expect(
      summaryLibraryUris(bundle.bytes),
      contains('package:flutter/painting.dart'),
    );

    // A mistake is still reported: the analysis is real.
    final broken = await _errorsOf(
      code.replaceFirst('TextDirection.ltr', 'TextDirection.up'),
      sdkSummary: sdkSummary,
      packageSummary: bundle.bytes,
    );
    expect(broken, isNotEmpty);
  });

  test(
    'GDU-2: a bundle of no Flutter packages links against the plain SDK',
    () async {
      write('plain/lib/plain.dart', 'int answer() => 42;\n');
      write('plain_consumer/.dart_tool/package_config.json', '''
{
  "configVersion": 2,
  "packages": [
    { "name": "plain", "rootUri": "../../plain", "packageUri": "lib/" }
  ]
}
''');
      final bundle = await GroupedPackageBundleBuilder().buildFromDirs([
        p.join(work.path, 'plain_consumer'),
      ], sdkPath: sdkPath);
      expect(bundle.embedderYamlPath, isNull);
      expect(bundle.libraryCount, 1);
    },
  );
}
