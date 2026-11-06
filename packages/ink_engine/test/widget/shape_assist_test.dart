// m5-7/03-ink 8.2 T39 (6.18, 6.1 layer 4′, K-9): automatic shape correction with
// FakeInkShapeFitter.
// - The preview is drawn at layer 4′ (the end of inkActive): over the ink items,
//   under the annotation layer (the glyph pixels of an overlapping text box do not
//   change) and under the cover layer (a covered tape's pixels do not change); the
//   committed result (pending, then in the content) is drawn at the same height —
//   the same pixels.
// - While the preview shows the live stroke is not drawn; moving again brings it
//   back (and drops the preview).
// - end() with a preview → InkEdit(addShape) → one AddObjects, no stroke; a null fit
//   → addStroke; highlighter, tape and laser never ask the fitter; a throwing fitter
//   keeps the stroke and warns shapeFitterThrew; the pen style maps to ShapeStyle
//   (dashed pen → LineDash.dashed).
// Pixel tests run in testWidgets (the hold timer is a fake timer, so the state does
// not change while tester.runAsync reads pixels).
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkPageRenderOf, liveObjectsOf;
import 'package:ink_engine/src/render/sessions.dart'
    show strokeSessionHoldOf, strokeSessionPreviewShape;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/pixels.dart';
import '../support/raster.dart';

const _pageId = 'p1';
const _white = 0xFFFFFFFF;
const _blue = 0xFF1E40C8;
const _red = 0xFFFF0000;
const _green = 0xFF00AA00;
const _tape = 0xFF7E57C2;

const _rect = core.PageRect(60, 50, 240, 250);
const _loopBounds = ui.Rect.fromLTRB(60, 50, 240, 250);

InkShapeFit _fitOf(core.PageRect r, {double score = 0.8}) => InkShapeFit(
  kind: core.ShapeKind.rectangle,
  geometry: core.ShapeGeometry.rectangle(r),
  score: score,
);

final class _ThrowingFitter implements InkShapeFitter {
  int calls = 0;

  @override
  InkShapeFit? fit(List<Offset> points, {required double viewScale}) {
    calls++;
    throw StateError('recognizer crashed');
  }
}

InkPageContent _content({
  List<core.Stroke> strokes = const [],
  List<core.PageObject> objects = const [],
  int revision = 1,
}) => InkPageContent.fromCore(
  page: SyntheticInk.page(
    pageId: _pageId,
    background: const core.BlankBackground(paperColorArgb: _white),
  ),
  strokes: strokes,
  objects: objects,
  revision: revision,
);

core.StrokeStyle _pen({
  core.PenTool tool = core.PenTool.ballpoint,
  int color = _blue,
  double width = 6,
}) =>
    core.StrokeStyle.defaultsFor(tool).copyWith(colorArgb: color, width: width);

/// The loop of SyntheticInk.loopThenHold (97 samples) and its hold part.
(List<InkSample>, List<InkSample>) _loopAndHold({int holdMs = 600}) {
  final all = SyntheticInk.loopThenHold(bounds: _loopBounds, holdMs: holdMs);
  return (all.take(97).toList(), all.skip(97).toList());
}

StrokeSession _begin(
  InkPageController c,
  InkSample first, {
  core.StrokeStyle? style,
  ShapeAssist assist = ShapeAssist.holdToSnap,
}) => c.beginStroke(
  first,
  style: style ?? _pen(),
  viewScale: 1,
  shapeAssist: assist,
);

/// [layers] (default all) of [c] over white, 1 px per pt, 300 × 300.
Future<Pixels> _pixels(
  WidgetTester tester,
  InkPageController c, {
  List<InkRenderLayer> layers = InkRenderLayer.values,
}) async => (await tester.runAsync(
  () => renderPixels(300, 300, (canvas) {
    paintPaper(canvas, _white);
    final render = inkPageRenderOf(c);
    for (final layer in layers) {
      render.paint(canvas, layer, 1);
    }
  }),
))!;

List<int> _rgba(int argb) => [
  (argb >> 16) & 0xFF,
  (argb >> 8) & 0xFF,
  argb & 0xFF,
  255,
];

