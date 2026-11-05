// T02 (03-ink 8, 6.9): the per-tool behaviour rows, and CORE
// StrokeStyle.defaultsFor = the 6.9 default rows (contract 7.2.4). If CORE's
// defaults drift from the table, this fails → contract change procedure.
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

  test('PenProfile.of: P0 tools → their profile, P1 tools → ballpoint', () {
    expect(PenProfile.of(core.PenTool.ballpoint), same(PenProfile.ballpoint));
    expect(PenProfile.of(core.PenTool.fountain), same(PenProfile.fountain));
    expect(
      PenProfile.of(core.PenTool.highlighter),
      same(PenProfile.highlighter),
    );
    expect(PenProfile.of(core.PenTool.pencil), same(PenProfile.pencil));
    expect(PenProfile.of(core.PenTool.marker), same(PenProfile.marker));
    for (final tool in core.PenTool.values.where((t) => !t.isP0)) {
      expect(
        PenProfile.of(tool),
        same(PenProfile.ballpoint),
        reason: tool.name,
      );
    }
  });

  test(
    'factor ranges: 0 < min ≤ max; pencil full pressure + tilt = 4.48 (K4)',
    () {
      for (final tool in core.PenTool.values.where((t) => t.isP0)) {
        final p = PenProfile.of(tool);
        expect(p.minFactor, greaterThan(0));
        expect(p.minFactor, lessThanOrEqualTo(p.maxFactor));
        expect(p.taperMinFactor, inInclusiveRange(0.0, 1.0));
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
