// Page objects (m5-7/02-core 6.2.3–6.2.5, 4.3): bounds per kind (arrowheads, stroke width),
// the single transform rule (move, scale 2 / 0.5, rotate 90°, scaleWidth: false, the clamp
// edges), UnknownObject unchanged, the normalization table, copies and meta, ==,
// estimatedBytes. Web-safe.
import 'dart:convert';
import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

import '../shared/entity_samples.dart';

Matcher _nearRect(PageRect r, [double eps = 1e-9]) => isA<PageRect>()
    .having((q) => q.left, 'left', closeTo(r.left, eps))
    .having((q) => q.top, 'top', closeTo(r.top, eps))
    .having((q) => q.right, 'right', closeTo(r.right, eps))
    .having((q) => q.bottom, 'bottom', closeTo(r.bottom, eps));

ShapeObject _shape({
  ShapeKind kind = ShapeKind.line,
  ShapeGeometry geometry = const PolylineGeometry([
    PagePoint(0, 0),
    PagePoint(100, 0),
  ], closed: false),
  ShapeStyle style = const ShapeStyle(strokeColorArgb: 0xFF000000),
}) => ShapeObject(
  id: 's1',
  pageId: 'p1',
  shapeKind: kind,
  geometry: geometry,
  style: style,
  createdAt: 10,
  updatedAt: 20,
  version: kV,
);

TextBoxObject _text({double fontSizePt = 16}) => TextBoxObject(
  id: 't1',
  pageId: 'p1',
  frame: const ElementFrame(PageRect(0, 0, 200, 40)),
  text: '안녕 hello',
  style: TextBoxStyle(fontSizePt: fontSizePt),
  createdAt: 10,
  updatedAt: 20,
  version: kV,
);

MathObject _math({double fontSizePt = 18}) => MathObject(
  id: 'm1',
  pageId: 'p1',
  frame: const ElementFrame(PageRect(0, 0, 100, 50)),
  latex: r'\frac{a}{b}',
  style: MathStyle(fontSizePt: fontSizePt),
  engineId: 'manual',
  createdAt: 10,
  updatedAt: 20,
  version: kV,
);

ImageObject _image() => ImageObject(
  id: 'i1',
  pageId: 'p1',
  frame: const ElementFrame(PageRect(0, 0, 400, 300)),
  assetId: kSampleImageAssetId,
  pixelWidth: 800,
  pixelHeight: 600,
  createdAt: 10,
  updatedAt: 20,
  version: kV,
);

