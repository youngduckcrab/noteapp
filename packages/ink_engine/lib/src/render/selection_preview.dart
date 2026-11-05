// lib/src/render/selection_preview.dart — INTERNAL (03-ink 6.22 미리보기, 6.12 R7,
// INK T18).
//
// The live preview of a selection being moved / resized / rotated (ink-layer
// strokes; highlighters stay in their active groups, 6.10-6):
//  * a similarity transform (a == d and b == −c within 1e-9: move, corner
//    resize keeping the aspect, rotation) whose widths stay inside
//    [StrokeStyle.minWidth, maxWidth]: the selected strokes are recorded ONCE
//    into a picture and drawn through canvas.transform(m) — the shape the
//    final CORE strokes get;
//  * otherwise (edge handles, a width limit reached): a picture of
//    previewTransformedOf(source, m) outlines is recorded for m, within the
//    frame work budget (InkRenderConfig.frameWorkBudgetMs, at least one
//    stroke per frame). A recording that does not finish goes on in the next
//    frames; meanwhile the last finished picture is drawn corrected by
//    m · m_last⁻¹ (the identity picture by m when there is none).
// Releasing the pointer commits; the pending transform is then drawn exactly
// (core.Stroke.transformed, like the final strokes).
import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../geometry/outline_generator.dart';
import '../geometry/stroke_outline.dart';
import '../interop/core_interop.dart' as interop;
import '../model/ink_stroke.dart';
import 'stroke_painter.dart';

/// One previewed stroke: the committed stroke and a pending recolor.
typedef SelectionPreviewItem = ({InkStroke stroke, int? colorArgb});

/// Counters of [SelectionPreviewCache] (tests, diagnostics).
typedef SelectionPreviewStats = ({
  int identityRecords,
  int exactRecords,
  int matrixFrames,
  int exactFrames,
  int correctedFrames,
});

@internal
final class SelectionPreviewCache {
  SelectionPreviewCache({
    required this.budgetUs,
    required this.nowUs,
    required this.requestFrame,
  });

  /// Work budget of one exact recording step (µs).
  final double budgetUs;
  final int Function() nowUs;

  /// Asks for another frame (the recording is not finished).
  final void Function() requestFrame;

  List<SelectionPreviewItem> _items = const [];
  _Recorded? _identity;
  _Recorded? _exact;
  _Building? _building;

  int _identityRecords = 0;
  int _exactRecords = 0;
  int _matrixFrames = 0;
  int _exactFrames = 0;
  int _correctedFrames = 0;

  SelectionPreviewStats get stats => (
    identityRecords: _identityRecords,
    exactRecords: _exactRecords,
    matrixFrames: _matrixFrames,
    exactFrames: _exactFrames,
    correctedFrames: _correctedFrames,
  );

  /// a == d and b == −c (±1e-9).
  static bool isSimilarity(core.Affine2 m) =>
      (m.a - m.d).abs() <= 1e-9 && (m.b + m.c).abs() <= 1e-9;

  /// Some width of [items] leaves [minWidth, maxWidth] under [m] (CORE then
  /// clamps it, so the matrix picture would differ from the final strokes).
  static bool reachesWidthLimit(
    List<SelectionPreviewItem> items,
    core.Affine2 m,
  ) {
    final s = m.uniformScale;
    for (final it in items) {
      final w = it.stroke.style.width * s;
      if (!(w >= core.StrokeStyle.minWidth && w <= core.StrokeStyle.maxWidth)) {
        return true;
      }
    }
    return false;
  }

