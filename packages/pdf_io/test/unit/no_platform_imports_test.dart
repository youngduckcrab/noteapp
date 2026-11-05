// Platform import rules of lib/ (06-pdf 3 원칙, 6.15, contract 7.4.3) and the color rule
// (contract 7.4.11 v1.3: the search highlight lives in PdfTuning only, no color literal in
// painters / widgets). VM only: reads the package sources with dart:io.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final class _Directive {
  _Directive(this.file, this.text);
  final String file; // relative to lib/, '/' separators
  final String text;

  bool get isExport => text.startsWith('export');
  bool get isConditional => text.contains('if (dart.library.');
  List<String> get uris => [
    for (final m in RegExp(r"'([^']+)'").allMatches(text)) m.group(1)!,
  ];
  String? get prefix => RegExp(r'\sas\s+(\w+)').firstMatch(text)?.group(1);
}

final Map<String, String> _sources = {
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart'))
      f.path.replaceAll(r'\', '/').substring('lib/'.length): f
          .readAsStringSync(),
};

final List<_Directive> _directives = [
  for (final e in _sources.entries)
    for (final m in RegExp(
      r'^(?:import|export)\s[^;]*;',
      multiLine: true,
    ).allMatches(e.value))
      _Directive(e.key, m.group(0)!),
];

List<String> _offending(bool Function(_Directive d, String uri) bad) => [
  for (final d in _directives)
    for (final uri in d.uris)
      if (bad(d, uri)) '${d.file}: $uri',
];

void main() {
  test('the sources were found', () {
    expect(_sources.keys, contains('pdf_io.dart'));
    expect(_sources.keys, contains('src/errors.dart'));
    expect(_directives.length, greaterThan(50));
  });

  test(
    'no dart:io, dart:html, dart:js, dart:js_util, package:js anywhere in lib/',
    () {
      const banned = {'dart:io', 'dart:html', 'dart:js', 'dart:js_util'};
      expect(
        _offending(
          (d, uri) => banned.contains(uri) || uri.startsWith('package:js/'),
        ),
        isEmpty,
      );
    },
  );

  test('dart:ffi, package:ffi, package:pdfium_dart only in compose_backend_native.dart', () {
    expect(
      _offending(
        (d, uri) =>
            (uri == 'dart:ffi' ||
                uri.startsWith('package:ffi/') ||
                uri.startsWith('package:pdfium_dart/')) &&
            d.file != 'src/compose/compose_backend_native.dart',
      ),
      isEmpty,
    );
  });

  test('dart:js_interop and package:web only in *_browser.dart', () {
    expect(
      _offending(
        (d, uri) =>
            (uri.startsWith('dart:js_interop') ||
                uri.startsWith('package:web/')) &&
            !d.file.endsWith('_browser.dart'),
      ),
      isEmpty,
    );
  });

  test('platform files are reached only through conditional exports', () {
    bool isPlatformFile(String uri) =>
        uri.endsWith('_browser.dart') || uri.endsWith('_native.dart');
    expect(
      _offending(
        (d, uri) => isPlatformFile(uri) && !(d.isExport && d.isConditional),
      ),
      isEmpty,
    );
    // Conditional directives live only in the two factory files.
    expect(
      {
        for (final d in _directives)
          if (d.isConditional) d.file,
      },
      {
        'src/compose/compose_backend_factory.dart',
        'src/output/output_sink_factory.dart',
      },
    );
  });

  test("package:pdfrx only in its three files, always 'as rx'", () {
    const allowed = {
      'src/engine/pdfrx_engine.dart',
      'src/init.dart',
      'src/compose/compose_backend_native.dart',
    };
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:pdfrx/') &&
            (!allowed.contains(d.file) || d.prefix != 'rx'),
      ),
      isEmpty,
    );
  });

  test(
    "package:ink_engine only in ink_adapter/ and init.dart, always 'as ink'",
    () {
      const allowed = {
        'src/init.dart',
        'src/ink_adapter/ink_background_builder.dart',
        'src/ink_adapter/ink_vectorizer.dart',
        'src/ink_adapter/template_underlay.dart',
      };
      expect(
        _offending(
          (d, uri) =>
              uri.startsWith('package:ink_engine/') &&
              (!allowed.contains(d.file) || d.prefix != 'ink'),
        ),
        isEmpty,
      );
    },
  );

  test("package:note_core is always imported 'as core'", () {
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:note_core/') &&
            !d.isExport &&
            d.prefix != 'core',
      ),
      isEmpty,
    );
  });

  test('Material only through package:material_ui', () {
    expect(
      _offending((d, uri) => uri == 'package:flutter/material.dart'),
      isEmpty,
    );
  });

  test(
    'no color literal in render/, ui/ and ink_adapter/ (PdfTuning only)',
    () {
      final literal = RegExp(
        r'Color\(\s*0x|Color\.fromARGB\(|Color\.fromRGBO\(|\bColors\.',
      );
      final offending = [
        for (final e in _sources.entries)
          if (e.key.startsWith('src/render/') ||
              e.key.startsWith('src/ui/') ||
              e.key.startsWith('src/ink_adapter/'))
            for (final m in literal.allMatches(e.value))
              '${e.key}: ${m.group(0)}',
      ];
      expect(offending, isEmpty);
      // The highlight colors exist, in PdfTuning.
      expect(_sources['src/tuning.dart'], contains('searchHighlightArgb'));
    },
  );
}
