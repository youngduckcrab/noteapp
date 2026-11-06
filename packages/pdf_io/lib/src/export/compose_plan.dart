// lib/src/export/compose_plan.dart — 06-pdf 4.9, 6.11.4, 6.11.5.
//
// Foundation step B4 (T0): types, opcodes and plain getters; encodePages is PDF T12.
// (2차, m5-7/06-pdf T21) image / text ops and the images / texts / fonts of a part.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;

import 'vectors.dart';

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

/// Binary ops of one output page (format 6.11.5; (2차) m5-7/06-pdf 4.1.4, 6.2.6).
///
/// (2차) One page may come as several parts (PdfComposeEncoder.encodeItems): parts of the same
/// [outputIndex] arrive in z order and each draws on top of what the page already has.
/// [images] / [texts] are referred to by index from the `image` / `text` ops; [fonts] are
/// loaded into the output document before these ops run (the first part of a job that uses
/// a font id carries it, later parts never again).
@immutable
final class PdfComposePageOps {
  const PdfComposePageOps({
    required this.outputIndex,
    required this.verbs,
    required this.coords,
    required this.paints,
    this.images = const [],
    this.texts = const [],
    this.fonts = const {},
  });
  final int outputIndex;
  final Uint8List verbs;
  final Float32List coords;
  final Float32List paints; // stride PdfComposeOpcodes.paintStride

  /// `image` ops refer to these by index.
  final List<PdfImageData> images;

  /// `text` ops refer to these by index.
  final List<String> texts;

  /// Fonts loaded into the output document BEFORE these ops run (fontId → TrueType bytes). A
  /// fontId is carried by the first part of the job that uses it, never again.
  final Map<int, Uint8List> fonts;

  /// No ops and no fonts (6.2.7: nothing to interpret).
  bool get isEmpty => verbs.isEmpty && fonts.isEmpty;

  /// verbs + coords + paints + image bytes + 2 B per text code unit + font bytes (6.2.6).
  int get byteLength {
    var n = verbs.lengthInBytes + coords.lengthInBytes + paints.lengthInBytes;
    for (final image in images) {
      n += image.byteLength;
    }
    for (final text in texts) {
      n += 2 * text.length;
    }
    for (final font in fonts.values) {
      n += font.lengthInBytes;
    }
    return n;
  }
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

  /// coords [imageIndex, a, b, c, d, e, f]: unit square → note pt (then note → user like paths).
  static const int image = 8;

  /// coords [textIndex, fontId, fontSize, r, g, b, alpha255, a, b, c, d, e, f]: text space → note pt.
  static const int text = 9;
  static const int imageArgs = 7, textArgs = 13;
  static const int fontRegular = 0, fontBold = 1;
}
