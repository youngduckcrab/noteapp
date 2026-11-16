/// (owner review, UI stage 2 follow-up — proposal §2 '폴더: 색 있는 폴더 그림
/// (종이가 살짝 보임)') A folder drawn as an object: a back with a tab, two
/// sheets of paper peeking out, a front flap in the folder's colour — no
/// image assets. Like the pen drawings, the paper colours are the drawn
/// object's own, so they live here in ui_kit.
library;

import 'package:material_ui/material_ui.dart';

/// Fixed material colours of the folder drawing.
abstract final class FolderArtColors {
  static const Color sheetBack = Color(0xFFF4F0E7);
  static const Color sheetFront = Color(0xFFFFFFFF);
  static const Color sheetLine = Color(0xFFD9DEE7);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
}

Color _lighten(Color c, double t) => Color.lerp(c, FolderArtColors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, FolderArtColors.black, t)!;

/// Paints a folder of [color] filling its size (best at about 4 : 3).
class FolderArtPainter extends CustomPainter {
  const FolderArtPainter(this.color, {this.shadow = true});

  final Color color;

  /// A soft drop shadow under the folder (off for small list icons).
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = (h * .12).clamp(2.0, 10.0);
    final tabTop = h * .04;
    final bodyTop = h * .14;
    final back = Path()
      ..moveTo(0, bodyTop + r)
      ..quadraticBezierTo(0, tabTop, r, tabTop)
      ..lineTo(w * .32, tabTop)
      ..quadraticBezierTo(w * .36, tabTop, w * .38, tabTop + h * .05)
      ..lineTo(w * .40, bodyTop)
      ..lineTo(w - r, bodyTop)
      ..quadraticBezierTo(w, bodyTop, w, bodyTop + r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(r, h)
      ..quadraticBezierTo(0, h, 0, h - r)
      ..close();
    if (shadow) {
      canvas.drawPath(
        back.shift(Offset(0, h * .05)),
        Paint()
          ..color = FolderArtColors.black.withValues(alpha: .14)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * .06),
      );
    }
    canvas.drawPath(back, Paint()..color = _darken(color, .18));
    // Two sheets peeking out of the folder.
    final sheets = [
      (w * .14, -.05, FolderArtColors.sheetBack),
      (w * .24, .04, FolderArtColors.sheetFront),
    ];
    for (final (dx, angle, c) in sheets) {
      canvas.save();
      canvas.translate(dx, bodyTop + h * .06);
      canvas.rotate(angle);
      final sheet = RRect.fromLTRBR(
        0,
        0,
        w * .6,
        h * .6,
        Radius.circular(r * .35),
      );
      canvas.drawRRect(sheet, Paint()..color = c);
      final line = Paint()
        ..color = FolderArtColors.sheetLine
        ..strokeWidth = (h * .012).clamp(.6, 1.2);
      for (var y = h * .09; y < h * .3; y += h * .07) {
        canvas.drawLine(Offset(w * .06, y), Offset(w * .54, y), line);
      }
      canvas.restore();
    }
    final front = RRect.fromLTRBR(0, h * .36, w, h, Radius.circular(r));
    canvas.drawRRect(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighten(color, .12), color],
        ).createShader(front.outerRect),
    );
    canvas.drawLine(
      Offset(r, h * .36 + 1.2),
      Offset(w - r, h * .36 + 1.2),
      Paint()
        ..color = FolderArtColors.white.withValues(alpha: .4)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(FolderArtPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.shadow != shadow;
}

/// A [FolderArtPainter] drawing [width] wide (3 : 4 high) with an optional
/// [emblem] (the folder's chosen icon) centred on the front flap.
class FolderArt extends StatelessWidget {
  const FolderArt({
    super.key,
    required this.color,
    required this.width,
    this.emblem,
    this.shadow = true,
  });

  final Color color;
  final double width;
  final IconData? emblem;
  final bool shadow;

  /// Height for [width].
  static double heightFor(double width) => width * .78;

  /// The default folder colour of a style: its accent, softened.
  static Color defaultColorFor(Color accent, {required bool dark}) =>
      dark ? _darken(accent, .28) : _lighten(accent, .18);

  /// The emblem colour on a front flap of [color].
  static Color emblemColorOn(Color color) => color.computeLuminance() > .5
      ? _darken(color, .55)
      : FolderArtColors.white.withValues(alpha: .92);

  @override
  Widget build(BuildContext context) {
    final h = heightFor(width);
    final icon = emblem;
    return SizedBox(
      width: width,
      height: h,
      child: CustomPaint(
        painter: FolderArtPainter(color, shadow: shadow),
        child: icon == null
            ? null
            : Padding(
                padding: EdgeInsets.only(top: h * .36),
                child: Center(
                  child: Icon(icon, size: h * .3, color: emblemColorOn(color)),
                ),
              ),
      ),
    );
  }
}
