// Engine names → engines (docs/plans/m5-7/07-sync.md 4.5, 6.8.4). (v2.1, SYNC-M7) The ONLY
// module that reads src/params.ts besides the onCall options in recognize_math.ts: adapters take
// everything through their constructors.
//
// R2-B7b skeleton: the fake engine only. Mathpix / Claude (S2-12) and the key settings
// (S2-10a) join EngineSettings and EngineFactories later; until then those names are
// notConfigured, like 'gemini' always is.

import type { EngineName } from "../protocol.js";
import { ALLOW_FAKE_ENGINE, MATH_ENGINE } from "../params.js";
import { EngineError, type EngineRegistry, type MathEngine } from "./engine.js";
import { FakeEngine } from "./fake.js";

export interface EngineSettings {
  /** MATH_ENGINE: the engine 'auto' means ('none' → nobody answers). */
  mathEngine: string;
  /** ALLOW_FAKE_ENGINE: the demo project only. */
  allowFake: boolean;
}

export interface EngineFactories {
  fake(): MathEngine;
}

const defaultFactories: EngineFactories = {
  fake: () => new FakeEngine(),
};

/** [settings] is read on every resolve; [factories] is the test seam. */
export function createRegistry(
  settings: () => EngineSettings,
  factories?: Partial<EngineFactories>,
): EngineRegistry {
  const make: EngineFactories = { ...defaultFactories, ...factories };
  return {
    resolve(requested: EngineName): MathEngine | EngineError {
      const s = settings();
      if (requested === "fake") {
        // A request may name the fake only where the demo config allows it (contract 7.2.13).
        return s.allowFake
          ? make.fake()
          : new EngineError("unsupportedInput", "engine fake is not allowed");
      }
      const name = requested === "auto" ? s.mathEngine : requested;
      // A named engine is taken only when it is the configured one (6.8.4).
      if (requested !== "auto" && name !== s.mathEngine) {
        return new EngineError("notConfigured", `engine ${name} is not configured`);
      }
      if (name === "fake" && s.allowFake) return make.fake();
      return new EngineError("notConfigured", `engine ${name} is not configured`);
    },
  };
}

/** Production registry: reads the params (`.value()`) on every call, never at load time. */
export function registryFromParams(): EngineRegistry {
  return createRegistry(() => ({
    mathEngine: MATH_ENGINE.value(),
    allowFake: ALLOW_FAKE_ENGINE.value(),
  }));
}
