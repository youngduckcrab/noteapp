/// Pen drawings (contract 7.1 v2.15-ui, 04-editor 22): every pen type as a
/// small vector drawing standing tip up, its body in the ink colour, plus the
/// eraser — no image assets. The colours of brass, steel, wood and rubber are
/// the drawn objects' own (document-like, not theme colours), so they live
/// here in ui_kit, the one package the colour rule does not scan.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The pens a [PenArtPainter] can draw — one per pen type of the app, in
/// the same order and with the same names as note_core's `PenTool`
/// (feature_editor maps them by name).
enum PenArtKind {
  ballpoint,
  fountain,
  highlighter,
  pencil,
  marker,
  brush,
  calligraphy,
  dashed,
  laser,
  tape,
  crayon,
  chalk,
  watercolor,
  spray,
  neon,
  jelly,
  rainbow,
  glitter;

  /// The kind named [name] (a `PenTool.name`), else [ballpoint].
  static PenArtKind byName(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return ballpoint;
  }
}

/// Fixed material colours of the drawings.
abstract final class PenArtColors {
  static const Color steel = Color(0xFFBFC4CA);
  static const Color brass = Color(0xFFD2AE6A);
  static const Color graphite = Color(0xFF26262A);
  static const Color wood = Color(0xFFE6C496);
  static const Color brushHandle = Color(0xFFB77B4B);
  static const Color cap = Color(0xFFEDEAE3);
  static const Color plastic = Color(0xFF3A3C42);
  static const Color nozzle = Color(0xFF3C3E44);
  static const Color neonBody = Color(0xFF2B2B31);
  static const Color tapeHead = Color(0xFFF2EFEA);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  /// The rainbow pen's barrel, top to bottom.
  static const List<Color> rainbow = [
    Color(0xFFE5533D),
    Color(0xFFF2A93B),
    Color(0xFFF5D547),
    Color(0xFF59B36B),
    Color(0xFF3F7DD8),
    Color(0xFF8A5CC9),
  ];

  /// The eraser: rubber (light → shade) and its blue sleeve.
  static const List<Color> rubber = [
    Color(0xFFFFFFFF),
    Color(0xFFF3EEE9),
    Color(0xFFD9D2CB),
  ];
  static const List<Color> sleeve = [
    Color(0xFF5B8BD0),
    Color(0xFF3567B2),
    Color(0xFF244C8A),
  ];
  static const Color sleeveBand = Color(0xFF1C1C1C);
}

Color _lighten(Color c, double t) => Color.lerp(c, PenArtColors.white, t)!;
Color _darken(Color c, double t) => Color.lerp(c, PenArtColors.black, t)!;

/// One pen standing tip up, drawn in [color] (the ink colour; the body is
/// that colour, the nib is the pen's own). Drawn in a 22-wide design space
/// scaled to the canvas width; the height is whatever the canvas gives (a
/// tray clips the bottom).
///
/// With [rimLight] (a dark tray — PenTrayStyle.rimLight) the pen's outline
/// gets a thin light edge on its right and top, so a black pen still reads
/// on a near-black strip.
class PenArtPainter extends CustomPainter {
  PenArtPainter({required this.kind, required this.color, this.rimLight});

  final PenArtKind kind;
  final Color color;

  /// The rim colour, or null for none.
  final Color? rimLight;

  /// Width of the design space.
  static const double designWidth = 22;

  late Canvas _c;

  Shader _shade(Rect r, Color c) => LinearGradient(
    colors: [_lighten(c, .42), _lighten(c, .08), c, _darken(c, .32)],
    stops: const [0, .3, .55, 1],
  ).createShader(r);

