// lib/src/pen/profiles/decor_profiles.dart — (v2.11, C211-01) decoration pens.
//
// OWNED BY THE DECOR TRACK (neon, jelly, rainbow, glitter). The foundation
// values below are ballpoint-like (light pressure gain, no taper); the track
// tunes them together with its renderers (render/pens/decor/). Every pen is
// static: no time animation, no transient trail.
import '../../model/ink_layer.dart';
import '../pen_profile.dart';

abstract final class DecorPenProfiles {
  static const PenProfile neon = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.15,
    minFactor: 0.85,
    maxFactor: 1.2,
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

  static const PenProfile jelly = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.20,
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

  static const PenProfile rainbow = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.15,
    minFactor: 0.85,
    maxFactor: 1.2,
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

  static const PenProfile glitter = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.15,
    minFactor: 0.85,
    maxFactor: 1.2,
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
}
