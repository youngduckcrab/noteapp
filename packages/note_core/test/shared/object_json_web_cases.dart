// Shared body (m5-7/02-core 6.2.1, 6.3 '웹 형식'): ElementFrame / page object / handwriting
// JSON as the web build writes it — reals without a fraction arrive as integers — and the
// frame boundary round trips. Run on the VM (test/model/object_json_web_format_test.dart) and
// in Chrome (test/web/object_json_browser_test.dart). Web-safe.
import 'dart:convert';
import 'dart:math' as math;

import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

const String _v = '001793750400000-0000-3f2a9c0d11e0b7a4';

Map<String, Object?> _decode(String text) =>
    jsonDecode(text) as Map<String, Object?>;

void defineObjectJsonWebCases() {
  group('ElementFrame JSON', () {
    test('integers are read as reals (web jsonEncode(1.0) == "1")', () {
      final f = ElementFrame.fromJson(
        jsonDecode('[1,2,301,402,0]') as List<Object?>,
      );
      expect(f, const ElementFrame(PageRect(1, 2, 301, 402)));
      expect(f.toJson(), [1.0, 2.0, 301.0, 402.0, 0.0]);
    });

    test('8 kinds of bad input are FormatException', () {
      const bad = <List<Object?>>[
        [0, 0, 1, 1], // 4 numbers
        [0, 0, 1, 1, 0, 0], // 6 numbers
        [0, 0, '1', 1, 0], // a string
        [0, 0, 1, null, 0], // null
        [0, 0, double.nan, 1, 0], // not finite (local maps can carry it)
        [10, 0, 5, 1, 0], // right < left
        [0, 10, 1, 5, 0], // bottom < top
        [0, 0, 14400.0001, 1, 0], // a side larger than maxSide
      ];
      for (final json in bad) {
        expect(
          () => ElementFrame.fromJson(json),
          throwsFormatException,
          reason: '$json',
        );
      }
      expect(
        () => ElementFrame.fromJson(const [0, 0, 1, 14400.0001, 0]),
        throwsFormatException,
      );
    });

    test(
      'boundary values round-trip unchanged (fromJson never normalizes)',
      () {
        final cases = <List<double>>[
          [10, 20, 110, 70, -math.pi],
          [10, 20, 110, 70, 3 * math.pi],
          [10, 10, 10, 40, 0], // width 0 (a vertical line)
          [5, 5, 5, 5, 0], // a point
          [0, 0, 14400, 14400, 0], // the largest box
        ];
        for (final json in cases) {
          final f = ElementFrame.fromJson(json);
          expect(f.toJson(), json, reason: '$json');
          expect(f.rotation, json[4]);
          expect(
            f,
            ElementFrame(
              PageRect(json[0], json[1], json[2], json[3]),
              rotation: json[4],
            ),
          );
          expect(
            ElementFrame.fromJson(
              jsonDecode(jsonEncode(f.toJson())) as List<Object?>,
            ),
            f,
          );
        }
        // == is over the raw values: -pi and pi are different frames.
        expect(
          ElementFrame.fromJson(cases[0]),
          isNot(ElementFrame.fromJson([10, 20, 110, 70, math.pi])),
        );
      },
    );
  });

  group('page objects written by the web build', () {
    test('shape: integer reals in geometry and style', () {
      final o = PageObject.fromJson(
        _decode(
          '{"id":"s1","pageId":"p1","type":"shape","frame":[0,0,1,1,0],'
          '"shape":"rectangle","geometry":{"poly":[120,80,320,80,320,200,120,200],'
          '"closed":true},"style":{"strokeColorArgb":4279900698,"strokeWidth":2,'
          '"strokeOpacity":1,"dash":"solid","fillColorArgb":null,"fillOpacity":1,'
          '"arrowHeads":"none"},"createdAt":1793750400000,"updatedAt":1793750400000,'
          '"deletedAt":null,"version":"$_v"}',
        ),
      );
      final s = o as ShapeObject;
      expect(s.style.strokeWidth, 2.0);
      expect(s.style.fillOpacity, 1.0);
      expect(
        (s.geometry as PolylineGeometry).points.first,
        const PagePoint(120, 80),
      );
      // The written frame is ignored: the frame comes from the geometry.
      expect(s.frame, const ElementFrame(PageRect(120, 80, 320, 200)));
      expect(s.toJson()['frame'], [120.0, 80.0, 320.0, 200.0, 0.0]);
    });

    test('ellipse, text, image, math', () {
      final ellipse = PageObject.fromJson(
        _decode(
          '{"id":"e1","pageId":"p1","type":"shape","frame":[0,0,0,0,0],'
          '"shape":"ellipse","geometry":{"ellipse":[100,300,260,400,0]},'
          '"style":{"strokeColorArgb":1,"strokeWidth":3},"createdAt":1,'
          '"updatedAt":1}',
        ),
      );
      expect(
        (ellipse as ShapeObject).geometry,
        const EllipseGeometry(ElementFrame(PageRect(100, 300, 260, 400))),
      );
      final text = PageObject.fromJson(
        _decode(
          '{"id":"t1","pageId":"p1","type":"text","frame":[60,620,360,690,0],'
          '"text":"안녕\\nhello","style":{"fontSizePt":18,"colorArgb":4279900698,'
          '"bold":true,"align":"center","lineHeight":2,"backgroundArgb":null},'
          '"createdAt":1,"updatedAt":2,"deletedAt":null,"version":null}',
        ),
      );
      expect((text as TextBoxObject).text, '안녕\nhello');
      expect(text.style.fontSizePt, 18.0);
      expect(text.style.lineHeight, 2.0);
      expect(text.style.align, TextAlignKind.center);
      final image = PageObject.fromJson(
        _decode(
          '{"id":"i1","pageId":"p1","type":"image","frame":[0,0,200,150,0],'
          '"assetId":"${'a' * 64}","px":[1600,1200],"createdAt":1,"updatedAt":1}',
        ),
      );
      expect((image as ImageObject).pixelWidth, 1600);
      expect(image.referencedAssets, {'a' * 64});
      final mathObject = PageObject.fromJson(
        _decode(
          '{"id":"m1","pageId":"p1","type":"math","frame":[0,0,10,10,0],'
          r'"latex":"\\frac{a}{b}","style":{"colorArgb":1,"fontSizePt":18},'
          '"engine":null,"createdAt":1,"updatedAt":1}',
        ),
      );
      expect((mathObject as MathObject).latex, r'\frac{a}{b}');
      expect(mathObject.style.fontSizePt, 18.0);
      expect(mathObject.engineId, isNull);
    });

    test(
      'every known type round-trips through jsonEncode on this platform',
      () {
        final objects = <PageObject>[
          ShapeObject(
            id: 's1',
            pageId: 'p1',
            shapeKind: ShapeKind.arrow,
            geometry: const PolylineGeometry([
              PagePoint(0.5, 1),
              PagePoint(20, 30.25),
            ], closed: false),
            style: const ShapeStyle(
              strokeColorArgb: 0xFF00FF00,
              dash: LineDash.dotted,
              arrowHeads: ArrowHeads.end,
            ),
            createdAt: 1,
          ),
          TextBoxObject(
            id: 't1',
            pageId: 'p1',
            frame: const ElementFrame(PageRect(0, 0, 100, 20), rotation: 0.5),
            text: '줄1\n줄2',
            style: const TextBoxStyle(backgroundArgb: 0x80FFFFFF),
            createdAt: 2,
            deletedAt: 3,
          ),
          MathObject(
            id: 'm1',
            pageId: 'p1',
            frame: const ElementFrame(PageRect(0, 0, 50, 20)),
            latex: 'x^2',
            style: const MathStyle(),
            engineId: 'claude/1',
            createdAt: 4,
          ),
        ];
        for (final o in objects) {
          final again = PageObject.fromJson(
            jsonDecode(jsonEncode(o.toJson())) as Map<String, Object?>,
          );
          expect(again, o);
        }
      },
    );

    test('handwriting with integer reals in line rects', () {
      final hw = HandwritingText.fromJson(
        _decode(
          '{"id":"hw_p1","noteId":"n1","pageId":"p1","engineId":"fake",'
          '"sourceRev":"e3b0c44298fc1c14","lines":[{"text":"회의","alternatives":[],'
          '"rect":[10,20,110,40],"strokeIds":["s1"],"languageTag":"ko",'
          '"userConfirmed":false}],"createdAt":1,"updatedAt":1,"deletedAt":null,'
          '"version":null}',
        ),
      );
      expect(hw.lines.single.rect, const PageRect(10, 20, 110, 40));
      expect(
        HandwritingText.fromJson(
          jsonDecode(jsonEncode(hw.toJson())) as Map<String, Object?>,
        ),
        hw,
      );
    });
  });
}

