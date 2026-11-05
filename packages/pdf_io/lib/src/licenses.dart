// lib/src/licenses.dart — 06-pdf 6.16, 7.1 (PDF-S7). Internal (not exported).
//
// PDFium and its third-party notices ship only inside the pdfium-binaries archives, so
// Flutter's automatic NOTICES do not hold them. initializePdfIo registers one
// LicenseRegistry collector (once per process) that reads the verbatim texts from the
// package assets packages/pdf_io/licenses/ (added with PDF T19) only when the app lists its
// licenses — nothing is read at start-up and the texts stay out of main.dart.js. A file
// that cannot be read is reported and left out (6.13).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'common/error_report.dart';

/// Asset folder of the license texts (pubspec flutter: assets:, PDF T19).
const String pdfiumLicenseAssetDir = 'packages/pdf_io/licenses/';

/// The union of the pdfium-binaries licenses/ files of chromium/7811 (web wasm) and
/// chromium/8125 (VM tests) — 19 files, 7.1 — plus the archive's own LICENSE, each with the
/// package names it is listed under.
const List<(String, List<String>)> pdfiumLicenseFiles = [
  ('LICENSE', ['pdfium-binaries']),
  ('pdfium.txt', ['PDFium']),
  ('abseil.txt', ['Abseil']),
  ('agg23.txt', ['Anti-Grain Geometry']),
  ('fast_float.txt', ['fast_float']),
  ('freetype.txt', ['FreeType']),
  ('icu.txt', ['ICU']),
  ('lcms.txt', ['Little CMS']),
  ('libjpeg_turbo.ijg', ['libjpeg-turbo']),
  ('libjpeg_turbo.md', ['libjpeg-turbo']),
  ('libopenjpeg.txt', ['OpenJPEG']),
  ('libpng.txt', ['libpng']),
  ('simdutf.txt', ['simdutf']),
  ('zlib.txt', ['zlib']),
  ('libtiff.txt', ['LibTIFF']),
  ('dragonbox-Apache2-LLVM.txt', ['Dragonbox']),
  ('dragonbox-Boost.txt', ['Dragonbox']),
  ('harfbuzz.txt', ['HarfBuzz']),
  ('highway.txt', ['Highway']),
  ('llvm-libc.txt', ['LLVM libc']),
];

/// The license entries of [pdfiumLicenseFiles], read from [bundle] (default rootBundle) in
/// table order. Unreadable files are reported and skipped.
Stream<LicenseEntry> pdfiumLicenses({AssetBundle? bundle}) async* {
  final assets = bundle ?? rootBundle;
  for (final (file, packages) in pdfiumLicenseFiles) {
    final String text;
    try {
      text = await assets.loadString('$pdfiumLicenseAssetDir$file');
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf_io license asset $file');
      continue;
    }
    yield LicenseEntryWithLineBreaks(packages, text);
  }
}
