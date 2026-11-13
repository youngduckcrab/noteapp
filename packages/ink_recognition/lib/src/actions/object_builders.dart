// lib/src/actions/object_builders.dart — (internal) m5-7/05-library 6.13.4,
// 6.14.6, 6.15.1, 6.15.3; contract 7.2.2 (objects), 7.2.3 (commands — the
// named-argument shape, (v2.1, C21-07) RemoveElements.elementIds is a List).
//
// Every object and command the recognition actions make, in one place:
//   strokes → TextBoxObject (recog.toText)      → CompositeCommand 'recog-to-text'
//   strokes → MathObject    (recog.toMath)      → CompositeCommand 'recog-to-math'
//   MathObject re-edited    (recog.editMath)    → UpdateObjects
//   typed / recognized math (recog.mathPad)     → AddObjects
// Pure except buildTextBox (awaits INK's text measure) and the math layouts
// (InkMathRenderer.layout — synchronous, never inside a frame phase).
import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:note_core/note_core.dart' as core;

import '../lines/glyph_boxes.dart';
import '../model/handwriting_trace.dart';

/// CompositeCommand labels (6.13.4, 6.15.3).
const String kToTextLabel = 'recog-to-text';
const String kToMathLabel = 'recog-to-math';

/// (math pen, phase 1) the math pen's conversion (design note 11.3).
const String kMathPenLabel = 'recog-math-pen';

/// (text pen, phase 1) the text pen's conversion (m5-7/05-library 6.24).
const String kTextPenLabel = 'recog-text-pen';

/// engineId of a formula the user typed or fixed by hand (6.14.6, 6.15.1).
const String kManualMathEngineId = 'manual';

/// 6.13.4 / 6.15.3 numbers.
abstract final class ObjectBuilderTuning {
  static const double textSizeFactor = 0.8; // fontSizePt = H × 0.8
  static const double minTextSizePt = 10, maxTextSizePt = 48;
  static const double minBoxWidthPt = 120; // width = max(bounds width, 120)
  static const double minBoxClampPt = 40; // … clamped to [40, page − 32]
  static const double pageMarginPt = 16;
  static const double mathBaseSizePt = 18; // layout(latex, 18)
  static const double minMathSizePt = core.MathStyle.minFontSize; // 6
  static const double maxMathSizePt = core.MathStyle.maxFontSize; // 144
}

/// The strokes recognition reads (z order kept): not highlighter / tape /
/// laser (CORE HandwritingText.isRecognitionInput).
List<core.Stroke> recognitionInputsOf(Iterable<core.Stroke> strokes) => [
  for (final s in strokes)
    if (core.HandwritingText.isRecognitionInput(s)) s,
];

/// Rounds [value] to the nearest 0.5.
double roundToHalf(double value) => (value * 2).roundToDouble() / 2;

/// 6.13.4 'text': each line trimmed, empty lines dropped, joined with '\n'.
String joinLineTexts(Iterable<String> lines) => [
  for (final l in lines)
    if (l.trim().isNotEmpty) l.trim(),
].join('\n');

/// 6.13.4: more than PageObjectLimits.maxTextLength characters → the
/// primary button is disabled (with a notice).
bool isTextTooLong(String text) =>
    text.length > core.PageObjectLimits.maxTextLength;

/// 6.13.4 'style.fontSizePt': clamp(H × 0.8, 10, 48) rounded to 0.5 (H = the
/// 6.5 glyph height of the input strokes).
double textBoxFontSizeFor(double glyphHeightPt) {
  final raw = glyphHeightPt.isFinite
      ? glyphHeightPt * ObjectBuilderTuning.textSizeFactor
      : ObjectBuilderTuning.minTextSizePt;
  return roundToHalf(
    raw.clamp(
      ObjectBuilderTuning.minTextSizePt,
      ObjectBuilderTuning.maxTextSizePt,
    ),
  );
}

/// The glyph height H (pt) of [strokes] (6.5 — the same estimate the line
/// grouping uses).
double glyphHeightOfStrokes(Iterable<core.Stroke> strokes) =>
    estimateGlyphHeight([
      for (final s in strokes) HandwritingTrace.fromStroke(s),
    ]);

/// The opaque form of [argb] (CORE's normalize rule — alpha 0xFF).
int opaqueColor(int argb) => 0xFF000000 + argb % 0x1000000;

