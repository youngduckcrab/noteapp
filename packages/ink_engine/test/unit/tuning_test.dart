// T01 (03-ink 8, 6.28): InkTuning values that are tied to CORE or to arithmetic
// limits. Constants that CORE owns are not repeated in InkTuning.
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

void main() {
  test(
    'minRadiusPt <= 0.75 × StrokeStyle.minWidth (contract 7.3.2 K-1 basis)',
    () {
      expect(InkTuning.minRadiusPt, greaterThan(0));
      expect(
        InkTuning.minRadiusPt,
        lessThanOrEqualTo(0.75 * core.StrokeStyle.minWidth),
      );
    },
  );

  test('strokeRolloverMs is the t value CORE clamps to', () {
    final data = Float32List.fromList([
      10, 10, 0.25, 0, 0, 0, //
      20, 20, 0.25, 0, 0, InkTuning.strokeRolloverMs + 1.0,
      30, 30, 0.25, 0, 0, InkTuning.strokeRolloverMs.toDouble(),
    ]);
    final points = core.StrokePoints.fromInterleaved(data);
    expect(points.t(1), InkTuning.strokeRolloverMs.toDouble());
    expect(points.t(2), InkTuning.strokeRolloverMs.toDouble());
    // Just below the limit is kept (0.1 ms quantization).
    final below = core.StrokePoints.fromInterleaved(
      Float32List.fromList([
        0,
        0,
        0.25,
        0,
        0,
        InkTuning.strokeRolloverMs - 1.0,
      ]),
    );
    expect(below.t(0), InkTuning.strokeRolloverMs - 1.0);
  });

  test('MINSTD seeds are in [1, 2^31 - 2] and products stay exact', () {
    const m = 2147483647; // 2^31 - 1
    expect(InkTuning.grainSeed, inInclusiveRange(1, m - 1));
    // s · 48271 < 2^53: exact in a double, so VM and web give the same values.
    expect((m - 1) * 48271, lessThan(9007199254740992));
    expect(InkTuning.grainSize, greaterThan(0));
    expect(InkTuning.grainTexelPt, greaterThan(0));
  });

  test('CORE-owned constants are used, not redefined', () {
    expect(core.kMaxWidthFactor, 4.0);
    expect(core.kNominalWidthQ, 0.25);
    expect(core.StrokePoints.maxLength, 100000);
  });

  test('lasso overlay colors are opaque path / translucent fill', () {
    expect(InkTuning.lassoPathArgb ~/ 0x1000000, 0xFF);
    expect(InkTuning.lassoFillArgb ~/ 0x1000000, lessThan(0x40));
    expect(
      InkTuning.lassoFillArgb % 0x1000000,
      InkTuning.lassoPathArgb % 0x1000000,
    );
  });

  test('6.28 values that later tasks rely on', () {
    expect(InkTuning.liveChunkPoints, 64);
    expect(InkTuning.gridCellPt, 64);
    expect(InkTuning.selectionMinSizePt, 4);
    expect(InkTuning.scaleMin, 0.05);
    expect(InkTuning.scaleMax, 20);
    expect(InkTuning.duplicateOffsetPt, 16);
    expect(InkTuning.lassoCoverage, 0.5);
    expect(InkTuning.exportPencilOpacityFactor, 0.85);
    expect(InkTuning.latencyWindow, 240);
    expect(InkTuning.diagnosticsNotifyMs, 250);
    expect(InkTuning.thumbnailYieldMs, 4);
    expect(
      InkTuning.syntheticMinPoints,
      lessThan(InkTuning.syntheticMaxPoints),
    );
  });
}
