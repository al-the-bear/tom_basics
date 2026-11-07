// Copyright (c) 2024. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Flutter's embedder SDK: the libraries Flutter adds to the Dart SDK
/// (`dart:ui`, `dart:ui_web` and the private libraries they need), listed in
/// `sky_engine/lib/_embedder.yaml`.
///
/// An analyzer summary of Flutter code needs them on **both** sides: the SDK
/// summary must hold `dart:ui` (`buildSdkSummary(embedderYamlPath: ...)`), and
/// a package summary must be linked against an SDK that holds it
/// ([dartSdkWithEmbedder]) — linked against the plain SDK, Flutter's
/// `export 'dart:ui' show ...` lines are dropped and `TextDirection`, `Color`,
/// `Offset` ... are undefined to everything reading the bundle.
library;

import 'dart:io';

import 'package:analyzer/file_system/file_system.dart' show ResourceProvider;
import 'package:analyzer/src/dart/sdk/sdk.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The embedder file of the Flutter SDK at [flutterSdkPath]
/// (`bin/cache/pkg/sky_engine/lib/_embedder.yaml`), or null when it has none.
String? flutterEmbedderYamlInSdk(String flutterSdkPath) => _existing(
  p.join(
    flutterSdkPath,
    'bin',
    'cache',
    'pkg',
    'sky_engine',
    'lib',
    '_embedder.yaml',
  ),
);

/// The embedder file of the `sky_engine` package among [packageRoots]
/// (name → package root, as `readPackageRoots` returns them): the embedder of
/// the very Flutter the packages were resolved against. Null when the
/// packages are no Flutter packages.
String? flutterEmbedderYamlInPackageRoots(Map<String, String> packageRoots) {
  final skyEngine = packageRoots['sky_engine'];
  return skyEngine == null
      ? null
      : _existing(p.join(skyEngine, 'lib', '_embedder.yaml'));
}

String? _existing(String path) =>
    File(path).existsSync() ? p.normalize(path) : null;

/// The Dart SDK at [sdkPath] with the libraries of the embedder at
/// [embedderYamlPath] added where the SDK lacks them — the same SDK
/// `buildSdkSummary(embedderYamlPath: ...)` summarises, for linking a package
/// summary that is read against that SDK summary. Without [embedderYamlPath]
/// it is the plain SDK.
FolderBasedDartSdk dartSdkWithEmbedder(
  ResourceProvider resourceProvider, {
  required String sdkPath,
  String? embedderYamlPath,
}) {
  final sdk = FolderBasedDartSdk(
    resourceProvider,
    resourceProvider.getFolder(sdkPath),
  );
  if (embedderYamlPath == null) return sdk;
  final file = resourceProvider.getFile(embedderYamlPath);
  final embedder = EmbedderSdk.new2(
    resourceProvider,
    file.parent,
    loadYaml(file.readAsStringSync()) as YamlMap,
    languageVersion: sdk.languageVersion,
  );
  for (final library in embedder.sdkLibraries) {
    if (sdk.libraryMap.getLibrary(library.shortName) == null) {
      sdk.libraryMap.setLibrary(library.shortName, library);
    }
  }
  return sdk;
}
