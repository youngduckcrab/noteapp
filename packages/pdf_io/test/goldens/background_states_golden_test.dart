// Background status goldens (06-pdf 6.8, 9.1; 8 T9): loading (after 300 ms), assetMissing,
// downloading, needsPassword, failed and ready — thumbnail mode, so icons only and no text
// (platform font differences). A renderer double hands the view a fixed snapshot.
// Update with: flutter test --update-goldens test/goldens/
@Tags(['golden'])
@TestOn('vm')
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';

const ui.Size _page = ui.Size(120, 160);

final class _FixedHandle extends ChangeNotifier implements PdfPageRenderHandle {
  _FixedHandle(this.params, this.snapshot);

  @override
  PdfBackgroundParams params;

  @override
  final PdfRenderSnapshot snapshot;

  @override
  void update(PdfBackgroundParams params) => this.params = params;
}

final class _FixedRenderer implements PdfPageRenderer {
  _FixedRenderer(this.snapshot);
  final PdfRenderSnapshot snapshot;

  @override
  PdfPageRenderHandle attach(PdfBackgroundParams params) =>
      _FixedHandle(params, snapshot);

  @override
  Future<ui.Image?> renderThumbnail({
    required core.AssetId assetId,
    required int pdfPageIndex,
    required int longSidePx,
    int backgroundArgb = 0xFFFFFFFF,
  }) async => null;

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

ui.Image _solid(int width, int height, int argb) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(ui.Color(argb), ui.BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

Future<void> _golden(
  WidgetTester tester,
  String name,
  PdfRenderSnapshot snapshot, {
  Duration wait = Duration.zero,
}) async {
  const key = Key('golden');
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: PdfPageBackgroundView(
            params: const PdfBackgroundParams(
              assetId: 'a',
              pdfPageIndex: 0,
              pageSize: _page,
              deviceScale: 2,
              paperColorArgb: 0xFFFBF7EC,
              isThumbnail: true,
            ),
            renderer: _FixedRenderer(snapshot),
            viewScale: 1,
          ),
        ),
      ),
    ),
  );
  await tester.pump(wait);
  await expectLater(
    find.byKey(key),
    matchesGoldenFile('background_states/$name.png'),
  );
}

void main() {
  testWidgets('loading (after 300 ms)', (tester) async {
    await _golden(
      tester,
      'loading',
      PdfRenderSnapshot.loading,
      wait: const Duration(milliseconds: 400),
    );
  });

  testWidgets('assetMissing', (tester) async {
    await _golden(
      tester,
      'asset_missing',
      const PdfRenderSnapshot(status: PdfRenderStatus.assetMissing),
    );
  });

  testWidgets('downloading (40%)', (tester) async {
    await _golden(
      tester,
      'downloading',
      const PdfRenderSnapshot(
        status: PdfRenderStatus.downloading,
        remote: core.RemoteAssetProgress(
          core.RemoteAssetState.downloading,
          received: 40,
          total: 100,
        ),
      ),
    );
  });

  testWidgets('needsPassword', (tester) async {
    await _golden(
      tester,
      'needs_password',
      const PdfRenderSnapshot(status: PdfRenderStatus.needsPassword),
    );
  });

  testWidgets('failed', (tester) async {
    await _golden(
      tester,
      'failed',
      const PdfRenderSnapshot(status: PdfRenderStatus.failed),
    );
  });

  testWidgets('ready (base + one tile)', (tester) async {
    final base = _solid(60, 80, 0xFF9E9E9E);
    final tile = _solid(40, 40, 0xFF303030);
    addTearDown(base.dispose);
    addTearDown(tile.dispose);
    await _golden(
      tester,
      'ready',
      PdfRenderSnapshot(
        status: PdfRenderStatus.ready,
        base: PdfPlacedImage(
          image: base,
          srcRect: const ui.Rect.fromLTWH(0, 0, 60, 80),
          pageRect: const ui.Rect.fromLTWH(0, 0, 120, 160),
        ),
        tiles: [
          PdfPlacedImage(
            image: tile,
            srcRect: const ui.Rect.fromLTWH(0, 0, 40, 40),
            pageRect: const ui.Rect.fromLTWH(20, 20, 40, 40),
          ),
        ],
      ),
    );
  });
}
