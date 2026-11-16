// Runnable example for Tom Package Scanner.
//
// Builds a small fixture repo in a temporary directory — four Dart packages
// and one TypeScript package, one for each rung of the status ladder — scans
// it twice (once as a public repo, once as a private one), classifies a few
// license bodies, and deletes the fixture at the end.
//
// Run from the package folder:
//
//     dart run example/tom_package_scanner_example.dart
import 'dart:io';

import 'package:tom_package_scanner/tom_package_scanner.dart';

void main() {
  final root = Directory.systemTemp.createTempSync('tom_package_scanner_ex_');
  try {
    _buildFixture(root.path);

    final scanner = PackageScanner(
      sourceRoot: root.path,
      pathPrefix: 'tom_ai',
      locThreshold: 200,
    );

    print('== Public repo "demo" ==');
    final packages = scanner.scanRepo('demo', repoIsPublic: true);
    for (final pkg in packages) {
      print('${pkg.dirName.padRight(14)} '
          '${pkg.status.yamlValue.padRight(12)} ${pkg.statusReason}');
    }

    print('');
    print('== The same repo, private ==');
    for (final pkg in scanner.scanRepo('demo', repoIsPublic: false)) {
      print('${pkg.dirName.padRight(14)} '
          '${pkg.status.yamlValue.padRight(12)} ${pkg.statusReason}');
    }

    print('');
    print('== One record in full ==');
    final pub = packages.firstWhere((p) => p.dirName == 'tom_pub');
    print('sourcePath     : ${pub.sourcePath}');
    print('name           : ${pub.name}');
    print('version        : ${pub.version}');
    print('description    : ${pub.description}');
    print('license        : ${pub.license}');
    print('hasProjectYaml : ${pub.hasProjectYaml}');
    print('metrics        : ${pub.metrics}');
    print('links          : ${pub.links}');

    print('');
    print('== License classification ==');
    const samples = {
      'MIT body': 'MIT License\n\nPermission is hereby granted, free of charge',
      'BSD-3 body': 'Copyright (c) 2026. All rights reserved.\n'
          'Redistribution and use in source and binary forms ...\n'
          'Neither the name of the copyright holder ...',
      'Apache body': 'Apache License\nVersion 2.0, January 2004',
      'placeholder': 'TODO: Add your license here',
    };
    samples.forEach((label, text) {
      print('${label.padRight(12)} -> ${classifyLicense(text)}');
    });
    print('isValidLicenseToken("proprietary")   = '
        '${isValidLicenseToken('proprietary')}');
    print('isValidLicenseToken("not-a-license") = '
        '${isValidLicenseToken('not-a-license')}');

    print('');
    print('== Absent repo ==');
    print('scanRepo("missing") -> '
        '${scanner.scanRepo('missing', repoIsPublic: true)}');
  } finally {
    root.deleteSync(recursive: true);
  }
}

/// Lays out `<root>/tom_ai/demo/<package>` for five packages.
void _buildFixture(String root) {
  final repo = '$root/tom_ai/demo';

  // A release marker wins over everything else.
  _write('$repo/tom_released/pubspec.yaml',
      'name: tom_released\nversion: 2.0.0\n');
  _write('$repo/tom_released/release.md', '# Release notes\n');
  _write('$repo/tom_released/lib/tom_released.dart', _lines(5));

  // A publishable pub package: published when its repo is public.
  _write(
    '$repo/tom_pub/pubspec.yaml',
    'name: tom_pub\n'
        'version: 1.2.3\n'
        'description: A small published package.\n'
        'repository: https://github.com/example/demo\n',
  );
  _write(
    '$repo/tom_pub/LICENSE',
    'Redistribution and use in source and binary forms, with or without\n'
        'modification, are permitted ... Neither the name of the copyright\n'
        'holder ...\n',
  );
  _write('$repo/tom_pub/lib/tom_pub.dart', _lines(5));
  _write(
    '$repo/tom_pub/test/tom_pub_test.dart',
    "void main() {\n  test('a', () {});\n  test('b', () {});\n}\n",
  );

  // Real code, but publish_to: none — ranked by its lib/ size.
  _write('$repo/tom_internal/pubspec.yaml',
      'name: tom_internal\nversion: 0.1.0\npublish_to: none\n');
  _write('$repo/tom_internal/lib/tom_internal.dart', _lines(250));

  // A stub at or below the threshold.
  _write('$repo/tom_stub/pubspec.yaml', 'name: tom_stub\npublish_to: none\n');
  _write('$repo/tom_stub/lib/tom_stub.dart', _lines(10));

  // A TypeScript package: package.json + tsconfig.json, metrics from src/.
  _write(
    '$repo/tom_ts_ext/package.json',
    '{"name": "@example/ext", "version": "0.3.0", "license": "MIT"}',
  );
  _write('$repo/tom_ts_ext/tsconfig.json', '{}');
  _write('$repo/tom_ts_ext/src/extension.ts', _lines(250, ts: true));

  // Not a package: neither pubspec.yaml nor package.json + tsconfig.json.
  _write('$repo/notes/readme.md', '# Not a package\n');
}

/// [count] real source lines (Dart or TypeScript).
String _lines(int count, {bool ts = false}) => List.generate(
      count,
      (i) => ts ? 'export const v$i = $i;' : 'const v$i = $i;',
    ).join('\n');

void _write(String path, String content) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(content);
}
