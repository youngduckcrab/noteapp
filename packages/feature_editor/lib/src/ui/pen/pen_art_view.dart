// lib/src/ui/pen/pen_art_view.dart — (v2.15-ui, UI stages 3–5 —
// m5-7/04-editor 22) the pen drawings (ui_kit PenArtPainter, body in the ink
// colour) and the real ink stroke (ink.PenPreviewPainter) as widgets, plus
// the words the tray, the picker and the quick pen share.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:ui_kit/ui_kit.dart';

import '../color/basic_colors_row.dart';
import '../editor_strings.dart';
import 'width_mapping.dart';

/// The drawing kind of [tool] (same names).
PenArtKind penArtKindOf(core.PenTool tool) => PenArtKind.byName(tool.name);

/// The colour a pen drawing of [style] is painted in: its ink colour,
/// opaque (a 35 % highlighter still reads as yellow). The laser draws in
/// its fixed trail colour.
Color penArtColorOf(core.StrokeStyle style) => style.tool == core.PenTool.laser
    ? Color(ink.InkTuning.laserArgb)
    : Color(style.colorArgb | 0xFF000000);

/// A pen of [style] standing tip up ([PenArtPainter]); [width] wide, as tall
/// as it is given (a tray clips the bottom).
class PenArt extends StatelessWidget {
  const PenArt({
    super.key,
    required this.tool,
    required this.color,
    this.width = 24,
    this.height = 72,
  });

  PenArt.of(
    core.StrokeStyle style, {
    Key? key,
    double width = 24,
    double height = 72,
  }) : this(
         key: key,
         tool: style.tool,
         color: penArtColorOf(style),
         width: width,
         height: height,
       );

  final core.PenTool tool;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, height),
    painter: PenArtPainter(kind: penArtKindOf(tool), color: color),
  );
}

/// The eraser standing up ([EraserArtPainter]).
class EraserArt extends StatelessWidget {
  const EraserArt({super.key, this.width = 24, this.height = 60});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: const EraserArtPainter());
}

/// The real stroke of [style] (ink.PenPreviewPainter with the PencilGrain
/// object — contract 7.2.16 v1.1), [size] logical px, no background.
class InkStroke extends ConsumerWidget {
  const InkStroke({
    super.key,
    required this.style,
    required this.size,
    this.shape = ink.PenPreviewShape.sCurve,
  });

  final core.StrokeStyle style;
  final Size size;
  final ink.PenPreviewShape shape;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CustomPaint(
    size: size,
    painter: ink.PenPreviewPainter(
      style: style,
      shape: shape,
      pencilGrain: ref.watch(ink.pencilGrainProvider),
    ),
  );
}

/// [style] with a width that reads in a small swatch: thin pens a little
/// thicker, wide ones thinner (the highlighter and the tape stay bars).
core.StrokeStyle swatchStyleOf(core.StrokeStyle style, {double max = 5}) {
  final wide =
      style.tool == core.PenTool.highlighter || style.tool == core.PenTool.tape;
  final width = style.width.clamp(1.4, wide ? max * 2 : max).toDouble();
  return style.copyWith(width: width);
}

/// The five widths the picker and the quick pen offer for [tool]: around
/// the pen's default width (× 0.55, 0.8, 1, 1.4, 1.9), snapped like the
/// width slider (WidthMapping.snap).
List<double> penWidthChoices(core.PenTool tool) {
  final d = core.StrokeStyle.defaultsFor(tool).width;
  return [
    for (final f in const [0.55, 0.8, 1.0, 1.4, 1.9]) WidthMapping.snap(d * f),
  ];
}

/// The name of an ink colour: the built-in colour's name when [argb] is one
/// of [kBasicColors] (RGB), else its HEX (#RRGGBB).
String inkColorName(int argb) {
  for (var i = 0; i < kBasicColors.length; i++) {
    if (kBasicColors[i] & 0xFFFFFF == argb & 0xFFFFFF) {
      return EditorStrings.basicColorNames[i];
    }
  }
  final hex = (argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '#${hex.toUpperCase()}';
}

/// "만년필 · 남색 2.2pt" — the tray's hover label and the pen's spoken name.
String penLabelOf(core.StrokeStyle style) => EditorStrings.penLabel(
  EditorStrings.penTypeName(style.tool),
  style.tool == core.PenTool.laser ? null : inkColorName(style.colorArgb),
  style.width,
);
