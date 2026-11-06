// T24 (m5-7/03-ink 8.1, reading rules 4.10): the 2nd round style extras — keys,
// lenient getters (missing key, wrong type, out of range → default / clamp),
// withInkExtras keeps the other keys, CORE defaultsFor reads the same, and the
// CORE calligraphy nib angle key is INK's key (C2-38).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:note_core/note_core.dart' as core;

core.StrokeStyle _with(Map<String, Object?> extras) => const core.StrokeStyle(
  tool: core.PenTool.calligraphy,
  colorArgb: 0xFF000000,
  width: 2,
).copyWith(extras: extras);

void main() {
  test('wire keys (contract 7.2.9)', () {
    expect(InkStyleExtras.highlighterStraightening, 'hlStraight');
    expect(InkStyleExtras.nibAngleDeg, 'nibAngleDeg');
    expect(InkStyleExtras.nibAspect, 'nibAspect');
    expect(InkStyleExtras.followBarrelRoll, 'rollNib');
    expect(InkStyleExtras.dash, 'dash');
    expect(InkStyleExtras.laserFadeMs, 'laserFadeMs');
    expect(InkStyleExtras.tapeStyle, 'tapeStyle');
    expect(InkTapeStyle.values.map((v) => v.name), ['solid', 'striped']);
  });

  test('defaults when the keys are missing', () {
    final s = _with(const {});
    expect(s.nibAngleDeg, 45);
    expect(s.nibAspect, 0.25);
    expect(s.followBarrelRoll, isTrue);
    expect(s.dashPattern, [4, 3]);
    expect(s.laserFadeMs, 1500);
    expect(s.tapeStyle, InkTapeStyle.solid);
  });

  test('wrong types → defaults, never throws', () {
    final s = _with(const {
      'nibAngleDeg': '30',
      'nibAspect': true,
      'rollNib': 'yes',
      'dash': '4,3',
      'laserFadeMs': [1],
      'tapeStyle': 1,
    });
    expect(s.nibAngleDeg, 45);
    expect(s.nibAspect, 0.25);
    expect(s.followBarrelRoll, isTrue);
    expect(s.dashPattern, [4, 3]);
    expect(s.laserFadeMs, 1500);
    expect(s.tapeStyle, InkTapeStyle.solid);
    final nonFinite = _with(const {
      'nibAngleDeg': double.nan,
      'nibAspect': double.infinity,
      'laserFadeMs': double.negativeInfinity,
    });
    expect(nonFinite.nibAngleDeg, 45);
    expect(nonFinite.nibAspect, 0.25);
    expect(nonFinite.laserFadeMs, 1500);
  });

  test('nibAngleDeg folds into [0, 180) (JSON ints too)', () {
    expect(_with(const {'nibAngleDeg': 30}).nibAngleDeg, 30);
    expect(_with(const {'nibAngleDeg': 180}).nibAngleDeg, 0);
    expect(
      _with(const {'nibAngleDeg': 200.5}).nibAngleDeg,
      closeTo(20.5, 1e-9),
    );
    expect(_with(const {'nibAngleDeg': -30}).nibAngleDeg, 150);
    expect(_with(const {'nibAngleDeg': 720}).nibAngleDeg, 0);
    final a = _with(const {'nibAngleDeg': -1e-20}).nibAngleDeg;
    expect(a >= 0 && a < 180, isTrue);
  });

  test('nibAspect clamps to (0.1 .. 1]', () {
    expect(_with(const {'nibAspect': 0.5}).nibAspect, 0.5);
    expect(_with(const {'nibAspect': 0}).nibAspect, 0.1);
    expect(_with(const {'nibAspect': -3}).nibAspect, 0.1);
    expect(_with(const {'nibAspect': 0.1}).nibAspect, 0.1);
    expect(_with(const {'nibAspect': 4}).nibAspect, 1);
    expect(_with(const {'nibAspect': 1}).nibAspect, 1);
  });

  test('followBarrelRoll reads a bool', () {
    expect(_with(const {'rollNib': false}).followBarrelRoll, isFalse);
    expect(_with(const {'rollNib': true}).followBarrelRoll, isTrue);
  });

  test('dashPattern: even length 2..8, each clamped to [0, 50], sum ≥ 0.5', () {
    expect(
      _with(const {
        'dash': [2, 1],
      }).dashPattern,
      [2, 1],
    );
    expect(
      _with(const {
        'dash': [6, 2, 1, 2],
      }).dashPattern,
      [6, 2, 1, 2],
    );
    expect(
      _with(const {
        'dash': [0, 2],
      }).dashPattern,
      [0, 2],
    );
    expect(
      _with(const {
        'dash': [-1, 80],
      }).dashPattern,
      [0, 50],
    );
    expect(
      _with(const {
        'dash': [1, 2, 3],
      }).dashPattern,
      [4, 3],
    ); // odd
    expect(
      _with(const {
        'dash': [1],
      }).dashPattern,
      [4, 3],
    ); // too short
    expect(
      _with(const {
        'dash': [1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
      }).dashPattern,
      [4, 3],
    ); // too long
    expect(
      _with(const {
        'dash': [0.2, 0.2],
      }).dashPattern,
      [4, 3],
    ); // Σ < 0.5
    expect(
      _with(const {
        'dash': [1, 'x'],
      }).dashPattern,
      [4, 3],
    );
    expect(
      _with(const {
        'dash': [1, double.nan],
      }).dashPattern,
      [4, 3],
    );
    expect(
      () => _with(const {
        'dash': [2, 1],
      }).dashPattern.add(1),
      throwsUnsupportedError,
    );
  });

  test('laserFadeMs rounds and clamps to [300, 5000]', () {
    expect(_with(const {'laserFadeMs': 2000}).laserFadeMs, 2000);
    expect(_with(const {'laserFadeMs': 2000.6}).laserFadeMs, 2001);
    expect(_with(const {'laserFadeMs': 10}).laserFadeMs, 300);
    expect(_with(const {'laserFadeMs': 99999}).laserFadeMs, 5000);
  });

  test('tapeStyle reads the wire names', () {
    expect(
      _with(const {'tapeStyle': 'striped'}).tapeStyle,
      InkTapeStyle.striped,
    );
    expect(_with(const {'tapeStyle': 'solid'}).tapeStyle, InkTapeStyle.solid);
    expect(_with(const {'tapeStyle': 'Striped'}).tapeStyle, InkTapeStyle.solid);
  });

  test('withInkExtras writes only the given keys and keeps the others', () {
    final base = _with(const {'hlStraight': 'snapOnLift', 'other': 1});
    final s = base.withInkExtras(
      nibAngleDeg: 30,
      tapeStyle: InkTapeStyle.striped,
    );
    expect(s.extras, {
      'hlStraight': 'snapOnLift',
      'other': 1,
      'nibAngleDeg': 30.0,
      'tapeStyle': 'striped',
    });
    final t = s.withInkExtras(
      nibAspect: 0.5,
      followBarrelRoll: false,
      dashPattern: [2, 1],
      laserFadeMs: 800,
    );
    expect(t.extras['nibAngleDeg'], 30.0);
    expect(t.extras['nibAspect'], 0.5);
    expect(t.extras['rollNib'], false);
    expect(t.extras['dash'], [2.0, 1.0]);
    expect(t.extras['laserFadeMs'], 800);
    expect(t.nibAspect, 0.5);
    expect(t.followBarrelRoll, isFalse);
    expect(t.dashPattern, [2, 1]);
    expect(t.laserFadeMs, 800);
    expect(identical(base.withInkExtras(), base), isTrue);
    // the written extras survive CORE JSON
    final back = core.StrokeStyle.fromJson(t.toJson());
    expect(back.dashPattern, [2, 1]);
    expect(back.nibAngleDeg, 30);
  });

  test('CORE defaultsFor reads with the same rules', () {
    final calligraphy = core.StrokeStyle.defaultsFor(core.PenTool.calligraphy);
    expect(calligraphy.nibAngleDeg, 45);
    expect(calligraphy.nibAspect, 0.25);
    final dashed = core.StrokeStyle.defaultsFor(core.PenTool.dashed);
    expect(dashed.dashPattern, [4, 3]);
    expect(core.StrokeStyle.defaultsFor(core.PenTool.laser).laserFadeMs, 1500);
    expect(
      core.StrokeStyle.defaultsFor(core.PenTool.tape).tapeStyle,
      InkTapeStyle.solid,
    );
  });

  test('C2-38: CORE turns the calligraphy nib angle under the same key', () {
    final stroke = core.Stroke(
      id: 's1',
      pageId: 'p1',
      style: core.StrokeStyle.defaultsFor(core.PenTool.calligraphy)
          .copyWith(extras: const {}),
      // two points, stride 6: x, y, widthQ, tilt, azimuth, t
      points: core.StrokePoints.fromInterleaved(
        Float32List.fromList([10, 10, 0.25, 0, 0, 0, 60, 30, 0.25, 0, 0, 10]),
      ),
      createdAt: 1,
    );
    final turned = stroke.transformed(
      core.Affine2.rotation(30 * math.pi / 180),
    );
    expect(turned.style.nibAngleDeg, closeTo(75, 1e-6));
  });

  test('P1 tools still use the ballpoint profile in R2-B3', () {
    for (final tool in [
      core.PenTool.brush,
      core.PenTool.calligraphy,
      core.PenTool.dashed,
      core.PenTool.laser,
      core.PenTool.tape,
    ]) {
      expect(PenProfile.of(tool), PenProfile.ballpoint, reason: tool.name);
    }
    expect(InkRenderMethod.values.map((v) => v.name), [
      'filledOutline',
      'strokedPolyline',
      'nibOutline',
      'dashedPolyline',
      'transientTrail',
    ]);
    expect(InkLayer.values.map((v) => v.name), ['highlighter', 'ink', 'cover']);
  });
}
