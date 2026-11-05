// The fake engine rules (contract 00-overview 7.6 'functions/ fake engine' block, 07-sync 6.8.5).
// LIBRARY's Dart emulator test asserts the same values through the callable.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { EngineError, type EngineInput } from "../src/engines/engine.js";
import { FAKE_ENGINE_VERSION, FakeEngine } from "../src/engines/fake.js";

const signal = new AbortController().signal;

function strokes(x: number[][], y: number[][] = x): EngineInput {
  return { strokes: { x, y }, locale: "ko" };
}

/** 67 bytes, a 1×1 PNG (the emulator test E6 sends the same size). */
const png67 = Buffer.alloc(67, 1);

describe("FakeEngine", () => {
  it("is the engine 'fake', version '1', taking strokes and images", () => {
    const engine = new FakeEngine();
    assert.equal(engine.name, "fake");
    assert.deepEqual(engine.accepts, { strokes: true, png: true });
    assert.equal(FAKE_ENGINE_VERSION, "1");
  });

  it('strokes: S strokes, P points → "\\frac{S}{P}", confidence 1, ["S/P"]', async () => {
    const out = await new FakeEngine().recognize(
      strokes([
        [10, 11.5, 12],
        [20, 21],
      ]),
      signal,
    );
    assert.deepEqual(out, {
      latex: "\\frac{2}{5}",
      confidence: 1,
      alternatives: ["2/5"],
      version: "1",
    });
  });

  it("strokes: a single point is one stroke of one point", async () => {
    const out = await new FakeEngine().recognize(strokes([[0]]), signal);
    assert.equal(out.latex, "\\frac{1}{1}");
    assert.deepEqual(out.alternatives, ["1/1"]);
  });

  it('pngBase64 only: B decoded bytes → "\\sqrt{B}", confidence 1, []', async () => {
    const out = await new FakeEngine().recognize({ png: png67, locale: "en" }, signal);
    assert.deepEqual(out, { latex: "\\sqrt{67}", confidence: 1, alternatives: [], version: "1" });
  });

  it("strokes and an image: the strokes rule answers", async () => {
    const out = await new FakeEngine().recognize(
      { strokes: { x: [[1, 2, 3]], y: [[1, 2, 3]] }, png: png67, locale: "ko" },
      signal,
    );
    assert.equal(out.latex, "\\frac{1}{3}");
  });

  for (const [point, kind] of [
    [-1, "upstream"],
    [-2, "badResponse"],
    [-3, "rateLimited"],
  ] as const) {
    it(`first point of the first stroke (${point},${point}) → EngineError(${kind})`, async () => {
      await assert.rejects(
        new FakeEngine().recognize(
          strokes([
            [point, 5],
            [7, 8],
          ]),
          signal,
        ),
        (e: unknown) => e instanceof EngineError && e.kind === kind,
      );
    });
  }

  it("the failure points count only as the first point of the first stroke", async () => {
    const engine = new FakeEngine();
    // Same value elsewhere: a normal answer.
    assert.equal((await engine.recognize(strokes([[0, -1]], [[0, -1]]), signal)).latex, "\\frac{1}{2}");
    assert.equal(
      (await engine.recognize(strokes([[0], [-2]], [[0], [-2]]), signal)).latex,
      "\\frac{2}{2}",
    );
    // Only x or only y at the failure value: a normal answer.
    assert.equal((await engine.recognize(strokes([[-1]], [[0]]), signal)).latex, "\\frac{1}{1}");
  });

  it("is deterministic and answers even with an aborted signal (no clock, no network)", async () => {
    const engine = new FakeEngine();
    const aborted = new AbortController();
    aborted.abort();
    const input = strokes([[1, 2], [3]]);
    const first = await engine.recognize(input, signal);
    const second = await engine.recognize(input, aborted.signal);
    assert.deepEqual(first, second);
  });

  it("no strokes and no image → EngineError(unsupportedInput)", async () => {
    await assert.rejects(
      new FakeEngine().recognize({ locale: "ko" }, signal),
      (e: unknown) => e instanceof EngineError && e.kind === "unsupportedInput",
    );
  });
});
