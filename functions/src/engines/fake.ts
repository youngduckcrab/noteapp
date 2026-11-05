// The deterministic fake engine (contract 00-overview 7.6 'functions/ fake engine' block,
// docs/plans/m5-7/07-sync.md 6.8.5). SYNC's emulator test and LIBRARY's Dart emulator test
// (CallableMathRecognizer) assert the same values. engine 'fake', engineVersion '1' → app
// engineId 'fake/1'. Demo config only (ALLOW_FAKE_ENGINE — the registry decides).
//
//   strokes (S strokes, P points in total) → latex "\frac{S}{P}", confidence 1, alternatives ["S/P"]
//   pngBase64 only (B decoded bytes)       → latex "\sqrt{B}", confidence 1, alternatives []
//   first point of the first stroke (-1,-1) → unavailable; (-2,-2) → internal; (-3,-3) → unavailable
//
// No network, clock or randomness. The signal is not used: the answer is immediate.

import { EngineError, type EngineInput, type EngineOutput, type MathEngine } from "./engine.js";

export const FAKE_ENGINE_VERSION = "1";

export class FakeEngine implements MathEngine {
  readonly name = "fake" as const;
  readonly accepts = { strokes: true, png: true } as const;

  constructor() {}

  async recognize(input: EngineInput, _signal: AbortSignal): Promise<EngineOutput> {
    const strokes = input.strokes;
    if (strokes !== undefined) {
      const x0 = strokes.x[0]?.[0];
      const y0 = strokes.y[0]?.[0];
      if (x0 === -1 && y0 === -1) throw new EngineError("upstream", "fake engine: upstream failure");
      if (x0 === -2 && y0 === -2) throw new EngineError("badResponse", "fake engine: bad response");
      if (x0 === -3 && y0 === -3) throw new EngineError("rateLimited", "fake engine: rate limited");
      const s = strokes.x.length;
      const p = strokes.x.reduce((sum, stroke) => sum + stroke.length, 0);
      return {
        latex: `\\frac{${s}}{${p}}`,
        confidence: 1,
        alternatives: [`${s}/${p}`],
        version: FAKE_ENGINE_VERSION,
      };
    }
    if (input.png !== undefined) {
      return {
        latex: `\\sqrt{${input.png.length}}`,
        confidence: 1,
        alternatives: [],
        version: FAKE_ENGINE_VERSION,
      };
    }
    throw new EngineError("unsupportedInput", "fake engine: strokes or png is required");
  }
}
