import 'package:note_core/note_core.dart';
import 'package:test/test.dart';

void main() {
  group('PenTool', () {
    test('P0 / P1 and wire names', () {
      expect(PenTool.values.where((t) => t.isP0), [
        PenTool.ballpoint,
        PenTool.fountain,
        PenTool.highlighter,
        PenTool.pencil,
        PenTool.marker,
      ]);
      for (final t in PenTool.values) {
        expect(t.wireName, t.name);
        expect(PenTool.fromWireName(t.wireName), t);
      }
      expect(() => PenTool.fromWireName('stamp'), throwsFormatException);
      expect(PenTool.tryFromWireName('stamp'), isNull);
      expect(PenTool.tryFromWireName('crayon'), PenTool.crayon);
    });

    test('(C211-01) new pens are appended after tape: old indices stay', () {
      expect(PenTool.values.map((t) => t.name), [
        'ballpoint',
        'fountain',
        'highlighter',
        'pencil',
        'marker',
        'brush',
        'calligraphy',
        'dashed',
        'laser',
        'tape',
        'crayon',
        'chalk',
        'watercolor',
        'spray',
        'neon',
        'jelly',
        'rainbow',
        'glitter',
      ]);
    });
  });

  group('(C211-01) unknown tool names (forward compatibility)', () {
    Map<String, Object?> json(String tool, [Map<String, Object?>? extras]) => {
      ...StrokeStyle.defaultsFor(PenTool.ballpoint).toJson(),
      'tool': tool,
      'extras': ?extras,
    };

    test('decode as ballpoint, keep the name, write it back', () {
      final s = StrokeStyle.fromJson(json('stamp', {'a': 1}));
      expect(s.tool, PenTool.ballpoint);
      expect(s.extras, {'a': 1, kUnknownPenToolKey: 'stamp'});
      expect(s.wireToolName, 'stamp');
      expect(s.toJson()['tool'], 'stamp');
      expect(StrokeStyle.fromJson(s.toJson()), s);
      // a restyle (lasso color change) keeps the pen for the newer app
      final recolored = const StrokeStylePatch(colorArgb: 0xFF00FF00)
          .applyTo(s);
      expect(recolored.toJson()['tool'], 'stamp');
    });

    test('a known name drops a stale key', () {
      final s = StrokeStyle.fromJson(
        json('crayon', {kUnknownPenToolKey: 'crayon', 'b': 2}),
      );
      expect(s.tool, PenTool.crayon);
      expect(s.extras, {'b': 2});
      expect(s.wireToolName, 'crayon');
    });

    test('Stroke.fromJson does not throw on an unknown pen', () {
      final style = StrokeStyle.fromJson(json('stamp'));
      expect(style.tool, PenTool.ballpoint);
      expect(style.extras, {kUnknownPenToolKey: 'stamp'});
    });
  });

  group('StrokeStyle.defaultsFor (contract 7.2.4 table, CORE 6.2.2)', () {
    // tool: (color, width, opacity, smoothing, extras)
    const table =
        <PenTool, (int, double, double, double, Map<String, Object?>)>{
          PenTool.ballpoint: (0xFF1A1A1A, 1.6, 1.0, 0.5, {}),
          PenTool.fountain: (0xFF1B2A6B, 2.2, 1.0, 0.55, {}),
          PenTool.highlighter: (
            0xFFFFE600,
            12.0,
            0.35,
            0.3,
            {'hlStraight': 'off'},
          ),
          PenTool.pencil: (0xFF3C3C3C, 1.4, 0.9, 0.4, {}),
          PenTool.marker: (0xFF1A1A1A, 5.0, 1.0, 0.5, {}),
          PenTool.brush: (0xFF1F1F1F, 2.0, 1.0, 0.5, {}),
          PenTool.calligraphy: (0xFF1F1F1F, 2.5, 1.0, 0.5, {'nibAngleDeg': 45}),
          PenTool.dashed: (
            0xFF1F1F1F,
            1.0,
            1.0,
            0.5,
            {
              'dash': [4, 3],
            },
          ),
          PenTool.laser: (0xFFFF3B30, 3.0, 1.0, 0.5, {}),
          PenTool.tape: (0xFF7E57C2, 14.0, 1.0, 0.3, {}),
          PenTool.crayon: (0xFFE5533D, 4.0, 1.0, 0.4, {}),
          PenTool.chalk: (0xFF4A6FA5, 4.0, 1.0, 0.4, {}),
          PenTool.watercolor: (0xFF2F80ED, 8.0, 1.0, 0.5, {}),
          PenTool.spray: (0xFF1F1F1F, 10.0, 1.0, 0.3, {}),
          PenTool.neon: (0xFFFF2D95, 6.0, 1.0, 0.5, {}),
          PenTool.jelly: (0xFF7C4DFF, 5.0, 1.0, 0.5, {}),
          PenTool.rainbow: (0xFFFF3B30, 4.0, 1.0, 0.5, {}),
          PenTool.glitter: (0xFFFFB300, 6.0, 1.0, 0.5, {}),
        };
    for (final MapEntry(key: tool, value: v) in table.entries) {
      test(tool.name, () {
        final s = StrokeStyle.defaultsFor(tool);
        expect(s.tool, tool);
        expect(s.colorArgb, v.$1);
        expect(s.width, v.$2);
        expect(s.opacity, v.$3);
        expect(s.smoothing, v.$4);
        expect(s.extras, v.$5);
        expect(s.pressureSensitivity, 1.0);
        expect(s.pressureCurve, PressureCurve.linear);
        expect(s.normalized(), s, reason: 'defaults are already normalized');
      });
    }
  });

  group('StrokeStyle.normalized', () {
    test('clamps every range, forces color alpha to 0xFF', () {
      const s = StrokeStyle(
        tool: PenTool.ballpoint,
        colorArgb: 0x80123456,
        width: 99,
        opacity: 0.01,
        pressureSensitivity: 2,
        pressureCurve: PressureCurve(x1: -1, y1: 2, x2: 0.5, y2: 0.5),
        smoothing: -0.5,
      );
      final n = s.normalized();
      expect(n.colorArgb, 0xFF123456);
      expect(n.width, StrokeStyle.maxWidth);
      expect(n.opacity, StrokeStyle.minOpacity);
      expect(n.pressureSensitivity, 1);
      expect(
        n.pressureCurve,
        const PressureCurve(x1: 0, y1: 1, x2: 0.5, y2: 0.5),
      );
      expect(n.smoothing, 0);
      expect(
        const StrokeStyle(
          tool: PenTool.pencil,
          colorArgb: 0xFF000000,
          width: 0.01,
        ).normalized().width,
        StrokeStyle.minWidth,
      );
    });

    test('NaN becomes the field default; width is not rounded', () {
      const s = StrokeStyle(
        tool: PenTool.ballpoint,
        colorArgb: 0xFF000000,
        width: double.nan,
        opacity: double.nan,
        smoothing: double.nan,
      );
      final n = s.normalized();
      expect(n.width.isNaN, isFalse);
      expect(n.opacity, 1);
      expect(n.smoothing, 0.5);
      expect(
        const StrokeStyle(
          tool: PenTool.ballpoint,
          colorArgb: 0xFF000000,
          width: 1.234,
        ).normalized().width,
        1.234,
      );
    });

    test('effectiveAlpha', () {
      const s = StrokeStyle(
        tool: PenTool.ballpoint,
        colorArgb: 0x80000000,
        width: 1,
        opacity: 0.5,
      );
      expect(s.effectiveAlpha, closeTo(128 / 255 * 0.5, 1e-12));
      expect(s.normalized().effectiveAlpha, 0.5);
    });

    test('copyWith, JSON round trip, value equality', () {
      final s = StrokeStyle.defaultsFor(PenTool.highlighter);
      expect(s.copyWith(width: 3).width, 3);
      expect(StrokeStyle.fromJson(s.toJson()), s);
      expect(s.toJson()['color'], 0xFFFFE600);
      expect(s.hashCode, StrokeStyle.fromJson(s.toJson()).hashCode);
      expect(
        () => StrokeStyle.fromJson({'tool': 'ballpoint'}),
        throwsFormatException,
      );
    });
  });

  group('StrokeStylePatch', () {
    test('isEmpty and applyTo (absolute width wins over widthScale)', () {
      expect(const StrokeStylePatch().isEmpty, isTrue);
      final base = StrokeStyle.defaultsFor(PenTool.ballpoint);
      expect(
        const StrokeStylePatch(width: 3, widthScale: 10).applyTo(base).width,
        3,
      );
      expect(const StrokeStylePatch(widthScale: 2).applyTo(base).width, 3.2);
      expect(
        const StrokeStylePatch(colorArgb: 0x00FF0000).applyTo(base).colorArgb,
        0xFFFF0000,
      );
      expect(const StrokeStylePatch(widthScale: 100).applyTo(base).width, 30);
    });
  });

  group('PressureCurve.evaluate (CORE 6.2.3)', () {
    test('linear is the identity', () {
      for (var i = 0; i <= 100; i++) {
        final x = i / 100;
        expect((PressureCurve.linear.evaluate(x) - x).abs(), lessThan(1e-6));
      }
    });

    test('soft / firm reference values (1e-4)', () {
      const xs = [0.1, 0.25, 0.5, 0.75, 0.9];
      const soft = [0.2533, 0.5198, 0.7955, 0.9416, 0.9855];
      const firm = [0.0145, 0.0584, 0.2045, 0.4802, 0.7467];
      for (var i = 0; i < xs.length; i++) {
        expect(PressureCurve.soft.evaluate(xs[i]), closeTo(soft[i], 1e-4));
        expect(PressureCurve.firm.evaluate(xs[i]), closeTo(firm[i], 1e-4));
      }
    });

    test('monotonic, ends fixed, input clamped', () {
      for (final c in [PressureCurve.soft, PressureCurve.firm]) {
        expect(c.evaluate(0), 0);
        expect(c.evaluate(1), closeTo(1, 1e-9));
        expect(c.evaluate(-3), 0);
        expect(c.evaluate(7), closeTo(1, 1e-9));
        var prev = -1.0;
        for (var i = 0; i <= 1000; i++) {
          final v = c.evaluate(i / 1000);
          expect(v, greaterThanOrEqualTo(prev));
          prev = v;
        }
      }
    });

    test('JSON', () {
      expect(PressureCurve.soft.toJson(), [0.15, 0.45, 0.45, 0.95]);
      expect(
        PressureCurve.fromJson([0.15, 0.45, 0.45, 0.95]),
        PressureCurve.soft,
      );
      expect(
        PressureCurve.fromJson([0, 0, 1, 1]),
        const PressureCurve(x1: 0, y1: 0, x2: 1, y2: 1),
      );
      expect(() => PressureCurve.fromJson([1]), throwsFormatException);
    });
  });
}