/// 6.13.4 'style.colorArgb' / 6.15.3 'color': the colour most strokes of
/// [strokes] use (compared opaque); a tie goes to the colour that comes first
/// in z order (Stroke.compareOrder). Alpha 0xFF. null for no strokes.
int? dominantColorOf(Iterable<core.Stroke> strokes) {
  final ordered = [...strokes]..sort(core.Stroke.compareOrder);
  final counts = <int, int>{}; // insertion order = first use in z order
  for (final s in ordered) {
    final c = opaqueColor(s.style.colorArgb);
    counts[c] = (counts[c] ?? 0) + 1;
  }
  int? best;
  var bestCount = 0;
  for (final MapEntry(key: color, value: n) in counts.entries) {
    if (n > bestCount) {
      best = color;
      bestCount = n;
    }
  }
  return best;
}

/// 6.13.4 'width' and 'position' (rotation 0; the height comes from INK's
/// measure): width = clamp(max(bounds width, 120), 40, page width − 32),
/// left = clamp(bounds left, 16, page width − 16 − width), top = max(bounds
/// top, 0).
({double left, double top, double width}) textBoxPlacementOf(
  Rect boundsPt,
  core.PageSize pageSize,
) {
  const m = ObjectBuilderTuning.pageMarginPt;
  final maxWidth = math.max(
    ObjectBuilderTuning.minBoxClampPt,
    pageSize.width - 2 * m,
  );
  final width = math
      .max(_finiteOr(boundsPt.width, 0), ObjectBuilderTuning.minBoxWidthPt)
      .clamp(ObjectBuilderTuning.minBoxClampPt, maxWidth)
      .toDouble();
  final maxLeft = math.max(m, pageSize.width - m - width);
  final left = _finiteOr(boundsPt.left, m).clamp(m, maxLeft).toDouble();
  final top = math.max(_finiteOr(boundsPt.top, 0), 0.0);
  return (left: left, top: top, width: width);
}

/// 6.13.4: the text box that replaces the converted strokes. [text] is the
/// joined line text ([joinLineTexts]); [glyphHeightPt] defaults to the 6.5
/// glyph height of [inputStrokes]. The height is INK's
/// InkTextLayout.measure (the metrics INK paints with — EDITOR writes the
/// same; it waits for NoteSans itself, ≤ 5 s, then measures with the
/// fallback font).
Future<core.TextBoxObject> buildTextBox({
  required String id,
  required String pageId,
  required core.EpochMillis nowMs,
  required String text,
  required List<core.Stroke> inputStrokes,
  required Rect boundsPt,
  required core.PageSize pageSize,
  double? glyphHeightPt,
}) async {
  final h = glyphHeightPt ?? glyphHeightOfStrokes(inputStrokes);
  final style = core.TextBoxStyle(
    fontSizePt: textBoxFontSizeFor(h),
    colorArgb:
        dominantColorOf(inputStrokes) ?? const core.TextBoxStyle().colorArgb,
  ).normalized();
  final place = textBoxPlacementOf(boundsPt, pageSize);
  final size = await ink.InkTextLayout.measure(
    text,
    style,
    widthPt: place.width,
  );
  return core.TextBoxObject(
    id: id,
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(place.left, place.top, place.width, size.height),
    ),
    text: text,
    style: style,
    createdAt: nowMs,
    updatedAt: nowMs,
  );
}

/// 6.13.4 / 6.15.3 'command': the input strokes removed and [object] added
/// in ONE command (one undo step — contract 7.2.3 '손글씨 → 텍스트 상자').
/// Only [strokes] are removed (callers pass the recognition inputs —
/// highlighter / tape strokes and other objects of the selection stay).
core.CompositeCommand replaceStrokesCommand({
  required String pageId,
  required Iterable<core.Stroke> strokes,
  required core.PageObject object,
  required String label,
}) => core.CompositeCommand([
  core.RemoveElements(
    pageId: pageId,
    elementIds: [for (final s in strokes) s.id],
  ),
  core.AddObjects(pageId: pageId, objects: [object]),
], label: label);

/// 6.14.6 step 4–5: one new object.
core.AddObjects addObjectCommand(String pageId, core.PageObject object) =>
    core.AddObjects(pageId: pageId, objects: [object]);

/// 6.15.1: one edited object.
core.UpdateObjects updateObjectCommand(String pageId, core.PageObject object) =>
    core.UpdateObjects(pageId: pageId, objects: [object]);

