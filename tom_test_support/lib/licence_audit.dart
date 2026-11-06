/// A licence audit of the packages an application resolves: every package it
/// links carries a `LICENSE`, and the licence is one the application's own
/// terms admit.
///
/// **The packages are the ones the application resolves.** They are read from
/// its own package configuration, and their dependencies from each package's
/// `pubspec.yaml`, so a path, a fork or a version that changes is followed
/// rather than recorded. Only `dependencies:` are walked: dev dependencies are
/// not linked into what the application ships.
///
/// A package of the Flutter SDK (`sdk: flutter`) is judged by the SDK's
/// licence, which is the `flutter` package's: `flutter_web_plugins` ships no
/// `LICENSE` of its own, and `sky_engine`'s is the engine's aggregated
/// third-party notices. The SDK is the precondition of every Flutter
/// application rather than a dependency the application chose.
///
/// What an application admits is its own decision, passed as `admitted`:
/// [TomLicence.permissive] for a product that takes in only permissive work,
/// or that set plus [TomLicence.mpl2] for one that carries the file-level
/// copyleft of MPL-2.0 with its notice.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'roots.dart';

/// The licences the audit recognises. Every one is redistributable inside a
/// statically linked application; the strong and the lesser GPLs are not
/// among them (an ahead-of-time build cannot honour the LGPL's relinking
/// requirement), so a package under one of them is never admitted.
enum TomLicence {
  bsd3,
  bsd2,
  mit,
  apache2,
  isc,
  zlib,

  /// Mozilla Public License 2.0: copyleft per file, so an application may
  /// link it under any terms as long as its notice says where the covered
  /// files' source is.
  mpl2;

  /// The permissive families: each is one-way compatible into BSD-3 and into
  /// GPL-3.0/AGPL-3.0 alike.
  static const permissive = {bsd3, bsd2, mit, apache2, isc, zlib};
}

/// What [text] grants, or null when it is none of the [TomLicence]s.
///
/// Recognised by the operative sentences of each licence rather than by a
/// name or an SPDX tag, which a file may carry without carrying the terms.
/// A GPL family wins over a permissive phrase quoted inside it.
TomLicence? tomClassifyLicence(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ');
  // First, because MPL-2.0 names the GNU licences itself (its "Secondary
  // Licenses"), and a GPL text never names the MPL.
  if (t.contains('Mozilla Public License Version 2.0') ||
      t.contains('Mozilla Public License, v. 2.0')) {
    return TomLicence.mpl2;
  }
  if (RegExp(
    r'GNU (Affero |Lesser |Library )?General Public License',
  ).hasMatch(t)) {
    return null;
  }
  if (t.contains('Apache License') && t.contains('Version 2.0')) {
    return TomLicence.apache2;
  }
  if (t.contains('Permission is hereby granted, free of charge')) {
    return TomLicence.mit;
  }
  if (t.contains('Redistribution and use in source and binary forms')) {
    return t.contains('Neither the name') ? TomLicence.bsd3 : TomLicence.bsd2;
  }
  if (t.contains(
    'Permission to use, copy, modify, and/or distribute this '
    'software for any purpose with or without fee',
  )) {
    return TomLicence.isc;
  }
  if (t.contains('This software is provided \'as-is\'') &&
      t.contains('Permission is granted to anyone to use this software')) {
    return TomLicence.zlib;
  }
  return null;
}

/// The licence file of the package at [root], or null when it has none.
File? tomLicenceFileOf(Directory root) {
  for (final name in ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING']) {
    final file = File(p.join(root.path, name));
    if (file.existsSync()) return file;
  }
  return null;
}

/// One package an application links: where it resolves, and whether it is
/// the SDK's.
typedef TomLinkedPackage = ({String name, Directory root, bool sdk});

/// The resolved package roots of the package configuration of the
/// application in [package], a directory of the repository root.
///
/// `flutter test` runs a test without `Isolate.packageConfig`, so the file is
/// found by landmark: the repository root, then the package by its name.
Map<String, Directory> tomResolvedPackages(String package) {
  final config = File(
    p.join(
      tomFindRepositoryRoot().path,
      package,
      '.dart_tool',
      'package_config.json',
    ),
  );
  if (!config.existsSync()) {
    throw StateError(
      '${config.path} is missing: run `flutter pub get` in '
      '$package, so the packages it resolves can be read',
    );
  }
  final decoded = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in (decoded['packages'] as List).cast<Map>())
      entry['name'] as String: Directory.fromUri(
        config.uri.resolve(entry['rootUri'] as String),
      ),
  };
}

/// Every package reached from [start] through `dependencies:` (dev
/// dependencies are not linked), [start] first, in discovery order.
List<TomLinkedPackage> tomLinkedPackages(
  String start,
  Map<String, Directory> packages,
) {
  final found = <String, TomLinkedPackage>{};
  void visit(String name, {required bool sdk}) {
    if (found.containsKey(name)) return;
    final root = packages[name];
    if (root == null) {
      throw StateError(
        '$name is a dependency reached from $start but the '
        'package configuration does not resolve it',
      );
    }
    found[name] = (name: name, root: root, sdk: sdk);
    final pubspec =
        loadYaml(File(p.join(root.path, 'pubspec.yaml')).readAsStringSync())
            as YamlMap;
    final dependencies = pubspec['dependencies'] as YamlMap? ?? YamlMap();
    for (final entry in dependencies.entries) {
      final spec = entry.value;
      visit(entry.key as String, sdk: spec is YamlMap && spec['sdk'] != null);
    }
  }

  visit(start, sdk: false);
  return found.values.toList();
}

/// The licence each package in [linked] grants; a missing licence, one the
/// audit does not recognise, or one outside [admitted] is a problem, named.
({Map<String, TomLicence> granted, List<String> problems}) tomAuditLicences(
  List<TomLinkedPackage> linked, {
  required Set<TomLicence> admitted,
}) {
  final granted = <String, TomLicence>{};
  final problems = <String>[];
  final sdkRoot = linked.where((e) => e.name == 'flutter').firstOrNull?.root;
  final admittedNames = admitted.map((l) => l.name).join(', ');
  for (final package in linked) {
    final file = package.sdk && sdkRoot != null
        ? tomLicenceFileOf(sdkRoot)
        : tomLicenceFileOf(package.root);
    if (file == null) {
      problems.add(
        '${package.name} (${package.root.path}) carries no '
        'LICENSE: it grants nothing, so it is not redistributable.',
      );
      continue;
    }
    final licence = tomClassifyLicence(file.readAsStringSync());
    if (licence == null) {
      problems.add(
        '${package.name}: ${file.path} is not a licence this '
        'audit admits ($admittedNames); a GPL family or an unrecognised '
        'text.',
      );
      continue;
    }
    if (!admitted.contains(licence)) {
      problems.add(
        '${package.name}: ${file.path} is ${licence.name}, which '
        'is not admitted here ($admittedNames).',
      );
      continue;
    }
    granted[package.name] = licence;
  }
  return (granted: granted, problems: problems);
}
