// lib/src/tuning.dart — 06-pdf 4.13. Every numeric constant of pdf_io lives
// here; change 06-pdf 4.13 together with a value.

abstract final class PdfTuning {
  // render (6.7)
  static const int previewMaxLongSidePx = 1024;
  static const int thumbnailLongSidePx = 256;
  static const double thumbnailModeMaxLongSidePx = 320;
  static const int tileSizePx = 512;
  static const int tileOverlapPx = 1;
  static const double scaleBucketBase = 1.25;
  static const double minScale = 0.125;
  static const double maxScale = 24;
  static const double bucketUnderSampleTolerance = 0.95;

  /// tiles when deviceScale > previewScale * 1.1
  static const double tilesOnlyAboveRatio = 1.1;
  static const double prefetchMarginFraction = 0.25;
  static const int maxTilesPerPage = 64;
  static const Duration settleDelay = Duration(milliseconds: 120);
  static const Duration loadingIndicatorDelay = Duration(milliseconds: 300);
  static const int maxInflightRenders = 2;
  static const Duration idleTileTtl = Duration(seconds: 30);
  static const Duration trimInterval = Duration(seconds: 5);

  /// PdfRenderStats.p95RenderMs: the last N render times
  static const int renderTimingSamples = 100;

  // documents (6.6)
  static const int maxIdleDocuments = 2;
  static const Duration idleDocumentTtl = Duration(seconds: 60);
  static const Duration failureMemo = Duration(seconds: 2);

  // import (6.3)
  static const int pdfMagicSearchBytes = 1024;

  /// = PageThumbnailRenderer default maxSidePx
  static const int coverThumbnailLongSidePx = 512;
  static const int maxTitleLength = 200;
  static const String defaultTitle = 'PDF 문서';

  // jobs (6.13): Running(progress) updates of the job notifiers are batched
  static const Duration jobProgressInterval = Duration(milliseconds: 100);

  // text/search (6.10)
  static const int textCachePages = 600;
  static const Duration searchDebounce = Duration(milliseconds: 250);
  static const int maxSearchHits = 2000;
  static const int snippetContextChars = 24;
  static const Duration searchProgressInterval = Duration(milliseconds: 100);

  // export (6.11)
  /// web (dedicated worker)
  static const int exportChunkPages = 16;

  /// native (shares the pdfrx worker isolate)
  static const int nativeExportChunkPages = 8;
  static const int exportChunkMaxBytes = 8 * 1024 * 1024;
  static const Duration exportSliceBudget = Duration(milliseconds: 8);
  static const Duration composeWorkerIdleTimeout = Duration(seconds: 60);
  static const int warnExportSourceBytesWeb = 150 * 1024 * 1024;

  /// 6.11.11
  static const int batchMaxTotalBytesWeb = 150 * 1024 * 1024;

  /// '3, 5, 7–9 외 4쪽'
  static const int missingPagesListMax = 10;
  static const int maxFileNameRunes = 100;

  // export objects (2차, m5-7/06-pdf 4.5.1 · 6.2.4 · 6.2.10)
  /// U17 — only inside the [maxRasterPixels] cap; larger frames get a lower dpi.
  static const double mathRasterDpi = 300;

  /// Text box raster fallback (6.2.5) — the same rule.
  static const double textRasterDpi = 300;

  /// One raster / decode ≤ 4 Mpx (16 MiB RGBA) — contract 7.4.5; the INK value (03-ink 4.10).
  static const int maxRasterPixels = 4194304;

  /// Texture-safe side (the INK value).
  static const int maxRasterSidePx = 8192;

  /// Engine decode target (long side) — the same as ImageImportLimits.maxLongSidePx.
  static const int exportDecodeLongSidePx = 2048;

  /// JPEG fast path (bytes as stored) limit — larger JPEGs are decoded (slow path).
  static const int exportJpegInlineMaxBytes = 8 * 1024 * 1024;

  /// Contract 7.4.5 '내보내기 중 이미지·래스터 임시 16 MB': RGBA + read image bytes + JPEG cache
  /// that Dart holds at once (ExportMemoryLedger). The native worker copy is outside (CP-PDF-14 ①).
  static const int exportImageTempBytes = 16 * 1024 * 1024;

  /// Slow path decode target floor (1 Mpx = 4 MiB RGBA). Only inputs > 12 MiB (outside M-3) go
  /// over the ledger budget with it (overBudget — CP-PDF-14 ②).
  static const int exportMinDecodePixels = 1048576;

  /// InkFonts.ensureLoaded() wait — longer → every text box is rasterized.
  static const Duration exportFontLoadTimeout = Duration(seconds: 5);

  /// One formula raster — longer → left out with a warning.
  static const Duration exportMathRasterTimeout = Duration(seconds: 3);

  // colors — contract 7.4.11 v1.2 (C12-07): the PDF search highlight is an exception to the
  // no-hard-coded-color rule. It is drawn OVER THE PAPER, so contrast with the paper (not the
  // UI theme) decides it; it does not follow the theme (dark mode included). PdfTuning is the
  // ONLY place for these values: painters / widgets hold no color literal (6.8 ④) and never
  // map them to colorScheme.
  static const int searchHighlightArgb = 0x66FFC107;
  static const int searchCurrentArgb = 0x99FF9800;
  static const double searchCurrentOutlinePt = 1.5;
}
