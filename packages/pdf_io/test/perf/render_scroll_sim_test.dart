// Performance simulation (06-pdf 8 T18, 6.7, iPad checks U5 · U16): scrolling a 500-page
// PDF note on an iPad Pro 13" (1032 × 1376 logical px, DPR 2, page width fitted → device
// scale ≈ 3.47, 35 tiles per A4 page) with the real PdfRenderService, document pool, render
// queue and cache on the web budget (PdfRenderBudget.web(): 24 / 64 / 16 MiB = 104 MiB — 2차 D22).
// The EDITOR side is modelled like contract E-2: the visible pages ± 1 have a page handle
// (off-screen neighbours with an empty visible rect), the page panel keeps thumbnail handles
// for the current page ± 6. FakePdfEngine renders with a latency (fake time).
//
// Phases: reading scroll (60 pages), fling to the end, five jumps start ↔ end (U5), reading
// back 30 pages. Checked at every frame: each kind within its budget, the cache total
// ≤ 104 MiB and nothing in use over budget (overBudgetBytes == 0, U16); every render that
// reaches the engine is for a page that has a handle at that moment. Over the run: render
// requests ≤ page visits × (1 preview + the 35 tiles of a page), thumbnail requests ≤
// thumbnail visits.
//
// perf tag (skipped by default): `flutter test --run-skipped -t perf
// test/perf/render_scroll_sim_test.dart`. No wall-clock assertion (fake time).
@Tags(['perf'])
@TestOn('vm')
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_io/pdf_io.dart';
import 'package:pdf_io/src/render/tile_math.dart';
import 'package:pdf_io/testing.dart';

const ui.Size _a4 = ui.Size(595.276, 841.89);
const int _pages = 500;
const String _asset = 'lecture-500';

const ui.Size _viewport = ui.Size(
  1032,
  1376,
); // iPad Pro 13" portrait (logical px)
const double _dpr = 2;
const double _gap = 16; // logical px between pages
const int _thumbnailRadius = 6; // page panel: current page ± 6

const Duration _frame = Duration(milliseconds: 16);
const Duration _previewLatency = Duration(milliseconds: 30);
const Duration _tileLatency = Duration(milliseconds: 12);
const Duration _thumbnailLatency = Duration(milliseconds: 8);

const PdfRenderBudget _budget = PdfRenderBudget.web();

final double _viewScale = _viewport.width / _a4.width; // ≈ 1.734
final double _deviceScale = _viewScale * _dpr; // ≈ 3.47
final double _pageHeightPx = _a4.height * _viewScale;
final double _pitch = _pageHeightPx + _gap;
final double _maxOffset = _pages * _pitch - _gap - _viewport.height;

/// Tiles of one A4 page at the bucket of [_deviceScale] (5 × 7 = 35).
final int _tilesPerPage = PdfTileGrid(_a4, bucketScale(_deviceScale)).tileCount;

final class _Sim {
  _Sim() {
    gateway.arriveBytes(
      _asset,
      Uint8List.fromList('%PDF-1.7\n% scroll\n%%EOF\n'.codeUnits),
    );
    pool = DefaultPdfDocumentPool(engine: engine, gateway: gateway);
    service = PdfRenderService(
      pool: pool,
      budget: _budget,
      trimOnAppHidden: false,
    );
    engine.beforeRender = (request) {
      final mounted =
          request.scale <
              0.5 // thumbnails: 256 px long side
          ? _thumbnails.containsKey(request.pageIndex)
          : _main.containsKey(request.pageIndex);
      if (!mounted) {
        violations.add(
          'frame $frames: render of unmounted ${request.pageIndex}',
        );
      }
      return Future<void>.delayed(
        request.scale < 0.5
            ? _thumbnailLatency
            : request.region == null
            ? _previewLatency
            : _tileLatency,
      );
    };
  }

  final FakePdfEngine engine = FakePdfEngine(pageCount: _pages, pageSize: _a4);
  final FakePdfNoteGateway gateway = FakePdfNoteGateway();
  late final DefaultPdfDocumentPool pool;
  late final PdfRenderService service;

