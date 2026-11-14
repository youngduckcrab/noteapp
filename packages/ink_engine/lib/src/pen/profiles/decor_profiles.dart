// lib/src/pen/profiles/decor_profiles.dart — (v2.11, C211-01) decoration pens.
//
// OWNED BY THE DECOR TRACK (neon, jelly, rainbow, glitter; renderers in
// render/pens/decor/). Every pen is static: no time animation, no transient
// trail. Neon and glitter have no pressure response (factor 1 everywhere — an
// even tube / gel line like the lock app's): their decorations then have a
// constant size, the live stroke draws exactly the stored look, and the K-1
// reach 0.75 · w leaves room for the glow and the stars. Jelly and rainbow keep
// a light ballpoint-like response; their body is the outline itself.
import '../../model/ink_layer.dart';
import '../pen_profile.dart';

abstract final class DecorPenProfiles {
  static const PenProfile neon = PenProfile(
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
    renderMethod: InkRenderMethod.filledOutline,
    textured: false,
    groupComposite: false,
  );
}
