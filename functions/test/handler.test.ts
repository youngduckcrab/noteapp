// The callable body of the R2-B7b skeleton (07-sync 6.8.2 steps 1–4 and 6, contract 7.2.13):
// sign-in, owner list, request shape, engine resolution and the fake engine's error rows as
// callable codes. S2-10b adds the daily cap, the output check and the log to this file.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/https";
import type { MathEngine } from "../src/engines/engine.js";
import { createRegistry, type EngineSettings } from "../src/engines/registry.js";
import {
  createRecognizeMathHandler,
  ENGINE_TIMEOUT_MS,
  type HandlerDeps,
} from "../src/recognize_math.js";

const demo: EngineSettings = { mathEngine: "fake", allowFake: true };
const owner = { uid: "owner-uid" };

function handlerWith(overrides: Partial<HandlerDeps> = {}, settings: EngineSettings = demo) {
  let clock = 1_000;
  return createRecognizeMathHandler({
    ownerUids: () => ["owner-uid"],
    engines: createRegistry(() => settings),
    now: () => (clock += 7),
    engineSignal: () => new AbortController().signal,
    ...overrides,
  });
}

/** Two strokes, five points (the emulator test E5). */
const twoStrokes = {
  x: [
    [1, 2, 3],
    [4, 5],
  ],
  y: [
    [1, 2, 3],
    [4, 5],
  ],
};
/** A 1×1 grayscale PNG, 67 bytes (the emulator test E6). */
const png67 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR42mNgAAAAAgAB5Sfe/AAAAABJRU5ErkJggg==";

function code(expected: string) {
  return (e: unknown) => {
    assert.ok(e instanceof HttpsError, `HttpsError expected, got ${String(e)}`);
    assert.equal(e.code, expected);
    return true;
  };
}

