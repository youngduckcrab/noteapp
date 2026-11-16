// lib/src/tuning.dart — every numeric constant of INK (03-ink 6.28).
//
// Values CORE already owns (width / opacity limits, kMaxWidthFactor,
// kNominalWidthQ, point count limit) are NOT repeated here: INK uses the CORE
// constants. Render budgets and timings live in InkRenderConfig (4.9).

/// Numeric constants of the ink engine (03-ink 6.28). Tests and benchmarks
/// refer to these names.
abstract final class InkTuning {
  // 6.3 input normalization
  static const double minSampleDistancePx = 0.15;
  static const int mergeWindowUs = 4000;

  // 6.4 pressure detection
  static const double pressureVariationDelta = 0.02;
  static const int constantRunLength = 12;
  static const double constantEpsilon = 1e-4;
  static const double defaultValueTolerance = 1e-3;

  // 6.6 real pressure smoothing
  static const double realPressureTauMs = 8;

  // 6.5 simulated pressure
  static const double simSpeedTauMs = 25;
  static const double simPressureTauMs = 45;
  static const double simV0 = 0.08;
  static const double simV1 = 1.6;
  static const double simAmplitude = 0.18;

  // 6.6 one-euro filter
  static const double oneEuroMinCutoffMax = 10.0;
  static const double oneEuroBetaMax = 0.12;
  static const double oneEuroDCutoff = 1.0;
  static const double rawTailMinDistancePt = 0.2;

  // 6.7 centerline processing
  static const double subdivideMinPt = 0.75;
  static const double subdivideMaxPt = 3.0;
  static const double subdivideWidthRatio = 0.5;
  static const double hookCos = -0.34;
  static const int hookMaxPoints = 4;
  static const double dotLengthMinPt = 0.3;
  static const double dotWidthRatio = 0.25;
  static const double taperMaxLengthRatio = 0.4;
  static const double straightenDevWidthRatio = 0.6;
  static const double straightenDevLengthRatio = 0.04;
  static const double axisSnapDeg = 4;
  static const double finishSimplifyPt = 0.03;
  static const double finishSimplifyWidthQ = 0.004;
  static const int maxSimplifyRetries = 4;
  static const double tiltPresentRad = 1e-3;
  static const double azimuthPresentRad = 1e-3;

  /// Lower bound of the render radius (pt). <= 0.75 × core.StrokeStyle.minWidth
  /// (= 0.075) — basis of contract 7.3.2 K-1 (v1.1).
  static const double minRadiusPt = 0.05;

  // 6.8 outline
  static const double sharpCornerCos = -0.17;
  static const double capChordPt = 0.75;
  static const int maxCapSegments = 16;
  static const double outlineSimplifyPt = 0.03;

  // 6.12 R5 live stroke
  static const int liveChunkPoints = 64;

  // 6.18 spatial index
  static const double gridCellPt = 64;

  // 6.20 partial eraser
  static const int goldenSectionIterations = 24;
  static const int bisectionIterations = 12;
  static const double minPieceLengthPt = 0.3;
  static const double minPieceWidthRatio = 0.25;

  // 6.21 lasso (the inclusion rule is a contract: LassoOptions)
  static const double lassoCoverage = 0.5;
  static const double lassoSimplifyPx = 0.75;
  static const double lassoMinAreaPt2 = 4.0;
  static const double lassoBandMinPt = 8.0;

  /// Lasso overlay colors (6.12 R8). The only non-paper display colors of INK:
  /// drawn over the paper, so the contrast basis is the paper, not the UI
  /// theme (contract 7.4.11 v1.3 exception). Painters reference these
  /// constants and never use color literals.
  static const int lassoPathArgb = 0xFF2F80ED;
  static const int lassoFillArgb = 0x142F80ED;

  // 6.22 selection transform (numeric contract). Width limits are
  // core.StrokeStyle.minWidth / maxWidth (0.1 / 30).
  static const double selectionMinSizePt = 4;
  static const double scaleMin = 0.05;
  static const double scaleMax = 20;
  static const double duplicateOffsetPt = 16;
  static const double similarityEpsilon = 1e-9;
  static const double previewRebuildBudgetMs = 4;

  /// 6.7 F8 rollover: the upper bound of core.StrokePoint.t (contract 7.2.3).
  static const int strokeRolloverMs = 500000;

  // 6.11 pencil grain (MINSTD seed in [1, 2^31 - 2])
  static const int grainSize = 256;
  static const int grainSeed = 20261104;
  static const double grainTexelPt = 0.5;

  // 6.24 vector export
  static const double exportPencilOpacityFactor = 0.85;

  // 6.15 diagnostics
  static const int latencyWindow = 240;
  static const int diagnosticsNotifyMs = 250;

