// registerAppLicenses (docs/plans/m5-7/01-infra.md 4.6.7, 6.18; contract
// 7.4.5 v2.1 — CP5): the NoteSans OFL text from ink_engine's asset becomes a
// LicenseRegistry entry; a missing asset → no entry and one record, however
// often the license page collects. The registry is lazy: registering reads
// nothing.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:noteapp/src/app/licenses.dart';
import 'package:noteapp/src/errors/app_error_log.dart';

const String _ofl =
    'Copyright 2014-2021 Adobe (http://www.adobe.com/)\n\n'
    'This Font Software is licensed under the SIL Open Font License, '
    'Version 1.1.';

/// Serves [assets] by key; counts loads; a missing key throws like the
/// platform bundle (FlutterError 'Unable to load asset'). No cache — every
/// collection reaches [load].
final class _FakeBundle extends AssetBundle {
  _FakeBundle(this.assets);

  final Map<String, String> assets;
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    loaded.add(key);
    final text = assets[key];
    if (text == null) throw FlutterError('Unable to load asset: "$key".');
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }
}

Future<List<LicenseEntry>> _entries() => LicenseRegistry.licenses.toList();

Iterable<LicenseEntry> _noteSans(List<LicenseEntry> entries) =>
    entries.where((e) => e.packages.contains(noteSansLicenseName));

String _text(LicenseEntry entry) =>
    entry.paragraphs.map((p) => p.text).join('\n');

void main() {
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test('the asset path is ink_engine OFL.txt (CP5)', () {
    expect(noteSansLicenseAsset, 'packages/ink_engine/assets/fonts/OFL.txt');
    expect(noteSansLicenseName, 'NoteSans (Noto Sans KR subset)');
  });

  test('asset there → one NoteSans entry with its text, no record', () async {
    final bundle = _FakeBundle({noteSansLicenseAsset: _ofl});
    final log = AppErrorLog();
    registerAppLicenses(bundle: bundle, errorLog: log);
    // Lazy: nothing is read until the entries are collected.
    expect(bundle.loaded, isEmpty);

    final entries = _noteSans(await _entries()).toList();
    expect(entries, hasLength(1));
    expect(entries.single.packages, [noteSansLicenseName]);
    expect(_text(entries.single), contains('SIL Open Font License'));
    expect(_text(entries.single), contains('Adobe'));
    expect(bundle.loaded, [noteSansLicenseAsset]);
    expect(log.totalCount, 0);
  });

  test('asset missing → no entry, logged once over two collections', () async {
    final bundle = _FakeBundle(const {});
    final log = AppErrorLog();
    registerAppLicenses(bundle: bundle, errorLog: log);

    expect(_noteSans(await _entries()), isEmpty);
    expect(_noteSans(await _entries()), isEmpty);
    expect(log.totalCount, 1);
    final record = log.records.single;
    expect(record.source, AppErrorSource.manual);
    expect(record.summary, contains('NoteSans'));
    expect(record.details, contains(noteSansLicenseAsset));
    // Each collection tried again (the page may open after the asset loads).
    expect(bundle.loaded, hasLength(2));
  });

  test('asset missing without an error log → no entry, no throw', () async {
    registerAppLicenses(bundle: _FakeBundle(const {}));
    expect(_noteSans(await _entries()), isEmpty);
  });

  test('the app bundle has the asset (ink_engine declares it — R-5)', () async {
    final log = AppErrorLog();
    registerAppLicenses(errorLog: log);
    final entries = _noteSans(await _entries()).toList();
    expect(entries, hasLength(1));
    expect(_text(entries.single), contains('SIL Open Font License'));
    expect(log.totalCount, 0);
  });

  testWidgets('the license page lists the entry', (tester) async {
    registerAppLicenses(bundle: _FakeBundle({noteSansLicenseAsset: _ofl}));
    await tester.pumpWidget(const MaterialApp(home: LicensePage()));
    // The page folds LicenseRegistry.licenses (microtasks) behind a
    // progress indicator; a few frames show the package list.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(noteSansLicenseName), findsOneWidget);
  });

  test(
    'the on-device math model: its MIT license as an entry (apps)',
    () async {
      registerAppLicenses(bundle: _FakeBundle({noteSansLicenseAsset: _ofl}));
      final entries = (await _entries())
          .where((e) => e.packages.contains(mathModelLicenseName))
          .toList();
      expect(entries, hasLength(1));
      final text = _text(entries.single);
      expect(text, contains('MIT License'));
      expect(text, contains('BreezeDeus'));
      expect(text, contains('1cef9f0bdcd6a4c63df7de1311fb0894593340cc'));
      expect(text, contains('int8'));
      expect(text, contains('Copyright (c) 2022 BreezeDeus'));
    },
  );

  test('ONNX Runtime (the native library under the math engine): its MIT '
      'license and a link to its third-party notices (apps)', () async {
    registerAppLicenses(bundle: _FakeBundle({noteSansLicenseAsset: _ofl}));
    final entries = (await _entries())
        .where((e) => e.packages.contains(onnxRuntimeLicenseName))
        .toList();
    expect(entries, hasLength(1));
    final text = _text(entries.single);
    expect(text, contains('Copyright (c) Microsoft Corporation'));
    expect(text, contains('MIT License'));
    expect(text, contains('v1.28.0/ThirdPartyNotices.txt'));
  });
}