describe("createRecognizeMathHandler (skeleton)", () => {
  it("no auth → unauthenticated", async () => {
    await assert.rejects(handlerWith()({ auth: null, data: { v: 1, strokes: twoStrokes } }), code("unauthenticated"));
    await assert.rejects(handlerWith()({ data: { v: 1, strokes: twoStrokes } }), code("unauthenticated"));
  });

  it("a uid outside OWNER_UIDS → permission-denied; an empty list lets nobody in", async () => {
    await assert.rejects(
      handlerWith()({ auth: { uid: "stranger-uid" }, data: { v: 1, strokes: twoStrokes } }),
      code("permission-denied"),
    );
    await assert.rejects(
      handlerWith({ ownerUids: () => [] })({ auth: owner, data: { v: 1, strokes: twoStrokes } }),
      code("permission-denied"),
    );
  });

  it("the owner check comes before the request check", async () => {
    await assert.rejects(handlerWith()({ auth: { uid: "stranger-uid" }, data: 42 }), code("permission-denied"));
  });

  for (const [label, data] of [
    ["not an object", "x"],
    ["no input", { v: 1 }],
    ["v ≠ 1", { v: 2, strokes: twoStrokes }],
    ["v missing", { strokes: twoStrokes }],
    ["unknown engine", { v: 1, engine: "other", strokes: twoStrokes }],
    ["unknown locale", { v: 1, locale: "fr", strokes: twoStrokes }],
    ["x / y of different shapes", { v: 1, strokes: { x: [[1, 2]], y: [[1]] } }],
    ["non-finite point", { v: 1, strokes: { x: [[Number.NaN]], y: [[1]] } }],
  ] as const) {
    it(`${label} → invalid-argument`, async () => {
      await assert.rejects(handlerWith()({ auth: owner, data }), code("invalid-argument"));
    });
  }

  it("strokes → the fake engine result with engine, engineVersion and ms", async () => {
    const result = await handlerWith()({ auth: owner, data: { v: 1, engine: "fake", strokes: twoStrokes } });
    assert.deepEqual(result, {
      latex: "\\frac{2}{5}",
      confidence: 1,
      alternatives: ["2/5"],
      engine: "fake",
      engineVersion: "1",
      ms: 7,
    });
  });

  it("pngBase64 only → \\sqrt{decoded bytes}", async () => {
    const result = await handlerWith()({ auth: owner, data: { v: 1, pngBase64: png67, locale: "en" } });
    assert.equal(result.latex, "\\sqrt{67}");
    assert.deepEqual(result.alternatives, []);
  });

  it("unknown top-level keys are ignored (v1 is additive)", async () => {
    const result = await handlerWith()({ auth: owner, data: { v: 1, strokes: twoStrokes, later: true } });
    assert.equal(result.latex, "\\frac{2}{5}");
  });

  it("engine omitted = 'auto' = MATH_ENGINE", async () => {
    const result = await handlerWith()({ auth: owner, data: { v: 1, strokes: twoStrokes } });
    assert.equal(result.engine, "fake");
  });

  it("'auto' with MATH_ENGINE 'none' → unavailable", async () => {
    await assert.rejects(
      handlerWith({}, { mathEngine: "none", allowFake: true })({ auth: owner, data: { v: 1, strokes: twoStrokes } }),
      code("unavailable"),
    );
  });

  it("'fake' without ALLOW_FAKE_ENGINE → invalid-argument; 'auto' → unavailable", async () => {
    const prod = { mathEngine: "fake", allowFake: false };
    await assert.rejects(
      handlerWith({}, prod)({ auth: owner, data: { v: 1, engine: "fake", strokes: twoStrokes } }),
      code("invalid-argument"),
    );
    await assert.rejects(
      handlerWith({}, prod)({ auth: owner, data: { v: 1, strokes: twoStrokes } }),
      code("unavailable"),
    );
  });

  for (const engine of ["gemini", "mathpix", "claude"]) {
    it(`'${engine}' (not configured) → unavailable`, async () => {
      await assert.rejects(
        handlerWith()({ auth: owner, data: { v: 1, engine, strokes: twoStrokes } }),
        code("unavailable"),
      );
    });
  }

  for (const [point, expected] of [
    [-1, "unavailable"],
    [-2, "internal"],
    [-3, "unavailable"],
  ] as const) {
    it(`first point (${point},${point}) → ${expected}`, async () => {
      const strokes = { x: [[point, 1]], y: [[point, 1]] };
      await assert.rejects(handlerWith()({ auth: owner, data: { v: 1, strokes } }), code(expected));
    });
  }

  it("input the engine cannot take → invalid-argument", async () => {
    const pngOnly: MathEngine = {
      name: "claude",
      accepts: { strokes: false, png: true },
      recognize: async () => ({ latex: "x", version: "test" }),
    };
    const handler = handlerWith({
      engines: createRegistry(() => demo, { fake: () => pngOnly }),
    });
    await assert.rejects(handler({ auth: owner, data: { v: 1, strokes: twoStrokes } }), code("invalid-argument"));
  });

  it("the deadline signal (25 s) aborting a waiting engine → unavailable", async () => {
    const ctl = new AbortController();
    let askedMs = 0;
    const waiting: MathEngine = {
      name: "fake",
      accepts: { strokes: true, png: true },
      recognize: (_input, signal) =>
        new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        }),
    };
    const handler = handlerWith({
      engines: createRegistry(() => demo, { fake: () => waiting }),
      engineSignal: (ms) => {
        askedMs = ms;
        return ctl.signal;
      },
    });
    const call = handler({ auth: owner, data: { v: 1, strokes: twoStrokes } });
    ctl.abort();
    await assert.rejects(call, code("unavailable"));
    assert.equal(askedMs, ENGINE_TIMEOUT_MS);
    assert.equal(ENGINE_TIMEOUT_MS, 25_000);
  });

  it("an unexpected engine exception → internal", async () => {
    const broken: MathEngine = {
      name: "fake",
      accepts: { strokes: true, png: true },
      recognize: async () => {
        throw new TypeError("boom");
      },
    };
    const handler = handlerWith({ engines: createRegistry(() => demo, { fake: () => broken }) });
    await assert.rejects(handler({ auth: owner, data: { v: 1, strokes: twoStrokes } }), code("internal"));
  });
});
