// lib/src/tools/shape_samples.dart — m5-7/04-editor 6.20 (E2-20, P-B): the
// shape sample ring buffer. LIBRARY tunes its shape fitter on samples taken
// on real devices (05-library 6.17); a committed stroke cannot serve (its
// points are base64, no viewScale, and a stroke turned into a shape is not
// stored — 7.2.3), so EDITOR keeps what it handed INK: the page-pt points of
// each pen session, the camera scale at pen down and what came out. Only
// while the developer toggle '도형 표본 모으기' (EditorDeviceState
// .collectShapeSamples, off by default) is on, only the last [capacity], in
// memory (never stored — gone with the editor screen; U18: only what the
// user copies leaves).
import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../scope/editor_scope.dart';

/// One pen session as INK got it.
@immutable
final class ShapeSample {
  const ShapeSample({
    required this.points,
    required this.viewScale,
    required this.result,
    required this.at,
  });

  /// Centre-line input points (page pt), down to up.
  final List<Offset> points;

  /// Logical px per page pt at pen down (what beginStroke got).
  final double viewScale;

  /// `stroke` or `addShape:<ShapeKind.name>` ([resultOf]).
  final String result;

  /// When the session ended (epoch ms).
  final core.EpochMillis at;
}

/// What a pen session's end produced: `addShape:<kind>` for INK's addShape
/// edit, else 'stroke' (a stroke, or nothing).
String resultOf(ink.InkEdit? edit) {
  if (edit != null && edit.kind == ink.InkEditKind.addShape) {
    for (final o in edit.addedObjects) {
      if (o is core.ShapeObject) return 'addShape:${o.shapeKind.name}';
    }
  }
  return 'stroke';
}

/// The last [capacity] samples, newest first.
final class ShapeSamples extends ChangeNotifier {
  /// How many samples are kept (6.20).
  static const int capacity = 5;

  final List<ShapeSample> _samples = [];

  /// Newest first.
  List<ShapeSample> get samples => List.unmodifiable(_samples);

  /// Adds [sample] in front; the oldest one goes past [capacity].
  void add(ShapeSample sample) {
    _samples.insert(0, sample);
    if (_samples.length > capacity) _samples.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_samples.isEmpty) return;
    _samples.clear();
    notifyListeners();
  }
}

double _hundredths(double v) => (v * 100).roundToDouble() / 100;

/// LIBRARY's sample format (05-library 6.17 — X-6): {"kind": the expected
/// ShapeKind name or "none" (not a shape — handwriting), "points": [[x, y],
/// …] (page pt, 2 decimals), "viewScale": s}.
Map<String, Object?> shapeSampleJson(
  ShapeSample sample, {
  required core.ShapeKind? expected,
}) => {
  'kind': expected?.name ?? 'none',
  'points': [
    for (final p in sample.points) [_hundredths(p.dx), _hundredths(p.dy)],
  ],
  'viewScale': sample.viewScale,
};

/// [shapeSampleJson] as the text the developer menu copies.
String shapeSampleText(
  ShapeSample sample, {
  required core.ShapeKind? expected,
}) => jsonEncode(shapeSampleJson(sample, expected: expected));

/// The note's samples (emptied with the editor screen).
final editorShapeSamplesProvider = Provider<ShapeSamples>(
  (ref) {
    ref.watch(editorNoteIdProvider);
    final samples = ShapeSamples();
    ref.onDispose(samples.dispose);
    return samples;
  },
  dependencies: [editorNoteIdProvider],
  name: 'editorShapeSamplesProvider',
);