  final Map<int, PdfPageRenderHandle> _main = {};
  final Map<int, PdfPageRenderHandle> _thumbnails = {};
  Set<int> _visible = {};
  Set<int> _thumbnailPages = {};

  int frames = 0;
  int pageVisits = 0; // a page becoming visible (again)
  int thumbnailVisits = 0; // a thumbnail handle attached
  final List<String> violations = [];
  PdfRenderStats peak = PdfRenderStats.zero;
  int peakTotal = 0;

  /// One frame at scroll [offset] (logical px from the top of page 1).
  Future<void> frame(WidgetTester tester, double offset) async {
    _layout(offset.clamp(0, _maxOffset));
    await tester.pump(_frame);
    frames++;
    _check();
  }

  /// [count] frames moving by [step] px per frame from [from]; returns the last offset.
  Future<double> scroll(
    WidgetTester tester, {
    required double from,
    required double step,
    required int count,
  }) async {
    var offset = from;
    for (var i = 0; i < count; i++) {
      offset = (offset + step).clamp(0, _maxOffset);
      await frame(tester, offset);
    }
    return offset;
  }

  /// [count] frames standing still at [offset] (renders finish).
  Future<void> dwell(WidgetTester tester, double offset, int count) async {
    for (var i = 0; i < count; i++) {
      await frame(tester, offset);
    }
  }

  void _layout(double offset) {
    final top = offset, bottom = offset + _viewport.height;
    final visible = <int, ui.Rect>{};
    for (var p = (top / _pitch).floor(); p < _pages; p++) {
      final pageTop = p * _pitch;
      if (pageTop >= bottom) break;
      if (pageTop + _pageHeightPx <= top) continue;
      visible[p] = ui.Rect.fromLTRB(
        0,
        math.max(0, (top - pageTop) / _viewScale),
        _a4.width,
        math.min(_a4.height, (bottom - pageTop) / _viewScale),
      );
    }
    for (final p in visible.keys) {
      if (!_visible.contains(p)) pageVisits++;
    }
    _visible = visible.keys.toSet();

    // Main view: visible ± 1 (contract E-2), off-screen neighbours see nothing.
    final first = visible.keys.reduce(math.min);
    final last = visible.keys.reduce(math.max);
    final mounted = <int, ui.Rect>{
      for (
        var p = math.max(0, first - 1);
        p <= math.min(_pages - 1, last + 1);
        p++
      )
        p: visible[p] ?? ui.Rect.zero,
    };
    _sync(_main, {
      for (final MapEntry(key: p, value: rect) in mounted.entries)
        p: _params(p, visibleRect: rect),
    });

    // Page panel: thumbnails of the current page ± 6.
    final thumbnails = {
      for (
        var p = math.max(0, first - _thumbnailRadius);
        p <= math.min(_pages - 1, first + _thumbnailRadius);
        p++
      )
        p,
    };
    thumbnailVisits += thumbnails.difference(_thumbnailPages).length;
    _thumbnailPages = thumbnails;
    _sync(_thumbnails, {
      for (final p in thumbnails) p: _params(p, thumbnail: true),
    });
  }

  void _sync(
    Map<int, PdfPageRenderHandle> handles,
    Map<int, PdfBackgroundParams> wanted,
  ) {
    for (final p in handles.keys.toList()) {
      if (!wanted.containsKey(p)) handles.remove(p)!.dispose();
    }
    for (final MapEntry(key: p, value: params) in wanted.entries) {
      final handle = handles[p];
      if (handle == null) {
        handles[p] = service.attach(params);
      } else {
        handle.update(params);
      }
    }
  }

  static PdfBackgroundParams _params(
    int page, {
    ui.Rect? visibleRect,
    bool thumbnail = false,
  }) => PdfBackgroundParams(
    assetId: _asset,
    pdfPageIndex: page,
    pageSize: _a4,
    deviceScale: thumbnail ? 0.5 : _deviceScale,
    visiblePageRect: thumbnail ? null : visibleRect,
    isThumbnail: thumbnail,
    pageId: 'page-$page',
  );

