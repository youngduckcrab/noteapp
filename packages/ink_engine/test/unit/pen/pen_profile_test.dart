// T02 (03-ink 8, 6.9): the per-tool behaviour rows, and CORE
// StrokeStyle.defaultsFor = the 6.9 default rows (contract 7.2.4). If CORE's
// defaults drift from the table, this fails → contract change procedure.
// v2 (m5-7/03-ink T27, 6.2): the five P1 profiles, defaultsFor for all ten
// tools, and the PenProfile.of mapping (brush since T27, calligraphy T28,
// dashed T29, tape T31; laser still ballpoint until T30 — each task updates
// its row).
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

typedef _Row = ({
  InkLayer layer,
  double pressureGain,
  double minFactor,
  double maxFactor,
  double velocityThinning,
  double taperStart,
  double taperEnd,
  double taperMinFactor,
  double tiltWidthGain,
  double tiltOpacityLoss,
  InkCap cap,
  InkRenderMethod renderMethod,
  bool textured,
  bool groupComposite,
});

_Row _row(PenProfile p) => (
  layer: p.layer,
  pressureGain: p.pressureGain,
  minFactor: p.minFactor,
  maxFactor: p.maxFactor,
  velocityThinning: p.velocityThinning,
  taperStart: p.taperStart,
  taperEnd: p.taperEnd,
  taperMinFactor: p.taperMinFactor,
  tiltWidthGain: p.tiltWidthGain,
  tiltOpacityLoss: p.tiltOpacityLoss,
  cap: p.cap,
  renderMethod: p.renderMethod,
  textured: p.textured,
  groupComposite: p.groupComposite,
);

const List<PenProfile> _all = [
  PenProfile.ballpoint,
  PenProfile.fountain,
  PenProfile.highlighter,
  PenProfile.pencil,
  PenProfile.marker,
  PenProfile.brush,
  PenProfile.calligraphy,
  PenProfile.dashed,
  PenProfile.laser,
  PenProfile.tape,
];