/// Calligraphy nib angle under TransformElements (C2-38, m5-7/02-core 6.2.7) — VM:
/// test/edit/calligraphy_transform_test.dart, Chrome: test/web/object_json_browser_test.dart.
void defineCalligraphyTransformCases() {
  group('Stroke.transformed: calligraphy nib angle (C2-38)', () {
    final ids = SequentialIdGenerator(prefix: 'c');
    Stroke pen(PenTool tool, Map<String, Object?> extras) => Stroke(
      id: ids.newId(),
      pageId: 'p1',
      style: StrokeStyle.defaultsFor(tool).copyWith(extras: extras),
      points: StrokePoints.fromList(const [
        StrokePoint(10, 10, widthQ: 0.5, t: 0),
        StrokePoint(20, 15, widthQ: 0.5, t: 8),
      ]),
      createdAt: 1,
    );
    double? nib(Stroke s) =>
        (s.style.extras['nibAngleDeg'] as num?)?.toDouble();
    Affine2 turn(double deg) => Affine2.rotation(deg * math.pi / 180);

    test('no key + 30° → 75', () {
      final s = pen(PenTool.calligraphy, const {});
      expect(nib(s.transformed(turn(30))), closeTo(75, 1e-9));
    });

    test('170 + 30° → 20 (folded into [0, 180))', () {
      final s = pen(PenTool.calligraphy, const {'nibAngleDeg': 170});
      expect(nib(s.transformed(turn(30))), closeTo(20, 1e-9));
    });

    test('-90° → 135', () {
      final s = pen(PenTool.calligraphy, const {});
      expect(nib(s.transformed(turn(-90))), closeTo(135, 1e-9));
    });

    test('180° and a move: extras unchanged (no key written)', () {
      final s = pen(PenTool.calligraphy, const {});
      expect(s.transformed(turn(180)).style.extras, isEmpty);
      expect(s.transformed(Affine2.rotation(math.pi)).style.extras, isEmpty);
      expect(s.transformed(Affine2.translation(5, 5)).style.extras, isEmpty);
      expect(s.transformed(Affine2.scaling(2, 2)).style.extras, isEmpty);
      final keyed = pen(PenTool.calligraphy, const {'nibAngleDeg': 30});
      expect(keyed.transformed(turn(180)).style, keyed.style);
    });

    test('a ballpoint stroke is unchanged', () {
      final s = pen(PenTool.ballpoint, const {});
      expect(s.transformed(turn(30)).style, s.style);
    });

    test("a non-number value ('x') is read as 45", () {
      final s = pen(PenTool.calligraphy, const {'nibAngleDeg': 'x', 'k': 1});
      final t = s.transformed(turn(30));
      expect(nib(t), closeTo(75, 1e-9));
      expect(t.style.extras['k'], 1);
      expect(t.style.extras['nibAngleDeg'], isA<double>());
    });
  });
}
