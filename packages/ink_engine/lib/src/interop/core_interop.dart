// lib/src/interop/core_interop.dart — INTERNAL. The ONLY place that creates CORE objects
// and converts CORE geometry (03-ink 3장 'CORE 객체 생성 지점', 6.23 function table).
// Exceptions (3장): InkEdit.toCommand() commands / patch, SelectionGeometry's Affine2
// factories, InkPoints[i] / lerpAt StrokePoint values, and testing.dart's test pages.
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect, Size;

import 'package:note_core/note_core.dart' as core;

import '../background/background_spec.dart';
import '../model/ink_stroke.dart';
import '../stroke/stroke_builder.dart';

/// The common constructor of every new stroke: points = StrokePoints.fromInterleaved
/// (CORE quantizes; INK renders the quantized result), style = style.normalized().
core.Stroke strokeFromData(
  Float32List data, {
  required String id,
  required String pageId,
  required core.StrokeStyle style,
  required core.EpochMillis createdAt,
  bool hasTilt = false,
  bool hasAzimuth = false,
  String? recordingId,
  int? recordingOffsetMs,
}) => core.Stroke(
  id: id,
  pageId: pageId,
  style: style.normalized(),
  points: core.StrokePoints.fromInterleaved(
    data,
    hasTilt: hasTilt,
    hasAzimuth: hasAzimuth,
  ),
  recordingId: recordingId,
  recordingOffsetMs: recordingOffsetMs,
  createdAt: createdAt,
);

/// Pen stroke (6.7 F8): createdAt = penDownMillis, recording fields from the meta.
core.Stroke newCoreStroke(
  FinishedStroke f, {
  required String id,
  required String pageId,
  required core.EpochMillis penDownMillis,
}) => strokeFromData(
  f.data,
  id: id,
  pageId: pageId,
  style: f.style,
  createdAt: penDownMillis,
  hasTilt: f.hasTilt,
  hasAzimuth: f.hasAzimuth,
  recordingId: f.meta.recordingId,
  recordingOffsetMs: f.meta.recordingOffsetMs,
);

/// Partial-eraser piece = original.fragment(...) (6.20 P7).
core.Stroke fragmentOf(
  core.Stroke original,
  Float32List data, {
  required String id,
}) => original.fragment(
  id: id,
  points: core.StrokePoints.fromInterleaved(
    data,
    hasTilt: original.points.hasTilt,
    hasAzimuth: original.points.hasAzimuth,
  ),
);

/// Partial-eraser PREVIEW piece (6.20 P8): id `pv-<seq>`, memory only — never leaves INK
/// and never enters InkCachePool.
core.Stroke previewFragmentOf(
  core.Stroke original,
  Float32List data, {
  required int seq,
}) => fragmentOf(original, data, id: 'pv-$seq');

/// Selection-transform PREVIEW (6.22) = source.transformed(m, scaleWidth: true): same id,
/// memory only (the commit sends only the transform).
core.Stroke previewTransformedOf(core.Stroke source, core.Affine2 m) =>
    source.transformed(m);

/// Lasso duplicate (6.22): moved by [offset] without width scaling, new id and createdAt.
core.Stroke duplicateOf(
  core.Stroke original, {
  required String id,
  required core.EpochMillis createdAt,
  required Offset offset,
}) => original
    .transformed(
      core.Affine2.translation(offset.dx, offset.dy),
      scaleWidth: false,
    )
    .copyWith(id: id, createdAt: createdAt, updatedAt: createdAt);

/// Thumbnail result (6.17 step 4): pageId / contentRevision from [page], PNG bytes as is.
core.PageThumbnail thumbnailOf(
  core.Page page, {
  required int width,
  required int height,
  required Uint8List png,
}) => core.PageThumbnail(
  pageId: page.id,
  contentRevision: page.contentRevision,
  width: width,
  height: height,
  mimeType: 'image/png',
  bytes: png,
);

/// Expando-cached render view (InkStroke.of).
InkStroke inkStrokeOf(core.Stroke s) => InkStroke.of(s);

/// InkBackgroundSpec.fromCore.
InkBackgroundSpec backgroundSpecOf(core.PageBackground b) => switch (b) {
  core.BlankBackground() => InkBackgroundSpec(
    kind: InkBackgroundKind.blank,
    paperColorArgb: b.paperColorArgb,
  ),
  core.TemplateBackground(:final template) => InkBackgroundSpec(
    kind: InkBackgroundKind.template,
    paperColorArgb: b.paperColorArgb,
    template: template,
  ),
  core.PdfBackground(:final assetId, :final pdfPageIndex) => InkBackgroundSpec(
    kind: InkBackgroundKind.pdf,
    paperColorArgb: b.paperColorArgb,
    assetId: assetId,
    pdfPageIndex: pdfPageIndex,
  ),
  core.ImageBackground(:final assetId) => InkBackgroundSpec(
    kind: InkBackgroundKind.image,
    paperColorArgb: b.paperColorArgb,
    assetId: assetId,
  ),
};

Size sizeOf(core.PageSize size) => Size(size.width, size.height);

Rect rectOf(core.PageRect rect) =>
    Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom);

core.PageRect pageRectOf(Rect rect) =>
    core.PageRect(rect.left, rect.top, rect.right, rect.bottom);

Offset applyAffine(core.Affine2 m, Offset p) {
  final (x, y) = m.apply(p.dx, p.dy);
  return Offset(x, y);
}

/// Column-major 4x4: [a, b, 0, 0,  c, d, 0, 0,  0, 0, 1, 0,  tx, ty, 0, 1].
Float64List matrix4Of(core.Affine2 m) => Float64List.fromList([
  m.a,
  m.b,
  0,
  0,
  m.c,
  m.d,
  0,
  0,
  0,
  0,
  1,
  0,
  m.tx,
  m.ty,
  0,
  1,
]);

/// Eraser / hitTest filter: highlighterOnly = highlighter only, exceptHighlighter = no
/// highlighter.
bool filterAccepts(core.StrokeFilter f, core.PenTool tool) => switch (f) {
  core.StrokeFilter.all => true,
  core.StrokeFilter.highlighterOnly => tool == core.PenTool.highlighter,
  core.StrokeFilter.exceptHighlighter => tool != core.PenTool.highlighter,
};

/// Alpha forced to 0xFF with arithmetic only (web safe, 7.4.3): 0xFF000000 + argb % 0x1000000.
int opaqueArgb(int argb) => 0xFF000000 + argb % 0x1000000;
