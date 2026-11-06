// The callable body (07-sync 6.8.2, contract 7.2.13): sign-in, owner list, request check, engine
// resolution and the fake engine's error rows as callable codes (R2-B7b); (S2-10b) the order of
// the daily cap (a bad request or an engine that cannot run uses no count, the cap comes right
// before the engine, a failed engine call keeps its count, a store failure is unavailable without
// an engine call), the deadline as an injected AbortController, the output check, engineVersion
// from the engine output, and one log line per call with sizes only (6.8.10).

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { HttpsError } from "firebase-functions/https";
import type { EngineOutput, MathEngine } from "../src/engines/engine.js";
import { createRegistry, type EngineSettings } from "../src/engines/registry.js";
import { MemoryQuotaStore, seoulDayKey, type QuotaStore } from "../src/quota.js";
import {
  createRecognizeMathHandler,
  ENGINE_TIMEOUT_MS,
  LOG_MESSAGE,
  type HandlerDeps,
} from "../src/recognize_math.js";
import { MemoryLogger } from "./support/memory_logger.js";

const demo: EngineSettings = {
  mathEngine: "fake",
  allowFake: true,
  apiKey: "",
  mathpixAppId: "",
  claudeModel: "",
};
const owner = { uid: "owner-uid" };

function handlerWith(overrides: Partial<HandlerDeps> = {}, settings: EngineSettings = demo) {
  let clock = 1_000;
  return createRecognizeMathHandler({
    ownerUids: () => ["owner-uid"],
    engines: createRegistry(() => settings),
    quota: new MemoryQuotaStore(),
    dailyCap: () => 200,
    now: () => (clock += 7),
    engineSignal: () => new AbortController().signal,
    log: new MemoryLogger(),
    ...overrides,
  });
}

/** An engine that answers [out] (or throws [error]) and counts its calls. */
function scripted(out: Partial<EngineOutput> | (() => never)) {
  const engine = {
    calls: 0,
    name: "fake" as const,
    accepts: { strokes: true, png: true },
    async recognize(): Promise<EngineOutput> {
      engine.calls++;
      if (typeof out === "function") out();
      return out as EngineOutput;
    },
  };
  return engine;
}

