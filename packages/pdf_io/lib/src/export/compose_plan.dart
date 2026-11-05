// lib/src/export/compose_plan.dart — 06-pdf 4.9, 6.11.4, 6.11.5.
//
// Foundation step B4 (T0): types, opcodes and plain getters; encodePages is PDF T12.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

@immutable
final class PdfComposeSource {
  const PdfComposeSource({required this.assetId, required this.bytes});
  final core.AssetId assetId;
  final Uint8List bytes;
}

sealed class PdfComposePagePlan {
  const PdfComposePagePlan({required this.noteSize});
  final ui.Size noteSize; // pt
}

final class PdfComposeSourcePage extends PdfComposePagePlan {
  const PdfComposeSourcePage({
    required this.sourceIndex,
    required this.pdfPageIndex,
    required super.noteSize,
  });
  final int sourceIndex;
  final int pdfPageIndex;
}

final class PdfComposeBlankPage extends PdfComposePagePlan {
  const PdfComposeBlankPage({required super.noteSize});
}

@immutable
final class PdfComposePlan {
  const PdfComposePlan({required this.sources, required this.pages});
  final List<PdfComposeSource> sources;
  final List<PdfComposePagePlan> pages; // output order
  /// Stride 6 per page: [kind(0 source, 1 blank), sourceIndex, pdfPageIndex, noteW, noteH, 0].
  ///
  /// T12: a blank page has sourceIndex and pdfPageIndex −1.
  Float64List encodePages() {
    final out = Float64List(pages.length * 6);
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final o = i * 6;
      switch (page) {
        case PdfComposeSourcePage(:final sourceIndex, :final pdfPageIndex):
          out[o] = 0;
          out[o + 1] = sourceIndex.toDouble();
          out[o + 2] = pdfPageIndex.toDouble();
        case PdfComposeBlankPage():
          out[o] = 1;
          out[o + 1] = -1;
          out[o + 2] = -1;
      }
      out[o + 3] = page.noteSize.width;
      out[o + 4] = page.noteSize.height;
    }
    return out;
  }
}

/// Binary ops of one output page (format 6.11.5).
@immutable
final class PdfComposePageOps {
  const PdfComposePageOps({
    required this.outputIndex,
    required this.verbs,
    required this.coords,
    required this.paints,
  });
  final int outputIndex;
  final Uint8List verbs;
  final Float32List coords;
  final Float32List paints; // stride PdfComposeOpcodes.paintStride
  bool get isEmpty => verbs.isEmpty;
  int get byteLength =>
      verbs.lengthInBytes + coords.lengthInBytes + paints.lengthInBytes;
}

abstract final class PdfComposeOpcodes {
  static const int moveTo = 0,
      lineTo = 1,
      cubicTo = 2,
      close = 3,
      endObject = 7;
  static const int paintStride = 10;
  // paint layout: [type(0 fill, 1 stroke), r, g, b, a(0..255), width, cap, join, blend, fillMode]
  static const int fillModeEvenOdd = 1,
      fillModeNonZero = 2; // FPDF_FILLMODE_ALTERNATE/WINDING
}
