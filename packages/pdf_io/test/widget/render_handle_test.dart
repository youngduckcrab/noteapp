// PdfRenderService page handles (06-pdf 6.7.2–6.7.6; 8 T8) with FakePdfEngine,
// FakePdfNoteGateway and the real DefaultPdfDocumentPool: preview then tiles (visible first,
// then the 25% margin), no requests while pinching and 120 ms after, older-bucket tiles kept
// until the new ones cover the visible area, releases after the frame, dispose (cancel,
// tiles released at once, preview kept), statuses (assetMissing / needsPassword / failed
// after one retry, reported), PdfPageFit placement and thumbnail mode. testWidgets: handles
// release images in post-frame callbacks.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/render/tile_math.dart';
import 'package:pdf_io/testing.dart';

const ui.Size _a4 = ui.Size(595.276, 841.89);
const String _asset = 'asset-a';

Uint8List _pdf() => Uint8List.fromList('%PDF-1.7\n% handle\n%%EOF\n'.codeUnits);

PdfBackgroundParams _params({
  String assetId = _asset,
  int pdfPageIndex = 0,
  ui.Size pageSize = _a4,
  double deviceScale = 1,
  ui.Rect? visible,
  bool isScaling = false,
  bool isThumbnail = false,
  int paper = 0xFFFFFFFF,
}) => PdfBackgroundParams(
  assetId: assetId,
  pdfPageIndex: pdfPageIndex,
  pageSize: pageSize,
  deviceScale: deviceScale,
  visiblePageRect: visible,
  isScaling: isScaling,
  isThumbnail: isThumbnail,
  paperColorArgb: paper,
);

final class _World {
  _World({FakePdfEngine? engine})
    : engine = engine ?? FakePdfEngine(pageCount: 2) {
    gateway.arriveBytes(_asset, _pdf());
    pool = DefaultPdfDocumentPool(engine: this.engine, gateway: gateway);
    service = PdfRenderService(
      pool: pool,
      budget: const PdfRenderBudget.web(),
      trimOnAppHidden: false,
    );
    this.engine.beforeRender = (request) async {
      if (!hold) return;
      final gate = Completer<void>();
      held.add(gate);
      await gate.future;
    };
  }

