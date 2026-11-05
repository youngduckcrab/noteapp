// PdfPageBackgroundView (06-pdf 6.7.7, 6.8; 8 T9) on PdfRenderService + DefaultPdfDocumentPool
// with FakePdfEngine, FakePdfNoteGateway and FakeRemoteAssetFetcher: opaque paper on the first
// frame, preview then tiles, no request while pinching (120 ms after), unmount releases tiles
// and the remote watch, status displays (6.14 texts, icon only in thumbnail mode), the
// 300 ms loading indicator, IgnorePointer, remote originals (request → downloading → arrival
// → ready; offline / failed; no fetcher) and search highlights. iPad Pro 13" 1032 × 1376.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/render/page_background_painter.dart';
import 'package:pdf_io/src/ui/strings_ko.dart';
import 'package:pdf_io/testing.dart';

const ui.Size _a4 = ui.Size(595.276, 841.89);
const String _asset = 'asset-a';
const String _remote = 'remote-a';
const Key _key = Key('view');

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7\n% view\n%%EOF\n'.codeUnits);

PdfBackgroundParams _params({
  String assetId = _asset,
  ui.Size pageSize = _a4,
  double deviceScale = 1,
  ui.Rect? visible,
  bool isScaling = false,
  bool isThumbnail = false,
  int paper = 0xFFFFFFFF,
  String? pageId = 'p1',
}) => PdfBackgroundParams(
  assetId: assetId,
  pdfPageIndex: 0,
  pageSize: pageSize,
  deviceScale: deviceScale,
  visiblePageRect: visible,
  isScaling: isScaling,
  isThumbnail: isThumbnail,
  paperColorArgb: paper,
  pageId: pageId,
);

final class _World {
  _World({this.fetcher}) {
    gateway.arriveBytes(_asset, _pdf());
    pool = DefaultPdfDocumentPool(
      engine: engine,
      gateway: gateway,
      remoteAssets: fetcher,
    );
    service = PdfRenderService(
      pool: pool,
      budget: const PdfRenderBudget.web(),
      trimOnAppHidden: false,
    );
    engine.beforeRender = (request) async {
      if (!hold) return;
      final gate = Completer<void>();
      held.add(gate);
      await gate.future;
    };
  }

  final FakePdfEngine engine = FakePdfEngine();
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  final FakeRemoteAssetFetcher? fetcher;
  late final DefaultPdfDocumentPool pool;
  late final PdfRenderService service;
  bool hold = false;
  final List<Completer<void>> held = [];

  List<PdfRenderRequest> get requests => engine.renderRequests;

  void releaseHeld() {
    hold = false;
    for (final gate in held) {
      if (!gate.isCompleted) gate.complete();
    }
    held.clear();
  }

  Future<void> close() async {
    releaseHeld();
    await service.dispose();
    await pool.dispose();
  }
}

Future<void> _show(
  WidgetTester tester,
  _World w,
  PdfBackgroundParams params, {
  double viewScale = 1,
  ValueListenable<PdfSearchState>? highlights,
}) => tester.pumpWidget(
  MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: PdfPageBackgroundView(
        key: _key,
        params: params,
        renderer: w.service,
        highlights: highlights,
        viewScale: viewScale,
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

void _ipad(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1032, 1376)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// RGBA of the view's pixels at [points] (logical px inside the view).
Future<List<List<int>>> _pixels(
  WidgetTester tester,
  List<(int, int)> points,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .descendant(
          of: find.byKey(_key),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = (await image.toByteData())!;
      return [
        for (final (x, y) in points)
          [
            for (var c = 0; c < 4; c++)
              data.getUint8((y * image.width + x) * 4 + c),
          ],
      ];
    } finally {
      image.dispose();
    }
  });
  return result!;
}

PdfPageBackgroundPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find
                  .descendant(
                    of: find.byKey(_key),
                    matching: find.byType(CustomPaint),
                  )
                  .first,
            )
            .painter!
        as PdfPageBackgroundPainter;

