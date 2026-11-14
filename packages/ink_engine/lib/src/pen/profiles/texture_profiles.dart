// lib/src/pen/profiles/texture_profiles.dart — (v2.11, C211-01) texture pens.
//
// OWNED BY THE TEXTURE TRACK (crayon, chalk, watercolor, spray). The
// foundation values below are a starting point close to the marker / brush;
// the track tunes them together with its renderers (render/pens/texture/).
// Rendering stays inside core.Stroke.bounds (K-1): every pixel within
// 2 · width · maxWidthQ of the centerline (see render/pens/pen_renderer.dart).
import '../../model/ink_layer.dart';
import '../pen_profile.dart';

abstract final class TexturePenProfiles {
  static const PenProfile crayon = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.30,
    minFactor: 0.70,
    maxFactor: 1.35,
    velocityThinning: 0,
    taperStart: 0.3,
    taperEnd: 0.45,
    taperMinFactor: 0.7,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: true,
    groupComposite: false,
  );

  static const PenProfile chalk = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.30,
    minFactor: 0.70,
    maxFactor: 1.35,
    velocityThinning: 0,
    taperStart: 0.25,
    taperEnd: 0.4,
    taperMinFactor: 0.75,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: true,
    groupComposite: false,
  );

  static const PenProfile watercolor = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.40,
    minFactor: 0.60,
    maxFactor: 1.45,
    velocityThinning: 0.20,
    // no stored taper: the renderer tapers each end over at most a quarter of
    // the stroke (watercolor_pen.dart) — the stored tapers (up to 40 % of the
    // length per end) turned short bars (ㅏ, the dot of ㅎ) into diamonds
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    textured: true,
    groupComposite: false,
  );

  static const PenProfile spray = PenProfile(
    layer: InkLayer.ink,
    pressureGain: 0.30,
    minFactor: 0.70,
    maxFactor: 1.35,
    velocityThinning: 0,
    taperStart: 0,
    taperEnd: 0,
    taperMinFactor: 1,
    tiltWidthGain: 0,
    tiltOpacityLoss: 0,
    cap: InkCap.round,
    renderMethod: InkRenderMethod.filledOutline,
    // textured: the mist layers are dithered with the paper tiles on screen
    // (render/pens/texture/spray_pen.dart); the PDF keeps the flat layers
    textured: true,
    groupComposite: false,
  );
}
