// lib/src/ui/color/hsv_wheel.dart — 04-editor 6.9.5 (wheel, 220 diameter).
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'color_drag_area.dart';
import 'color_math.dart';

/// Hue / saturation wheel: hue = angle about the centre measured clockwise
/// from screen +x (the SweepGradient direction), saturation = distance /
/// radius (cut at 1). The value comes from the ValueSlider below it; the
/// wheel keeps [hsv]'s value and only changes hue and saturation.
class HsvWheel extends StatelessWidget {
  const HsvWheel({
    super.key,
    required this.hsv,
    required this.onChanged,
    this.diameter = defaultDiameter,
  });

  static const double defaultDiameter = 220;

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;
  final double diameter;

  /// The colour at local [position] of a wheel [diameter] wide, with
  /// [current]'s value (and its hue at the exact centre).
  static HSVColor colorAt(Offset position, double diameter, HSVColor current) {
    final r = diameter / 2;
    final d = position - Offset(r, r);
    if (d.distance == 0) return current.withSaturation(0);
    final degrees = math.atan2(d.dy, d.dx) * 180 / math.pi;
    return HSVColor.fromAHSV(
      1,
      (degrees + 360) % 360,
      math.min(1, d.distance / r),
      current.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: diameter,
      child: ColorDragArea(
        onPosition: (p) => onChanged(colorAt(p, diameter, hsv)),
        child: CustomPaint(
          painter: HsvWheelPainter(
            hsv: hsv,
            markerRing: scheme.surface,
            markerOutline: scheme.outline,
          ),
        ),
      ),
    );
  }
}

/// SweepGradient of the hues, a white → transparent RadialGradient over it
/// and a black (1 − value) cover; a marker at the colour's place.
class HsvWheelPainter extends CustomPainter {
  HsvWheelPainter({
    required this.hsv,
    required this.markerRing,
    required this.markerOutline,
  });

  final HSVColor hsv;
  final Color markerRing;
  final Color markerOutline;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: centre, radius: r);
    final white = PickerSpectrum.white;
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = SweepGradient(colors: PickerSpectrum.hueStops)
            .createShader(rect),
    );
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(colors: [white, white.withValues(alpha: 0)])
            .createShader(rect),
    );
    if (hsv.value < 1) {
      canvas.drawCircle(
        centre,
        r,
        Paint()..color = PickerSpectrum.black.withValues(alpha: 1 - hsv.value),
      );
    }
    final angle = hsv.hue * math.pi / 180;
    final marker =
        centre +
        Offset(math.cos(angle), math.sin(angle)) * (hsv.saturation * r);
    paintMarker(canvas, marker, hsv, markerRing, markerOutline);
  }

  @override
  bool shouldRepaint(HsvWheelPainter old) =>
      old.hsv != hsv ||
      old.markerRing != markerRing ||
      old.markerOutline != markerOutline;
}

/// The round marker of the wheel and the square: the colour inside a ring.
void paintMarker(
  Canvas canvas,
  Offset centre,
  HSVColor hsv,
  Color ring,
  Color outline,
) {
  canvas.drawCircle(centre, 9, Paint()..color = Color(ColorMath.fromHsv(hsv)));
  canvas.drawCircle(
    centre,
    9,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ring,
  );
  canvas.drawCircle(
    centre,
    10.5,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = outline,
  );
}
