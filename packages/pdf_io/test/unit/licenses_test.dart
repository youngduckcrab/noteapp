// PDFium license texts (06-pdf 6.16, 7.1, 8 T19, PDF-S7): licenses/ holds exactly the 7.1
// table (19 files + the archive LICENSE), byte for byte the pdfium-binaries copies
// (sha256), pubspec.yaml declares the folder as a Flutter asset, the registry table in
// lib/src/licenses.dart lists the same files, every file reads through pdfiumLicenses
// (freetype.txt is ISO-8859-1) — also from the real flutter test asset bundle — and
// THIRD_PARTY_NOTICES.md names every file. VM only: reads the package files with dart:io.
@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/src/licenses.dart';

/// 7.1: file → (sha256 of the archive copy, in web chromium/7811, in VM chromium/8125).
/// Shared files are copied from 7811 (the build the web app ships); VM-only ones from 8125.
const Map<String, (String, bool, bool)> _expected = {
  'LICENSE': (
    'ba26c1263131696b86c10496b5066b918a20b7161822a80c274d0080105f6c93',
    true,
    true,
  ),
  'pdfium.txt': (
    '961eacd9633fff6d051db7208b755e9210e30efac7adec3e6a6d52798f0ccf0e',
    true,
    true,
  ),
  'abseil.txt': (
    'c79a7fea0e3cac04cd43f20e7b648e5a0ff8fa5344e644b0ee09ca1162b62747',
    true,
    true,
  ),
  'agg23.txt': (
    'c110d3ea2ad77467ce0dcff7d3337e6c8be8049a5103f4b9bd5fd911a77972e5',
    true,
    true,
  ),
  'fast_float.txt': (
    'e562f3f974ced7e69dd1db77b820b36bcf8f30377f1aa105723fba449c53c4e6',
    true,
    true,
  ),
  'freetype.txt': (
    'f4b133e25df1f86ad3ffea453aa0e613f0474f34778dbbb3e437e7b2724937d8',
    true,
    true,
  ),
  'icu.txt': (
    'e55522d81edc687a341a4411e0776e54ca654e90147f354a90458aaced4116af',
    true,
    true,
  ),
  'lcms.txt': (
    '5132b7530ae5acab7058634da86470d3d38bb01d70c2b67ba10c96bc62ced1af',
    true,
    true,
  ),
  'libjpeg_turbo.ijg': (
    '75815e3bf6484201a3c3d17a1bbf10f2e8e3237f84df10a2357ea896db2a81d6',
    true,
    true,
  ),
  'libjpeg_turbo.md': (
    '96f5b328adbb78eeaaec6980d73fd558cb1e4d62560ed615646bc3cf5e532430',
    true,
    true,
  ),
  'libopenjpeg.txt': (
    'c5ab0890a737c2dfa7ba675036554f6d17741d98629b0c2a145354d00617e6b2',
    true,
    true,
  ),
  'libpng.txt': (
    'bdb0a645ea18c60507d0368379b1ac5474b92255fcc2d115e07486a7672ba526',
    true,
    true,
  ),
  'simdutf.txt': (
    'fc8dbc04e03ad4efc08a647ffe7f995b811a95bc04c0e85a56d5277c6593fa5f',
    true,
    true,
  ),
  'zlib.txt': (
    '33fd641c9f3b0e0be64bc78fea9e94807674cdd70c48477599226cb8956565fe',
    true,
    true,
  ),
  'libtiff.txt': (
    '92b72ba97e6c2749c2a94bc0ef646b47080217f1e772a482b33cf5a5f98a6506',
    true,
    false,
  ),
  'dragonbox-Apache2-LLVM.txt': (
    '9e45e856bedccee9f67254082ca11851d954de2fed7448c4bed19ad9aab99a91',
    false,
    true,
  ),
  'dragonbox-Boost.txt': (
    'c9bff75738922193e67fa726fa225535870d2aa1059f91452c411736284ad566',
    false,
    true,
  ),
  'harfbuzz.txt': (
    'ba8f810f2455c2f08e2d56bb49b72f37fcf68f1f4fade38977cfd7372050ad64',
    false,
    true,
  ),
  'highway.txt': (
    'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4',
    false,
    true,
  ),
  'llvm-libc.txt': (
    'ebcd9bbf783a73d05c53ba4d586b8d5813dcdf3bbec50265860ccc885e606f47',
    false,
    true,
  ),
};

/// Package root (flutter test runs in the package; ws may run from the workspace root).
Directory _packageRoot() {
  for (final candidate in [
    Directory.current,
    Directory('${Directory.current.path}/packages/pdf_io'),
  ]) {
    if (File('${candidate.path}/lib/src/licenses.dart').existsSync()) {
      return candidate;
    }
  }
  throw StateError('pdf_io package root not found from ${Directory.current}');
}

/// Serves `packages/pdf_io/licenses/<file>` from the package's licenses/ folder — what the
/// app's rootBundle serves once pubspec.yaml declares the folder.
final class _PackageLicenseBundle extends CachingAssetBundle {
  _PackageLicenseBundle(this.dir);
  final Directory dir;
  final List<String> loaded = [];

