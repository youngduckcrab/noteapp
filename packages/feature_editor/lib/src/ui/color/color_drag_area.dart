// lib/src/ui/color/color_drag_area.dart — 04-editor 6.9.5 (shared by the
// wheel, the square and the colour sliders).
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'color_math.dart';

/// Colours of the picker's own drawing — pure hues, white and black. They are
/// points of the colour space the picker shows (computed from HSV), not theme
/// colours (contract 7.4.11 — the UI around them uses colorScheme).
abstract final class PickerSpectrum {
  /// The pure hue at [degrees] (saturation 1, value 1).
  static Color hue(double degrees) =>
      Color(ColorMath.fromHsv(HSVColor.fromAHSV(1, degrees % 360, 1, 1)));

  /// Hues 0, 60, …, 360 (red, yellow, green, cyan, blue, magenta, red).
  static List<Color> get hueStops => [
    for (var i = 0; i <= 6; i++) hue(i * 60.0),
  ];

  static Color get white =>
      Color(ColorMath.fromHsv(HSVColor.fromAHSV(1, 0, 0, 1)));

  static Color get black =>
      Color(ColorMath.fromHsv(HSVColor.fromAHSV(1, 0, 0, 0)));
}

/// Reports the local position of the first pointer from down to up. An
/// EagerGestureRecognizer claims the pointer at once, so a drag here never
/// scrolls the popup panel around it (6.9.3 — the panel scrolls).
class ColorDragArea extends StatefulWidget {
  const ColorDragArea({
    super.key,
    required this.onPosition,
    this.onEnd,
    required this.child,
  });

  final ValueChanged<Offset> onPosition;
  final VoidCallback? onEnd;
  final Widget child;

  @override
  State<ColorDragArea> createState() => _ColorDragAreaState();
}

class _ColorDragAreaState extends State<ColorDragArea> {
  int? _pointer;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    widget.onPosition(e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer == _pointer) widget.onPosition(e.localPosition);
  }

  void _finish(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: const {EagerGestureRecognizer: _eagerFactory},
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _finish,
      onPointerCancel: _finish,
      child: widget.child,
    ),
  );
}

const _eagerFactory = _EagerFactory();

final class _EagerFactory
    extends GestureRecognizerFactory<EagerGestureRecognizer> {
  const _EagerFactory();

  @override
  EagerGestureRecognizer constructor() => EagerGestureRecognizer();

  @override
  void initializer(EagerGestureRecognizer instance) {}
}

/// A horizontal slider over a gradient track (hue, value, opacity): [value]
/// in 0..1, the thumb at value × usable width. [background] paints under the
/// gradient (the opacity slider's checkerboard).
class GradientTrackSlider extends StatelessWidget {
  const GradientTrackSlider({
    super.key,
    required this.value,
    required this.colors,
    required this.onChanged,
    required this.semanticLabel,
    required this.semanticValue,
    this.onChangeEnd,
    this.background,
    this.height = 28,
  });

  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;
  final VoidCallback? onChangeEnd;
  final String semanticLabel;
  final String semanticValue;
  final CustomPainter? background;
  final double height;

  /// Distance of the 0 and 1 positions from the ends (thumb radius).
  double get inset => height / 2;

  /// The value at local x for a slider [width] wide.
  double valueAt(double x, double width) {
    final usable = width - 2 * inset;
    if (usable <= 0) return 0;
    return ((x - inset) / usable).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      slider: true,
      label: semanticLabel,
      value: semanticValue,
      child: SizedBox(
        height: 44, // touch target (contract 7.4.8)
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return ColorDragArea(
              onPosition: (p) => onChanged(valueAt(p.dx, width)),
              onEnd: onChangeEnd,
              child: CustomPaint(
                size: Size(width, 44),
                painter: _TrackPainter(
                  value: value.clamp(0.0, 1.0),
                  colors: colors,
                  height: height,
                  background: background,
                  outline: scheme.outlineVariant,
                  thumbFill: scheme.surface,
                  thumbBorder: scheme.outline,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({
    required this.value,
    required this.colors,
    required this.height,
    required this.background,
    required this.outline,
    required this.thumbFill,
    required this.thumbBorder,
  });

  final double value;
  final List<Color> colors;
  final double height;
  final CustomPainter? background;
  final Color outline;
  final Color thumbFill;
  final Color thumbBorder;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - height) / 2;
    final track = Rect.fromLTWH(0, top, size.width, height);
    final rrect = RRect.fromRectAndRadius(track, Radius.circular(height / 2));
    canvas.save();
    canvas.clipRRect(rrect);
    if (background != null) {
      canvas.translate(track.left, track.top);
      background!.paint(canvas, track.size);
      canvas.translate(-track.left, -track.top);
    }
    canvas.drawRect(
      track,
      Paint()..shader = LinearGradient(colors: colors).createShader(track),
    );
    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = outline,
    );
    final inset = height / 2;
    final x = inset + value * (size.width - 2 * inset);
    final centre = Offset(x, size.height / 2);
    final r = height / 2 - 2;
    canvas.drawCircle(centre, r, Paint()..color = thumbFill);
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = thumbBorder,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.value != value ||
      !_sameColors(old.colors, colors) ||
      old.height != height ||
      old.background != background ||
      old.outline != outline ||
      old.thumbFill != thumbFill ||
      old.thumbBorder != thumbBorder;

  static bool _sameColors(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
