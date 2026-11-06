// lib/ must stay web-safe and Material-free (contract 7.4.3, 03-ink 3장, 8 T00):
// no dart:io / dart:ffi / dart:html / dart:js / dart:js_util / package:js, no SDK
// Material / Cupertino (lib and test), no flutter_riverpod (INK uses package:riverpod
// only, 7.4.4), and dart:js_interop only in *_browser.dart files reached through a
// conditional import. (v2.0, m5-7/03-ink 3.1 / 8.1 T25) No `Platform` identifier
// (kIsWeb + defaultTargetPlatform only); flutter_math_fork only under lib/src/math/;
// INK never imports provider or flutter_svg, and vector_graphics only in the
// off-screen math host (T36).
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _libForbidden = [
  'dart:io',
  'dart:ffi',
  'dart:html',
  'dart:js',
  'dart:js_util',
  'package:js/',
  'package:flutter_riverpod/',
];

const List<String> _everywhereForbidden = [
  'package:flutter/material.dart',
  'package:flutter/cupertino.dart',
];

const List<String> _webOnly = ['dart:js_interop', 'package:web/'];

/// URIs of every import / export directive in [source], conditional ones included.
List<String> _directiveUris(String source) {
  final uris = <String>[];
  final directive = RegExp(r'^(?:import|export)\s[^;]*;', multiLine: true);
  // prefer_single_quotes: directives use single quotes only.
  final quoted = RegExp(r"'([^']+)'");
  for (final d in directive.allMatches(source)) {
    for (final q in quoted.allMatches(d.group(0)!)) {
      uris.add(q.group(1)!);
    }
  }
  return uris;
}

bool _matches(String uri, String banned) =>
    banned.endsWith('/') ? uri.startsWith(banned) : uri == banned;

Iterable<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

void main() {
  test('lib/ has no forbidden or platform-only imports', () {
    final problems = <String>[];
    for (final file in _dartFiles('lib')) {
      final uris = _directiveUris(file.readAsStringSync());
      for (final uri in uris) {
        for (final banned in [..._libForbidden, ..._everywhereForbidden]) {
          if (_matches(uri, banned)) problems.add('${file.path}: $uri');
        }
        for (final web in _webOnly) {
          if (_matches(uri, web) && !file.path.endsWith('_browser.dart')) {
            problems.add('${file.path}: $uri outside a *_browser.dart file');
          }
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('test/ does not use SDK Material / Cupertino', () {
    final problems = <String>[
      for (final file in _dartFiles('test'))
        for (final uri in _directiveUris(file.readAsStringSync()))
          for (final banned in _everywhereForbidden)
            if (_matches(uri, banned)) '${file.path}: $uri',
    ];
    expect(problems, isEmpty);
  });

  test('(v2.0) no Platform identifier in lib/', () {
    final platform = RegExp(r'(?<![\w.])Platform\.');
    final problems = <String>[
      for (final file in _dartFiles('lib'))
        if (platform.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(problems, isEmpty);
  });

  test('(v2.0) flutter_math_fork only under lib/src/math/; no provider / '
      'flutter_svg; vector_graphics only in the off-screen host', () {
    final problems = <String>[];
    for (final file in _dartFiles('lib')) {
      final path = file.path.replaceAll(r'\', '/');
      for (final uri in _directiveUris(file.readAsStringSync())) {
        if (uri.startsWith('package:flutter_math_fork/') &&
            !path.startsWith('lib/src/math/')) {
          problems.add('$path: $uri');
        }
        if (uri.startsWith('package:provider/') ||
            uri.startsWith('package:flutter_svg/')) {
          problems.add('$path: $uri');
        }
        if (uri.startsWith('package:vector_graphics') &&
            path != 'lib/src/math/offscreen_host.dart') {
          problems.add('$path: $uri');
        }
      }
    }
    expect(problems, isEmpty);
  });

  test('the browser clock is reached only through the conditional import', () {
    final clock = File('lib/src/diagnostics/ink_clock.dart').readAsStringSync();
    expect(
      clock,
      contains("if (dart.library.js_interop) 'ink_clock_browser.dart'"),
    );
    final importers = [
      for (final file in _dartFiles('lib'))
        if (_directiveUris(file.readAsStringSync())
            .any((u) => u.endsWith('ink_clock_browser.dart')))
          file.path,
    ];
    expect(importers, hasLength(1));
  });
}
