// lib/ boundary rules of sync_engine (foundation step B7 completion
// condition, contract 00-overview 7.6; 07-sync 3.1 '라이브러리 경계 규칙' and
// 8 T1):
// - lib/ top level holds exactly the four entry points (contract 7.1);
// - no dart:io / dart:ffi / dart:html / dart:js / dart:js_util / package:js
//   anywhere in lib/ (contract 7.4.3);
// - sync_engine.dart and testing.dart, with everything they reach, never
//   import Flutter, Firebase, connectivity_plus or package:web (contract 7.1);
// - no package:fake_async / test / test_api / matcher / flutter_test in lib/
//   (contract 7.2.20 v1.1);
// - package:web (and dart:js_interop) only in *_browser.dart files, and
//   platform files only through the contract's conditional import / export
//   form (contract 7.4.3);
// - no test-only entry point (CORE testing*.dart, own testing.dart) and no
//   other package's src/ in lib/ (contract 7.1 rule 2).
//
// The checker (support/lib_boundary.dart) reads source text. The second group
// feeds it synthetic files, so every rule is shown to fire.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/lib_boundary.dart';

/// Every `.dart` file under `lib/`, keyed by its path relative to `lib/`.
Map<String, String> _readLib() {
  final lib = Directory('lib');
  return {
    for (final entity in lib.listSync(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('.dart'))
        entity.path
            .substring(lib.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'): entity
            .readAsStringSync(),
  };
}

/// The minimal valid lib/: the four entry points, empty.
Map<String, String> _frame([Map<String, String> extra = const {}]) => {
  for (final entry in kEntryPoints) entry: 'library;\n',
  ...extra,
};

Set<BoundaryRule> _rules(Map<String, String> libFiles) => {
  for (final v in checkLibBoundary(libFiles)) v.rule,
};

void main() {
  group('lib/ of sync_engine', () {
    late Map<String, String> libFiles;
    late List<BoundaryViolation> violations;

    setUpAll(() {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('name: sync_engine'),
        reason: 'run from packages/sync_engine (flutter test / ws test)',
      );
      libFiles = _readLib();
      violations = checkLibBoundary(libFiles);
    });

    List<BoundaryViolation> of(BoundaryRule rule) => [
      for (final v in violations)
        if (v.rule == rule) v,
    ];

    test('has exactly the four entry points at the top of lib/', () {
      expect({
        for (final path in libFiles.keys)
          if (!path.contains('/')) path,
      }, kEntryPoints.toSet());
      expect(of(BoundaryRule.entryPoints), isEmpty);
    });

    test('never imports dart:io, dart:ffi, dart:html, dart:js, '
        'dart:js_util or package:js', () {
      expect(of(BoundaryRule.forbiddenImport), isEmpty);
    });

    test('sync_engine.dart and testing.dart stay pure Dart, transitively', () {
      for (final entry in kPureEntryPoints) {
        expect(reachableFiles(libFiles, entry), contains(entry));
      }
      expect(of(BoundaryRule.pureClosure), isEmpty);
    });

    test('never imports fake_async, test, test_api, matcher or '
        'flutter_test', () {
      expect(of(BoundaryRule.devOnlyImport), isEmpty);
    });

    test('uses package:web only in *_browser.dart files, loaded through '
        'conditional imports / exports', () {
      expect(of(BoundaryRule.webOnlyImport), isEmpty);
      expect(of(BoundaryRule.conditionalForm), isEmpty);
    });

    test('uses no test-only entry point and no other package src/', () {
      expect(of(BoundaryRule.testOnlyEntry), isEmpty);
      expect(of(BoundaryRule.otherPackageSrc), isEmpty);
    });

    test('every in-package URI resolves to a file under lib/', () {
      expect(of(BoundaryRule.unresolved), isEmpty);
    });

    test('breaks no rule at all', () {
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('the checker', () {
    test('accepts the empty frame', () {
      expect(checkLibBoundary(_frame()), isEmpty);
    });

    test('reads multi-line, conditional and commented directives', () {
      final directives = scanDirectives('''
// import 'dart:io';
/* export 'dart:html'; /* nested */ import 'dart:ffi'; */
@SomeAnnotation('x')
library;

import "package:meta/meta.dart"
    show immutable, internal;
import 'src/a.dart' as a hide B;
export 'src/mode_stub.dart'
    if (dart.library.js_interop) 'src/mode_browser.dart'
    if (dart.library.ffi) 'src/mode_native.dart';
import r'src/raw.dart';
part 'src/part.dart';
part of 'other.dart';

const String text = "import 'dart:io';";
final String multi = """
export 'dart:html';
""";
String interpolated(Object x) => '\${x.import} \$x';
''');
      expect(
        [for (final d in directives) d.kind],
        [
          DirectiveKind.import,
          DirectiveKind.import,
          DirectiveKind.export,
          DirectiveKind.import,
          DirectiveKind.part,
        ],
      );
      expect(
        [for (final d in directives) d.uri],
        [
          'package:meta/meta.dart',
          'src/a.dart',
          'src/mode_stub.dart',
          'src/raw.dart',
          'src/part.dart',
        ],
      );
      expect([for (final d in directives) d.line], [6, 8, 9, 12, 13]);
      final conditional = directives[2];
      expect(
        [for (final c in conditional.conditionals) (c.condition, c.uri)],
        [
          ('dart.library.js_interop', 'src/mode_browser.dart'),
          ('dart.library.ffi', 'src/mode_native.dart'),
        ],
      );
    });

    test('reports missing and extra top-level files', () {
      final files = _frame({'extra.dart': 'library;\n'})
        ..remove('platform.dart');
      final violations = checkLibBoundary(files);
      expect([
        for (final v in violations)
          if (v.rule == BoundaryRule.entryPoints) v.file,
      ], unorderedEquals(['platform.dart', 'extra.dart']));
    });

    test('reports dart:io and friends anywhere in lib/', () {
      for (final uri in [
        'dart:io',
        'dart:ffi',
        'dart:html',
        'dart:js',
        'dart:js_util',
        'package:js/js.dart',
      ]) {
        final files = _frame({
          'firebase.dart': "import 'src/x_stub.dart';\n",
          'src/x_stub.dart': "import '$uri';\n",
        });
        expect(_rules(files), {BoundaryRule.forbiddenImport}, reason: uri);
      }
    });

    test('does not mistake dart:js_interop for dart:js', () {
      final files = _frame({
        'firebase.dart':
            "export 'src/m_stub.dart' "
            "if (dart.library.js_interop) 'src/m_browser.dart';\n",
        'src/m_stub.dart': 'library;\n',
        'src/m_browser.dart':
            "import 'dart:js_interop';\nimport 'package:web/web.dart';\n",
      });
      expect(checkLibBoundary(files), isEmpty);
    });

    test('reports dev-only packages, testing.dart included', () {
      for (final uri in [
        'package:fake_async/fake_async.dart',
        'package:test/test.dart',
        'package:test_api/test_api.dart',
        'package:matcher/matcher.dart',
      ]) {
        final files = _frame({'testing.dart': "import '$uri';\n"});
        expect(_rules(files), {BoundaryRule.devOnlyImport}, reason: uri);
      }
      final flutterTest = _frame({
        'firebase.dart': "import 'package:flutter_test/flutter_test.dart';\n",
      });
      expect(_rules(flutterTest), {BoundaryRule.devOnlyImport});
    });

    test('reports Flutter / Firebase / web reached from a pure entry point, '
        'with the import chain', () {
      final files = _frame({
        'sync_engine.dart': "export 'src/a.dart';\n",
        'src/a.dart': "import 'b.dart';\n",
        'src/b.dart': "import 'package:flutter/foundation.dart';\n",
      });
      final violations = checkLibBoundary(files);
      expect([for (final v in violations) v.rule], [BoundaryRule.pureClosure]);
      expect(violations.single.file, 'src/b.dart');
      expect(violations.single.line, 1);
      expect(
        violations.single.message,
        contains('sync_engine.dart → src/a.dart → src/b.dart'),
      );

      for (final uri in [
        'dart:ui',
        'package:flutter_riverpod/flutter_riverpod.dart',
        'package:firebase_core/firebase_core.dart',
        'package:firebase_auth/firebase_auth.dart',
        'package:firebase_storage/firebase_storage.dart',
        'package:cloud_firestore/cloud_firestore.dart',
        'package:connectivity_plus/connectivity_plus.dart',
      ]) {
        final viaTesting = _frame({
          'testing.dart': "import 'src/testing/fake.dart';\n",
          'src/testing/fake.dart': "import '$uri';\n",
        });
        expect(_rules(viaTesting), {BoundaryRule.pureClosure}, reason: uri);
      }
    });

    test(
      'allows Flutter and Firebase behind firebase.dart / platform.dart',
      () {
        final files = _frame({
          'firebase.dart': "export 'src/firebase/bindings.dart';\n",
          'platform.dart':
              "import 'package:connectivity_plus/connectivity_plus.dart';\n",
          'src/firebase/bindings.dart':
              "import 'package:cloud_firestore/cloud_firestore.dart';\n"
              "import 'package:flutter/foundation.dart';\n",
        });
        expect(checkLibBoundary(files), isEmpty);
      },
    );

    test('follows conditional URIs into the pure closure', () {
      final files = _frame({
        'sync_engine.dart':
            "import 'src/m_stub.dart' "
            "if (dart.library.js_interop) 'src/m_browser.dart';\n",
        'src/m_stub.dart': 'library;\n',
        'src/m_browser.dart': "import 'package:web/web.dart';\n",
      });
      expect(_rules(files), {BoundaryRule.pureClosure});
    });

    test('reports package:web outside *_browser.dart files', () {
      for (final uri in [
        'package:web/web.dart',
        'dart:js_interop',
        'dart:js_interop_unsafe',
      ]) {
        final files = _frame({'firebase.dart': "import '$uri';\n"});
        expect(_rules(files), {BoundaryRule.webOnlyImport}, reason: uri);
      }
    });

    test('reports platform files outside the conditional form', () {
      final unconditional = _frame({
        'firebase.dart': "import 'src/m_browser.dart';\n",
        'src/m_browser.dart': 'library;\n',
      });
      expect(_rules(unconditional), {BoundaryRule.conditionalForm});

      final wrongCondition = _frame({
        'firebase.dart':
            "import 'src/m_stub.dart' "
            "if (dart.library.html) 'src/m_browser.dart';\n",
        'src/m_stub.dart': 'library;\n',
        'src/m_browser.dart': 'library;\n',
      });
      expect(_rules(wrongCondition), {BoundaryRule.conditionalForm});

      final wrongSuffix = _frame({
        'firebase.dart':
            "import 'src/m_stub.dart' "
            "if (dart.library.js_interop) 'src/m_web.dart';\n",
        'src/m_stub.dart': 'library;\n',
        'src/m_web.dart': 'library;\n',
      });
      expect(_rules(wrongSuffix), {BoundaryRule.conditionalForm});

      final native = _frame({
        'platform.dart':
            "import 'src/m_stub.dart' "
            "if (dart.library.ffi) 'src/m_native.dart';\n",
        'src/m_stub.dart': 'library;\n',
        'src/m_native.dart': 'library;\n',
      });
      expect(checkLibBoundary(native), isEmpty);
    });

    test('reports test-only entry points and other packages src/', () {
      for (final uri in [
        'package:note_core/testing.dart',
        'package:note_core/testing_vm.dart',
        'package:sync_engine/testing.dart',
      ]) {
        final files = _frame({'src/engine.dart': "import '$uri';\n"});
        expect(_rules(files), {BoundaryRule.testOnlyEntry}, reason: uri);
      }
      final relative = _frame({
        'src/engine.dart': "import '../testing.dart';\n",
      });
      expect(_rules(relative), {BoundaryRule.testOnlyEntry});

      final fakeInProduction = _frame({
        'sync_engine.dart': "export 'src/testing/fake.dart';\n",
        'src/testing/fake.dart': 'library;\n',
      });
      expect(_rules(fakeInProduction), {BoundaryRule.testOnlyEntry});

      final otherSrc = _frame({
        'src/engine.dart': "import 'package:note_core/src/x.dart';\n",
      });
      expect(_rules(otherSrc), {BoundaryRule.otherPackageSrc});

      final ownSrc = _frame({
        'sync_engine.dart': "export 'package:sync_engine/src/engine.dart';\n",
        'src/engine.dart': "import 'package:note_core/note_core.dart';\n",
      });
      expect(checkLibBoundary(ownSrc), isEmpty);
    });

    test('reports in-package URIs that do not resolve', () {
      final files = _frame({
        'sync_engine.dart':
            "export 'src/missing.dart';\nimport '../../test/x.dart';\n",
      });
      expect(
        [for (final v in checkLibBoundary(files)) (v.rule, v.line)],
        [(BoundaryRule.unresolved, 1), (BoundaryRule.unresolved, 2)],
      );
    });
  });
}
