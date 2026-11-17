// BOM and line endings of an MD 문서 (08-markdown 4.6, B-8). The store keeps the original
// text byte for byte; the editor and every position calculation (task marks, search
// landing, block ranges) work on the decoded text: no BOM, LF only.
import 'package:meta/meta.dart';

/// How an original text is shown in the editor and written back.
///
/// [decode] strips a leading U+FEFF and turns CRLF into LF; [encode] puts both back. A
/// file with mixed endings is kept as it is until it is edited; once edited it is written
/// with the majority ending (08-markdown 18 R2). A file whose lines end with a lone CR
/// (classic Mac) is shown with LF lines and written back with CR ([cr]).
@immutable
final class LineEndingCodec {
  const LineEndingCodec({
    required this.bom,
    required this.crlf,
    this.cr = false,
  });

  /// The codec of [raw]: BOM present?, CRLF or lone CR the majority line ending?
  factory LineEndingCodec.of(String raw) {
    var crlf = 0;
    var lf = 0;
    var cr = 0;
    for (var i = 0; i < raw.length; i++) {
      final c = raw.codeUnitAt(i);
      if (c == 0x0A) {
        if (i > 0 && raw.codeUnitAt(i - 1) == 0x0D) {
          crlf++;
        } else {
          lf++;
        }
      } else if (c == 0x0D &&
          (i + 1 >= raw.length || raw.codeUnitAt(i + 1) != 0x0A)) {
        cr++;
      }
    }
    final loneCr = cr > 0 && cr > crlf && cr > lf;
    return LineEndingCodec(
      bom: raw.startsWith(_bom),
      crlf: !loneCr && crlf > 0 && crlf >= lf,
      cr: loneCr,
    );
  }

  static const String _bom = '﻿';

  /// The original started with U+FEFF.
  final bool bom;

  /// The original's lines end with CRLF (the majority).
  final bool crlf;

  /// The original's lines end with a lone CR (the majority).
  final bool cr;

  /// The editor text of [raw]: no BOM, LF line endings.
  String decode(String raw) {
    var s = raw.startsWith(_bom) ? raw.substring(1) : raw;
    if (s.contains('\r\n')) s = s.replaceAll('\r\n', '\n');
    if (cr && s.contains('\r')) s = s.replaceAll('\r', '\n');
    return s;
  }

  /// The stored text of the editor [text] (CRLF and BOM restored).
  String encode(String text) {
    var s = text.contains('\r\n') ? text.replaceAll('\r\n', '\n') : text;
    if (crlf) s = s.replaceAll('\n', '\r\n');
    if (cr) s = s.replaceAll('\n', '\r');
    return bom ? '$_bom$s' : s;
  }

  @override
  bool operator ==(Object other) =>
      other is LineEndingCodec &&
      other.bom == bom &&
      other.crlf == crlf &&
      other.cr == cr;

  @override
  int get hashCode => Object.hash(bom, crlf, cr);

  @override
  String toString() => 'LineEndingCodec(bom: $bom, crlf: $crlf, cr: $cr)';
}