void main() {
  test('behaviour rows (6.9 snapshot)', () {
    // taperMinFactor '—' in the table = 1 (no taper).
    expect(_row(PenProfile.ballpoint), (
      layer: InkLayer.ink,
      pressureGain: 0.18,
      minFactor: 0.80,
      maxFactor: 1.25,
      velocityThinning: 0.0,
      taperStart: 0.0,
      taperEnd: 0.0,
      taperMinFactor: 1.0,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
      cap: InkCap.round,
      renderMethod: InkRenderMethod.filledOutline,
      textured: false,
      groupComposite: false,
    ));
    expect(_row(PenProfile.fountain), (
      layer: InkLayer.ink,
      pressureGain: 0.75,
      minFactor: 0.30,
      maxFactor: 1.80,
      velocityThinning: 0.25,
      taperStart: 1.5,
      taperEnd: 3.0,
      taperMinFactor: 0.15,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
      cap: InkCap.round,
      renderMethod: InkRenderMethod.filledOutline,
      textured: false,
      groupComposite: false,
    ));
    expect(_row(PenProfile.highlighter), (
      layer: InkLayer.highlighter,
      pressureGain: 0.0,
      minFactor: 1.0,
      maxFactor: 1.0,
      velocityThinning: 0.0,
      taperStart: 0.0,
      taperEnd: 0.0,
      taperMinFactor: 1.0,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
      cap: InkCap.square,
      renderMethod: InkRenderMethod.strokedPolyline,
      textured: false,
      groupComposite: true,
    ));
    expect(_row(PenProfile.pencil), (
      layer: InkLayer.ink,
      pressureGain: 0.45,
      minFactor: 0.50,
      maxFactor: 1.60,
      velocityThinning: 0.0,
      taperStart: 2.0,
      taperEnd: 2.0,
      taperMinFactor: 0.30,
      tiltWidthGain: 1.8,
      tiltOpacityLoss: 0.5,
      cap: InkCap.round,
      renderMethod: InkRenderMethod.filledOutline,
      textured: true,
      groupComposite: false,
    ));
    expect(_row(PenProfile.marker), (
      layer: InkLayer.ink,
      pressureGain: 0.12,
      minFactor: 0.85,
      maxFactor: 1.15,
      velocityThinning: 0.0,
      taperStart: 0.0,
      taperEnd: 0.0,
      taperMinFactor: 1.0,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
      cap: InkCap.round,
      renderMethod: InkRenderMethod.filledOutline,
      textured: false,
      groupComposite: false,
    ));
  });

  test('P1 behaviour rows (m5-7/03-ink 6.2)', () {
    expect(_row(PenProfile.brush), (
      layer: InkLayer.ink,
      pressureGain: 0.90,
      minFactor: 0.20,
      maxFactor: 2.20,
      velocityThinning: 0.30,
      taperStart: 2.5,
      taperEnd: 5.0,
      taperMinFactor: 0.08,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
      cap: InkCap.round,
      renderMethod: InkRenderMethod.filledOutline,
      textured: false,
      groupComposite: false,
    ));
    expect(_row(PenProfile.calligraphy), (
      layer: InkLayer.ink,
      pressureGain: 0.35,
      minFactor: 0.60,
      maxFactor: 1.40,
      velocityThinning: 0.0,
      taperStart: 0.0,
      taperEnd: 0.0,
      taperMinFactor: 1.0,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
      cap: InkCap.round,
      renderMethod: InkRenderMethod.nibOutline,
      textured: false,
      groupComposite: false,
    ));
    const constant = (
      pressureGain: 0.0,
      minFactor: 1.0,
      maxFactor: 1.0,
      velocityThinning: 0.0,
      taperStart: 0.0,
      taperEnd: 0.0,
      taperMinFactor: 1.0,
      tiltWidthGain: 0.0,
      tiltOpacityLoss: 0.0,
    );
    for (final (profile, layer, cap, method) in [
      (
        PenProfile.dashed,
        InkLayer.ink,
        InkCap.round,
        InkRenderMethod.dashedPolyline,
      ),
      (
        PenProfile.laser,
        InkLayer.ink,
        InkCap.round,
        InkRenderMethod.transientTrail,
      ),
      (
        PenProfile.tape,
        InkLayer.cover,
        InkCap.square,
        InkRenderMethod.filledOutline,
      ),
    ]) {
      expect(_row(profile), (
        layer: layer,
        pressureGain: constant.pressureGain,
        minFactor: constant.minFactor,
        maxFactor: constant.maxFactor,
        velocityThinning: constant.velocityThinning,
        taperStart: constant.taperStart,
        taperEnd: constant.taperEnd,
        taperMinFactor: constant.taperMinFactor,
        tiltWidthGain: constant.tiltWidthGain,
        tiltOpacityLoss: constant.tiltOpacityLoss,
        cap: cap,
        renderMethod: method,
        textured: false,
        groupComposite: false,
      ), reason: '$profile');
    }
    // ten distinct values
    expect(_all.toSet(), hasLength(10));
  });

  test('PenProfile.of: P0 tools, brush, calligraphy, dashed and tape → their '
      'profile; laser → ballpoint until T30', () {
    expect(PenProfile.of(core.PenTool.ballpoint), same(PenProfile.ballpoint));
    expect(PenProfile.of(core.PenTool.fountain), same(PenProfile.fountain));
    expect(
      PenProfile.of(core.PenTool.highlighter),
      same(PenProfile.highlighter),
    );
    expect(PenProfile.of(core.PenTool.pencil), same(PenProfile.pencil));
    expect(PenProfile.of(core.PenTool.marker), same(PenProfile.marker));
    expect(PenProfile.of(core.PenTool.brush), same(PenProfile.brush));
    expect(PenProfile.of(core.PenTool.dashed), same(PenProfile.dashed));
    expect(PenProfile.of(core.PenTool.tape), same(PenProfile.tape));
    expect(
      PenProfile.of(core.PenTool.calligraphy),
      same(PenProfile.calligraphy),
    );
    expect(PenProfile.of(core.PenTool.laser), same(PenProfile.ballpoint));
    expect(
      core.StrokeStyle.defaultsFor(core.PenTool.brush).profile,
      same(PenProfile.brush),
    );
  });

  test(
    'factor ranges: 0 < min ≤ max; pencil full pressure + tilt = 4.48 (K4)',
    () {
      for (final p in _all) {
        expect(p.minFactor, greaterThan(0));
        expect(p.minFactor, lessThanOrEqualTo(p.maxFactor));
        expect(p.taperMinFactor, inInclusiveRange(0.0, 1.0));
      }
      // brush: the factor bound 2.20 stays below the K6 saturation (6.2)
      expect(PenProfile.brush.maxFactor, lessThan(core.kMaxWidthFactor));
      // dashed, laser, tape: widthQ is exactly kNominalWidthQ (f = 1)
      for (final p in [PenProfile.dashed, PenProfile.laser, PenProfile.tape]) {
        expect(
          1 + p.pressureGain * (2 * 1.0 - 1),
          1.0,
          reason: '$p full pressure',
        );
        expect([p.minFactor, p.maxFactor], [1.0, 1.0]);
      }
      const pencil = PenProfile.pencil;
      // Above kMaxWidthFactor (4): widthQ saturates at 1 (6.7 K4, K6).
      expect(
        pencil.maxFactor * (1 + pencil.tiltWidthGain),
        closeTo(4.48, 1e-9),
      );
    },
  );

  test('value equality', () {
    const b = PenProfile.ballpoint;
    final copy = PenProfile(
      layer: b.layer,
      pressureGain: b.pressureGain,
      minFactor: b.minFactor,
      maxFactor: b.maxFactor,
      velocityThinning: b.velocityThinning,
      taperStart: b.taperStart,
      taperEnd: b.taperEnd,
      taperMinFactor: b.taperMinFactor,
      tiltWidthGain: b.tiltWidthGain,
      tiltOpacityLoss: b.tiltOpacityLoss,
      cap: b.cap,
      renderMethod: b.renderMethod,
      textured: b.textured,
      groupComposite: b.groupComposite,
    );
    expect(identical(copy, b), isFalse);
    expect(copy, PenProfile.ballpoint);
    expect(copy.hashCode, PenProfile.ballpoint.hashCode);
    expect(PenProfile.ballpoint == PenProfile.marker, isFalse);
  });

  test(
    'core.StrokeStyle.defaultsFor (5 P1 tools) = m5-7/03-ink 6.2 ¹ rows',
    () {
      final table =
          <core.PenTool, (double, double, int, double, Map<String, Object?>)>{
            core.PenTool.brush: (2.0, 1.0, 0xFF1F1F1F, 0.5, const {}),
            core.PenTool.calligraphy: (
              2.5,
              1.0,
              0xFF1F1F1F,
              0.5,
              const {'nibAngleDeg': 45},
            ),
            core.PenTool.dashed: (
              1.0,
              1.0,
              0xFF1F1F1F,
              0.5,
              const {
                'dash': [4, 3],
              },
            ),
            core.PenTool.laser: (3.0, 1.0, 0xFFFF3B30, 0.5, const {}),
            core.PenTool.tape: (14.0, 1.0, 0xFF7E57C2, 0.3, const {}),
          };
      expect(table.keys.toSet(), {
        for (final t in core.PenTool.values)
          if (!t.isP0) t,
      });
      for (final MapEntry(key: tool, value: row) in table.entries) {
        final s = core.StrokeStyle.defaultsFor(tool);
        expect(s.tool, tool);
        expect(s.width, row.$1, reason: '${tool.name} width');
        expect(s.opacity, row.$2, reason: '${tool.name} opacity');
        expect(s.colorArgb, row.$3, reason: '${tool.name} color');
        expect(s.smoothing, row.$4, reason: '${tool.name} smoothing');
        expect(s.extras, row.$5, reason: '${tool.name} extras');
        expect(s.pressureSensitivity, 1.0, reason: '${tool.name} sensitivity');
        expect(s.pressureCurve, core.PressureCurve.linear);
        expect(s.normalized(), s);
      }
      // the extras read back as the 6.2 defaults
      expect(
        core.StrokeStyle.defaultsFor(core.PenTool.calligraphy).nibAngleDeg,
        45,
      );
      expect(core.StrokeStyle.defaultsFor(core.PenTool.dashed).dashPattern, [
        4,
        3,
      ]);
      expect(
        core.StrokeStyle.defaultsFor(core.PenTool.laser).laserFadeMs,
        1500,
      );
      expect(
        core.StrokeStyle.defaultsFor(core.PenTool.tape).tapeStyle,
        InkTapeStyle.solid,
      );
    },
  );

  test('core.StrokeStyle.defaultsFor (5 P0 tools) = 6.9 default rows', () {
    // (width pt, opacity, color, smoothing, extras); pressureSensitivity 1.0,
    // pressureCurve linear for all.
    final table =
        <core.PenTool, (double, double, int, double, Map<String, Object?>)>{
          core.PenTool.ballpoint: (1.6, 1.0, 0xFF1A1A1A, 0.5, const {}),
          core.PenTool.fountain: (2.2, 1.0, 0xFF1B2A6B, 0.55, const {}),
          core.PenTool.highlighter: (
            12.0,
            0.35,
            0xFFFFE600,
            0.3,
            const {'hlStraight': 'off'},
          ),
          core.PenTool.pencil: (1.4, 0.9, 0xFF3C3C3C, 0.4, const {}),
          core.PenTool.marker: (5.0, 1.0, 0xFF1A1A1A, 0.5, const {}),
        };
    for (final MapEntry(key: tool, value: row) in table.entries) {
      final s = core.StrokeStyle.defaultsFor(tool);
      expect(s.tool, tool);
      expect(s.width, row.$1, reason: '${tool.name} width');
      expect(s.opacity, row.$2, reason: '${tool.name} opacity');
      expect(s.colorArgb, row.$3, reason: '${tool.name} color');
      expect(s.smoothing, row.$4, reason: '${tool.name} smoothing');
      expect(s.extras, row.$5, reason: '${tool.name} extras');
      expect(s.pressureSensitivity, 1.0, reason: '${tool.name} sensitivity');
      expect(s.pressureCurve, core.PressureCurve.linear);
      // Already normalized (alpha 0xFF, ranges).
      expect(s.normalized(), s);
    }
    expect(
      core.StrokeStyle.defaultsFor(core.PenTool.highlighter)
          .highlighterStraightening,
      HighlighterStraightening.off,
    );
  });
}
