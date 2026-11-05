// lib/src/ui/color/sv_square.dart — 04-editor 6.9.5 (square, 220 × 180).
import 'package:material_ui/material_ui.dart';

import 'color_drag_area.dart';
import 'hsv_wheel.dart';

/// Saturation / value square for [hsv]'s hue: x = saturation (0 left → 1
/// right), y = value (1 top → 0 bottom). The hue comes from the HueSlider
/// below it.
class SvSquare extends StatelessWidget {
  const SvSquare({
    super.key,
    required this.hsv,
    required this.onChanged,
    this.size = defaultSize,
  });

  static const Size defaultSize = Size(220, 180);

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final Size size;

  /// The colour at local [position] of a square of [size], with [current]'s hue.
  static HSVColor colorAt(Offset position, Size size, HSVColor current) =>
      HSVColor.fromAHSV(
        1,
        current.hue,
        (position.dx / size.width).clamp(0.0, 1.0),
        1 - (position.dy / size.height).clamp(0.0, 1.0),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.fromSize(
      size: size,
      child: ColorDragArea(
        onPosition: (p) => onChanged(colorAt(p, size, hsv)),
        child: CustomPaint(
          painter: _SvSquarePainter(
            hsv: hsv,
            markerRing: scheme.surface,
            markerOutline: scheme.outline,
          ),
        ),
      ),
    );
  }
}

class _SvSquarePainter extends CustomPainter {
  _SvSquarePainter({
    required this.hsv,
    required this.markerRing,
    required this.markerOutline,
  });

  final HSVColor hsv;
  final Color markerRing;
  final Color markerOutline;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final white = PickerSpectrum.white;
    final black = PickerSpectrum.black;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    canvas.drawRect(rect, Paint()..color = PickerSpectrum.hue(hsv.hue));
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: [white, white.withValues(alpha: 0)])
            .createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [black.withValues(alpha: 0), black],
        ).createShader(rect),
    );
    canvas.restore();
    final marker = Offset(
      hsv.saturation * size.width,
      (1 - hsv.value) * size.height,
    );
    paintMarker(canvas, marker, hsv, markerRing, markerOutline);
  }

  @override
  bool shouldRepaint(_SvSquarePainter old) =>
      old.hsv != hsv ||
      old.markerRing != markerRing ||
      old.markerOutline != markerOutline;
}
