// Import boundaries of media_io lib/ (m5-7/06-pdf 3.5 I-2..I-8, 6.18; contract 7.4.1) and the
// v2.1 review M-1 rule (no MockPlatformInterfaceMixin, no package:plugin_platform_interface/ in
// lib/). VM only: reads the package sources with dart:io.
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

/// Source text without comments (rules about code, not about the words in doc comments).
String _code(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    })
    .join('\n');

void main() {
  test('the sources were found', () {
    expect(
      _sources.keys,
      containsAll(['media_io.dart', 'testing.dart', 'src/init.dart']),
    );
    expect(_directives.length, greaterThan(15));
  });

  test('dart:io only in *_native.dart; no dart:html, dart:js, dart:js_util, package:js', () {
    const banned = {'dart:html', 'dart:js', 'dart:js_util'};
    expect(
      _offending(
        (d, uri) =>
            banned.contains(uri) ||
            uri.startsWith('package:js/') ||
            (uri == 'dart:io' && !d.file.endsWith('_native.dart')),
      ),
      isEmpty,
    );
  });

  test(
    'dart:js_interop, package:web and the web plugins only in *_browser.dart',
    () {
      bool webOnly(String uri) =>
          uri.startsWith('dart:js_interop') ||
          uri.startsWith('package:web/') ||
          uri.startsWith('package:flutter_web_plugins/') ||
          uri.startsWith('package:record_web/') ||
          uri.startsWith('package:just_audio_web/');
      expect(
        _offending(
          (d, uri) => webOnly(uri) && !d.file.endsWith('_browser.dart'),
        ),
        isEmpty,
      );
    },
  );

  test('native-only plugins only in *_native.dart (I-2, I-3)', () {
    bool nativeOnly(String uri) =>
        uri.startsWith('package:path_provider/') ||
        uri.startsWith('package:flutter_foreground_task/') ||
        uri.startsWith('package:record/') ||
        uri.startsWith('package:audio_session/');
    expect(
      _offending(
        (d, uri) => nativeOnly(uri) && !d.file.endsWith('_native.dart'),
      ),
      isEmpty,
    );
  });

  test('package:record / audio_session only in their native files (I-3)', () {
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:record/') &&
            d.file != 'src/record/recorder_engine_native.dart',
      ),
      isEmpty,
    );
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:audio_session/') &&
            d.file != 'src/record/audio_session_native.dart',
      ),
      isEmpty,
    );
  });

  test('package:just_audio / image_picker only in their port files (I-4)', () {
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:just_audio/') &&
            !{
              'src/playback/player_port.dart',
              'src/playback/duration_probe.dart',
            }.contains(d.file),
      ),
      isEmpty,
    );
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:image_picker/') &&
            d.file != 'src/image/image_picker_port.dart',
      ),
      isEmpty,
    );
  });

  test(
    'platform interface packages only in the test helpers (v2.1, CP-PDF-9)',
    () {
      bool interface(String uri) =>
          uri.startsWith('package:record_platform_interface/') ||
          uri.startsWith('package:just_audio_platform_interface/') ||
          uri.startsWith('package:image_picker_platform_interface/');
      expect(
        _offending(
          (d, uri) =>
              interface(uri) &&
              !{
                'testing.dart',
                'src/testing/fake_platforms.dart',
              }.contains(d.file),
        ),
        isEmpty,
      );
    },
  );

  test('no MockPlatformInterfaceMixin, no package:plugin_platform_interface/ (review M-1)', () {
    expect(
      _offending(
        (d, uri) => uri.startsWith('package:plugin_platform_interface/'),
      ),
      isEmpty,
    );
    expect([
      for (final e in _sources.entries)
        if (_code(e.value).contains('MockPlatformInterfaceMixin')) e.key,
    ], isEmpty);
  });

  test('platform files are reached only through conditional exports', () {
    bool isPlatformFile(String uri) =>
        uri.endsWith('_browser.dart') || uri.endsWith('_native.dart');
    // (T33) a platform file may import a platform file of the same kind (the native engine
    // uses the native audio session and foreground service): it is itself reached only
    // through a conditional export, so no web-safe file gets the platform code.
    bool sameKind(_Directive d, String uri) =>
        (d.file.endsWith('_native.dart') && uri.endsWith('_native.dart')) ||
        (d.file.endsWith('_browser.dart') && uri.endsWith('_browser.dart'));
    expect(
      _offending(
        (d, uri) =>
            isPlatformFile(uri) &&
            !(d.isExport && d.isConditional) &&
            !(!d.isExport && sameKind(d, uri)),
      ),
      isEmpty,
    );
    // Conditional directives live only in *_factory.dart files.
    expect([
      for (final d in _directives)
        if (d.isConditional && !d.file.endsWith('_factory.dart')) d.file,
    ], isEmpty);
  });

  test('no dart:io Platform, no color literal; Material only through material_ui (I-5–I-7)', () {
    final offenders = <String>[];
    for (final e in _sources.entries) {
      final code = _code(e.value);
      if (RegExp(r'\bPlatform\.is').hasMatch(code)) {
        offenders.add('${e.key}: Platform.is');
      }
      if (code.contains('Color(0x')) offenders.add('${e.key}: Color(0x');
    }
    expect(offenders, isEmpty);
    expect(
      _offending(
        (d, uri) =>
            uri == 'package:flutter/material.dart' ||
            uri == 'package:flutter/cupertino.dart',
      ),
      isEmpty,
    );
    expect(
      _offending(
        (d, uri) =>
            uri.startsWith('package:flutter_riverpod/') &&
            uri != 'package:flutter_riverpod/flutter_riverpod.dart' &&
            uri != 'package:flutter_riverpod/misc.dart',
      ),
      isEmpty,
    );
  });

  test("package:note_core always 'as core' (I-8)", () {
    expect([
      for (final d in _directives)
        for (final uri in d.uris)
          if (uri.startsWith('package:note_core/') && d.prefix != 'core')
            '${d.file}: $uri',
    ], isEmpty);
  });

  test('media_io imports no feature package and no pdf_io (I-1, contract 7.1 rule 4)', () {
    const others = [
      'package:pdf_io/',
      'package:ink_engine/',
      'package:feature_editor/',
      'package:feature_library/',
      'package:sync_engine/',
      'package:ink_recognition/',
      'package:pencil_bridge/',
    ];
    expect(_offending((d, uri) => others.any(uri.startsWith)), isEmpty);
  });
}
