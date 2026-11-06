// T26a (m5-7/03-ink 6.10.1): note_sans_coverage.dart = the cmap of the committed
// NoteSans-Regular.ttf (format 4, Windows Unicode BMP) — the font cannot change
// without the table. Both weights have the same code points.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/src/text/note_sans_coverage.dart';

/// Code points of the (3, 1) format 4 cmap subtable of a TrueType file.
Set<int> _cmapCodePoints(Uint8List ttf) {
  final d = ByteData.sublistView(ttf);
  final numTables = d.getUint16(4);
  int? cmap;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + 16 * i;
    final tag = String.fromCharCodes(ttf.sublist(rec, rec + 4));
    if (tag == 'cmap') cmap = d.getUint32(rec + 8);
  }
  if (cmap == null) throw StateError('no cmap');
  final n = d.getUint16(cmap + 2);
  int? sub;
  for (var i = 0; i < n; i++) {
    final e = cmap + 4 + 8 * i;
    if (d.getUint16(e) == 3 && d.getUint16(e + 2) == 1) {
      sub = cmap + d.getUint32(e + 4);
    }
  }
  if (sub == null || d.getUint16(sub) != 4) throw StateError('no format 4');
  final segX2 = d.getUint16(sub + 6);
  final ends = sub + 14;
  final starts = ends + segX2 + 2;
  final deltas = starts + segX2;
  final offsets = deltas + segX2;
  final out = <int>{};
  for (var s = 0; s < segX2 ~/ 2; s++) {
    final end = d.getUint16(ends + 2 * s);
    final start = d.getUint16(starts + 2 * s);
    final delta = d.getInt16(deltas + 2 * s);
    final rangeOffset = d.getUint16(offsets + 2 * s);
    for (var c = start; c <= end && c != 0xFFFF; c++) {
      int glyph;
      if (rangeOffset == 0) {
        glyph = (c + delta) & 0xFFFF;
      } else {
        final at = offsets + 2 * s + rangeOffset + 2 * (c - start);
        final g = d.getUint16(at);
        glyph = g == 0 ? 0 : (g + delta) & 0xFFFF;
      }
      if (glyph != 0) out.add(c);
    }
  }
  return out;
}

Set<int> _tableCodePoints() {
  final out = <int>{};
  for (var i = 0; i < noteSansCoverage.length; i += 2) {
    for (var c = noteSansCoverage[i]; c <= noteSansCoverage[i + 1]; c++) {
      out.add(c);
    }
  }
  return out;
}

void main() {
  test('the range table is sorted, disjoint and = the regular font cmap', () {
    expect(noteSansCoverage.length.isEven, isTrue);
    for (var i = 0; i < noteSansCoverage.length; i += 2) {
      expect(noteSansCoverage[i], lessThanOrEqualTo(noteSansCoverage[i + 1]));
      if (i > 0) {
        expect(noteSansCoverage[i], greaterThan(noteSansCoverage[i - 1] + 1));
      }
    }
    final regular = _cmapCodePoints(
      File('assets/fonts/NoteSans-Regular.ttf').readAsBytesSync(),
    );
    expect(_tableCodePoints(), regular);
    expect(regular, hasLength(2674));
  });

  test('the bold font covers the same code points', () {
    expect(
      _cmapCodePoints(File('assets/fonts/NoteSans-Bold.ttf').readAsBytesSync()),
      _tableCodePoints(),
    );
  });
}