  void _cyl(
    double cx,
    double y0,
    double y1,
    double w,
    Color c, {
    double r = 2.2,
  }) {
    final rect = Rect.fromLTRB(cx - w / 2, y0, cx + w / 2, y1);
    _c.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(r)),
      Paint()..shader = _shade(rect, c),
    );
    _c.drawLine(
      Offset(rect.left + w * .26, y0 + 2.5),
      Offset(rect.left + w * .26, y1 - 2),
      Paint()
        ..color = PenArtColors.white.withValues(alpha: .38)
        ..strokeWidth = math.max(1, w * .09)
        ..strokeCap = StrokeCap.round,
    );
  }

  void _cone(double cx, double y0, double y1, double w0, double w1, Color c) {
    final path = Path()
      ..moveTo(cx - w0 / 2, y0)
      ..lineTo(cx + w0 / 2, y0)
      ..lineTo(cx + w1 / 2, y1)
      ..lineTo(cx - w1 / 2, y1)
      ..close();
    _c.drawPath(path, Paint()..shader = _shade(path.getBounds(), c));
  }

  void _fill(Path path, Color c) =>
      _c.drawPath(path, Paint()..shader = _shade(path.getBounds(), c));

  Paint _solid(Color c) => Paint()..color = c;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = size.width / designWidth;
    final rim = rimLight;
    if (rim != null) {
      // The silhouette in the rim colour, 1 px right and up, under the pen.
      canvas.saveLayer(
        (Offset.zero & size).inflate(2),
        Paint()..colorFilter = ColorFilter.mode(rim, BlendMode.srcIn),
      );
      canvas.translate(1, -.8);
      canvas.scale(s);
      _c = canvas;
      _paint(canvas, designWidth, size.height / s);
      canvas.restore();
    }
    canvas.save();
    canvas.scale(s);
    _c = canvas;
    _paint(canvas, designWidth, size.height / s);
    canvas.restore();
  }

  void _paint(Canvas canvas, double w, double h) {
    final cx = w / 2;
    final bw = w * .56;
    final c = color;
    final white = PenArtColors.white;
    switch (kind) {
      case PenArtKind.ballpoint:
      case PenArtKind.dashed:
        _cone(cx, 3, 13, 1.6, bw * .62, PenArtColors.steel);
        canvas.drawCircle(Offset(cx, 2.6), 1, _solid(_darken(c, .2)));
        _cyl(cx, 13, 27, bw * .84, _darken(c, .38), r: 1.5);
        _cyl(cx, 27, h, bw, c);
        if (kind == PenArtKind.dashed) {
          for (var y = 31.0; y < h - 4; y += 7) {
            canvas.drawRRect(
              RRect.fromLTRBR(
                cx - 1,
                y,
                cx + 1,
                y + 3.5,
                const Radius.circular(1),
              ),
              _solid(white.withValues(alpha: .75)),
            );
          }
        } else {
          final clip = Rect.fromLTRB(
            cx + bw / 2 - 2.4,
            31,
            cx + bw / 2 + .4,
            60,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(clip, const Radius.circular(1.2)),
            Paint()..shader = _shade(clip, PenArtColors.steel),
          );
        }
      case PenArtKind.fountain:
        final nib = Path()
          ..moveTo(cx, 0)
          ..quadraticBezierTo(cx - bw * .55, 8, cx - bw * .42, 16)
          ..lineTo(cx + bw * .42, 16)
          ..quadraticBezierTo(cx + bw * .55, 8, cx, 0)
          ..close();
        _fill(nib, PenArtColors.brass);
        canvas.drawLine(
          Offset(cx, 1.5),
          Offset(cx, 10),
          Paint()
            ..color = _darken(PenArtColors.brass, .5)
            ..strokeWidth = .7,
        );
        canvas.drawCircle(
          Offset(cx, 10.8),
          1.1,
          _solid(_darken(PenArtColors.brass, .5)),
        );
        _cyl(cx, 16, 25, bw * .86, PenArtColors.graphite, r: 1.5);
        _cyl(cx, 25, h, bw * 1.04, c);
        _cyl(cx, 32, 34.5, bw * 1.06, PenArtColors.brass, r: .5);
      case PenArtKind.pencil:
        _cone(cx, 0.5, 6, 1.2, 3.4, _darken(c, .15));
        _cone(cx, 6, 18, 3.4, bw, PenArtColors.wood);
        _cyl(cx, 17, h, bw, c, r: 1);
        for (var i = 0; i < 3; i++) {
          final x = cx - bw / 2 + bw / 6 + i * bw / 3;
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(x, 17.6),
              width: bw / 3,
              height: 3.4,
            ),
            math.pi,
            math.pi,
            true,
            _solid(c),
          );
        }
        for (final dx in [-bw / 6, bw / 6]) {
          canvas.drawLine(
            Offset(cx + dx, 19),
            Offset(cx + dx, h),
            Paint()
              ..color = PenArtColors.black.withValues(alpha: .12)
              ..strokeWidth = .8,
          );
        }
      case PenArtKind.marker:
      case PenArtKind.neon:
      case PenArtKind.rainbow:
        if (kind == PenArtKind.neon) {
          canvas.drawCircle(
            Offset(cx, 5),
            7.5,
            Paint()
              ..color = c.withValues(alpha: .55)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
          );
        }
        final tipC = kind == PenArtKind.rainbow
            ? PenArtColors.rainbow.first
            : c;
        canvas.drawRRect(
          RRect.fromLTRBAndCorners(
            cx - bw * .23,
            1,
            cx + bw * .23,
            10,
            topLeft: Radius.circular(bw * .23),
            topRight: Radius.circular(bw * .23),
          ),
          Paint()
            ..shader = _shade(
              Rect.fromLTRB(cx - 4, 0, cx + 4, 10),
              kind == PenArtKind.neon ? _lighten(c, .35) : tipC,
            ),
        );
        _cone(cx, 9, 18, bw * .56, bw * 1.12, PenArtColors.cap);
        if (kind == PenArtKind.rainbow) {
          final r = Rect.fromLTRB(cx - bw * .56, 18, cx + bw * .56, h);
          final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
          canvas.drawRRect(
            rr,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: PenArtColors.rainbow,
              ).createShader(r),
          );
          canvas.drawRRect(
            rr,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  white.withValues(alpha: .35),
                  white.withValues(alpha: 0),
                  PenArtColors.black.withValues(alpha: .25),
                ],
              ).createShader(r),
          );
        } else {
          _cyl(
            cx,
            18,
            h,
            bw * 1.12,
            kind == PenArtKind.neon ? PenArtColors.neonBody : c,
            r: 3,
          );
          canvas.drawRect(
            Rect.fromLTRB(cx - bw * .56, 23, cx + bw * .56, 25),
            _solid(kind == PenArtKind.neon ? c : white.withValues(alpha: .55)),
          );
        }
      case PenArtKind.highlighter:
        final chisel = Path()
          ..moveTo(cx - bw * .32, 11)
          ..lineTo(cx - bw * .32, 4)
          ..lineTo(cx + bw * .32, 0)
          ..lineTo(cx + bw * .32, 11)
          ..close();
        _fill(chisel, c);
        _cone(cx, 10, 19, bw * .72, bw * 1.32, _lighten(c, .55));
        _cyl(cx, 19, h, bw * 1.32, c, r: 3.5);
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw * .4,
            30,
            cx + bw * .4,
            52,
            const Radius.circular(2),
          ),
          _solid(white.withValues(alpha: .45)),
        );
      case PenArtKind.brush:
      case PenArtKind.watercolor:
        final long = kind == PenArtKind.watercolor;
        final tipEnd = long ? 19.0 : 17.0;
        final bristle = Path()
          ..moveTo(cx, 0)
          ..cubicTo(cx + bw * .15, 5, cx + bw * .42, 12, cx + bw * .34, tipEnd)
          ..lineTo(cx - bw * .34, tipEnd)
          ..cubicTo(cx - bw * .42, 12, cx - bw * .15, 5, cx, 0)
          ..close();
        _fill(bristle, c);
        _cyl(cx, tipEnd - 1, tipEnd + 8, bw * .78, PenArtColors.steel, r: 1);
        if (long) {
          _cone(cx, tipEnd + 8, h, bw * .7, bw * 1.0, PenArtColors.brushHandle);
          canvas.drawRect(
            Rect.fromLTRB(cx - bw * .44, 40, cx + bw * .44, 43),
            _solid(c),
          );
        } else {
          _cyl(cx, tipEnd + 8, h, bw * .96, _darken(c, .1));
          _cyl(
            cx,
            tipEnd + 13,
            tipEnd + 15.5,
            bw * .98,
            PenArtColors.brass,
            r: .5,
          );
        }
      case PenArtKind.calligraphy:
        final nib = Path()
          ..moveTo(cx - bw * .44, 1)
          ..lineTo(cx + bw * .44, 1)
          ..lineTo(cx + bw * .3, 15)
          ..lineTo(cx - bw * .3, 15)
          ..close();
        _fill(nib, PenArtColors.steel);
        canvas.drawLine(
          Offset(cx - bw * .44, 1.2),
          Offset(cx + bw * .44, 1.2),
          Paint()
            ..color = c
            ..strokeWidth = 1.8,
        );
        canvas.drawLine(
          Offset(cx, 2),
          Offset(cx, 10),
          Paint()
            ..color = PenArtColors.black.withValues(alpha: .45)
            ..strokeWidth = .6,
        );
        _cyl(cx, 15, 24, bw * .8, PenArtColors.graphite, r: 1);
        _cyl(cx, 24, h, bw * .95, c);
      case PenArtKind.laser:
        canvas.drawCircle(
          Offset(cx, 4),
          6.5,
          Paint()
            ..color = c.withValues(alpha: .6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        _cone(cx, 4, 10, bw * .4, bw * .82, PenArtColors.steel);
        canvas.drawCircle(Offset(cx, 4), 1.8, _solid(white));
        _cyl(cx, 10, h, bw * .82, PenArtColors.plastic, r: 3);
        canvas.drawCircle(Offset(cx, 30), bw * .2, _solid(c));
      case PenArtKind.tape:
        final head = Rect.fromLTRB(cx - bw * .66, 2, cx + bw * .66, 11);
        canvas.drawRRect(
          RRect.fromRectAndRadius(head, const Radius.circular(2)),
          Paint()..shader = _shade(head, PenArtColors.tapeHead),
        );
        canvas.drawRect(
          Rect.fromLTRB(cx - bw * .5, 1, cx + bw * .5, 3.2),
          _solid(c),
        );
        _cyl(cx, 11, h, bw * 1.32, _lighten(c, .15), r: 3);
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(cx - bw * .66, 11, cx + bw * .66, h));
        for (var y = 8.0; y < h + 10; y += 7) {
          canvas.drawLine(
            Offset(cx - bw, y + 6),
            Offset(cx + bw, y - 6),
            Paint()
              ..color = white.withValues(alpha: .28)
              ..strokeWidth = 2.2,
          );
        }
        canvas.restore();
      case PenArtKind.crayon:
        final tip = Path()
          ..moveTo(cx - bw * .3, 2.5)
          ..lineTo(cx + bw * .26, 0.5)
          ..lineTo(cx + bw * .56, 13)
          ..lineTo(cx - bw * .56, 13)
          ..close();
        _fill(tip, c);
        _cyl(cx, 12, h, bw * 1.12, c, r: 1.5);
        _cyl(cx, 19, h, bw * 1.16, _lighten(c, .78), r: 1);
        for (final y in [22.0, 26.0]) {
          canvas.drawRect(
            Rect.fromLTRB(cx - bw * .58, y, cx + bw * .58, y + 1.4),
            _solid(c),
          );
        }
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw * .35,
            31,
            cx + bw * .35,
            48,
            const Radius.circular(2),
          ),
          _solid(c.withValues(alpha: .85)),
        );
      case PenArtKind.chalk:
        final r = Rect.fromLTRB(cx - bw * .58, 2, cx + bw * .58, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            r,
            topLeft: const Radius.circular(5),
            topRight: const Radius.circular(4),
          ),
          Paint()..shader = _shade(r, _lighten(c, .3)),
        );
        final rnd = math.Random(3);
        for (var i = 0; i < 26; i++) {
          canvas.drawCircle(
            Offset(
              r.left + rnd.nextDouble() * r.width,
              r.top + rnd.nextDouble() * r.height,
            ),
            .55,
            _solid(white.withValues(alpha: .6)),
          );
        }
      case PenArtKind.spray:
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw * .3,
            1,
            cx + bw * .3,
            7.5,
            const Radius.circular(1.5),
          ),
          _solid(PenArtColors.nozzle),
        );
        canvas.drawCircle(Offset(cx + bw * .12, 3.5), 1.1, _solid(c));
        _cone(cx, 7, 13, bw * .9, bw * 1.62, PenArtColors.steel);
        _cyl(cx, 13, h, bw * 1.62, c, r: 4);
        canvas.drawRRect(
          RRect.fromLTRBR(
            cx - bw * .6,
            24,
            cx + bw * .6,
            44,
            const Radius.circular(2),
          ),
          _solid(white.withValues(alpha: .5)),
        );
      case PenArtKind.jelly:
      case PenArtKind.glitter:
        _cone(cx, 3, 12, 1.6, bw * .6, PenArtColors.steel);
        final body = Rect.fromLTRB(cx - bw / 2, 12, cx + bw / 2, h);
        final jelly = kind == PenArtKind.jelly;
        canvas.drawRRect(
          RRect.fromRectAndRadius(body, const Radius.circular(2.5)),
          _solid(
            (jelly ? _lighten(c, .55) : c).withValues(alpha: jelly ? .55 : 1),
          ),
        );
        if (jelly) {
          canvas.drawLine(
            Offset(cx, 13),
            Offset(cx, h),
            Paint()
              ..color = c
              ..strokeWidth = 2.2,
          );
        } else {
          canvas.drawRRect(
            RRect.fromRectAndRadius(body, const Radius.circular(2.5)),
            Paint()..shader = _shade(body, c),
          );
          final rnd = math.Random(7);
          for (var i = 0; i < 14; i++) {
            final o = Offset(
              body.left + 1.5 + rnd.nextDouble() * (body.width - 3),
              body.top + 2 + rnd.nextDouble() * (body.height - 4),
            );
            canvas.drawCircle(
              o,
              .5 + rnd.nextDouble() * .7,
              _solid(white.withValues(alpha: .9)),
            );
          }
        }
        canvas.drawLine(
          Offset(body.left + bw * .26, 14),
          Offset(body.left + bw * .26, h - 2),
          Paint()
            ..color = white.withValues(alpha: .5)
            ..strokeWidth = 1.2,
        );
    }
  }

  @override
  bool shouldRepaint(PenArtPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.color != color ||
      oldDelegate.rimLight != rimLight;
}