/// The LaTeX an insert or a conversion may use: trimmed; null when empty, too
/// long (> PageObjectLimits.maxLatexLength) or not renderable
/// (InkMathRenderer.validate) — 6.14.6 step 1.
String? usableLatex(String latex) {
  final t = latex.trim();
  if (t.isEmpty || t.length > core.PageObjectLimits.maxLatexLength) {
    return null;
  }
  return ink.InkMathRenderer.validate(t) == null ? t : null;
}

/// 6.15.3 step 3: the formula that replaces the selected strokes —
/// f = clamp(18 × bounds height ÷ layout(latex, 18).height, 6, 144) to 0.5,
/// the frame centred on the selection bounds with layout(latex, f).sizePt,
/// colour = the input strokes' dominant colour. null when [latex] cannot be
/// laid out.
core.MathObject? buildMathFromStrokes({
  required String id,
  required String pageId,
  required core.EpochMillis nowMs,
  required String latex,
  required String engineId,
  required List<core.Stroke> inputStrokes,
  required Rect boundsPt,
}) {
  final tex = usableLatex(latex);
  if (tex == null) return null;
  final base = ink.InkMathRenderer.layout(
    tex,
    fontSizePt: ObjectBuilderTuning.mathBaseSizePt,
  );
  if (base == null) return null;
  final fontSize = mathFontSizeFor(
    boundsHeightPt: boundsPt.height,
    baseHeightPt: base.sizePt.height,
  );
  final laid = fontSize == ObjectBuilderTuning.mathBaseSizePt
      ? base
      : ink.InkMathRenderer.layout(tex, fontSizePt: fontSize);
  if (laid == null) return null;
  final center = boundsPt.center;
  return core.MathObject(
    id: id,
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(
        center.dx - laid.sizePt.width / 2,
        center.dy - laid.sizePt.height / 2,
        laid.sizePt.width,
        laid.sizePt.height,
      ),
    ),
    latex: tex,
    style: core.MathStyle(
      colorArgb:
          dominantColorOf(inputStrokes) ?? const core.MathStyle().colorArgb,
      fontSizePt: fontSize,
    ).normalized(),
    engineId: engineId,
    createdAt: nowMs,
    updatedAt: nowMs,
  );
}

/// (math pen, phase 1 — docs/plans/m5-7/research/math-pen-phase1.md 11.3)
/// The formula a math pen group becomes: f = mathFontSizeFor(the ink's
/// point-bounds height) — about as tall as the handwriting — the frame
/// LEFT-aligned to the ink and vertically centred on it, colour = the
/// strokes' dominant colour, and [strokes] kept as its ink (z order, version
/// null) so it can be reopened; ink [] when they are over
/// PageObjectLimits.maxMathInkStrokes / maxMathInkPoints (the caller tells
/// the user). null when [latex] cannot be laid out or there is no stroke.
core.MathObject? buildMathFromPen({
  required String id,
  required String pageId,
  required core.EpochMillis nowMs,
  required String latex,
  required String engineId,
  required List<core.Stroke> strokes,
}) {
  if (strokes.isEmpty) return null;
  final tex = usableLatex(latex);
  if (tex == null) return null;
  Rect? area;
  for (final s in strokes) {
    final b = s.points.pointBounds;
    final r = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    area = area == null ? r : area.expandToInclude(r);
  }
  final bounds = area!;
  final base = _mathSizeOf(tex, ObjectBuilderTuning.mathBaseSizePt);
  if (base == null) return null;
  final fontSize = mathFontSizeFor(
    boundsHeightPt: bounds.height,
    baseHeightPt: base.height,
  );
  final laid = fontSize == ObjectBuilderTuning.mathBaseSizePt
      ? base
      : _mathSizeOf(tex, fontSize);
  if (laid == null) return null;
  final keep = mathInkFits(strokes);
  return core.MathObject(
    id: id,
    pageId: pageId,
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(
        bounds.left,
        bounds.center.dy - laid.height / 2,
        laid.width,
        laid.height,
      ),
    ),
    latex: tex,
    style: core.MathStyle(
      colorArgb: dominantColorOf(strokes) ?? const core.MathStyle().colorArgb,
      fontSizePt: fontSize,
    ).normalized(),
    engineId: engineId,
    ink: keep
        ? [
            for (final s in [...strokes]..sort(core.Stroke.compareOrder))
              s.copyWith(pageId: pageId),
          ]
        : const [],
    createdAt: nowMs,
    updatedAt: nowMs,
  );
}