void main() {
  testWidgets('first frame: opaque paper of pageSize × viewScale', (
    tester,
  ) async {
    _ipad(tester);
    final w = _World();
    await _show(
      tester,
      w,
      _params(pageSize: const ui.Size(200, 100), paper: 0x80FBF7EC),
      viewScale: 1.5,
    );
    expect(tester.getSize(find.byKey(_key)), const Size(300, 150));
    expect(_painter(tester).snapshot.status, PdfRenderStatus.loading);
    final pixels = await _pixels(tester, [(0, 0), (150, 75), (299, 149)]);
    for (final p in pixels) {
      expect(p, [0xFB, 0xF7, 0xEC, 0xFF]);
    }
    final ignore = tester.widget<IgnorePointer>(
      find
          .descendant(
            of: find.byKey(_key),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(ignore.ignoring, isTrue);
    await tester.pumpWidget(const SizedBox());
    await w.close();
  });

  testWidgets('preview, then tiles when zoomed in; the PDF is drawn', (
    tester,
  ) async {
    _ipad(tester);
    final w = _World();
    await _show(tester, w, _params(pageSize: const ui.Size(200, 100)));
    await _settle(tester);
    expect(_painter(tester).snapshot.status, PdfRenderStatus.ready);
    expect(w.requests, hasLength(1));
    // FakePdfEngine draws 0xFF808080.
    expect((await _pixels(tester, [(100, 50)])).single, [
      0x80,
      0x80,
      0x80,
      0xFF,
    ]);

    await _show(
      tester,
      w,
      _params(pageSize: const ui.Size(200, 100), deviceScale: 12),
    );
    await _settle(tester);
    expect(w.requests.skip(1).where((r) => r.region != null), isNotEmpty);
    expect(_painter(tester).snapshot.tiles, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    await w.close();
  });

  testWidgets(
    'pinch: no request while isScaling, the new bucket 120 ms after',
    (tester) async {
      _ipad(tester);
      final w = _World();
      await _show(tester, w, _params());
      await _settle(tester);
      expect(w.requests, hasLength(1));
      await _show(tester, w, _params(deviceScale: 3.47, isScaling: true));
      await tester.pump(const Duration(seconds: 1));
      expect(w.requests, hasLength(1));
      await _show(tester, w, _params(deviceScale: 3.47));
      await tester.pump(const Duration(milliseconds: 110));
      expect(w.requests, hasLength(1));
      await tester.pump(const Duration(milliseconds: 20));
      await _settle(tester);
      expect(w.requests.length, greaterThan(1));
      await tester.pumpWidget(const SizedBox());
      await w.close();
    },
  );

  testWidgets('unmount: tiles released at once, the preview kept', (
    tester,
  ) async {
    _ipad(tester);
    final w = _World();
    await _show(
      tester,
      w,
      _params(
        deviceScale: 3.47,
        visible: const ui.Rect.fromLTWH(0, 0, 300, 300),
      ),
    );
    await _settle(tester);
    expect(w.service.stats.tileBytes, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    expect(w.service.stats.tileBytes, 0);
    expect(w.service.stats.previewBytes, greaterThan(0));
    await w.close();
  });

  testWidgets('loading indicator only after 300 ms', (tester) async {
    _ipad(tester);
    final w = _World()..hold = true;
    await _show(tester, w, _params());
    await tester.pump(const Duration(milliseconds: 290));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    w.releaseHeld();
    await _settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await w.close();
  });

  group('statuses (6.14 texts)', () {
    testWidgets('no fetcher → assetMissing, no request', (tester) async {
      _ipad(tester);
      final w = _World();
      await _show(tester, w, _params(assetId: 'nowhere'));
      await _settle(tester);
      expect(_painter(tester).snapshot.status, PdfRenderStatus.assetMissing);
      expect(_painter(tester).snapshot.remote, isNull);
      expect(find.text(PdfStringsKo.backgroundNoSource), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await w.close();
    });

    testWidgets('needsPassword and failed', (tester) async {
      _ipad(tester);
      final w = _World();
      w.engine.userPassword = 'pw';
      await _show(tester, w, _params());
      await _settle(tester);
      expect(find.text(PdfStringsKo.backgroundNeedsPassword), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await w.close();

      final failing = _World();
      failing.engine.renderError = StateError('render crashed');
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      try {
        await _show(tester, failing, _params());
        await _settle(tester);
      } finally {
        FlutterError.onError = previous;
      }
      expect(find.text(PdfStringsKo.backgroundRenderFailed), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(reports, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await failing.close();
    });

    testWidgets('thumbnail mode: icon only, no text', (tester) async {
      _ipad(tester);
      final w = _World();
      await _show(tester, w, _params(assetId: 'nowhere', isThumbnail: true));
      await _settle(tester);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await w.close();
    });
  });

  group('remote original (6.7.7)', () {
    testWidgets('request → downloading with progress → arrival → ready', (
      tester,
    ) async {
      _ipad(tester);
      final fetcher = FakeRemoteAssetFetcher();
      final w = _World(fetcher: fetcher);
      await _show(tester, w, _params(assetId: _remote));
      await _settle(tester);
      expect(fetcher.ensureLocalCalls, [_remote]);
      expect(fetcher.watchListenerCount(_remote), 1);
      expect(_painter(tester).snapshot.status, PdfRenderStatus.assetMissing);

      fetcher.emit(
        _remote,
        const core.RemoteAssetProgress(
          core.RemoteAssetState.downloading,
          received: 25,
          total: 100,
        ),
      );
      await _settle(tester);
      expect(_painter(tester).snapshot.status, PdfRenderStatus.downloading);
      expect(find.text(PdfStringsKo.backgroundDownloading(25)), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.25,
      );
      expect(find.byIcon(Icons.cloud_download_outlined), findsOneWidget);

      fetcher.emit(
        _remote,
        const core.RemoteAssetProgress(core.RemoteAssetState.waiting),
      );
      await _settle(tester);
      expect(find.text(PdfStringsKo.backgroundWaiting), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );

      w.gateway.arriveBytes(_remote, _pdf());
      await _settle(tester);
      expect(_painter(tester).snapshot.status, PdfRenderStatus.ready);
      expect(find.byType(Text), findsNothing);
      expect(fetcher.watchListenerCount(_remote), 0);
      expect(w.requests, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await w.close();
    });

    testWidgets('download without a known size: no percentage', (tester) async {
      _ipad(tester);
      final fetcher = FakeRemoteAssetFetcher();
      final w = _World(fetcher: fetcher);
      await _show(tester, w, _params(assetId: _remote));
      await _settle(tester);
      fetcher.emit(
        _remote,
        const core.RemoteAssetProgress(
          core.RemoteAssetState.downloading,
          received: 25,
        ),
      );
      await _settle(tester);
      expect(
        find.text(PdfStringsKo.backgroundDownloading(null)),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await w.close();
    });

    testWidgets('offline and failed texts; unavailable = no source', (
      tester,
    ) async {
      _ipad(tester);
      final fetcher = FakeRemoteAssetFetcher();
      final w = _World(fetcher: fetcher);
      await _show(tester, w, _params(assetId: _remote));
      await _settle(tester);
      for (final (state, text) in [
        (core.RemoteAssetState.offline, PdfStringsKo.backgroundOffline),
        (core.RemoteAssetState.failed, PdfStringsKo.backgroundDownloadFailed),
        (core.RemoteAssetState.unavailable, PdfStringsKo.backgroundNoSource),
      ]) {
        fetcher.emit(_remote, core.RemoteAssetProgress(state));
        await _settle(tester);
        expect(_painter(tester).snapshot.status, PdfRenderStatus.assetMissing);
        expect(_painter(tester).snapshot.remote?.state, state);
        expect(find.text(text), findsOneWidget, reason: state.name);
      }
      await tester.pumpWidget(const SizedBox());
      await w.close();
    });

    testWidgets('fetcher reports local → opened again (once)', (tester) async {
      _ipad(tester);
      final fetcher = FakeRemoteAssetFetcher();
      final w = _World(fetcher: fetcher);
      await _show(tester, w, _params(assetId: _remote));
      await _settle(tester);
      int reads() => w.gateway.calls.where((c) => c == 'readAssetBytes').length;
      expect(reads(), 1);
      // After the pool's 2 s failure memo: local, but the bytes are still unreadable → one
      // more open, then it stays missing (the shared watch replays `local` to the new
      // listener — no loop).
      await tester.pump(const Duration(seconds: 3));
      fetcher.emit(
        _remote,
        const core.RemoteAssetProgress(core.RemoteAssetState.local),
      );
      await _settle(tester);
      expect(reads(), 2);
      await tester.pump(const Duration(seconds: 10));
      await _settle(tester);
      expect(reads(), 2);
      expect(_painter(tester).snapshot.status, PdfRenderStatus.assetMissing);
      // The bytes arrive: opened and drawn.
      w.gateway.arriveBytes(_remote, _pdf());
      await _settle(tester);
      expect(_painter(tester).snapshot.status, PdfRenderStatus.ready);
      await tester.pumpWidget(const SizedBox());
      await w.close();
    });

    testWidgets('unmount cancels the remote watch', (tester) async {
      _ipad(tester);
      final fetcher = FakeRemoteAssetFetcher();
      final w = _World(fetcher: fetcher);
      await _show(tester, w, _params(assetId: _remote, isThumbnail: true));
      await _settle(tester);
      expect(fetcher.ensureLocalCalls, [
        _remote,
      ], reason: 'thumbnail handles ask too');
      expect(fetcher.watchListenerCount(_remote), 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(fetcher.watchListenerCount(_remote), 0);
      await w.close();
    });
  });

  testWidgets('search highlights: rectsFor(pageId) + current hit', (
    tester,
  ) async {
    _ipad(tester);
    final w = _World();
    const rect1 = ui.Rect.fromLTWH(10, 10, 50, 20);
    const rect2 = ui.Rect.fromLTWH(10, 40, 50, 20);
    PdfSearchHit hit(String pageId, ui.Rect rect) => PdfSearchHit(
      pageId: pageId,
      notePageNumber: 1,
      assetId: _asset,
      pdfPageIndex: 0,
      rects: [rect],
      snippet: 'x',
      matchStart: 0,
      matchLength: 1,
    );
    final highlights = ValueNotifier(
      PdfSearchState(
        query: 'x',
        status: PdfSearchStatus.done,
        hits: [hit('p1', rect1), hit('p2', rect2), hit('p1', rect2)],
        currentIndex: 0,
      ),
    );
    addTearDown(highlights.dispose);
    await _show(tester, w, _params(), highlights: highlights);
    await _settle(tester);
    var painter = _painter(tester);
    expect(painter.highlightRects, [rect1, rect2]);
    expect(painter.currentRects, [rect1]);

    highlights.value = PdfSearchState(
      query: 'x',
      status: PdfSearchStatus.done,
      hits: [hit('p1', rect1), hit('p2', rect2), hit('p1', rect2)],
      currentIndex: 1,
    );
    await tester.pump();
    painter = _painter(tester);
    expect(painter.currentRects, isEmpty, reason: 'the current hit is on p2');

    highlights.value = PdfSearchState.idle;
    await tester.pump();
    expect(_painter(tester).highlightRects, isEmpty);

    // Highlight pixels: PdfTuning.searchHighlightArgb over the gray PDF image.
    highlights.value = PdfSearchState(
      query: 'x',
      status: PdfSearchStatus.done,
      hits: [hit('p1', rect1)],
    );
    await tester.pump();
    final [inside, outside] = await _pixels(tester, [(30, 20), (300, 300)]);
    expect(outside, [0x80, 0x80, 0x80, 0xFF]);
    expect(inside, isNot(outside));
    await tester.pumpWidget(const SizedBox());
    await w.close();
  });
}