  void _check() {
    final s = service.stats;
    final total = s.previewBytes + s.tileBytes + s.thumbnailBytes;
    if (s.previewBytes > _budget.previewBytes ||
        s.tileBytes > _budget.tileBytes ||
        s.thumbnailBytes > _budget.thumbnailBytes ||
        total > _budget.totalBytes ||
        s.overBudgetBytes != 0) {
      violations.add('frame $frames: over budget $s');
    }
    if (total > peakTotal) {
      peakTotal = total;
      peak = s;
    }
  }

  Future<void> close(WidgetTester tester) async {
    for (final handle in [..._main.values, ..._thumbnails.values]) {
      handle.dispose();
    }
    _main.clear();
    _thumbnails.clear();
    await tester.pump(const Duration(seconds: 1));
    await service.dispose();
    await pool.dispose();
  }
}

String _mib(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

void main() {
  testWidgets('500-page scroll on the web budget: ≤ 104 MiB, bounded requests', (
    tester,
  ) async {
    final sim = _Sim();
    final pageScreens = _pitch / _viewport.height;

    // 1. Reading: 60 pages at 40 px per frame (2 400 px/s), a short stop every page.
    var offset = 0.0;
    await sim.dwell(tester, offset, 10);
    for (var p = 0; p < 60; p++) {
      offset = await sim.scroll(
        tester,
        from: offset,
        step: 40,
        count: (_pitch / 40).round(),
      );
      await sim.dwell(tester, offset, 4);
    }
    // 2. Fling to the end at 400 px per frame (24 000 px/s).
    offset = await sim.scroll(
      tester,
      from: offset,
      step: 400,
      count: ((_maxOffset - offset) / 400).ceil(),
    );
    await sim.dwell(tester, offset, 20);
    // 3. Five jumps start ↔ end (scrubber), reading a little at each end (U5).
    for (var i = 0; i < 5; i++) {
      for (final target in [0.0, _maxOffset]) {
        await sim.dwell(tester, target, 10);
        await sim.scroll(
          tester,
          from: target,
          step: target == 0 ? 40 : -40,
          count: (pageScreens * _viewport.height / 40).round(),
        );
      }
    }
    // 4. Reading back 30 pages from the end at 80 px per frame.
    offset = _maxOffset;
    for (var p = 0; p < 30; p++) {
      offset = await sim.scroll(
        tester,
        from: offset,
        step: -80,
        count: (_pitch / 80).round(),
      );
      await sim.dwell(tester, offset, 4);
    }

    final requests = sim.engine.renderRequests;
    final thumbnailRequests = requests.where((r) => r.scale < 0.5).length;
    final pageRequests = requests.length - thumbnailRequests;
    final previews = requests
        .where((r) => r.scale >= 0.5 && r.region == null)
        .length;
    final stats = sim.service.stats;
    debugPrint(
      'perf scroll: ${sim.frames} frames, ${sim.pageVisits} page visits, '
      '${sim.thumbnailVisits} thumbnail visits; requests: $previews previews, '
      '${pageRequests - previews} tiles, $thumbnailRequests thumbnails '
      '(${stats.cancelled} cancelled); peak ${_mib(sim.peakTotal)} MiB '
      '(preview ${_mib(sim.peak.previewBytes)}, tile ${_mib(sim.peak.tileBytes)}, '
      'thumbnail ${_mib(sim.peak.thumbnailBytes)}), '
      'live images now ${stats.liveImages}',
    );

    expect(sim.violations, isEmpty);
    expect(_tilesPerPage, 35);
    expect(sim.peakTotal, lessThanOrEqualTo(_budget.totalBytes));
    expect(sim.peakTotal, greaterThan(0));
    expect(previews, greaterThan(0));
    expect(
      pageRequests,
      lessThanOrEqualTo(sim.pageVisits * (1 + _tilesPerPage)),
    );
    expect(thumbnailRequests, lessThanOrEqualTo(sim.thumbnailVisits));
    expect(stats.overBudgetBytes, 0);

    await sim.close(tester);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
