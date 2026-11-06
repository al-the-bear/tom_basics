/// The licence audit names every package it cannot admit, and why; the
/// walk follows `dependencies:` and leaves dev dependencies out.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tom_test_support/licence_audit.dart';
import 'package:tom_test_support/roots.dart';

const _mit = 'Permission is hereby granted, free of charge, to any person';
const _bsd3 =
    'Redistribution and use in source and binary forms, with or '
    'without modification ... Neither the name of the copyright holder';
const _gpl =
    'GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n'
    'GNU General Public License';
const _lgpl =
    'GNU LESSER GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n'
    'GNU Lesser General Public License';
const _mpl = 'Mozilla Public License Version 2.0';

void main() {
  late Directory scratch;
  setUp(() {
    scratch = tomWorkspaceZtmp().createTempSync('tsup_licence_');
  });
  tearDown(() => scratch.deleteSync(recursive: true));

  Directory make(String name, {String? licence, String pubspec = ''}) {
    final dir = Directory(p.join(scratch.path, name))..createSync();
    if (licence != null) {
      File(p.join(dir.path, 'LICENSE')).writeAsStringSync(licence);
    }
    File(
      p.join(dir.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: $name\n$pubspec');
    return dir;
  }

  group('TSUP-LIC the licence audit', () {
    test('TSUP-LIC-1: each family is recognised by its operative text', () {
      expect(tomClassifyLicence(_mit), TomLicence.mit);
      expect(tomClassifyLicence(_bsd3), TomLicence.bsd3);
      expect(
        tomClassifyLicence('Redistribution and use in source and binary forms'),
        TomLicence.bsd2,
      );
      expect(
        tomClassifyLicence('Apache License\n  Version 2.0'),
        TomLicence.apache2,
      );
      expect(tomClassifyLicence(_mpl), TomLicence.mpl2);
      // MPL-2.0 names the GNU licences as its Secondary Licenses.
      expect(
        tomClassifyLicence(
          '$_mpl\n1.12. "Secondary License" means either '
          'the GNU General Public License, Version 2.0, the GNU Lesser '
          'General Public License',
        ),
        TomLicence.mpl2,
      );
      expect(tomClassifyLicence(_gpl), isNull);
      expect(tomClassifyLicence(_lgpl), isNull);
      expect(tomClassifyLicence('All rights reserved.'), isNull);
      // A GPL text that quotes a permissive sentence is still the GPL.
      expect(tomClassifyLicence('$_lgpl\n$_mit'), isNull);
    });

    test('TSUP-LIC-2: a package with no LICENSE, a GPL, an LGPL and an MPL '
        'one each fail by name when only the permissive families are '
        'admitted', () {
      final linked = <TomLinkedPackage>[
        for (final (name, licence) in [
          ('granted', _mit),
          ('bare', null),
          ('strong', _gpl),
          ('lesser', _lgpl),
          ('weak', _mpl),
        ])
          (name: name, root: make(name, licence: licence), sdk: false),
      ];
      final audit = tomAuditLicences(linked, admitted: TomLicence.permissive);
      expect(audit.granted, {'granted': TomLicence.mit});
      expect(audit.problems, hasLength(4));
      expect(
        audit.problems[0],
        allOf(contains('bare'), contains('carries no LICENSE')),
      );
      expect(audit.problems[1], contains('strong'));
      expect(audit.problems[2], contains('lesser'));
      expect(audit.problems[3], allOf(contains('weak'), contains('mpl2')));
    });

    test('TSUP-LIC-3: MPL-2.0 passes where it is admitted; the LGPL never', () {
      final linked = <TomLinkedPackage>[
        (name: 'weak', root: make('weak', licence: _mpl), sdk: false),
        (name: 'lesser', root: make('lesser', licence: _lgpl), sdk: false),
      ];
      final audit = tomAuditLicences(
        linked,
        admitted: {...TomLicence.permissive, TomLicence.mpl2},
      );
      expect(audit.granted, {'weak': TomLicence.mpl2});
      expect(audit.problems.single, contains('lesser'));
    });

    test('TSUP-LIC-4: the walk follows dependencies, not dev dependencies, and '
        'judges an SDK package by the flutter package\'s licence', () {
      final packages = {
        'app': make(
          'app',
          licence: _bsd3,
          pubspec: '''
dependencies:
  lib_a: any
  flutter:
    sdk: flutter
  flutter_web_plugins:
    sdk: flutter
dev_dependencies:
  tool: any
''',
        ),
        'lib_a': make(
          'lib_a',
          licence: _mit,
          pubspec: '''
dependencies:
  lib_b: any
''',
        ),
        'lib_b': make('lib_b', licence: _mit),
        'flutter': make('flutter', licence: _bsd3),
        'flutter_web_plugins': make('flutter_web_plugins'),
        'tool': make('tool', licence: _gpl),
      };
      final linked = tomLinkedPackages('app', packages);
      expect(linked.map((e) => e.name), [
        'app',
        'lib_a',
        'lib_b',
        'flutter',
        'flutter_web_plugins',
      ]);
      final audit = tomAuditLicences(linked, admitted: TomLicence.permissive);
      expect(audit.problems, isEmpty, reason: audit.problems.join('\n'));
      expect(audit.granted['flutter_web_plugins'], TomLicence.bsd3);
    });

    test('TSUP-LIC-5: a dependency the configuration does not resolve is an '
        'error naming it', () {
      final packages = {
        'app': make('app', pubspec: 'dependencies:\n  missing: any\n'),
      };
      expect(
        () => tomLinkedPackages('app', packages),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('missing'),
          ),
        ),
      );
    });
  });
}