/** A quota store that records its calls (and can fail). */
class SpyQuota implements QuotaStore {
  readonly calls: Array<{ uid: string; dayKey: string; cap: number }> = [];
  private readonly inner = new MemoryQuotaStore();
  constructor(private readonly fail = false) {}
  async take(uid: string, dayKey: string, cap: number) {
    this.calls.push({ uid, dayKey, cap });
    if (this.fail) throw new Error("store down");
    return this.inner.take(uid, dayKey, cap);
  }
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

describe("createRecognizeMathHandler: steps 1–4 and 6 (R2-B7b)", () => {
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
      handlerWith({}, { ...demo, mathEngine: "none" })({ auth: owner, data: { v: 1, strokes: twoStrokes } }),
      code("unavailable"),
    );
  });

  it("'fake' without ALLOW_FAKE_ENGINE → invalid-argument; 'auto' → unavailable", async () => {
    const prod = { ...demo, allowFake: false };
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
    let started!: () => void;
    const waitingStarted = new Promise<void>((resolve) => (started = resolve));
    const waiting: MathEngine = {
      name: "fake",
      accepts: { strokes: true, png: true },
      recognize: (_input, signal) =>
        new Promise((_resolve, reject) => {
          signal.addEventListener("abort", () => reject(signal.reason), { once: true });
          started();
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
    await waitingStarted; // the engine waits on the signal (after the daily count)
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

describe("createRecognizeMathHandler: daily cap (6.8.2 step 5, 6.8.7)", () => {
  it("a bad request, an unknown or unconfigured engine and input the engine cannot take use no count", async () => {
    const quota = new SpyQuota();
    const pngOnly = scripted({ latex: "x", version: "1" });
    pngOnly.accepts = { strokes: false, png: true };
    for (const [deps, data] of [
      [{}, { v: 2, strokes: twoStrokes }],
      [{}, { v: 1, engine: "other", strokes: twoStrokes }],
      [{}, { v: 1, engine: "gemini", strokes: twoStrokes }],
      [{ engines: createRegistry(() => demo, { fake: () => pngOnly }) }, { v: 1, strokes: twoStrokes }],
    ] as const) {
      await assert.rejects(handlerWith({ quota, ...deps })({ auth: owner, data }), HttpsError);
    }
    await assert.rejects(handlerWith({ quota })({ auth: { uid: "stranger-uid" }, data: { v: 1 } }), HttpsError);
    assert.deepEqual(quota.calls, []);
    assert.equal(pngOnly.calls, 0);
  });

  it("the count is taken for the uid and the Seoul day of the call, with DAILY_CAP", async () => {
    const quota = new SpyQuota();
    const t = Date.parse("2026-11-05T15:00:00.000Z"); // 00:00 on 11-06 in Seoul
    await handlerWith({ quota, dailyCap: () => 3, now: () => t })({ auth: owner, data: { v: 1, strokes: twoStrokes } });
    assert.deepEqual(quota.calls, [{ uid: "owner-uid", dayKey: seoulDayKey(t), cap: 3 }]);
    assert.equal(quota.calls[0]?.dayKey, "20261106");
  });

  it("at the cap → resource-exhausted and the engine is not called; the next Seoul day passes again", async () => {
    const engine = scripted({ latex: "x", version: "1" });
    const quota = new MemoryQuotaStore();
    let now = Date.parse("2026-11-06T14:00:00.000Z"); // 23:00 in Seoul
    const handler = handlerWith({
      quota,
      dailyCap: () => 2,
      now: () => now,
      engines: createRegistry(() => demo, { fake: () => engine }),
    });
    const call = () => handler({ auth: owner, data: { v: 1, strokes: twoStrokes } });
    await call();
    await call();
    await assert.rejects(call(), code("resource-exhausted"));
    assert.equal(engine.calls, 2);
    now += 60 * 60 * 1000; // 00:00 the next day in Seoul
    await call();
    assert.equal(engine.calls, 3);
  });

  it("DAILY_CAP ≤ 0 → no cap: the store is never asked", async () => {
    for (const cap of [0, -5]) {
      const quota = new SpyQuota();
      const handler = handlerWith({ quota, dailyCap: () => cap });
      for (let i = 0; i < 3; i++) await handler({ auth: owner, data: { v: 1, strokes: twoStrokes } });
      assert.deepEqual(quota.calls, []);
    }
  });

  it("a failed engine call keeps its count", async () => {
    const quota = new MemoryQuotaStore();
    const handler = handlerWith({ quota, dailyCap: () => 2 });
    const failing = { x: [[-1, 1]], y: [[-1, 1]] }; // the fake engine's upstream row
    await assert.rejects(handler({ auth: owner, data: { v: 1, strokes: failing } }), code("unavailable"));
    await handler({ auth: owner, data: { v: 1, strokes: twoStrokes } });
    await assert.rejects(handler({ auth: owner, data: { v: 1, strokes: twoStrokes } }), code("resource-exhausted"));
  });

  it("a store failure → unavailable, logged, and the engine is not called", async () => {
    const engine = scripted({ latex: "x", version: "1" });
    const log = new MemoryLogger();
    const handler = handlerWith({
      quota: new SpyQuota(true),
      log,
      engines: createRegistry(() => demo, { fake: () => engine }),
    });
    await assert.rejects(handler({ auth: owner, data: { v: 1, strokes: twoStrokes } }), code("unavailable"));
    assert.equal(engine.calls, 0);
    assert.equal(log.entries.length, 1);
    assert.equal(log.entries[0]?.level, "error");
    assert.equal(log.entries[0]?.fields.outcome, "unavailable");
    assert.equal(log.entries[0]?.fields.quotaError, "Error");
  });
});

describe("createRecognizeMathHandler: output check (6.8.2 step 7) and engineVersion", () => {
  const long = "x".repeat(4000);
  for (const [label, out, expected] of [
    ["latex 4000 chars", { latex: long, version: "1" }, { latex: long }],
    ["confidence 0.25 kept", { latex: "a", version: "1", confidence: 0.25 }, { latex: "a", confidence: 0.25 }],
    ["confidence 0 and 1 kept", { latex: "a", version: "1", confidence: 0 }, { latex: "a", confidence: 0 }],
    ["confidence 1.5 dropped", { latex: "a", version: "1", confidence: 1.5 }, { latex: "a" }],
    ["confidence -0.1 dropped", { latex: "a", version: "1", confidence: -0.1 }, { latex: "a" }],
    ["confidence NaN dropped", { latex: "a", version: "1", confidence: Number.NaN }, { latex: "a" }],
    [
      "empty alternatives dropped",
      { latex: "a", version: "1", alternatives: ["", "b", "", "c"] },
      { latex: "a", alternatives: ["b", "c"] },
    ],
    [
      "5 alternatives (+ empty ones) kept",
      { latex: "a", version: "1", alternatives: ["1", "2", "", "3", "4", "5"] },
      { latex: "a", alternatives: ["1", "2", "3", "4", "5"] },
    ],
    ["alternative of 4000 chars", { latex: "a", version: "1", alternatives: [long] }, { latex: "a", alternatives: [long] }],
  ] as const) {
    it(`${label} → ok`, async () => {
      const engine = scripted(out as Partial<EngineOutput>);
      const result = await handlerWith({ engines: createRegistry(() => demo, { fake: () => engine }) })({
        auth: owner,
        data: { v: 1, strokes: twoStrokes },
      });
      assert.deepEqual(result, { ...expected, engine: "fake", engineVersion: "1", ms: 7 });
    });
  }

  for (const [label, out] of [
    ["empty latex", { latex: "", version: "1" }],
    ["latex not a string", { latex: 42, version: "1" }],
    ["latex of 4001 chars", { latex: "x".repeat(4001), version: "1" }],
    ["no version", { latex: "a" }],
    ["empty version", { latex: "a", version: "" }],
    ["alternatives not an array", { latex: "a", version: "1", alternatives: "b" }],
    ["an alternative not a string", { latex: "a", version: "1", alternatives: ["b", 3] }],
    ["an alternative of 4001 chars", { latex: "a", version: "1", alternatives: ["x".repeat(4001)] }],
    ["6 alternatives", { latex: "a", version: "1", alternatives: ["1", "2", "3", "4", "5", "6"] }],
  ] as const) {
    it(`${label} → internal`, async () => {
      const engine = scripted(out as unknown as Partial<EngineOutput>);
      const handler = handlerWith({ engines: createRegistry(() => demo, { fake: () => engine }) });
      await assert.rejects(handler({ auth: owner, data: { v: 1, strokes: twoStrokes } }), code("internal"));
    });
  }

  it("engineVersion is the version the engine output names (e.g. a fallback model)", async () => {
    const engine = scripted({ latex: "a", version: "model-that-answered", logInfo: { fallback: true } });
    const result = await handlerWith({ engines: createRegistry(() => demo, { fake: () => engine }) })({
      auth: owner,
      data: { v: 1, strokes: twoStrokes },
    });
    assert.equal(result.engine, "fake");
    assert.equal(result.engineVersion, "model-that-answered");
  });
});

describe("createRecognizeMathHandler: log (6.8.10)", () => {
  it("one info line for a success: uid, engine, version, sizes, count, outcome, ms — no content", async () => {
    const log = new MemoryLogger();
    const engine = scripted({
      latex: "\\frac{secret}{result}",
      version: "1",
      logInfo: { inputTokens: 120, fallback: false, outcome: "spoofed", uid: "spoofed" },
    });
    const strokes = { x: [[101.5, 202.25, 303.125]], y: [[404.5, 505.25, 606.125]] };
    await handlerWith({ log, engines: createRegistry(() => demo, { fake: () => engine }) })({
      auth: owner,
      data: { v: 1, strokes, pngBase64: png67 },
    });
    assert.equal(log.entries.length, 1);
    const entry = log.entries[0]!;
    assert.equal(entry.level, "info");
    assert.equal(entry.message, LOG_MESSAGE);
    assert.deepEqual(entry.fields, {
      uid: "owner-uid",
      locale: "ko",
      requestedEngine: "auto",
      strokes: 1,
      points: 3,
      pngBytes: 67,
      engine: "fake",
      quotaUsed: 1,
      quotaCap: 200,
      engineVersion: "1",
      outcome: "ok",
      ms: 14,
      inputTokens: 120,
      fallback: false,
    });
    const text = JSON.stringify(log.entries);
    for (const content of ["secret", "101.5", "606.125", png67.slice(0, 16)]) {
      assert.ok(!text.includes(content), `${content} must not be logged`);
    }
  });

  for (const [label, deps, data, outcome, level] of [
    ["no auth", {}, { v: 1, strokes: twoStrokes }, "unauthenticated", "warn"],
    ["bad request", {}, { v: 2 }, "invalid-argument", "warn"],
    ["engine error", {}, { v: 1, strokes: { x: [[-2]], y: [[-2]] } }, "internal", "error"],
    ["cap reached", { dailyCap: () => 1, quota: { take: async () => ({ allowed: false, used: 1 }) } }, { v: 1, strokes: twoStrokes }, "resource-exhausted", "warn"],
  ] as const) {
    it(`${label} → one ${level} line with outcome ${outcome}`, async () => {
      const log = new MemoryLogger();
      const handler = handlerWith({ log, ...(deps as Partial<HandlerDeps>) });
      await assert.rejects(handler({ auth: label === "no auth" ? null : owner, data }), code(outcome));
      assert.equal(log.entries.length, 1);
      assert.equal(log.entries[0]?.level, level);
      assert.equal(log.entries[0]?.fields.outcome, outcome);
    });
  }

  it("an engine error names its kind in the log", async () => {
    const log = new MemoryLogger();
    await assert.rejects(
      handlerWith({ log })({ auth: owner, data: { v: 1, strokes: { x: [[-3]], y: [[-3]] } } }),
      code("unavailable"),
    );
    assert.equal(log.entries[0]?.fields.engineError, "rateLimited");
  });
});