  // 6.14 web raster tiles
  static const double webTileRasterP95LimitMs = 8;

  // 6.17 thumbnails
  static const double thumbnailYieldMs = 4;
  static const int thumbnailGrainWaitMs = 1000;

  // 4.14 synthetic strokes (InkDevTools)
  static const int syntheticMinPoints = 40;
  static const int syntheticMaxPoints = 160;
  static const double syntheticHz = 120;
  static const double syntheticMarginPt = 24;

  // ---- 2nd round (m5-7/03-ink 6.26) ------------------------------------------------

  // 6.18 automatic shape correction (contract 7.2.9 values)
  static const int shapeHoldMs = 500;
  static const double shapeHoldRadiusPx = 8;

  // 6.19 playback emphasis. Colors drawn over the paper (contract 7.4.10 exception).
  static const int playbackEmphasisArgb = 0xFFFF8A00;
  static const double playbackDimOpacity = 0.25;
  static const double playbackEmphasisWidthPx = 2.0;
  static const int playbackVeilBlock = 64;

  // 6.6 laser (fixed color, CP-INK-7 — never StrokeStyle.colorArgb)
  static const int laserArgb = 0xFFFF3B30;
  static const int laserMaxTrails = 16;
  static const double laserGlowWidthFactor = 2.5;
  static const double laserGlowOpacity = 0.3;
  static const int laserFadeSteps = 8;

  // 6.5 / 6.9 dashes and shapes
  static const int dashMaxSegments = 4096;
  static const double arrowHeadHalfAngleDeg = 25;
  static const double ellipseDashSegmentPt = 2.0;
  static const int ellipseMinSegments = 32;
  static const int ellipseMaxSegments = 256;

  // 6.7 memorization tape
  static const double tapeStripeSpacingPt = 6;
  static const double tapeStripeWidthPt = 1.5;
  static const double tapeRevealedBorderOpacity = 0.6;

  // 6.11 images and placeholders
  /// Placeholder tint: light paper 8% darker, dark paper 8% lighter (6.11.5).
  static const double placeholderTint = 0.08;
  static const List<int> imageBucketsPx = [128, 256, 512, 1024, 2048, 4096];
  static const int maxConcurrentImageDecodes = 2;

  /// (v2.1, 7.4.5) one formula / text raster: ≤ 4 Mpx (16 MiB RGBA), longest side ≤ 8192.
  static const int maxRasterPixels = 4194304;
  static const int maxRasterSidePx = 8192;

  // 6.12 formulas — waiting for asynchronously loaded SVG glyph pictures
  static const int mathSvgPollMs = 4;
  static const int mathSvgSettleMaxRebuilds = 8;
  static const int mathSvgSettleMs = 1000;
  static const int mathRasterRetryMs = 5000;

  // 6.10 fonts (contract 7.2.9 value: 5 s)
  static const int fontLoadTimeoutMs = 5000;
  static const int fontRetryAfterMs = 30000;

  // 6.20 thumbnails v2
  static const int thumbnailObjectWaitMs = 2000;

  // (v2.11, C211-01) texture pens (render/pens/texture/)
  /// One texel of the texture tiles (pt): half the pencil grain's, so the
  /// grain stays 1–2 px at zoom 1 and turns into crisp lumps, not smears, when
  /// zoomed in.
  static const double textureTexelPt = 0.25;

  /// The texture pens' shared geometry cache (least recently used out first).
  static const int textureGeometryBudgetBytes = 24 * 1024 * 1024;

  // (v2.12, C212-01) 6.18 adjusting a snapped shape (shape/shape_adjust.dart)
  /// The pen must leave this radius (logical px) around the hold anchor before
  /// the shape follows it — the tail of the hold does not move it. (review) Wider
  /// than shapeHoldRadiusPx, so every sample the hold counted as still stays
  /// inside; the shape follows from where the pen left it (no jump).
  static const double shapeAdjustDeadZonePx = 12;

  /// A drag never shrinks a side, diameter or line below this (logical px), nor
  /// below the snapped size when that is smaller.
  static const double shapeAdjustMinSizePx = 8;

  /// A dragged line within this of a multiple of 15° lies on it (the fitter's
  /// step, SelectionGeometry.snapAngle).
  static const double shapeAdjustAngleSnapDeg = 3;

  /// (review) A line / arrow whose held end is turned more than this about its
  /// fixed end is the stroke going on (a corner pause of a triangle, ㄱ): the
  /// preview drops and the stroke continues as ink.
  static const double shapeAdjustEscapeDeg = 30;

  /// (review) A lift sample within this (logical px) of the previous one is not
  /// applied — the skid of a lifting stylus is not committed.
  static const double shapeAdjustLiftSkidPx = 3;
}
