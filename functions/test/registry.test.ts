// The engine registry (07-sync 6.8.4): 'auto' follows MATH_ENGINE, a named engine only when it is
// the configured one, 'fake' only with ALLOW_FAKE_ENGINE, 'gemini' never; settings are read on
// every resolve; factories are the injection seam. Also the source rule: only the registry reads
// the params module (adapters take constructor arguments — SYNC-M7).

import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { describe, it } from "node:test";
import { ClaudeEngine } from "../src/engines/claude.js";
import { EngineError, type EngineInput, type MathEngine } from "../src/engines/engine.js";
import { FakeEngine } from "../src/engines/fake.js";
import { MathpixEngine } from "../src/engines/mathpix.js";
import { createRegistry, type EngineFactories, type EngineSettings } from "../src/engines/registry.js";
import type { EngineName } from "../src/protocol.js";

const none: EngineSettings = {
  mathEngine: "none",
  allowFake: false,
  apiKey: "",
  mathpixAppId: "",
  claudeModel: "",
};

function stub(name: "mathpix" | "claude"): MathEngine {
  return {
    name,
    accepts: { strokes: name === "mathpix", png: true },
    recognize: async (_input: EngineInput) => ({ latex: "x", version: "stub" }),
  };
}

function kindOf(r: MathEngine | EngineError): string {
  return r instanceof EngineError ? r.kind : `engine:${r.name}`;
}

function resolveWith(settings: Partial<EngineSettings>, requested: EngineName, factories?: Partial<EngineFactories>) {
  return createRegistry(() => ({ ...none, ...settings }), factories).resolve(requested);
}

