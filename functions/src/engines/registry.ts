// Engine names → engines (docs/plans/m5-7/07-sync.md 4.5, 6.8.4). (v2.1, SYNC-M7) The ONLY
// module that reads src/params.ts besides the onCall options in recognize_math.ts: adapters take
// everything through their constructors, so the comparison tool (6.9) builds the same adapters
// from developer environment variables and tests inject fakes through [factories].
//
// 'auto' follows MATH_ENGINE ('none' → notConfigured). A request that names an engine gets it only
// when it is the configured one, or 'fake' where ALLOW_FAKE_ENGINE allows it. 'gemini' is always
// notConfigured this round. The Mathpix and Claude adapters arrive with S2-12; until a factory for
// them exists they are notConfigured as well, even when their settings are complete.

import type { EngineName } from "../protocol.js";
import { ALLOW_FAKE_ENGINE, CLAUDE_MODEL, MATH_API_KEY, MATH_ENGINE, MATHPIX_APP_ID } from "../params.js";
import { EngineError, type EngineRegistry, type MathEngine } from "./engine.js";
import { FakeEngine } from "./fake.js";

export interface EngineSettings {
  /** MATH_ENGINE: the engine 'auto' means ('none' → nobody answers). */
  mathEngine: string;
  /** ALLOW_FAKE_ENGINE: the demo project only. */
  allowFake: boolean;
  /** MATH_API_KEY: the key of the MATH_ENGINE engine. Read only when that engine is built. */
  apiKey: string;
  /** MATHPIX_APP_ID. */
  mathpixAppId: string;
  /** CLAUDE_MODEL ('' → Claude notConfigured — C23-02). */
  claudeModel: string;
}

export interface EngineFactories {
  fake(): MathEngine;
  mathpix(opts: { appId: string; apiKey: string }): MathEngine;
  claude(opts: { apiKey: string; model: string }): MathEngine;
}

const defaultFactories: Partial<EngineFactories> = {
  fake: () => new FakeEngine(),
};

function notConfigured(name: string, why: string): EngineError {
  return new EngineError("notConfigured", `engine ${name} is not configured (${why})`);
}

/** [settings] is read on every resolve; [factories] is the test seam (and S2-12's adapters). */
export function createRegistry(
  settings: () => EngineSettings,
  factories?: Partial<EngineFactories>,
): EngineRegistry {
  const make: Partial<EngineFactories> = { ...defaultFactories, ...factories };
  return {
    resolve(requested: EngineName): MathEngine | EngineError {
      const s = settings();
      if (requested === "fake") {
        // A request may name the fake only where the demo config allows it (contract 7.2.13).
        // Not allowed → unsupportedInput → invalid-argument (6.8.2 step 4).
        if (!s.allowFake) return new EngineError("unsupportedInput", "engine fake is not allowed");
        return make.fake?.() ?? notConfigured("fake", "no adapter");
      }
      const name = requested === "auto" ? s.mathEngine : requested;
      if (requested !== "auto" && name !== s.mathEngine) {
        return notConfigured(name, "MATH_ENGINE names another engine");
      }
      switch (name) {
        case "fake":
          if (!s.allowFake) return notConfigured("fake", "ALLOW_FAKE_ENGINE is false");
          return make.fake?.() ?? notConfigured("fake", "no adapter");
        case "mathpix": {
          if (s.mathpixAppId === "") return notConfigured(name, "MATHPIX_APP_ID is empty");
          const apiKey = s.apiKey;
          if (apiKey === "") return notConfigured(name, "MATH_API_KEY is empty");
          return make.mathpix?.({ appId: s.mathpixAppId, apiKey }) ?? notConfigured(name, "no adapter");
        }
        case "claude": {
          if (s.claudeModel === "") return notConfigured(name, "CLAUDE_MODEL is empty");
          const apiKey = s.apiKey;
          if (apiKey === "") return notConfigured(name, "MATH_API_KEY is empty");
          return make.claude?.({ apiKey, model: s.claudeModel }) ?? notConfigured(name, "no adapter");
        }
        case "gemini":
          return notConfigured(name, "not available this round");
        default:
          // 'none' (the default) or an unknown MATH_ENGINE value.
          return notConfigured(name, "MATH_ENGINE");
      }
    },
  };
}

/** Production registry: reads the params (`.value()`) on every call, never at load time. The
 *  secret is read only when an engine that needs it is built (a getter), not on the fake path. */
export function registryFromParams(): EngineRegistry {
  return createRegistry(() => ({
    mathEngine: MATH_ENGINE.value(),
    allowFake: ALLOW_FAKE_ENGINE.value(),
    get apiKey() {
      return MATH_API_KEY.value();
    },
    mathpixAppId: MATHPIX_APP_ID.value(),
    claudeModel: CLAUDE_MODEL.value(),
  }));
}
