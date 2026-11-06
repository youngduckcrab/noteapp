// T26a follow-up (m5-7/03-ink 3.1, contract v2.3 C23-03): the `flutter: assets:`
// block of pubspec.yaml lists the three font files one by one — not the folder,
// not README.md, and not as `fonts:` (NoteSans stays out of FontManifest.json,
// contract 7.4.5). With the block in, rootBundle serves the committed bytes and
// InkFonts loads without a debug source.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';

const List<String> _expectedAssets = [
  'assets/fonts/NoteSans-Regular.ttf',
  'assets/fonts/NoteSans-Bold.ttf',
  'assets/fonts/OFL.txt',
];

/// The lines of the top-level `flutter:` section (up to the next top-level key).
List<String> _flutterSection(List<String> lines) {
  final start = lines.indexOf('flutter:');
  if (start < 0) return const [];
  final out = <String>[];
  for (final line in lines.skip(start + 1)) {
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      break;
    }
    out.add(line);
  }
  return out;
}

/// The `- item` entries of the `assets:` list inside the flutter section.
List<String> _assetEntries(List<String> section) {
  final start = section.indexWhere((l) => l.trim() == 'assets:');
  if (start < 0) return const [];
  final indent = section[start].indexOf('assets:');
  final out = <String>[];
  for (final line in section.skip(start + 1)) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final lead = line.length - line.trimLeft().length;
    if (lead <= indent) break;
    if (!t.startsWith('- ')) break;
    final value = t.substring(2).split('#').first.trim();
    out.add(value);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pubspec = File('pubspec.yaml').readAsLinesSync();
  final section = _flutterSection(pubspec);

  test('flutter.assets = the three font files, file by file', () {
    expect(section, isNotEmpty, reason: 'pubspec.yaml has a flutter: section');
    expect(_assetEntries(section), _expectedAssets);
  });

  test('no folder entry, no README, no fonts: block', () {
    final entries = _assetEntries(section);
    expect(entries.where((e) => e.endsWith('/')), isEmpty);
    expect(entries.where((e) => e.toLowerCase().contains('readme')), isEmpty);
    expect(section.where((l) => l.trim().startsWith('fonts:')), isEmpty);
  });

  test('every listed file exists; README.md stays a repository file', () {
    for (final asset in _expectedAssets) {
      expect(File(asset).existsSync(), isTrue, reason: asset);
    }
    expect(File('assets/fonts/README.md').existsSync(), isTrue);
  });

  test('rootBundle serves the committed bytes under the package key', () async {
    for (final asset in _expectedAssets) {
      final data = await rootBundle.load('packages/ink_engine/$asset');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      expect(bytes, File(asset).readAsBytesSync(), reason: asset);
    }
  });

  test('InkFonts loads from rootBundle (no debug source)', () async {
    await InkFonts.ensureLoaded();
    final regular = await InkFonts.noteSansBytes();
    final bold = await InkFonts.noteSansBytes(bold: true);
    expect(regular, File(_expectedAssets[0]).readAsBytesSync());
    expect(bold, File(_expectedAssets[1]).readAsBytesSync());
  });
}