/// Whether [strokes] fit in a formula's ink (PageObjectLimits).
bool mathInkFits(List<core.Stroke> strokes) {
  if (strokes.length > core.PageObjectLimits.maxMathInkStrokes) return false;
  var points = 0;
  for (final s in strokes) {
    points += s.points.length;
  }
  return points <= core.PageObjectLimits.maxMathInkPoints;
}

/// INK's layout size of [tex] at [fontSizePt] (pt), or null.
Size? _mathSizeOf(String tex, double fontSizePt) =>
    ink.InkMathRenderer.layout(tex, fontSizePt: fontSizePt)?.sizePt;

/// 6.15.3: clamp(18 × [boundsHeightPt] ÷ [baseHeightPt], 6, 144) to 0.5
/// (18 when the base layout has no height).
double mathFontSizeFor({
  required double boundsHeightPt,
  required double baseHeightPt,
}) {
  const base = ObjectBuilderTuning.mathBaseSizePt;
  if (!(baseHeightPt > 0) || !boundsHeightPt.isFinite) return base;
  return roundToHalf(
    (base * boundsHeightPt / baseHeightPt).clamp(
      ObjectBuilderTuning.minMathSizePt,
      ObjectBuilderTuning.maxMathSizePt,
    ),
  );
}

/// 6.15.1: [m] with [latex] laid out again at its own font size — centre and
/// rotation kept, engineId 'manual', updatedAt [nowMs]. (math pen) A formula
/// written with the math pen (it keeps its ink) and not rotated keeps its
/// LEFT edge and vertical centre instead — it starts where the handwriting
/// did, so a longer formula grows to the right only. null when [latex]
/// cannot be laid out.
core.MathObject? relayoutMath(
  core.MathObject m, {
  required String latex,
  required core.EpochMillis nowMs,
}) {
  final tex = usableLatex(latex);
  if (tex == null) return null;
  final laid = ink.InkMathRenderer.layout(tex, fontSizePt: m.style.fontSizePt);
  if (laid == null) return null;
  final c = m.frame.center;
  final keepLeft = m.ink.isNotEmpty && m.frame.rotation == 0;
  return m.copyWith(
    frame: core.ElementFrame(
      core.PageRect.fromLTWH(
        keepLeft ? m.frame.rect.left : c.x - laid.sizePt.width / 2,
        c.y - laid.sizePt.height / 2,
        laid.sizePt.width,
        laid.sizePt.height,
      ),
      rotation: m.frame.rotation,
    ),
    latex: tex,
    engineId: kManualMathEngineId,
    updatedAt: nowMs,
  );
}

/// 6.14.6 steps 2–4: a new formula at the default MathStyle (18 pt), centred
/// in [areaPt] (the insert context's visible rect) and moved inside the page,
/// rotation 0. null when [latex] cannot be laid out.
core.MathObject? buildInsertedMath({
  required String id,
  required String pageId,
  required core.EpochMillis nowMs,
  required String latex,
  required String engineId,
  required Rect areaPt,
  required core.PageSize pageSize,
}) {
  final tex = usableLatex(latex);
  if (tex == null) return null;
  const style = core.MathStyle();
  final laid = ink.InkMathRenderer.layout(tex, fontSizePt: style.fontSizePt);
  if (laid == null) return null;
  final w = laid.sizePt.width, h = laid.sizePt.height;
  final center = areaPt.isFinite
      ? areaPt.center
      : Rect.fromLTWH(0, 0, pageSize.width, pageSize.height).center;
  final left = (center.dx - w / 2)
      .clamp(0.0, math.max(0.0, pageSize.width - w))
      .toDouble();
  final top = (center.dy - h / 2)
      .clamp(0.0, math.max(0.0, pageSize.height - h))
      .toDouble();
  return core.MathObject(
    id: id,
    pageId: pageId,
    frame: core.ElementFrame(core.PageRect.fromLTWH(left, top, w, h)),
    latex: tex,
    style: style,
    engineId: engineId,
    createdAt: nowMs,
    updatedAt: nowMs,
  );
}

double _finiteOr(double v, double fallback) => v.isFinite ? v : fallback;
