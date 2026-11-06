// Internal (not exported) — PDF character boxes of m5-7/02-core 6.10.3 / 6.10.4: the blob format
// (SearchRectsCodec), the per-line merge of a hit's boxes and the fraction → note page pt
// conversion (pdf_io's 1차 PdfPageFit, contain + centered).
import 'dart:math' as math;
import 'dart:typed_data';

import '../common/geometry.dart';

/// `"SR"` + version 1, then (little endian) char count n (uint32), line group count L (uint32);
/// per group: first char, length (uint32 × 2), top, bottom (uint16 × 2); per char: left, right
/// (uint16 × 2). Coordinates are page fractions × 65535, rounded (precision 1/65535 — 7.2.5
/// '≥ 1/65535'); consecutive chars with the same top and bottom form one group. PageRect.zero is
/// stored as all zeros (skipped when merged). No 64-bit integers (1차 7.4.3 web-safe numbers).
abstract final class SearchRectsCodec {
  static const int version = 1;
  static const int _scale = 65535;

  static int _q(double f) => (f.clamp(0.0, 1.0) * _scale).round();

  static Uint8List encode(List<PageRect> rects) {
    final n = rects.length;
    final groups = <(int, int, int, int)>[]; // start, length, top, bottom
    final lr = Uint16List(2 * n);
    for (var i = 0; i < n; i++) {
      final r = rects[i];
      final top = _q(r.top), bottom = _q(r.bottom);
      lr[2 * i] = _q(r.left);
      lr[2 * i + 1] = _q(r.right);
      if (groups.isNotEmpty &&
          groups.last.$3 == top &&
          groups.last.$4 == bottom) {
        final g = groups.removeLast();
        groups.add((g.$1, g.$2 + 1, top, bottom));
      } else {
        groups.add((i, 1, top, bottom));
      }
    }
    final bytes = ByteData(3 + 8 + 12 * groups.length + 4 * n);
    bytes
      ..setUint8(0, 0x53) // 'S'
      ..setUint8(1, 0x52) // 'R'
      ..setUint8(2, version)
      ..setUint32(3, n, Endian.little)
      ..setUint32(7, groups.length, Endian.little);
    var o = 11;
    for (final (start, length, top, bottom) in groups) {
      bytes
        ..setUint32(o, start, Endian.little)
        ..setUint32(o + 4, length, Endian.little)
        ..setUint16(o + 8, top, Endian.little)
        ..setUint16(o + 10, bottom, Endian.little);
      o += 12;
    }
    for (var i = 0; i < 2 * n; i++) {
      bytes.setUint16(o, lr[i], Endian.little);
      o += 2;
    }
    return bytes.buffer.asUint8List();
  }

  /// The boxes as page fractions (k / 65535). FormatException on a damaged blob.
  static List<PageRect> decode(Uint8List data) {
    if (data.length < 11 ||
        data[0] != 0x53 ||
        data[1] != 0x52 ||
        data[2] != version) {
      throw const FormatException('not a SearchRectsCodec blob');
    }
    final b = ByteData.sublistView(data);
    final n = b.getUint32(3, Endian.little);
    final groupCount = b.getUint32(7, Endian.little);
    final expected = 11 + 12 * groupCount + 4 * n;
    if (data.length != expected) {
      throw FormatException(
        'SearchRectsCodec blob: ${data.length} != $expected',
      );
    }
    final tops = Uint16List(n), bottoms = Uint16List(n);
    var o = 11;
    var covered = 0;
    for (var g = 0; g < groupCount; g++) {
      final start = b.getUint32(o, Endian.little);
      final length = b.getUint32(o + 4, Endian.little);
      final top = b.getUint16(o + 8, Endian.little);
      final bottom = b.getUint16(o + 10, Endian.little);
      if (start != covered || start + length > n) {
        throw const FormatException('SearchRectsCodec blob: bad line groups');
      }
      for (var i = start; i < start + length; i++) {
        tops[i] = top;
        bottoms[i] = bottom;
      }
      covered = start + length;
      o += 12;
    }
    if (covered != n) {
      throw const FormatException(
        'SearchRectsCodec blob: groups do not cover n',
      );
    }
    return [
      for (var i = 0; i < n; i++)
        PageRect(
          b.getUint16(o + 4 * i, Endian.little) / _scale,
          tops[i] / _scale,
          b.getUint16(o + 4 * i + 2, Endian.little) / _scale,
          bottoms[i] / _scale,
        ),
    ];
  }
}

/// The boxes of code units [start, end) merged per text line (consecutive boxes with the same
/// top and bottom), PageRect.zero boxes skipped (6.10.4).
List<PageRect> mergeLineRects(List<PageRect> rects, int start, int end) {
  final out = <PageRect>[];
  PageRect? current;
  for (var i = math.max(0, start); i < math.min(end, rects.length); i++) {
    final r = rects[i];
    if (r == PageRect.zero) continue;
    if (current != null && current.top == r.top && current.bottom == r.bottom) {
      current = current.expandToInclude(r);
    } else {
      if (current != null) out.add(current);
      current = r;
    }
  }
  if (current != null) out.add(current);
  return out;
}

/// A page-fraction box in note page pt (6.10.4 'pdf' row): pdf_io's PdfPageFit (contain,
/// centered) for a PDF page of aspect [pdfPageAspect] (width / height); without it the
/// fractions fill the note page.
PageRect fractionToPagePt(
  PageRect f,
  double pageWidth,
  double pageHeight, {
  double? pdfPageAspect,
}) {
  var ox = 0.0, oy = 0.0, w = pageWidth, h = pageHeight;
  final a = pdfPageAspect;
  if (a != null && a.isFinite && a > 0) {
    final k = math.min(pageWidth / a, pageHeight / 1);
    w = a * k;
    h = k;
    ox = (pageWidth - w) / 2;
    oy = (pageHeight - h) / 2;
  }
  return PageRect(
    ox + f.left * w,
    oy + f.top * h,
    ox + f.right * w,
    oy + f.bottom * h,
  );
}