  final FakePdfEngine engine;
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
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

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

/// Collects FlutterError reports while [body] runs.
Future<List<FlutterErrorDetails>> _reports(Future<void> Function() body) async {
  final reports = <FlutterErrorDetails>[];
  final previous = FlutterError.onError;
  FlutterError.onError = reports.add;
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return reports;
}

void main() {
  testWidgets('attach: loading → preview → ready, base on the page box', (
    tester,
  ) async {
    final w = _World();
    final handle = w.service.attach(_params());
    expect(handle.snapshot.status, PdfRenderStatus.loading);
    var notified = 0;
    handle.addListener(() => notified++);
    await _settle(tester);

    final snapshot = handle.snapshot;
    expect(snapshot.status, PdfRenderStatus.ready);
    expect(notified, greaterThan(0));
    expect(w.requests, hasLength(1));
    final request = w.requests.single;
    expect(request.scale, 1.0);
    expect(request.region, isNull);
    expect(request.priority, PdfRenderPriority.high);
    expect(request.backgroundArgb, 0xFFFFFFFF);
    final base = snapshot.base!;
    expect((base.image.width, base.image.height), (596, 842));
    expect(base.srcRect, const ui.Rect.fromLTWH(0, 0, 596, 842));
    expect(base.pageRect, ui.Offset.zero & _a4);
    expect(snapshot.tiles, isEmpty);
    expect(snapshot.error, isNull);
    handle.dispose();
    await w.close();
  });

  testWidgets('zoomed in: preview at pv, then visible tiles, then the margin', (
    tester,
  ) async {
    final w = _World();
    final params = _params(
      deviceScale: 3.47,
      visible: const ui.Rect.fromLTWH(0, 0, 595.276, 400),
    );
    final plan = PdfRenderPlan.of(params, _a4);
    final handle = w.service.attach(params);
    await _settle(tester);

    expect(w.requests.first.region, isNull);
    expect(w.requests.first.scale, closeTo(1.2163, 1e-4));
    final tileRequests = w.requests.skip(1).toList();
    expect(tileRequests, hasLength(plan.tiles.length));
    final grid = plan.grid!;
    for (var i = 0; i < plan.tiles.length; i++) {
      final tile = plan.tiles[i];
      final request = tileRequests[i];
      expect(request.scale, grid.bucket);
      final expected = grid.requestRect(tile.column, tile.row);
      expect(
        (request.region!.left, request.region!.top),
        (expected.left, expected.top),
      );
      expect(
        (request.region!.width, request.region!.height),
        (expected.width, expected.height),
      );
      expect(
        request.priority,
        tile.prefetch ? PdfRenderPriority.low : PdfRenderPriority.high,
      );
    }
    final firstPrefetch = plan.tiles.indexWhere((t) => t.prefetch);
    expect(firstPrefetch, greaterThan(0));
    expect(plan.tiles.skip(firstPrefetch).every((t) => t.prefetch), isTrue);

    final snapshot = handle.snapshot;
    expect(snapshot.tiles, hasLength(plan.tiles.length));
    final first = snapshot.tiles.firstWhere(
      (t) => t.pageRect.topLeft == ui.Offset.zero,
    );
    expect(first.srcRect, const ui.Rect.fromLTWH(0, 0, 512, 512));
    expect(first.pageRect.width, closeTo(512 / grid.bucket, 1e-9));
    expect((first.image.width, first.image.height), (513, 513));
    handle.dispose();
    await w.close();
  });

  testWidgets(
    'no requests while pinching; the new bucket 120 ms after it ends',
    (tester) async {
      final w = _World();
      final handle = w.service.attach(_params());
      await _settle(tester);
      expect(w.requests, hasLength(1));
      final base = handle.snapshot.base!.image;

      const visible = ui.Rect.fromLTWH(0, 0, 300, 300);
      handle.update(
        _params(deviceScale: 2.5, visible: visible, isScaling: true),
      );
      await tester.pump(const Duration(seconds: 1));
      handle.update(
        _params(deviceScale: 3.47, visible: visible, isScaling: true),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(w.requests, hasLength(1), reason: 'no request while scaling');
      expect(identical(handle.snapshot.base!.image, base), isTrue);

      handle.update(_params(deviceScale: 3.47, visible: visible));
      await tester.pump(const Duration(milliseconds: 100));
      expect(w.requests, hasLength(1));
      // A change inside the 120 ms starts the wait again.
      handle.update(
        _params(
          deviceScale: 3.47,
          visible: const ui.Rect.fromLTWH(0, 0, 310, 300),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(w.requests, hasLength(1));
      await tester.pump(const Duration(milliseconds: 25));
      await _settle(tester);
      expect(w.requests.length, greaterThan(2));
      expect(w.requests[1].scale, closeTo(1.2163, 1e-4)); // new preview
      expect(w.requests[2].scale, closeTo(3.815, 1e-3)); // tiles
      expect(handle.snapshot.tiles, isNotEmpty);
      handle.dispose();
      await w.close();
    },
  );

  testWidgets('a page mounted during a pinch asks for its base only', (
    tester,
  ) async {
    final w = _World();
    final handle = w.service.attach(
      _params(deviceScale: 3.47, isScaling: true),
    );
    await _settle(tester);
    expect(w.requests, hasLength(1));
    expect(w.requests.single.region, isNull);
    expect(handle.snapshot.status, PdfRenderStatus.ready);

    handle.update(_params(deviceScale: 3.47));
    await tester.pump(const Duration(milliseconds: 130));
    await _settle(tester);
    expect(w.requests.length, greaterThan(1));
    expect(w.requests.skip(1).every((r) => r.region != null), isTrue);
    handle.dispose();
    await w.close();
  });

  testWidgets(
    'older-bucket tiles stay under the new ones until those cover the visible area',
    (tester) async {
      final w = _World();
      const visible = ui.Rect.fromLTWH(100, 100, 100, 100);
      final handle = w.service.attach(
        _params(deviceScale: 3.47, visible: visible),
      );
      await _settle(tester);
      final oldTiles = [for (final t in handle.snapshot.tiles) t.image];
      expect(oldTiles, isNotEmpty);

      w.hold = true;
      handle.update(_params(deviceScale: 6, visible: visible));
      await _settle(tester);
      final b2 = bucketScale(6);
      expect(w.requests.last.scale, b2);
      // Nothing of the new bucket yet: the old tiles are still drawn.
      expect([for (final t in handle.snapshot.tiles) t.image], oldTiles);

      w.releaseHeld();
      await _settle(tester);
      final now = handle.snapshot.tiles;
      expect(now, isNotEmpty);
      expect(now.every((t) => !oldTiles.contains(t.image)), isTrue);
      // The old tiles were released after the frame: unused now, so a trim drops them.
      w.service.trimMemory();
      expect(oldTiles.every((i) => i.debugDisposed), isTrue);
      expect(now.every((t) => !t.image.debugDisposed), isTrue);
      handle.dispose();
      await w.close();
    },
  );

  testWidgets('images that leave the snapshot are released after the frame', (
    tester,
  ) async {
    final w = _World();
    final handle = w.service.attach(
      _params(
        deviceScale: 3.47,
        visible: const ui.Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
    await _settle(tester);
    final tiles = [for (final t in handle.snapshot.tiles) t.image];
    expect(tiles, isNotEmpty);
    // Zoom out: no tiles any more.
    handle.update(_params());
    expect(handle.snapshot.tiles, isEmpty);
    w.service.trimMemory(); // same frame: still referenced
    expect(tiles.any((i) => i.debugDisposed), isFalse);
    await tester.pump();
    w.service.trimMemory();
    expect(tiles.every((i) => i.debugDisposed), isTrue);
    handle.dispose();
    await w.close();
  });

  testWidgets('dispose: tiles released at once, the preview stays in the LRU', (
    tester,
  ) async {
    final w = _World();
    final handle = w.service.attach(
      _params(
        deviceScale: 3.47,
        visible: const ui.Rect.fromLTWH(0, 0, 200, 200),
      ),
    );
    await _settle(tester);
    final tiles = [for (final t in handle.snapshot.tiles) t.image];
    final preview = handle.snapshot.base!.image;
    expect(tiles, isNotEmpty);
    handle.dispose();
    expect(tiles.every((i) => i.debugDisposed), isTrue);
    expect(preview.debugDisposed, isFalse);
    expect(w.service.stats.tileBytes, 0);
    expect(w.service.stats.previewBytes, preview.width * preview.height * 4);

    // Mounting the page again shows the cached preview without a render.
    final count = w.requests.length;
    final again = w.service.attach(_params());
    await _settle(tester);
    expect(w.requests.length, count + 1, reason: 'preview at scale 1 is new');
    again.dispose();
    final third = w.service.attach(
      _params(deviceScale: 3.47, visible: const ui.Rect.fromLTWH(0, 0, 1, 1)),
    );
    await _settle(tester);
    expect(identical(third.snapshot.base!.image, preview), isTrue);
    third.dispose();
    await w.close();
  });

  testWidgets('dispose cancels queued and running renders', (tester) async {
    final w = _World()..hold = true;
    final handle = w.service.attach(
      _params(
        deviceScale: 3.47,
        visible: const ui.Rect.fromLTWH(0, 0, 595, 600),
      ),
    );
    await _settle(tester);
    expect(w.service.stats.inflight, 2);
    expect(w.service.stats.queued, greaterThan(0));
    handle.dispose();
    await tester.pump();
    expect(w.service.stats.queued, 0);
    w.releaseHeld();
    await _settle(tester);
    final stats = w.service.stats;
    expect(stats.inflight, 0);
    expect(stats.rendered, 0, reason: 'late images are disposed');
    expect(stats.cancelled, greaterThan(2));
    expect(stats.liveImages, 0);
    expect(w.requests, hasLength(2), reason: 'queued renders never started');
    await w.close();
  });

  group('statuses', () {
    testWidgets('missing original → assetMissing (not reported)', (
      tester,
    ) async {
      final w = _World();
      late PdfPageRenderHandle handle;
      final reports = await _reports(() async {
        handle = w.service.attach(_params(assetId: 'nowhere'));
        await _settle(tester);
      });
      expect(handle.snapshot.status, PdfRenderStatus.assetMissing);
      expect(handle.snapshot.error?.code, PdfErrorCode.assetMissing);
      expect(handle.snapshot.base, isNull);
      expect(reports, isEmpty);
      handle.dispose();
      await w.close();
    });

    testWidgets('user password → needsPassword (not reported)', (tester) async {
      final w = _World(engine: FakePdfEngine(userPassword: 'pw'));
      late PdfPageRenderHandle handle;
      final reports = await _reports(() async {
        handle = w.service.attach(_params());
        await _settle(tester);
      });
      expect(handle.snapshot.status, PdfRenderStatus.needsPassword);
      expect(reports, isEmpty);
      handle.dispose();
      await w.close();
    });

    testWidgets(
      'engine error on open → one retry after 2 s → failed, reported',
      (tester) async {
        final w = _World();
        w.engine.openError = const PdfIoException(
          PdfErrorCode.corrupt,
          detail: 'broken xref',
        );
        late PdfPageRenderHandle handle;
        final reports = await _reports(() async {
          handle = w.service.attach(_params());
          await _settle(tester);
          expect(handle.snapshot.status, PdfRenderStatus.loading);
          expect(w.engine.openCalls, hasLength(1));
          await tester.pump(const Duration(milliseconds: 2100));
          await _settle(tester);
        });
        expect(w.engine.openCalls, hasLength(2));
        expect(handle.snapshot.status, PdfRenderStatus.failed);
        expect(handle.snapshot.error?.code, PdfErrorCode.corrupt);
        expect(reports, hasLength(1));
        expect(reports.single.library, 'pdf_io');
        handle.dispose();
        await w.close();
      },
    );

    testWidgets(
      'engine error on open, retry succeeds → ready, nothing reported',
      (tester) async {
        final w = _World();
        w.engine.openError = const PdfIoException(PdfErrorCode.corrupt);
        late PdfPageRenderHandle handle;
        final reports = await _reports(() async {
          handle = w.service.attach(_params());
          await _settle(tester);
          w.engine.openError = null;
          await tester.pump(const Duration(milliseconds: 2100));
          await _settle(tester);
        });
        expect(handle.snapshot.status, PdfRenderStatus.ready);
        expect(reports, isEmpty);
        handle.dispose();
        await w.close();
      },
    );

    testWidgets('render error → one retry → failed, reported', (tester) async {
      final w = _World();
      w.engine.renderError = StateError('render crashed');
      late PdfPageRenderHandle handle;
      final reports = await _reports(() async {
        handle = w.service.attach(_params());
        await _settle(tester);
      });
      expect(w.requests, hasLength(2));
      expect(handle.snapshot.status, PdfRenderStatus.failed);
      expect(handle.snapshot.error?.code, PdfErrorCode.corrupt);
      expect(reports, hasLength(1));
      handle.dispose();
      await w.close();
    });

    testWidgets('render error once → the retry draws the page', (tester) async {
      final w = _World();
      w.engine.renderError = StateError('flaky');
      var calls = 0;
      w.engine.beforeRender = (request) async {
        if (calls++ == 1) w.engine.renderError = null;
      };
      late PdfPageRenderHandle handle;
      final reports = await _reports(() async {
        handle = w.service.attach(_params());
        await _settle(tester);
      });
      expect(handle.snapshot.status, PdfRenderStatus.ready);
      expect(reports, isEmpty);
      handle.dispose();
      await w.close();
    });

    testWidgets('page index out of range → failed', (tester) async {
      final w = _World();
      late PdfPageRenderHandle handle;
      final reports = await _reports(() async {
        handle = w.service.attach(_params(pdfPageIndex: 7));
        await _settle(tester);
      });
      expect(handle.snapshot.status, PdfRenderStatus.failed);
      expect(w.requests, isEmpty);
      expect(reports, hasLength(1));
      handle.dispose();
      await w.close();
    });
  });

  testWidgets('s ≠ 1: the PDF is drawn in its PdfPageFit box (letterbox)', (
    tester,
  ) async {
    final w = _World(engine: FakePdfEngine(pageSize: const ui.Size(612, 792)));
    final handle = w.service.attach(_params());
    await _settle(tester);
    final fit = PdfPageFit(
      notePageSize: _a4,
      pdfPageSize: const ui.Size(612, 792),
    );
    final base = handle.snapshot.base!;
    expect(base.pageRect.top, closeTo(fit.oy, 1e-9));
    expect(base.pageRect, fit.pdfBoxInNote);
    // s = deviceScale × k ≈ 0.973 → bucket 1.0.
    expect(w.requests.single.scale, 1.0);
    handle.dispose();
    await w.close();
  });

  testWidgets('thumbnail mode: one image, long side 256 px', (tester) async {
    final w = _World();
    final handle = w.service.attach(_params(deviceScale: 4, isThumbnail: true));
    await _settle(tester);
    expect(w.requests, hasLength(1));
    final image = handle.snapshot.base!.image;
    expect(math.max(image.width, image.height), 256);
    expect(w.requests.single.priority, PdfRenderPriority.normal);
    expect(w.service.stats.thumbnailBytes, image.width * image.height * 4);
    handle.dispose();
    await w.close();
  });

  testWidgets('another page in the same handle starts over', (tester) async {
    final w = _World();
    final handle = w.service.attach(_params());
    await _settle(tester);
    handle.update(_params(pdfPageIndex: 1));
    expect(handle.snapshot.status, PdfRenderStatus.loading);
    await _settle(tester);
    expect(handle.snapshot.status, PdfRenderStatus.ready);
    expect(w.requests.last.pageIndex, 1);
    expect(w.engine.openCalls, hasLength(1), reason: 'same document');
    handle.dispose();
    await w.close();
  });

  testWidgets('renders on the opaque paper color; paper is part of the key', (
    tester,
  ) async {
    final w = _World();
    final ivory = w.service.attach(_params(paper: 0x80FBF7EC));
    await _settle(tester);
    expect(w.requests.single.backgroundArgb, 0xFFFBF7EC);
    final white = w.service.attach(_params());
    await _settle(tester);
    expect(w.requests, hasLength(2));
    expect(w.requests.last.backgroundArgb, 0xFFFFFFFF);
    final again = w.service.attach(_params(paper: 0x80FBF7EC));
    await _settle(tester);
    expect(w.requests, hasLength(2), reason: 'cached');
    expect(
      identical(again.snapshot.base!.image, ivory.snapshot.base!.image),
      isTrue,
    );
    for (final h in [ivory, white, again]) {
      h.dispose();
    }
    await w.close();
  });

  testWidgets('renderThumbnail: caller-owned image, never cached', (
    tester,
  ) async {
    final w = _World();
    final image = await w.service.renderThumbnail(
      assetId: _asset,
      pdfPageIndex: 0,
      longSidePx: 512,
    );
    expect(image, isNotNull);
    expect(math.max(image!.width, image.height), 512);
    expect(w.service.stats.liveImages, 0);
    image.dispose();
    expect(
      await w.service.renderThumbnail(
        assetId: 'nowhere',
        pdfPageIndex: 0,
        longSidePx: 64,
      ),
      isNull,
    );
    await w.close();
  });
}
