// lib/src/engine/page_info.dart — 06-pdf 4.3 (engine port value types).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

@immutable
final class PdfPageInfo {
  const PdfPageInfo({
    required this.index,
    required this.width,
    required this.height,
    required this.rotationQuarterTurns,
  });
  final int index; // 0-based
  final double width; // displayed size in pt (after /Rotate, CropBox)
  final double height;
  final int rotationQuarterTurns; // /Rotate / 90, 0..3
}

@immutable
final class PdfDocumentInfo {
  const PdfDocumentInfo({
    required this.pages,
    required this.isEncrypted,
    required this.usedPassword,
  });
  final List<PdfPageInfo> pages;
  int get pageCount => pages.length;
  final bool isEncrypted; // any security handler (incl. owner-password-only)
  final bool usedPassword; // a non-empty user password was needed to open
}

@immutable
final class PdfPasswordRequest {
  const PdfPasswordRequest({required this.fileName, required this.attempt});
  final String fileName;
  final int attempt; // 1-based; attempt > 1 means the previous one was wrong
}

/// Return null to give up.
typedef PdfPasswordCallback = Future<String?> Function(
  PdfPasswordRequest request,
);

enum PdfRenderPriority { high, normal, low }

final class PdfRenderCancelToken {
  PdfRenderCancelToken();

  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Idempotent; runs the listeners added with [whenRenderCancelled] once.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = _cancelListeners[this];
    _cancelListeners[this] = null;
    if (listeners == null) return;
    for (final listener in listeners) {
      listener();
    }
  }
}

final Expando<List<void Function()>> _cancelListeners = Expando(
  'PdfRenderCancelToken listeners',
);

/// Internal (not exported): runs [listener] when [token] is cancelled — at once when it
/// already is. Engines forward the cancel to their own token (PdfrxEngine → pdfrx).
void whenRenderCancelled(PdfRenderCancelToken token, void Function() listener) {
  if (token.isCancelled) {
    listener();
    return;
  }
  (_cancelListeners[token] ??= []).add(listener);
}

/// Integer pixel rectangle inside the full rendered page (scale * page size).
@immutable
final class PdfPixelRect {
  const PdfPixelRect(this.left, this.top, this.width, this.height);
  final int left, top, width, height;
  int get right => left + width;
  int get bottom => top + height;
  bool get isEmpty => width <= 0 || height <= 0;
}

@immutable
final class PdfRenderRequest {
  const PdfRenderRequest({
    required this.pageIndex,
    required this.scale,
    this.region,
    this.backgroundArgb = 0xFFFFFFFF,
    this.priority = PdfRenderPriority.normal,
  });
  final int pageIndex;
  final double scale; // device pixels per pt
  final PdfPixelRect? region; // null → whole page
  final int backgroundArgb;
  final PdfRenderPriority priority;

  /// Full page size in pixels: (ceil(width * scale), ceil(height * scale)).
  (int, int) fullPixelSize(PdfPageInfo page) =>
      ((page.width * scale).ceil(), (page.height * scale).ceil());
}

@immutable
final class PdfPageTextData {
  const PdfPageTextData({
    required this.pageIndex,
    required this.text,
    required this.charRects,
  });
  final int pageIndex;
  final String text; // raw text from PDFium (lines separated by \r\n)
  /// One rect per UTF-16 code unit of [text], displayed page pt, y down
  /// (converted from PDF bottom-left coordinates incl. rotation). Rect.zero when unknown.
  final List<ui.Rect> charRects;
}