void main() {
  group('bounds (6.2.4)', () {
    test('shape: frame bounds + 0.75 × strokeWidth', () {
      final s = _shape(
        kind: ShapeKind.rectangle,
        geometry: ShapeGeometry.rectangle(const PageRect(10, 10, 110, 60)),
        style: const ShapeStyle(strokeColorArgb: 1, strokeWidth: 4),
      );
      expect(s.bounds, const PageRect(7, 7, 113, 63));
    });

    test('line / arrow with heads add max(6, 3 × strokeWidth)', () {
      const thin = ShapeStyle(
        strokeColorArgb: 1,
        strokeWidth: 1,
        arrowHeads: ArrowHeads.end,
      );
      expect(thin.arrowHeadLength, 6);
      const thick = ShapeStyle(
        strokeColorArgb: 1,
        strokeWidth: 4,
        arrowHeads: ArrowHeads.both,
      );
      expect(thick.arrowHeadLength, 12);
      expect(
        _shape(kind: ShapeKind.arrow, style: thin).bounds,
        const PageRect(-6.75, -6.75, 106.75, 6.75),
      );
      expect(_shape(style: thick).bounds, const PageRect(-15, -15, 115, 15));
      // No heads, or a shape kind that ignores arrowHeads: the stroke part only.
      expect(
        _shape(style: const ShapeStyle(strokeColorArgb: 1, strokeWidth: 4))
            .bounds,
        const PageRect(-3, -3, 103, 3),
      );
      expect(
        _shape(kind: ShapeKind.polygon, style: thick).bounds,
        const PageRect(-3, -3, 103, 3),
      );
    });

    test('ellipse: the rotated frame AABB', () {
      final s = _shape(
        kind: ShapeKind.ellipse,
        geometry: const EllipseGeometry(
          ElementFrame(PageRect(0, 0, 100, 50), rotation: math.pi / 2),
        ),
        style: const ShapeStyle(strokeColorArgb: 1, strokeWidth: 2),
      );
      expect(
        s.bounds,
        _nearRect(const PageRect(25 - 1.5, -25 - 1.5, 75 + 1.5, 75 + 1.5)),
      );
    });

    test('text, image, math, unknown: frame.bounds', () {
      expect(_text().bounds, const PageRect(0, 0, 200, 40));
      expect(_image().bounds, const PageRect(0, 0, 400, 300));
      expect(_math().bounds, const PageRect(0, 0, 100, 50));
      expect(
        kSampleObjects['unknown']!.bounds,
        const PageRect(400, 100, 450, 150),
      );
      const rotated = ElementFrame(
        PageRect(0, 0, 10, 10),
        rotation: math.pi / 4,
      );
      expect(_text().copyWith(frame: rotated).bounds, rotated.bounds);
    });
  });

  group('transformed — the single rule (6.2.5)', () {
    final move = Affine2.translation(10, 5);
    final double2 = Affine2.scaling(2, 2);
    final half = Affine2.scaling(0.5, 0.5);
    final quarter = Affine2.rotation(math.pi / 2);

    test('shape: geometry mapped; strokeWidth × s clamped [0.1, 30]', () {
      final s = _shape(
        style: const ShapeStyle(strokeColorArgb: 1, strokeWidth: 4),
      );
      final moved = s.transformed(move) as ShapeObject;
      expect((moved.geometry as PolylineGeometry).points, const [
        PagePoint(10, 5),
        PagePoint(110, 5),
      ]);
      expect(moved.style.strokeWidth, 4);
      expect((s.transformed(double2) as ShapeObject).style.strokeWidth, 8);
      expect((s.transformed(half) as ShapeObject).style.strokeWidth, 2);
      final turned = s.transformed(quarter) as ShapeObject;
      expect(
        (turned.geometry as PolylineGeometry).points.last.y,
        closeTo(100, 1e-9),
      );
      expect(turned.style.strokeWidth, closeTo(4, 1e-12));
      expect(
        (s.transformed(
          double2,
          scaleWidth: false,
        ) as ShapeObject).style.strokeWidth,
        4,
      );
      final wide = _shape(
        style: const ShapeStyle(strokeColorArgb: 1, strokeWidth: 20),
      );
      expect((wide.transformed(double2) as ShapeObject).style.strokeWidth, 30);
      final hair = _shape(
        style: const ShapeStyle(strokeColorArgb: 1, strokeWidth: 0.15),
      );
      expect((hair.transformed(half) as ShapeObject).style.strokeWidth, 0.1);
    });

    test('text box: frame and fontSizePt × s clamped [6, 144], also with scaleWidth: false', () {
      final t = _text();
      final big = t.transformed(double2) as TextBoxObject;
      expect(big.frame.rect, const PageRect(0, 0, 400, 80));
      expect(big.style.fontSizePt, 32);
      expect(
        (t.transformed(
          double2,
          scaleWidth: false,
        ) as TextBoxObject).style.fontSizePt,
        32,
      );
      expect((t.transformed(half) as TextBoxObject).style.fontSizePt, 8);
      expect(
        (_text(
          fontSizePt: 100,
        ).transformed(double2) as TextBoxObject).style.fontSizePt,
        144,
      );
      expect(
        (_text(
          fontSizePt: 8,
        ).transformed(half) as TextBoxObject).style.fontSizePt,
        6,
      );
      final moved = t.transformed(move) as TextBoxObject;
      expect(moved.frame, const ElementFrame(PageRect(10, 5, 210, 45)));
      expect(moved.style, t.style);
      final turned = t.transformed(quarter) as TextBoxObject;
      expect(turned.frame.rotation, closeTo(math.pi / 2, 1e-12));
      expect(turned.text, t.text);
    });

    test('math: frame and fontSizePt × s clamped [6, 144]', () {
      final m = _math();
      expect((m.transformed(double2) as MathObject).style.fontSizePt, 36);
      expect(
        (_math(
          fontSizePt: 100,
        ).transformed(double2) as MathObject).style.fontSizePt,
        144,
      );
      expect(
        (_math(
          fontSizePt: 10,
        ).transformed(half) as MathObject).style.fontSizePt,
        6,
      );
      expect(
        (m.transformed(move) as MathObject).frame.rect,
        const PageRect(10, 5, 110, 55),
      );
      expect((m.transformed(move) as MathObject).engineId, 'manual');
    });

    test('image: frame only', () {
      final i = _image();
      final t = i.transformed(double2) as ImageObject;
      expect(t.frame.rect, const PageRect(0, 0, 800, 600));
      expect(t.pixelWidth, 800);
      expect(t.assetId, i.assetId);
    });

    test('UnknownObject: the same instance', () {
      final u = kSampleObjects['unknown']!;
      expect(u.transformed(double2), same(u));
      expect(u.transformed(move, scaleWidth: false), same(u));
    });

    test('meta is kept (the resolver sets updatedAt and version)', () {
      for (final o in <PageObject>[_shape(), _text(), _math(), _image()]) {
        final t = o.transformed(move);
        expect(t.id, o.id);
        expect(t.pageId, o.pageId);
        expect(t.createdAt, o.createdAt);
        expect(t.updatedAt, o.updatedAt);
        expect(t.version, o.version);
        expect(t.runtimeType, o.runtimeType);
      }
    });

    test('the identity transform changes nothing', () {
      for (final o in kSampleObjects.values) {
        expect(o.transformed(Affine2.identity), o, reason: o.id);
      }
    });
  });

  group('normalization (6.2.3)', () {
    test(
      'ShapeStyle: colors opaque, widths and opacities clamped, NaN → default',
      () {
        const s = ShapeStyle(
          strokeColorArgb: 0x00123456,
          strokeWidth: 100,
          strokeOpacity: 0,
          fillColorArgb: 0x80ABCDEF,
          fillOpacity: 5,
        );
        expect(
          s.normalized(),
          const ShapeStyle(
            strokeColorArgb: 0xFF123456,
            strokeWidth: 30,
            strokeOpacity: 0.05,
            fillColorArgb: 0xFFABCDEF,
            fillOpacity: 1,
          ),
        );
        expect(
          const ShapeStyle(
            strokeColorArgb: 1,
            strokeWidth: double.nan,
            strokeOpacity: double.nan,
            fillOpacity: double.nan,
          ).normalized(),
          const ShapeStyle(strokeColorArgb: 0xFF000001),
        );
        expect(
          const ShapeStyle(
            strokeColorArgb: 1,
            strokeWidth: 0.01,
          ).normalized().strokeWidth,
          0.1,
        );
        expect(
          const ShapeStyle(
            strokeColorArgb: 1,
            fillOpacity: -1,
          ).normalized().fillOpacity,
          0,
        );
      },
    );

    test('TextBoxStyle: size [6, 144], color opaque, lineHeight [1, 3], background as is', () {
      const s = TextBoxStyle(
        fontSizePt: 500,
        colorArgb: 0x10203040,
        lineHeight: 0.5,
        backgroundArgb: 0x33FFE600,
      );
      expect(
        s.normalized(),
        const TextBoxStyle(
          fontSizePt: 144,
          colorArgb: 0xFF203040,
          lineHeight: 1,
          backgroundArgb: 0x33FFE600,
        ),
      );
      expect(
        const TextBoxStyle(fontSizePt: 1, lineHeight: 9).normalized(),
        const TextBoxStyle(fontSizePt: 6, lineHeight: 3),
      );
      expect(
        const TextBoxStyle(fontSizePt: double.nan).normalized().fontSizePt,
        16,
      );
    });

    test('MathStyle: color opaque, size [6, 144]', () {
      expect(
        const MathStyle(colorArgb: 0x7F000000, fontSizePt: 1).normalized(),
        const MathStyle(colorArgb: 0xFF000000, fontSizePt: 6),
      );
      expect(const MathStyle(fontSizePt: 200).normalized().fontSizePt, 144);
    });

    test('already normal styles are unchanged', () {
      const shape = ShapeStyle(strokeColorArgb: 0xFF1A1A1A);
      expect(shape.normalized(), shape);
      expect(const TextBoxStyle().normalized(), const TextBoxStyle());
      expect(const MathStyle().normalized(), const MathStyle());
    });
  });

  group('copyWith, copyTo, copyWithMeta', () {
    test('style copyWith (clearFill, clearBackground)', () {
      const s = ShapeStyle(strokeColorArgb: 1, fillColorArgb: 2);
      expect(s.copyWith(strokeWidth: 3).strokeWidth, 3);
      expect(s.copyWith(strokeWidth: 3).fillColorArgb, 2);
      expect(s.copyWith(clearFill: true).fillColorArgb, isNull);
      expect(
        s.copyWith(dash: LineDash.dotted, arrowHeads: ArrowHeads.end),
        const ShapeStyle(
          strokeColorArgb: 1,
          fillColorArgb: 2,
          dash: LineDash.dotted,
          arrowHeads: ArrowHeads.end,
        ),
      );
      const t = TextBoxStyle(backgroundArgb: 5);
      expect(
        t.copyWith(bold: true),
        const TextBoxStyle(backgroundArgb: 5, bold: true),
      );
      expect(t.copyWith(clearBackground: true), const TextBoxStyle());
      expect(
        const MathStyle().copyWith(fontSizePt: 20),
        const MathStyle(fontSizePt: 20),
      );
    });

    test('object copyWith keeps id, page, createdAt, deletedAt, version', () {
      final s = _shape().copyWith(shapeKind: ShapeKind.arrow, updatedAt: 99);
      expect(s.shapeKind, ShapeKind.arrow);
      expect(s.updatedAt, 99);
      expect(s.createdAt, 10);
      expect(s.version, kV);
      final t = _text().copyWith(text: 'x');
      expect(t.text, 'x');
      expect(t.updatedAt, 20);
      final m = _math().copyWith(latex: 'y', engineId: 'claude/1');
      expect([m.latex, m.engineId], ['y', 'claude/1']);
      final i = _image().copyWith(
        frame: const ElementFrame(PageRect(0, 0, 1, 1)),
      );
      expect(i.frame.rect, const PageRect(0, 0, 1, 1));
    });

    test('copyTo: new id, page, createdAt; updatedAt = createdAt; version and deletedAt cleared', () {
      for (final o in kSampleObjects.values) {
        final c = o.copyTo(id: 'new-id', pageId: 'p9', createdAt: 77);
        expect(c.id, 'new-id', reason: o.id);
        expect(c.pageId, 'p9');
        expect(c.createdAt, 77);
        expect(c.updatedAt, 77);
        expect(c.version, isNull);
        expect(c.deletedAt, isNull);
        expect(c.type, o.type);
        expect(c.runtimeType, o.runtimeType);
        // Every other key is the same.
        final strip = {
          'id',
          'pageId',
          'createdAt',
          'updatedAt',
          'deletedAt',
          'version',
        };
        Map<String, Object?> body(PageObject x) =>
            Map.of(x.toJson())..removeWhere((k, _) => strip.contains(k));
        expect(jsonEncode(body(c)), jsonEncode(body(o)), reason: o.id);
      }
      final u = kSampleObjects['unknown']!.copyTo(
        id: 'u2',
        pageId: 'p2',
        createdAt: 3,
      ) as UnknownObject;
      expect(
        u.rawJson['sticker'],
        (kSampleObjects['unknown']! as UnknownObject).rawJson['sticker'],
      );
      expect(u.rawJson['id'], 'u2');
    });

    test('copyWithMeta changes updatedAt, deletedAt, version only', () {
      final v2 = Hlc.parse('001793750500000-0001-3f2a9c0d11e0b7a4');
      for (final o in kSampleObjects.values) {
        final c = o.copyWithMeta(updatedAt: 500, deletedAt: 600, version: v2);
        expect(
          [c.updatedAt, c.deletedAt, c.version],
          [500, 600, v2],
          reason: o.id,
        );
        expect(c.createdAt, o.createdAt);
        final cleared = c.copyWithMeta(clearDeletedAt: true);
        expect(cleared.deletedAt, isNull);
        expect(cleared.version, v2);
        expect(cleared.updatedAt, 500);
        expect(o.copyWithMeta(), o, reason: '${o.id} unchanged');
      }
    });
  });

  test('== and hashCode over every field', () {
    expect(_shape(), _shape());
    expect(_shape().hashCode, _shape().hashCode);
    expect(_shape(), isNot(_shape(kind: ShapeKind.arrow)));
    expect(_text(), isNot(_text(fontSizePt: 17)));
    expect(_math(), isNot(_math().copyWith(engineId: 'x')));
    expect(_image(), isNot(_image().copyWithMeta(updatedAt: 1)));
  });

  test('estimatedBytes (4.3 formula)', () {
    expect(_text().estimatedBytes, 160 + 2 * '안녕 hello'.length);
    expect(_math().estimatedBytes, 160 + 2 * r'\frac{a}{b}'.length);
    expect(_shape().estimatedBytes, 160 + 16 * 2);
    expect(kSampleObjects['shape_ellipse']!.estimatedBytes, 160);
    expect(_image().estimatedBytes, 160);
    final u = kSampleObjects['unknown']! as UnknownObject;
    expect(u.estimatedBytes, 160 + 2 * jsonEncode(u.rawJson).length);
    // A 10,000-char text box: about 20 KB.
    expect(_text().copyWith(text: 'a' * 10000).estimatedBytes, 20160);
  });
}
