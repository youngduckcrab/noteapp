// Directive scanner used by R2 / R7 (and R4–R6 from I1).

import 'package:test/test.dart';

import '../src/dart_imports.dart';

void main() {
  test('single-line imports and exports with prefixes and combinators', () {
    final directives = scanDirectives('''
library;

import 'dart:async';
import "package:a/a.dart" as a show A, B;
export 'src/x.dart' hide Y;
import 'package:b/b.dart' deferred as b;
''');
    expect(directives.map((d) => (d.kind, d.uri, d.line)), [
      (DirectiveKind.import, 'dart:async', 3),
      (DirectiveKind.import, 'package:a/a.dart', 4),
      (DirectiveKind.export, 'src/x.dart', 5),
      (DirectiveKind.import, 'package:b/b.dart', 6),
    ]);
    expect(directives.every((d) => !d.isConditional), isTrue);
  });

  test('a directive spread over several lines', () {
    final directives = scanDirectives('''
import
    'package:a/a.dart'
    show
        A;
''');
    expect(directives.single.uri, 'package:a/a.dart');
    expect(directives.single.line, 1);
  });

  test('conditional import with two clauses', () {
    final d = scanDirectives('''
import 'x_stub.dart'
    if (dart.library.js_interop) 'x_browser.dart'
    if (dart.library.ffi) 'x_native.dart';
''').single;
    expect(d.uri, 'x_stub.dart');
    expect(d.conditionalUris.map((c) => (c.condition, c.uri)), [
      ('dart.library.js_interop', 'x_browser.dart'),
      ('dart.library.ffi', 'x_native.dart'),
    ]);
    expect(d.allUris, ['x_stub.dart', 'x_browser.dart', 'x_native.dart']);
  });

  test('conditional export with an == test', () {
    final d = scanDirectives(
      "export 'a.dart' if (dart.library.io == 'true') 'b.dart';",
    ).single;
    expect(d.kind, DirectiveKind.export);
    expect(d.conditionalUris.single.condition, "dart.library.io=='true'");
    expect(d.conditionalUris.single.uri, 'b.dart');
  });

  test('commented-out directives are ignored', () {
    final directives = scanDirectives('''
// import 'package:flutter/material.dart';
/// import 'doc.dart';
/*
import 'package:flutter/cupertino.dart';
*/
import 'kept.dart';
''');
    expect(directives.map((d) => d.uri), ['kept.dart']);
    expect(directives.single.line, 6);
  });

  test('import-like text in strings and code is not a directive', () {
    final directives = scanDirectives(r'''
import 'real.dart';
const s = "import 'fake.dart';";
const t = """
export 'fake2.dart';
""";
void f() {
  final import = 1;
  print(import);
  foo.import;
  final u = 'a ${"import 'x.dart'"} b';
}
''');
    expect(directives.map((d) => d.uri), ['real.dart']);
  });

  test('raw strings and escaped quotes do not confuse the scanner', () {
    final directives = scanDirectives(r'''
const a = r'C:\path\';
const b = 'it\'s';
import 'after.dart';
''');
    expect(directives.map((d) => d.uri), ['after.dart']);
  });
}