  @override
  Future<ByteData> load(String key) async {
    if (!key.startsWith(pdfiumLicenseAssetDir)) {
      throw FlutterError('not a license asset: $key');
    }
    final file = File(
      '${dir.path}/${key.substring(pdfiumLicenseAssetDir.length)}',
    );
    loaded.add(key);
    return ByteData.sublistView(await file.readAsBytes());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final root = _packageRoot();
  final licenses = Directory('${root.path}/licenses');

  test('licenses/ holds exactly the 7.1 table: 19 files + LICENSE', () {
    final names = [
      for (final entity in licenses.listSync())
        entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
    ]..sort();
    expect(names, (_expected.keys.toList()..sort()));
    expect(names, hasLength(20));
    // Web 7811: 14 files of licenses/ + LICENSE; VM 8125: 18 + LICENSE.
    expect(_expected.values.where((e) => e.$2), hasLength(15));
    expect(_expected.values.where((e) => e.$3), hasLength(19));
    for (final entity in licenses.listSync()) {
      expect(entity, isA<File>(), reason: '${entity.path} is not a file');
    }
  });

  test('every file is byte for byte the archive copy (sha256)', () {
    for (final MapEntry(key: name, value: (sha256Hex, _, _))
        in _expected.entries) {
      final bytes = File('${licenses.path}/$name').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), sha256Hex, reason: name);
    }
  });

  test('pubspec.yaml declares licenses/ as a Flutter asset (all platforms)', () {
    final lines = File('${root.path}/pubspec.yaml').readAsLinesSync();
    final flutter = lines.indexOf('flutter:');
    expect(flutter, isNot(-1), reason: 'no top-level flutter: section');
    final assets = lines.indexOf('  assets:', flutter);
    expect(assets, greaterThan(flutter), reason: 'no flutter: assets:');
    final entries = <String>[];
    for (var i = assets + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      if (!line.startsWith('    ')) break; // end of the assets list
      entries.add(line.split('#').first.trim());
    }
    // A plain entry: no `platforms:` restriction, so native builds get it too.
    expect(entries, contains('- licenses/'));
  });

  test('the registry table lists the same files (lib/src/licenses.dart)', () {
    expect(pdfiumLicenseAssetDir, 'packages/pdf_io/licenses/');
    expect([
      for (final (file, _) in pdfiumLicenseFiles) file,
    ], _expected.keys.toList());
    for (final (file, packages) in pdfiumLicenseFiles) {
      expect(packages, isNotEmpty, reason: file);
    }
  });

  test(
    'every file reads through pdfiumLicenses; nothing is reported',
    () async {
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      addTearDown(() => FlutterError.onError = previous);
      final bundle = _PackageLicenseBundle(licenses);

      final entries = await pdfiumLicenses(bundle: bundle).toList();

      expect(reports, isEmpty);
      expect(entries, hasLength(20));
      expect(bundle.loaded, [
        for (final (file, _) in pdfiumLicenseFiles)
          '$pdfiumLicenseAssetDir$file',
      ]);
      String textOf(String package) => entries
          .where((e) => e.packages.contains(package))
          .expand((e) => e.paragraphs)
          .map((p) => p.text)
          .join('\n');
      // freetype.txt is ISO-8859-1: '©' (0xA9) decodes as U+00A9, not a replacement char.
      final freetype = textOf('FreeType');
      expect(freetype, contains('Portions of this software are copyright ©'));
      expect(freetype, isNot(contains('�')));
      expect(textOf('libjpeg-turbo'), contains('the Independent JPEG Group'));
      expect(
        textOf('pdfium-binaries'),
        contains('third-party software. See the licenses/ directory'),
      );
      expect(textOf('ICU'), contains('UNICODE LICENSE V3'));
    },
  );

  test('the Flutter asset build serves them: pdfiumLicenses on rootBundle', () async {
    // flutter test bundles the pubspec assets of this package (build/unit_test_assets),
    // also under the packages/pdf_io/ keys an app uses — so a missing or wrong
    // declaration fails here, not only in the app's license list.
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    addTearDown(() => FlutterError.onError = previous);

    final entries = await pdfiumLicenses().toList();

    expect(reports, isEmpty);
    expect(entries, hasLength(pdfiumLicenseFiles.length));
    expect(
      [for (final e in entries) e.packages.single],
      [for (final (_, packages) in pdfiumLicenseFiles) packages.single],
    );
  });

  test('decodeLicenseText: UTF-8 (BOM dropped), else Latin-1', () {
    expect(decodeLicenseText(Uint8List.fromList('a © b'.codeUnits)), 'a © b');
    expect(
      decodeLicenseText(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x41, 0xC2, 0xA9]),
      ),
      'A©',
    );
    expect(decodeLicenseText(Uint8List.fromList([0x41, 0xC2, 0xA9])), 'A©');
  });

  test('THIRD_PARTY_NOTICES.md and README.md name every file', () {
    final notices = File('${root.path}/THIRD_PARTY_NOTICES.md')
        .readAsStringSync();
    for (final name in _expected.keys) {
      expect(notices, contains('`$name`'), reason: name);
    }
    expect(notices, contains('chromium/7811'));
    expect(notices, contains('chromium/8125'));
    final readme = File('${root.path}/README.md').readAsStringSync();
    expect(readme, contains('THIRD_PARTY_NOTICES.md'));
  });
}