describe("createRegistry", () => {
  it("'auto' with MATH_ENGINE 'none' (the default) → notConfigured", () => {
    assert.equal(kindOf(resolveWith({}, "auto")), "notConfigured");
    assert.equal(kindOf(resolveWith({ allowFake: true }, "auto")), "notConfigured");
  });

  it("'auto' → the MATH_ENGINE engine; fake only with ALLOW_FAKE_ENGINE", () => {
    const fake = resolveWith({ mathEngine: "fake", allowFake: true }, "auto");
    assert.ok(fake instanceof FakeEngine);
    assert.equal(kindOf(resolveWith({ mathEngine: "fake" }, "auto")), "notConfigured");
  });

  it("naming 'fake': allowed → the fake; not allowed → unsupportedInput (invalid-argument)", () => {
    assert.equal(kindOf(resolveWith({ allowFake: true }, "fake")), "engine:fake");
    assert.equal(kindOf(resolveWith({ allowFake: true, mathEngine: "mathpix" }, "fake")), "engine:fake");
    assert.equal(kindOf(resolveWith({}, "fake")), "unsupportedInput");
    assert.equal(kindOf(resolveWith({ mathEngine: "fake" }, "fake")), "unsupportedInput");
  });

  it("'gemini' is always notConfigured", () => {
    assert.equal(kindOf(resolveWith({}, "gemini")), "notConfigured");
    assert.equal(kindOf(resolveWith({ mathEngine: "gemini", apiKey: "k" }, "gemini")), "notConfigured");
    assert.equal(kindOf(resolveWith({ mathEngine: "gemini", apiKey: "k" }, "auto")), "notConfigured");
  });

  it("a named engine other than MATH_ENGINE → notConfigured", () => {
    const factories = { mathpix: () => stub("mathpix"), claude: () => stub("claude") };
    const full = { apiKey: "k", mathpixAppId: "app", claudeModel: "m" };
    assert.equal(kindOf(resolveWith({ ...full, mathEngine: "claude" }, "mathpix", factories)), "notConfigured");
    assert.equal(kindOf(resolveWith({ ...full, mathEngine: "mathpix" }, "claude", factories)), "notConfigured");
    assert.equal(kindOf(resolveWith({ ...full, mathEngine: "mathpix" }, "mathpix", factories)), "engine:mathpix");
  });

  it("an unknown MATH_ENGINE value → notConfigured", () => {
    assert.equal(kindOf(resolveWith({ mathEngine: "openai", apiKey: "k" }, "auto")), "notConfigured");
    assert.equal(kindOf(resolveWith({ mathEngine: "" }, "auto")), "notConfigured");
  });

  it("Mathpix needs MATHPIX_APP_ID and MATH_API_KEY; the factory gets both", () => {
    const calls: { appId: string; apiKey: string }[] = [];
    const factories = {
      mathpix: (opts: { appId: string; apiKey: string }) => {
        calls.push(opts);
        return stub("mathpix");
      },
    };
    const base = { mathEngine: "mathpix" };
    assert.equal(kindOf(resolveWith({ ...base, apiKey: "k" }, "auto", factories)), "notConfigured");
    assert.equal(kindOf(resolveWith({ ...base, mathpixAppId: "app" }, "auto", factories)), "notConfigured");
    assert.deepEqual(calls, []);
    assert.equal(
      kindOf(resolveWith({ ...base, mathpixAppId: "app", apiKey: "k" }, "auto", factories)),
      "engine:mathpix",
    );
    assert.deepEqual(calls, [{ appId: "app", apiKey: "k" }]);
  });

  it("Claude needs CLAUDE_MODEL (default '' → notConfigured, C23-02) and MATH_API_KEY", () => {
    const calls: { apiKey: string; model: string }[] = [];
    const factories = {
      claude: (opts: { apiKey: string; model: string }) => {
        calls.push(opts);
        return stub("claude");
      },
    };
    const base = { mathEngine: "claude" };
    assert.equal(kindOf(resolveWith({ ...base, apiKey: "k" }, "auto", factories)), "notConfigured");
    assert.equal(kindOf(resolveWith({ ...base, claudeModel: "m" }, "claude", factories)), "notConfigured");
    assert.deepEqual(calls, []);
    assert.equal(
      kindOf(resolveWith({ ...base, claudeModel: "m", apiKey: "k" }, "claude", factories)),
      "engine:claude",
    );
    assert.deepEqual(calls, [{ apiKey: "k", model: "m" }]);
  });

  it("complete settings → the real adapters by default (S2-12), built from the settings", () => {
    const mathpix = resolveWith({ mathEngine: "mathpix", mathpixAppId: "app", apiKey: "k" }, "auto");
    assert.ok(mathpix instanceof MathpixEngine);
    assert.deepEqual(mathpix.accepts, { strokes: true, png: true });
    const claude = resolveWith({ mathEngine: "claude", claudeModel: "m", apiKey: "k" }, "auto");
    assert.ok(claude instanceof ClaudeEngine);
    assert.deepEqual(claude.accepts, { strokes: false, png: true });
    assert.equal(claude.requestFor(Buffer.from("png"), "en").model, "m");
    // Incomplete settings still answer before any adapter is built.
    assert.equal(kindOf(resolveWith({ mathEngine: "claude", apiKey: "k" }, "auto")), "notConfigured");
  });

  it("a factory replaces the fake", () => {
    const mine = new FakeEngine();
    const r = resolveWith({ allowFake: true }, "fake", { fake: () => mine });
    assert.equal(r, mine);
  });

  it("settings are read on every resolve; the key only when an engine needs it", () => {
    let reads = 0;
    let keyReads = 0;
    let current: EngineSettings = { ...none, mathEngine: "fake", allowFake: true };
    const registry = createRegistry(() => {
      reads++;
      const s = current;
      return {
        ...s,
        get apiKey() {
          keyReads++;
          return s.apiKey;
        },
      };
    });
    assert.equal(kindOf(registry.resolve("auto")), "engine:fake");
    current = { ...none };
    assert.equal(kindOf(registry.resolve("auto")), "notConfigured");
    assert.equal(kindOf(registry.resolve("fake")), "unsupportedInput");
    assert.equal(reads, 3);
    assert.equal(keyReads, 0);
  });

  it("errors carry a message naming the engine", () => {
    const r = resolveWith({ mathEngine: "claude", apiKey: "k" }, "auto");
    assert.ok(r instanceof EngineError);
    assert.match(r.message, /claude/);
    assert.match(r.message, /CLAUDE_MODEL/);
  });
});

describe("source rule (SYNC-M7)", () => {
  // lib/test/registry.test.js → ../../src (the TypeScript sources).
  const src = resolve(__dirname, "..", "..", "src");
  const importsParams = (file: string) =>
    /from\s+["'](?:\.\.?\/)+params(?:\.js)?["']|firebase-functions\/params/.test(readFileSync(file, "utf8"));

  it("no engine adapter imports params; the registry does", () => {
    const dir = join(src, "engines");
    const files = readdirSync(dir).filter((f) => f.endsWith(".ts"));
    for (const f of ["registry.ts", "fake.ts", "mathpix.ts", "claude.ts"]) assert.ok(files.includes(f), files.join(","));
    for (const f of files) {
      assert.equal(importsParams(join(dir, f)), f === "registry.ts", f);
    }
  });

  it("outside engines/, only recognize_math.ts (onCall options) and params.ts itself", () => {
    for (const f of readdirSync(src).filter((n) => n.endsWith(".ts"))) {
      const expected = f === "recognize_math.ts" || f === "params.ts";
      assert.equal(importsParams(join(src, f)), expected, f);
    }
  });
});