/// The eraser standing up: white rubber over a blue sleeve. Drawn in a
/// 22-wide design space like [PenArtPainter].
class EraserArtPainter extends CustomPainter {
  const EraserArtPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = size.width / PenArtPainter.designWidth;
    canvas.save();
    canvas.scale(s);
    final w = PenArtPainter.designWidth;
    final h = size.height / s;
    final cx = w / 2;
    final bw = w * .74;
    final rubber = RRect.fromLTRBAndCorners(
      cx - bw / 2,
      1,
      cx + bw / 2,
      22,
      topLeft: const Radius.circular(6),
      topRight: const Radius.circular(3),
    );
    canvas.drawRRect(
      rubber,
      Paint()
        ..shader = const LinearGradient(
          colors: PenArtColors.rubber,
          stops: [0, .5, 1],
        ).createShader(rubber.outerRect),
    );
    final sleeve = Rect.fromLTRB(cx - bw / 2 - .5, 18, cx + bw / 2 + .5, h);
    canvas.drawRect(
      sleeve,
      Paint()
        ..shader = const LinearGradient(
          colors: PenArtColors.sleeve,
          stops: [0, .5, 1],
        ).createShader(sleeve),
    );
    canvas.drawRect(
      Rect.fromLTRB(sleeve.left, 26, sleeve.right, 29),
      Paint()..color = PenArtColors.white,
    );
    canvas.drawRect(
      Rect.fromLTRB(sleeve.left, 31, sleeve.right, 33),
      Paint()..color = PenArtColors.sleeveBand,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// (v2.15-ui) The eraser as a line glyph in [color], [strokeWidth] wide
/// (StyleTokens.iconStrokeWidth): the flat 미니멀 tray shows it beside its
/// ink chips instead of the standing [EraserArtPainter]. Drawn in a 24 × 24
/// box scaled to the canvas.
class EraserGlyphPainter extends CustomPainter {
  const EraserGlyphPainter({required this.color, this.strokeWidth = 1.5});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.translate((size.width - 24 * s) / 2, (size.height - 24 * s) / 2);
    canvas.scale(s);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // A block tilted 45°: its rubber end (bottom left) and the band.
    final body = Path()
      ..moveTo(13.6, 3.6)
      ..lineTo(20.4, 10.4)
      ..lineTo(10.8, 20)
      ..lineTo(7.2, 20)
      ..lineTo(3.6, 16.4)
      ..lineTo(3.6, 13.6)
      ..close();
    canvas.drawPath(body, line);
    canvas.drawLine(const Offset(8.4, 8.8), const Offset(15.2, 15.6), line);
    canvas.drawLine(const Offset(10.8, 20), const Offset(20.4, 20), line);
    canvas.restore();
  }

  @override
  bool shouldRepaint(EraserGlyphPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
