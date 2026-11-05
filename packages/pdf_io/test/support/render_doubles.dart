// Test doubles of the render side for import tests (06-pdf 8 T5, T6) until the real document
// pool (T7) and render service (T8) exist: a pool that records adopted documents, a page
// renderer whose renderThumbnail draws a solid image, and a scripted
// core.PageThumbnailRenderer (the INK renderer INFRA injects in the app).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';

/// Records adopt(); every other member is unused by the import service.
final class RecordingDocumentPool implements PdfDocumentPool {
  final List<(core.AssetId, PdfEngineDocument)> adopted = [];

  @override
  void adopt(core.AssetId assetId, PdfEngineDocument document) =>
      adopted.add((assetId, document));

  @override
  Future<PdfDocumentLease> acquire(core.AssetId assetId) =>
      throw UnimplementedError('RecordingDocumentPool.acquire');

  @override
  Stream<core.AssetId> get assetArrived => const Stream.empty();

  @override
  Stream<core.RemoteAssetProgress>? requestRemote(core.AssetId assetId) => null;

  @override
  int get openCount => adopted.length;

  @override
  Future<void> closeIdle() async {}

  @override
  Future<void> dispose() async {}
}

/// renderThumbnail draws [imageArgb] at [pageSize]'s aspect (long side = longSidePx),
/// or returns null / throws when told to. Other members are unused by the import service.
final class SolidThumbnailRenderer implements PdfPageRenderer {
  SolidThumbnailRenderer({
    this.pageSize = const ui.Size(595.276, 841.89),
    this.imageArgb = 0xFF202020,
  });

  ui.Size pageSize;
  int imageArgb;
  bool returnNull = false;
  Object? error;
  final List<({core.AssetId assetId, int pdfPageIndex, int longSidePx})>
  thumbnailCalls = [];

  @override
  Future<ui.Image?> renderThumbnail({
    required core.AssetId assetId,
    required int pdfPageIndex,
    required int longSidePx,
    int backgroundArgb = 0xFFFFFFFF,
  }) async {
    thumbnailCalls.add((
      assetId: assetId,
      pdfPageIndex: pdfPageIndex,
      longSidePx: longSidePx,
    ));
    final failure = error;
    if (failure != null) Error.throwWithStackTrace(failure, StackTrace.current);
    if (returnNull) return null;
    final long = math.max(pageSize.width, pageSize.height);
    final width = math.max(1, (pageSize.width / long * longSidePx).round());
    final height = math.max(1, (pageSize.height / long * longSidePx).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(ui.Color(imageArgb), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  @override
  PdfPageRenderHandle attach(PdfBackgroundParams params) =>
      throw UnimplementedError('SolidThumbnailRenderer.attach');

  @override
  PdfRenderStats get stats => PdfRenderStats.zero;

  @override
  ValueListenable<PdfRenderStats> get statsListenable =>
      ValueNotifier(PdfRenderStats.zero);

  @override
  void trimMemory() {}

  @override
  Future<void> dispose() async {}
}

/// Scripted core.PageThumbnailRenderer: records (page id, maxSidePx); returns a 1×1 PNG-typed
/// thumbnail of the page, null, or throws.
final class ScriptedThumbnailRenderer implements core.PageThumbnailRenderer {
  bool returnNull = false;
  Object? error;
  final List<(core.PageId, int)> calls = [];

  @override
  Future<core.PageThumbnail?> render(
    core.PageContent content, {
    int maxSidePx = 512,
  }) async {
    calls.add((content.page.id, maxSidePx));
    final failure = error;
    if (failure != null) Error.throwWithStackTrace(failure, StackTrace.current);
    if (returnNull) return null;
    return core.PageThumbnail(
      pageId: content.page.id,
      contentRevision: content.page.contentRevision,
      width: 1,
      height: 1,
      mimeType: 'image/png',
      bytes: Uint8List.fromList(const [1, 2, 3]),
    );
  }
}
