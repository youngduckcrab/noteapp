// lib/src/pen/pen_profile.dart — 03-ink 4.2, values 6.9 (2nd round: m5-7/03-ink 4.1, 4.10).
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../model/ink_layer.dart';

enum InkCap { round, square }

/// (v2.0) PenProfile.of: brush → filledOutline (high pressure gain, long taper);
/// calligraphy → nibOutline; dashed → dashedPolyline (round caps); laser → transientTrail;
/// tape → filledOutline, square cap, layer cover. Foundation step R2-B3: the five P1 tools
/// still map to the ballpoint profile (m5-7/03-ink 4.13 — T27~T31 switch them one by one).
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

  /// ballpoint / fountain / highlighter / pencil / marker → their profile;
  /// brush, calligraphy, dashed, laser, tape (P1) → ballpoint (R2-B3; m5-7/03-ink T27~T31
  /// give them their own profiles).
  static PenProfile of(core.PenTool tool) => switch (tool) {
    core.PenTool.ballpoint => ballpoint,
    core.PenTool.fountain => fountain,
    core.PenTool.highlighter => highlighter,
    core.PenTool.pencil => pencil,
    core.PenTool.marker => marker,
    core.PenTool.brush ||
    core.PenTool.calligraphy ||
    core.PenTool.dashed ||
    core.PenTool.laser ||
    core.PenTool.tape => ballpoint,
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
