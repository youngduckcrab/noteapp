// lib/src/pen/pen_profile.dart — 03-ink 4.2, values 6.9 (2nd round: m5-7/03-ink 4.1, 4.10).
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../model/ink_layer.dart';
import 'profiles/decor_profiles.dart';
import 'profiles/texture_profiles.dart';

enum InkCap { round, square }

/// (v2.0) PenProfile.of: brush → filledOutline (high pressure gain, long taper);
/// calligraphy → nibOutline; dashed → dashedPolyline (round caps); laser → transientTrail;
/// tape → filledOutline, square cap, layer cover. The P1 profiles exist (m5-7/03-ink 6.2);
/// PenProfile.of switches the tools to them one by one: brush since T27, calligraphy
/// since T28, dashed since T29, laser since T30, tape since T31. A stored laser stroke
/// (abnormal data) draws like a ballpoint: transientTrail outlines are the round-cap
/// filled outline (6.6-5).
enum InkRenderMethod {
  filledOutline,
  strokedPolyline,
  nibOutline,
  dashedPolyline,
  transientTrail,
}

/// Fixed per-tool rendering behaviour (6.9). Not user-editable, never stored.
/// Default style values (color, width, opacity, smoothing, extras) are NOT here: they are
/// core.StrokeStyle.defaultsFor(tool), whose values come from the 6.9 table.
@immutable
final class PenProfile {
  const PenProfile({
    required this.layer,
    required this.pressureGain,
    required this.minFactor,
    required this.maxFactor,
    required this.velocityThinning,
    required this.taperStart,
    required this.taperEnd,
    required this.taperMinFactor,
    required this.tiltWidthGain,
    required this.tiltOpacityLoss,
    required this.cap,
    required this.renderMethod,
    required this.textured,
    required this.groupComposite,
  });

  final InkLayer layer;

  /// f = 1 + pressureGain * style.pressureSensitivity * (2p - 1)
  final double pressureGain;

  /// clamp of f before tilt / taper
  final double minFactor;
  final double maxFactor;

  /// applied with real pressure only (6.7 K3)
  final double velocityThinning;

  /// taper length = taperStart * width (pt)
  final double taperStart;
  final double taperEnd;

  /// width multiplier at the very tip
  final double taperMinFactor;

  /// pencil only (6.11)
  final double tiltWidthGain;

  /// pencil only (6.11)
  final double tiltOpacityLoss;
  final InkCap cap;
  final InkRenderMethod renderMethod;

  /// pencil grain shader
  final bool textured;

  /// highlighter non-darkening composite (6.10)
  final bool groupComposite;

  /// Every tool → its own profile (m5-7/03-ink T27–T31).
  static PenProfile of(core.PenTool tool) => switch (tool) {
    core.PenTool.ballpoint => ballpoint,
    core.PenTool.fountain => fountain,
    core.PenTool.highlighter => highlighter,
    core.PenTool.pencil => pencil,
    core.PenTool.marker => marker,
    core.PenTool.brush => brush,
    core.PenTool.calligraphy => calligraphy,
    core.PenTool.dashed => dashed,
    core.PenTool.laser => laser,
    core.PenTool.tape => tape,
    // (v2.11, C211-01) texture / decoration pens: profiles/*.dart (one file per track)
    core.PenTool.crayon => TexturePenProfiles.crayon,
    core.PenTool.chalk => TexturePenProfiles.chalk,
    core.PenTool.watercolor => TexturePenProfiles.watercolor,
    core.PenTool.spray => TexturePenProfiles.spray,
    core.PenTool.neon => DecorPenProfiles.neon,
    core.PenTool.jelly => DecorPenProfiles.jelly,
    core.PenTool.rainbow => DecorPenProfiles.rainbow,
    core.PenTool.glitter => DecorPenProfiles.glitter,
  };

