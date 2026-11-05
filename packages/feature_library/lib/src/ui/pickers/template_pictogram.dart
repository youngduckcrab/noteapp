// lib/src/ui/pickers/template_pictogram.dart — 05-library 6.12. A schematic
// icon of a page template (48 × 64) so the kinds can be told apart — NOT
// INK's real template rendering: lines every 6 px, grid 6 px, dots 6 px,
// cornell = lines + a vertical line at 30 % + a bottom 20 % box, music = two
// five-line staves, planner = seven rows. Lines in onSurfaceVariant 50 %.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' show PageTemplateKind;

class TemplatePictogram extends StatelessWidget {
  const TemplatePictogram({super.key, required this.kind});

  /// null = blank page.
  final PageTemplateKind? kind;

  static const Size size = Size(48, 64);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: size,
      painter: TemplatePictogramPainter(
        kind: kind,
        paper: scheme.surfaceContainerLowest,
        edge: scheme.outlineVariant,
        line: scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class TemplatePictogramPainter extends CustomPainter {
  const TemplatePictogramPainter({
    required this.kind,
    required this.paper,
    required this.edge,
    required this.line,
  });

  final PageTemplateKind? kind;
  final Color paper, edge, line;

  /// Line / grid / dot spacing.
  static const double spacing = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final page = Offset.zero & size;
    canvas.drawRect(page, Paint()..color = paper);
    final stroke = Paint()
      ..color = line
      ..strokeWidth = 1;
    final w = size.width, h = size.height;
    void hLine(double y, [double x0 = 0, double? x1]) =>
        canvas.drawLine(Offset(x0, y), Offset(x1 ?? w, y), stroke);
    void vLine(double x, [double y0 = 0, double? y1]) =>
        canvas.drawLine(Offset(x, y0), Offset(x, y1 ?? h), stroke);
    switch (kind) {
      case null:
        break;
      case PageTemplateKind.lined:
        for (var y = 2 * spacing; y < h; y += spacing) {
          hLine(y);
        }
      case PageTemplateKind.grid:
        for (var y = spacing; y < h; y += spacing) {
          hLine(y);
        }
        for (var x = spacing; x < w; x += spacing) {
          vLine(x);
        }
      case PageTemplateKind.dotted:
        final dot = Paint()..color = line;
        for (var y = spacing; y < h; y += spacing) {
          for (var x = spacing; x < w; x += spacing) {
            canvas.drawCircle(Offset(x, y), 0.9, dot);
          }
        }
      case PageTemplateKind.cornell:
        final bottom = h * 0.8;
        for (var y = 2 * spacing; y < bottom; y += spacing) {
          hLine(y, w * 0.3);
        }
        vLine(w * 0.3, 0, bottom);
        hLine(bottom);
      case PageTemplateKind.music:
        for (final top in [h * 0.18, h * 0.58]) {
          for (var i = 0; i < 5; i++) {
            hLine(top + i * 3, 4, w - 4);
          }
        }
      case PageTemplateKind.planner:
        for (var i = 1; i < 7; i++) {
          hLine(h * i / 7);
        }
    }
    canvas.drawRect(
      page.deflate(0.5),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(TemplatePictogramPainter old) =>
      old.kind != kind ||
      old.paper != paper ||
      old.edge != edge ||
      old.line != line;
}
