// T12 (03-ink 8, M0): the M0 scenario end to end with the CORE fake store —
// a fake stylus pointer script (raw PointerEvents with rising pressure) goes
// through a Listener the way EDITOR wires it (InkSampleAdapter →
// beginStroke / addSample / end) on an empty page, the fountain-pen stroke is
// committed (toCommand → session.execute → pageChanges → updateContent), and
// the drawn width follows the pressure linearly: the stored widthQ and the
// on-screen thickness both fit a + b·pressure with the slope 6.7 K2 gives.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart' as core_testing;

import '../support/page_view.dart';

const _width = 10.0; // pt — wide enough to measure on screen
const _dpr = 2.0;
const _y = 200.0;
const _x0 = 60.0, _x1 = 540.0;
const _samples = 361; // 3 s at 120 Hz → 160 pt/s, below the K3 thinning speed
const _p0 = 0.15, _p1 = 0.95;

/// Raw pressure of the script at page x.
double _pressureAt(double x) => _p0 + (_p1 - _p0) * (x - _x0) / (_x1 - _x0);

/// Least-squares fit y = a + b·x; returns (a, b, r²).
(double, double, double) _fit(List<double> xs, List<double> ys) {
  final n = xs.length;
  final mx = xs.reduce((a, b) => a + b) / n;
  final my = ys.reduce((a, b) => a + b) / n;
  var sxx = 0.0, sxy = 0.0, syy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (xs[i] - mx) * (xs[i] - mx);
    sxy += (xs[i] - mx) * (ys[i] - my);
    syy += (ys[i] - my) * (ys[i] - my);
  }
  final b = sxy / sxx;
  return (my - b * mx, b, sxy * sxy / (sxx * syy));
}