bool _isPaper(List<int> p) => samePixel(p, _rgba(_white), tol: 2);

/// The point of the loop's ellipse at [deg] (not on the fitted rectangle).
(int, int) _onLoop(double deg) {
  final a = deg * 3.141592653589793 / 180;
  final c = _loopBounds.center;
  return (
    (c.dx + _loopBounds.width / 2 * _cos(a)).round(),
    (c.dy + _loopBounds.height / 2 * _sin(a)).round(),
  );
}

double _cos(double a) => ui.Offset.fromDirection(a).dx;
double _sin(double a) => ui.Offset.fromDirection(a).dy;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await InkFonts.ensureLoaded();
  });

  group('layer 4′ (6.1, K-9)', () {
    testWidgets('the preview is over the ink, under the text glyphs and the '
        'covered tape; the pending and committed shape draw the same pixels', (
      tester,
    ) async {
      final text = core.TextBoxObject(
        id: 'text',
        pageId: _pageId,
        frame: const core.ElementFrame(core.PageRect(40, 26, 280, 76)),
        text: 'HHH 가가가 HHH',
        style: const core.TextBoxStyle(fontSizePt: 32, colorArgb: _red),
        createdAt: 2,
      );
      final tape = strokeThrough(
        segment(const Offset(150, 20), const Offset(150, 280)),
        _pen(tool: core.PenTool.tape, color: _tape, width: 20),
        id: 'tape',
        createdAt: 1,
      );
      final ink = strokeThrough(
        segment(const Offset(30, 150), const Offset(270, 150)),
        _pen(color: _green, width: 10),
        id: 'ink',
        createdAt: 3,
      );
      final fitter = FakeInkShapeFitter(fit: _fitOf(_rect));
      final c = createTestPageController(shapeFitter: fitter)
        ..updateContent(_content(strokes: [tape, ink], objects: [text]));
      final base = await _pixels(tester, c);
      final (loop, hold) = _loopAndHold();
      final session = _begin(c, loop.first)
        ..addSamples(loop.skip(1))
        ..addSamples(hold);
      expect(session.shapePreview.value, _fitOf(_rect));
      expect(fitter.calls, 1);
      final preview = await _pixels(tester, c);

      // the glyphs: every pure text-color pixel of the box is unchanged
      var glyphs = 0;
      for (var y = 26; y < 76; y++) {
        for (var x = 40; x < 280; x++) {
          final p = base.at(x, y);
          if (!samePixel(p, _rgba(_red), tol: 2)) continue;
          glyphs++;
          expect(
            samePixel(preview.at(x, y), p, tol: 2),
            isTrue,
            reason: 'glyph ($x, $y)',
          );
        }
      }
      expect(glyphs, greaterThan(100));
      // … and the preview does run under the text row (y = 50) between glyphs
      var underText = 0;
      for (var x = 62; x < 238; x++) {
        if (samePixel(preview.at(x, 50), _rgba(_blue), tol: 24)) underText++;
      }
      expect(underText, greaterThan(10), reason: 'the top edge between glyphs');
      // the covered tape: its inside is unchanged where the edges cross it
      for (var y = 26; y <= 274; y++) {
        for (var x = 143; x <= 157; x++) {
          expect(
            samePixel(preview.at(x, y), base.at(x, y), tol: 1),
            isTrue,
            reason: 'tape ($x, $y)',
          );
        }
      }
      expect(samePixel(base.at(150, 250), _rgba(_tape), tol: 3), isTrue);
      // over the older ink stroke (the left edge crosses it at (60, 150))
      expect(samePixel(base.at(60, 150), _rgba(_green), tol: 3), isTrue);
      expect(samePixel(preview.at(60, 150), _rgba(_blue), tol: 3), isTrue);
      expect(samePixel(preview.at(240, 100), _rgba(_blue), tol: 3), isTrue);

      // pending (end) and committed: the same pixels as the preview
      final edit = session.end(hold.last)!;
      final shape = edit.addedObjects.single as core.ShapeObject;
      final pending = await _pixels(tester, c);
      expect(differingShare(preview, pending, tolerance: 2), 0);
      c.updateContent(
        _content(strokes: [tape, ink], objects: [text, shape], revision: 2),
      );
      expect(c.pendingIds, isEmpty);
      final committed = await _pixels(tester, c);
      expect(differingShare(preview, committed, tolerance: 2), 0);
      c.dispose();
    });

    testWidgets('the live stroke is not drawn while the preview shows; '
        'moving again drops the preview and the stroke is back', (
      tester,
    ) async {
      final fitter = FakeInkShapeFitter(fit: _fitOf(_rect));
      final c = createTestPageController(shapeFitter: fitter)
        ..updateContent(_content());
      const active = [InkRenderLayer.inkActive];
      final (loop, hold) = _loopAndHold();
      final session = _begin(c, loop.first)..addSamples(loop.skip(1));
      final (lx, ly) = _onLoop(45); // on the loop, off the rectangle
      // a corner of the rectangle, off the loop
      const cx = 61, cy = 51;

      final writing = await _pixels(tester, c, layers: active);
      expect(session.shapePreview.value, isNull);
      expect(_isPaper(writing.at(lx, ly)), isFalse, reason: 'the stroke');
      expect(_isPaper(writing.at(cx, cy)), isTrue);

      session.addSamples(hold);
      expect(session.shapePreview.value, isNotNull);
      final shown = await _pixels(tester, c, layers: active);
      expect(_isPaper(shown.at(lx, ly)), isTrue, reason: 'stroke hidden');
      expect(samePixel(shown.at(cx, cy), _rgba(_blue), tol: 24), isTrue);
      // nothing but the shape: every inked pixel is near the rectangle outline
      for (var y = 0; y < 300; y += 2) {
        for (var x = 0; x < 300; x += 2) {
          if (_isPaper(shown.at(x, y))) continue;
          final nearX = (x - 60).abs() <= 4 || (x - 240).abs() <= 4;
          final nearY = (y - 50).abs() <= 4 || (y - 250).abs() <= 4;
          expect(nearX || nearY, isTrue, reason: 'ink at ($x, $y)');
        }
      }

      // moving again (out of the 8 pt radius)
      final last = hold.last;
      session.addSample(
        last.copyWith(
          position: last.position + const Offset(30, 20),
          timeUs: last.timeUs + 8000,
        ),
      );
      expect(session.shapePreview.value, isNull);
      expect(strokeSessionPreviewShape(session), isNull);
      final back = await _pixels(tester, c, layers: active);
      expect(_isPaper(back.at(lx, ly)), isFalse, reason: 'the stroke again');
      expect(_isPaper(back.at(cx, cy)), isTrue, reason: 'no shape');
      final edit = session.end()!;
      expect(edit.kind, InkEditKind.addStroke);
      expect(edit.addedObjects, isEmpty);
      c.dispose();
    });
  });

  group('end() and the fitter', () {
    test('with a preview: addShape → AddObjects with one ShapeObject and no '
        'stroke; shown as pending until updateContent', () {
      final fit = _fitOf(_rect, score: 0.75);
      final fitter = FakeInkShapeFitter(fit: fit);
      final c = createTestPageController(
        shapeFitter: fitter,
        services: InkCoreServices(
          newStrokeId: () => 'shape-1',
          nowMillis: () => 4242,
        ),
      )..updateContent(_content());
      addTearDown(c.dispose);
      c.diagnostics.enabled = true;
      addTearDown(() => c.diagnostics.enabled = false);
      final samples = SyntheticInk.loopThenHold(bounds: _loopBounds);
      final session = _begin(c, samples.first)..addSamples(samples.skip(1));
      final previewShape = strokeSessionPreviewShape(session)!;
      final edit = session.end(samples.last)!;
      expect(session.isActive, isFalse);
      expect(session.shapePreview.value, isNull);
      expect(strokeSessionHoldOf(session)!.timerArmed, isFalse);
      expect(edit.kind, InkEditKind.addShape);
      expect(edit.pageId, _pageId);
      expect(edit.added, isEmpty, reason: 'the stroke is not saved');
      final shape = edit.addedObjects.single as core.ShapeObject;
      expect(shape.id, 'shape-1');
      expect(shape.pageId, _pageId);
      expect(shape.createdAt, 4242, reason: 'pen-down nowMillis');
      expect(shape.shapeKind, fit.kind);
      expect(shape.geometry, fit.geometry);
      expect(shape.style, previewShape.style);
      expect(previewShape.geometry, shape.geometry);
      final command = edit.toCommand();
      expect(command, isA<core.AddObjects>());
      final add = command as core.AddObjects;
      expect(add.pageId, _pageId);
      expect(add.objects, [same(shape)]);
      // pending: drawn by the live part until the content has it
      expect(c.pendingIds, {'shape-1'});
      expect(liveObjectsOf(c), [same(shape)]);
      c.updateContent(_content(objects: [shape], revision: 2));
      expect(c.pendingIds, isEmpty);
      expect(liveObjectsOf(c), isEmpty);
      final stats = c.diagnostics.shapeFitStats;
      expect(
        (stats.fits, stats.accepted, stats.lastKind, stats.lastScore),
        (1, 1, 'rectangle', 0.75),
      );
      expect(c.diagnostics.snapshot.warnings, 0);
    });

    test('a null fit → addStroke (the fitter was asked once, with the '
        'centerline so far)', () {
      final fitter = FakeInkShapeFitter();
      final c = createTestPageController(shapeFitter: fitter)
        ..updateContent(_content());
      addTearDown(c.dispose);
      final samples = SyntheticInk.loopThenHold(bounds: _loopBounds);
      final session = _begin(c, samples.first)..addSamples(samples.skip(1));
      expect(fitter.calls, 1);
      expect(fitter.received.single.length, greaterThan(90));
      expect(session.shapePreview.value, isNull);
      final edit = session.end(samples.last)!;
      expect(edit.kind, InkEditKind.addStroke);
      expect(edit.added, hasLength(1));
      expect(edit.addedObjects, isEmpty);
    });

    test('highlighter, tape and laser never ask the fitter (holdToSnap is '
        'ignored); off never asks it either', () {
      final fitter = FakeInkShapeFitter(fit: _fitOf(_rect));
      final c = createTestPageController(shapeFitter: fitter)
        ..updateContent(_content());
      addTearDown(c.dispose);
      final samples = SyntheticInk.loopThenHold(bounds: _loopBounds);
      for (final (tool, assist) in [
        (core.PenTool.highlighter, ShapeAssist.holdToSnap),
        (core.PenTool.tape, ShapeAssist.holdToSnap),
        (core.PenTool.laser, ShapeAssist.holdToSnap),
        (core.PenTool.ballpoint, ShapeAssist.off),
      ]) {
        final session = _begin(
          c,
          samples.first,
          style: core.StrokeStyle.defaultsFor(tool),
          assist: assist,
        )..addSamples(samples.skip(1));
        expect(session.shapeAssist, assist);
        expect(session.shapePreview.value, isNull, reason: tool.name);
        final edit = session.end(samples.last);
        if (tool == core.PenTool.laser) {
          expect(edit, isNull);
        } else {
          expect(edit!.kind, InkEditKind.addStroke, reason: tool.name);
        }
      }
      expect(fitter.calls, 0);
    });

    test('a throwing fitter: no shape, the stroke is kept; warning '
        'shapeFitterThrew for each hold, reported once', () {
      final fitter = _ThrowingFitter();
      final c = createTestPageController(shapeFitter: fitter)
        ..updateContent(_content());
      addTearDown(c.dispose);
      c.diagnostics.enabled = true;
      addTearDown(() => c.diagnostics.enabled = false);
      final reported = <FlutterErrorDetails>[];
      final onError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = onError);
      final samples = SyntheticInk.loopThenHold(bounds: _loopBounds);
      final session = _begin(c, samples.first)..addSamples(samples.skip(1));
      expect(fitter.calls, 1);
      expect(session.shapePreview.value, isNull);
      // move away and hold again: asked again, throws again
      final t = samples.last.timeUs;
      session
        ..addSample(
          samples.last.copyWith(
            position: const Offset(20, 20),
            timeUs: t + 8000,
          ),
        )
        ..addSample(
          samples.last.copyWith(
            position: const Offset(21, 20),
            timeUs: t + 508000,
          ),
        );
      expect(fitter.calls, 2);
      expect(c.diagnostics.snapshot.warnings, 2);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'ink_engine');
      expect(reported.single.exception, isA<StateError>());
      final edit = session.end()!;
      expect(edit.kind, InkEditKind.addStroke);
      expect(edit.added, hasLength(1));
    });

    test('moving again drops the preview, a new hold shows it again; cancel '
        'drops it with no edit', () {
      final fitter = FakeInkShapeFitter(fit: _fitOf(_rect));
      final c = createTestPageController(shapeFitter: fitter)
        ..updateContent(_content());
      addTearDown(c.dispose);
      c.diagnostics.enabled = true;
      addTearDown(() => c.diagnostics.enabled = false);
      final samples = SyntheticInk.loopThenHold(bounds: _loopBounds);
      final session = _begin(c, samples.first)..addSamples(samples.skip(1));
      expect(session.shapePreview.value, isNotNull);
      final t = samples.last.timeUs;
      InkSample at(Offset p, int dtMs) =>
          samples.last.copyWith(position: p, timeUs: t + dtMs * 1000);
      session.addSample(at(const Offset(260, 260), 8));
      expect(session.shapePreview.value, isNull);
      fitter.result = _fitOf(const core.PageRect(60, 50, 260, 260));
      session.addSample(at(const Offset(261, 261), 508));
      expect(fitter.calls, 2);
      expect(
        session.shapePreview.value,
        _fitOf(const core.PageRect(60, 50, 260, 260)),
      );
      session.cancel();
      expect(session.shapePreview.value, isNull);
      expect(strokeSessionHoldOf(session)!.timerArmed, isFalse);
      expect(c.pendingIds, isEmpty);
      final stats = c.diagnostics.shapeFitStats;
      expect((stats.fits, stats.accepted), (2, 0));
    });
  });

  group('style → ShapeStyle (6.18)', () {
    test('the pen color, width and opacity; the dashed pen → dashed, the '
        'other pens solid; no fill, no heads; normalized', () {
      final c = createTestPageController(
        shapeFitter: FakeInkShapeFitter(fit: _fitOf(_rect)),
      )..updateContent(_content());
      addTearDown(c.dispose);
      final samples = SyntheticInk.loopThenHold(bounds: _loopBounds);
      final tools = [
        for (final t in core.PenTool.values)
          if (t != core.PenTool.highlighter &&
              t != core.PenTool.laser &&
              t != core.PenTool.tape)
            t,
      ];
      expect(tools, hasLength(7));
      for (final tool in tools) {
        final style = core.StrokeStyle.defaultsFor(tool)
            .copyWith(colorArgb: 0xFF336699, width: 3.5, opacity: 0.6);
        final session = _begin(c, samples.first, style: style)
          ..addSamples(samples.skip(1));
        final s = session.style;
        final shape =
            session.end(samples.last)!.addedObjects.single as core.ShapeObject;
        expect(
          shape.style,
          core.ShapeStyle(
            strokeColorArgb: s.colorArgb,
            strokeWidth: s.width,
            strokeOpacity: s.opacity,
            dash: tool == core.PenTool.dashed
                ? core.LineDash.dashed
                : core.LineDash.solid,
          ).normalized(),
          reason: tool.name,
        );
        expect(shape.style.strokeColorArgb, 0xFF336699);
        expect(shape.style.strokeWidth, 3.5);
        expect(shape.style.strokeOpacity, 0.6);
        expect(shape.style.fillColorArgb, isNull);
        expect(shape.style.arrowHeads, core.ArrowHeads.none);
        expect(shape.style, shape.style.normalized());
        expect(
          shape.style.dash,
          tool == core.PenTool.dashed
              ? core.LineDash.dashed
              : core.LineDash.solid,
        );
        c.updateContent(
          _content(objects: [shape], revision: tools.indexOf(tool) + 2),
        );
      }
    });
  });
}
