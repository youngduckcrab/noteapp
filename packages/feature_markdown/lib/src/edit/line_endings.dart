// BOM and line endings of an MD 문서 (08-markdown 4.6, B-8). The store keeps the original
// text byte for byte; the editor and every position calculation (task marks, search
// landing, block ranges) work on the decoded text: no BOM, LF only.
import 'package:meta/meta.dart';

/// How an original text is shown in the editor and written back.
///
/// [decode] strips a leading U+FEFF and turns CRLF into LF; [encode] puts both back. A
/// file with mixed endings is kept as it is until it is edited; once edited it is written
/// with the majority ending (08-markdown 18 R2). A lone CR (classic Mac) is left alone.
@immutable
final class LineEndingCodec {
  const LineEndingCodec({required this.bom, required this.crlf});

  /// The codec of [raw]: BOM present?, CRLF the majority line ending?
  factory LineEndingCodec.of(String raw) {
    var crlf = 0;
    var lf = 0;
    for (var i = 0; i < raw.length; i++) {
      if (raw.codeUnitAt(i) == 0x0A) {
        if (i > 0 && raw.codeUnitAt(i - 1) == 0x0D) {
          crlf++;
        } else {
          lf++;
        }
      }
    }
    return LineEndingCodec(
      bom: raw.startsWith(_bom),
      crlf: crlf > 0 && crlf >= lf,
    );
  }

  static const String _bom = '﻿';

  /// The original started with U+FEFF.
  final bool bom;

  /// The original's lines end with CRLF (the majority).
  final bool crlf;

  /// The editor text of [raw]: no BOM, LF line endings.
  String decode(String raw) {
    var s = raw.startsWith(_bom) ? raw.substring(1) : raw;
    if (s.contains('\r\n')) s = s.replaceAll('\r\n', '\n');
    return s;
  }

  /// The stored text of the editor [text] (CRLF and BOM restored).
  String encode(String text) {
    var s = text.contains('\r\n') ? text.replaceAll('\r\n', '\n') : text;
    if (crlf) s = s.replaceAll('\n', '\r\n');
    return bom ? '$_bom$s' : s;
  }

  @override
  bool operator ==(Object other) =>
      other is LineEndingCodec && other.bom == bom && other.crlf == crlf;

  @override
  int get hashCode => Object.hash(bom, crlf);

  @override
  String toString() => 'LineEndingCodec(bom: $bom, crlf: $crlf)';
}