  /// Paints [items] (z order) under [m]. [grain] gives the pencil grain or
  /// null (not ready); [outlineOf] the cached outline of a committed stroke.
  void paint(
    ui.Canvas canvas,
    List<SelectionPreviewItem> items,
    core.Affine2 m, {
    required ui.Image? Function() grain,
    required StrokeOutline Function(InkStroke stroke) outlineOf,
  }) {
    _sync(items, grain);
    if (items.isEmpty) return;
    if (isSimilarity(m) && !reachesWidthLimit(items, m)) {
      _drawThrough(canvas, _identityPicture(grain, outlineOf), m);
      _matrixFrames++;
      return;
    }
    final exact = _exact;
    if (exact != null && exact.m == m) {
      canvas.drawPicture(exact.picture);
      _exactFrames++;
      return;
    }
    var b = _building;
    if (b == null || b.m != m) {
      b?.discard();
      b = _building = _Building(m);
    }
    final start = nowUs();
    while (b.next < items.length) {
      final it = items[b.next++];
      final s = InkStroke.of(interop.previewTransformedOf(it.stroke.source, m));
      ui.Image? g;
      if (s.profile.textured) {
        g = grain();
        if (g == null) b.missingGrain = true;
      }
      paintFillStroke(
        b.canvas,
        s,
        OutlineGenerator.outline(s),
        colorArgb: it.colorArgb,
        grain: g,
      );
      if (b.next < items.length && nowUs() - start >= budgetUs) break;
    }
    if (b.next >= items.length) {
      _exact?.dispose();
      final done = _exact = _Recorded(
        b.recorder.endRecording(),
        m,
        missingGrain: b.missingGrain,
      );
      _building = null;
      _exactRecords++;
      canvas.drawPicture(done.picture);
      _exactFrames++;
      return;
    }
    // over budget: the last finished picture, corrected; go on next frame
    final inverse = exact?.m.inverse();
    if (exact != null && inverse != null) {
      _drawThrough(canvas, exact.picture, inverse.then(m));
    } else {
      _drawThrough(canvas, _identityPicture(grain, outlineOf), m);
    }
    _correctedFrames++;
    requestFrame();
  }

  /// Drops every picture (no selection preview any more).
  void reset() {
    _items = const [];
    _identity?.dispose();
    _identity = null;
    _exact?.dispose();
    _exact = null;
    _building?.discard();
    _building = null;
  }

  void dispose() => reset();

  void _drawThrough(ui.Canvas canvas, ui.Picture picture, core.Affine2 m) {
    canvas
      ..save()
      ..transform(interop.matrix4Of(m))
      ..drawPicture(picture)
      ..restore();
  }

  /// New strokes or colors → everything is recorded again; a pencil grain
  /// that became ready → the pictures recorded without it are dropped.
  void _sync(List<SelectionPreviewItem> items, ui.Image? Function() grain) {
    if (!_sameItems(items)) {
      reset();
      _items = List.unmodifiable(items);
      return;
    }
    final identity = _identity;
    if (identity != null && identity.missingGrain && grain() != null) {
      identity.dispose();
      _identity = null;
    }
    final exact = _exact;
    if (exact != null && exact.missingGrain && grain() != null) {
      exact.dispose();
      _exact = null;
    }
  }

  bool _sameItems(List<SelectionPreviewItem> items) {
    if (items.length != _items.length) return false;
    for (var i = 0; i < items.length; i++) {
      if (!identical(items[i].stroke.source, _items[i].stroke.source) ||
          items[i].colorArgb != _items[i].colorArgb) {
        return false;
      }
    }
    return true;
  }

  ui.Picture _identityPicture(
    ui.Image? Function() grain,
    StrokeOutline Function(InkStroke stroke) outlineOf,
  ) {
    final cached = _identity;
    if (cached != null) return cached.picture;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    var missingGrain = false;
    for (final it in _items) {
      ui.Image? g;
      if (it.stroke.profile.textured) {
        g = grain();
        if (g == null) missingGrain = true;
      }
      paintFillStroke(
        canvas,
        it.stroke,
        outlineOf(it.stroke),
        colorArgb: it.colorArgb,
        grain: g,
      );
    }
    final done = _identity = _Recorded(
      recorder.endRecording(),
      core.Affine2.identity,
      missingGrain: missingGrain,
    );
    _identityRecords++;
    return done.picture;
  }
}

final class _Recorded {
  _Recorded(this.picture, this.m, {required this.missingGrain});
  final ui.Picture picture;
  final core.Affine2 m;
  final bool missingGrain;
  void dispose() => picture.dispose();
}

final class _Building {
  _Building(this.m) {
    canvas = ui.Canvas(recorder);
  }
  final core.Affine2 m;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  late final ui.Canvas canvas;
  int next = 0;
  bool missingGrain = false;

  void discard() => recorder.endRecording().dispose();
}