void main() {
  late core.NoteStore store;
  late core.NoteSession session;
  late String pageId;
  late InkPageController controller;
  late StreamSubscription<core.PageContentChange> sub;
  final style = core.StrokeStyle.defaultsFor(core.PenTool.fountain)
      .copyWith(colorArgb: 0xFF000000, width: _width);

  InkPageContent inkContentOf(core.PageContent c) => InkPageContent.fromCore(
    page: c.page,
    strokes: c.strokes,
    revision: c.revision,
  );

  setUp(() async {
    store = core_testing.createFakeNoteStore();
    final note = await store.library.createNote(title: 'M0');
    session = await store.openSession(note.id);
    pageId = session.pages.single.id;
    final loaded = await session.openPage(pageId);
    controller = createTestPageController(
      pageId: pageId,
      services: testInkCoreServices(idPrefix: 'ink'),
    )..updateContent(inkContentOf(loaded));
    // EDITOR's commit wiring (contract 7.2.15 '커밋 인계')
    sub = session
        .pageChanges(pageId)
        .listen((c) => controller.updateContent(inkContentOf(c.content)));
  });

  tearDown(() async {
    await sub.cancel();
    controller.dispose();
    await session.close();
    await store.close();
  });

  /// EDITOR's pen wiring around InkPageView: page pt = local px / viewScale.
  Widget penPage(double viewScale) {
    StrokeSession? stroke;
    InkSample sampleOf(PointerEvent e) => InkSampleAdapter.fromPointerEvent(
      e,
      pagePosition: e.localPosition / viewScale,
    );
    return Listener(
      onPointerDown: (e) => stroke = controller.beginStroke(
        sampleOf(e),
        style: style,
        viewScale: viewScale,
      ),
      onPointerMove: (e) => stroke?.addSample(sampleOf(e)),
      onPointerUp: (e) {
        final edit = stroke?.end(sampleOf(e));
        stroke = null;
        if (edit != null) session.execute(edit.toCommand());
      },
      child: InkPageView(controller: controller),
    );
  }

  testWidgets('stylus script → fountain stroke → commit → width ∝ pressure', (
    tester,
  ) async {
    final pageWidth = controller.content!.pageSize.width;
    const viewScale = 1.0;
    tester.view
      ..devicePixelRatio = _dpr
      ..physicalSize = const Size(620, 880) * _dpr;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: pageViewKey,
            child: SizedBox(
              width: pageWidth * viewScale,
              child: penPage(viewScale),
            ),
          ),
        ),
      ),
    );
    final empty = await capturePixels(tester);
    for (var x = 0; x < empty.width; x += 37) {
      for (var y = 0; y < empty.height; y += 41) {
        expect(empty.at(x, y), [255, 255, 255, 255], reason: 'empty page');
      }
    }

    // the fake pointer script: one stylus, 120 Hz, pressure rising 0.15 → 0.95
    final origin = tester.getTopLeft(find.byType(InkPageView));
    PointerEvent event(int i, {bool down = false, bool up = false}) {
      final x = _x0 + (_x1 - _x0) * i / (_samples - 1);
      final position = origin + Offset(x, _y) * viewScale;
      final time = Duration(microseconds: (i * 1000000 / 120).round());
      if (down) {
        return PointerDownEvent(
          timeStamp: time,
          pointer: 7,
          kind: PointerDeviceKind.stylus,
          position: position,
          pressure: _pressureAt(x),
          pressureMin: 0,
          pressureMax: 1,
        );
      }
      if (up) {
        return PointerUpEvent(
          timeStamp: time,
          pointer: 7,
          kind: PointerDeviceKind.stylus,
          position: position,
          pressureMin: 0,
          pressureMax: 1,
        );
      }
      return PointerMoveEvent(
        timeStamp: time,
        pointer: 7,
        kind: PointerDeviceKind.stylus,
        position: position,
        pressure: _pressureAt(x),
        pressureMin: 0,
        pressureMax: 1,
        buttons: kPrimaryStylusButton,
      );
    }

    await tester.sendEventToBinding(event(0, down: true));
    for (var i = 1; i < _samples - 1; i++) {
      await tester.sendEventToBinding(event(i));
      if (i % 60 == 0) await tester.pump();
    }
    expect(controller.activeSession, isA<StrokeSession>());
    await tester.sendEventToBinding(event(_samples - 1, up: true));
    await tester.pump();

    // committed through CORE: one fountain stroke, nothing pending
    expect(controller.activeSession, isNull);
    expect(controller.pendingIds, isEmpty);
    final committed = session.pageIfLoaded(pageId)!.strokes;
    expect(committed, hasLength(1));
    final stroke = committed.single;
    expect(stroke.style.tool, core.PenTool.fountain);
    expect(stroke.id, startsWith('ink-'));
    expect(controller.content!.strokes.single.id, stroke.id);

    // stored width: widthQ = f / 4 with f = 1 + 0.75·(2p − 1) (6.7 K2, fountain,
    // linear curve, sensitivity 1) → slope 0.375 per unit pressure. Real
    // pressure smoothing only shifts it by a constant lag on a ramp.
    final pts = stroke.points;
    for (var i = 1; i < pts.length; i++) {
      expect(
        pts.x(i),
        greaterThanOrEqualTo(pts.x(i - 1)),
        reason: 'left → right',
      );
    }
    // widthQ at page x, linear between the stored (simplified, F7) points
    double qAt(double x) {
      for (var k = 0; k + 1 < pts.length; k++) {
        final xa = pts.x(k), xb = pts.x(k + 1);
        if (x >= xa && x <= xb) {
          final t = xb > xa ? (x - xa) / (xb - xa) : 0.0;
          return pts.widthQ(k) + (pts.widthQ(k + 1) - pts.widthQ(k)) * t;
        }
      }
      fail('x $x is not on the stroke');
    }

    final ps = <double>[], qs = <double>[];
    for (var x = 120.0; x <= 470; x += 10) {
      // away from both tapers
      ps.add(_pressureAt(x));
      qs.add(qAt(x));
    }
    final (_, slopeQ, r2Q) = _fit(ps, qs);
    expect(r2Q, greaterThan(0.99));
    expect(slopeQ, closeTo(0.375, 0.375 * 0.1));

    // on-screen thickness (device px summed coverage of black on white) at
    // columns along the stroke = width · f(p) · viewScale · dpr
    final shot = await capturePixels(tester);
    final xs = <double>[], thickness = <double>[];
    for (var x = 130.0; x <= 460; x += 15) {
      final col = ((origin.dx + x * viewScale) * _dpr).round();
      var coverage = 0.0;
      final yMid = ((origin.dy + _y * viewScale) * _dpr).round();
      for (var y = yMid - 60; y <= yMid + 60; y++) {
        coverage += (255 - shot.at(col, y)[0]) / 255;
      }
      xs.add(_pressureAt(x));
      thickness.add(coverage / _dpr / viewScale); // pt
    }
    for (var i = 1; i < thickness.length; i++) {
      expect(
        thickness[i],
        greaterThan(thickness[i - 1]),
        reason: 'thicker as the pressure rises',
      );
    }
    final (_, slopeT, r2T) = _fit(xs, thickness);
    expect(r2T, greaterThan(0.99));
    // diameter = 2 · radiusAt = 4 · width · widthQ → slope 4 · 10 · 0.375 = 15 pt
    expect(slopeT, closeTo(4 * _width * slopeQ, 4 * _width * slopeQ * 0.08));
    // and each column matches the stored radius there
    for (var i = 0; i < xs.length; i++) {
      final x = 130.0 + 15 * i;
      final expected = 4 * _width * qAt(x);
      expect(
        thickness[i],
        closeTo(expected, math.max(0.6, expected * 0.06)),
        reason: 'x $x',
      );
    }
  });
}