  // values: 6.9 table
  static const PenProfile ballpoint = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.18,
    minFactor: 0.80,
    maxFactor: 1.25,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: false,
    groupComposite: false,
  );

  static const PenProfile fountain = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.75,
    minFactor: 0.30,
    maxFactor: 1.80,
    velocityThinning: 0.25,
    taperStart: 1.5,
    taperEnd: 3.0,
    taperMinFactor: 0.15,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: false,
    groupComposite: false,
  );

  static const PenProfile highlighter = PenProfile(
    layer: InkLayer.highlighter,
    pressureGain: 0,
    minFactor: 1,
    maxFactor: 1,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.square,
    renderMethod: InkRenderMethod.strokedPolyline,
    textured: false,
    groupComposite: true,
  );

  static const PenProfile pencil = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.45,
    minFactor: 0.50,
    maxFactor: 1.60,
    velocityThinning: 0,
    taperStart: 2.0,
    taperEnd: 2.0,
    taperMinFactor: 0.30,
    tiltWidthGain: 1.8,
    tiltOpacityLoss: 0.5,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: true,
    groupComposite: false,
  );

  static const PenProfile marker = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.12,
    minFactor: 0.85,
    maxFactor: 1.15,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: false,
    groupComposite: false,
  );

  // P1 profiles: m5-7/03-ink 6.2 table (4.10). Pressure, taper and width factor
  // baking are the round-1 K1–K6 / F1–F8 rules with these values.

  /// Brush (6.3): large pressure gain (0.2× light … 2.2× hard, below the K6
  /// saturation 4), speed thinning with real pressure, long tapers.
  static const PenProfile brush = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.90,
    minFactor: 0.20,
    maxFactor: 2.20,
    velocityThinning: 0.30,
    taperStart: 2.5,
    taperEnd: 5.0,
    taperMinFactor: 0.08,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: false,
    groupComposite: false,
  );

  /// Calligraphy (6.4): elliptic nib outline; the factor stays near 1.
  static const PenProfile calligraphy = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.35,
    minFactor: 0.60,
    maxFactor: 1.40,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.nibOutline,
    textured: false,
    groupComposite: false,
  );

  /// Dashed (6.5): constant width (widthQ = kNominalWidthQ), round caps.
  static const PenProfile dashed = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0,
    minFactor: 1,
    maxFactor: 1,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.dashedPolyline,
    textured: false,
    groupComposite: false,
  );

  /// Laser (6.6): a fading trail on the overlay, never stored.
  static const PenProfile laser = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0,
    minFactor: 1,
    maxFactor: 1,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.transientTrail,
    textured: false,
    groupComposite: false,
  );

  /// Memorization tape (6.7): constant width (radius w / 2), square caps, cover layer.
  /// No pressure or taper: the K-1 proof needs widthQ = kNominalWidthQ exactly.
  static const PenProfile tape = PenProfile(
    layer: InkLayer.cover,
    pressureGain: 0,
    minFactor: 1,
    maxFactor: 1,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.square,
    renderMethod: InkRenderMethod.filledOutline,
    textured: false,
    groupComposite: false,
  );

  @override
  bool operator ==(Object other) =>
      other is PenProfile &&
      other.layer == layer &&
      other.pressureGain == pressureGain &&
      other.minFactor == minFactor &&
      other.maxFactor == maxFactor &&
      other.velocityThinning == velocityThinning &&
      other.taperStart == taperStart &&
      other.taperEnd == taperEnd &&
      other.taperMinFactor == taperMinFactor &&
      other.tiltWidthGain == tiltWidthGain &&
      other.tiltOpacityLoss == tiltOpacityLoss &&
      other.cap == cap &&
      other.renderMethod == renderMethod &&
      other.textured == textured &&
      other.groupComposite == groupComposite;

  @override
  int get hashCode => Object.hash(
    layer,
    pressureGain,
    minFactor,
    maxFactor,
    velocityThinning,
    taperStart,
    taperEnd,
    taperMinFactor,
    tiltWidthGain,
    tiltOpacityLoss,
    cap,
    renderMethod,
    textured,
    groupComposite,
  );

  @override
  String toString() => 'PenProfile(${layer.name}, ${renderMethod.name})';
}
