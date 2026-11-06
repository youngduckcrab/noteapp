// parseRequest — every row of the 07-sync 6.8.3 table and its boundary values (contract 7.2.13).

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { LIMITS, MESSAGES, parseRequest, PNG_SIGNATURE, type RecognizeMathRequest } from "../src/protocol.js";

const one = { x: [[1, 2]], y: [[3, 4]] };

/** A base64 PNG: the signature followed by [extra] zero bytes. */
function png(extra = 8): string {
  return Buffer.concat([Buffer.from(PNG_SIGNATURE), Buffer.alloc(extra)]).toString("base64");
}

function ok(data: unknown): RecognizeMathRequest {
  const r = parseRequest(data);
  assert.ok(!("error" in r), `expected a request, got ${JSON.stringify(r)}`);
  return r;
}

function err(data: unknown, message: string) {
  assert.deepEqual(parseRequest(data), { error: message });
}

/** [n] strokes of [points] points each; x = y = [value]. */
function grid(n: number, points: number, value = 1) {
  const rows = () => Array.from({ length: n }, () => new Array<number>(points).fill(value));
  return { x: rows(), y: rows() };
}

describe("parseRequest — data, v, engine, locale", () => {
  it("data must be an object", () => {
    for (const data of [null, undefined, 1, "x", true, [], [{ v: 1 }]]) err(data, MESSAGES.notObject);
  });

  it("v is exactly 1", () => {
    for (const v of [undefined, 0, 2, "1", 1.5, null]) err({ v, strokes: one }, MESSAGES.version);
    ok({ v: 1, strokes: one });
  });

  it("engine: default 'auto', one of the five names", () => {
    assert.equal(ok({ v: 1, strokes: one }).engine, "auto");
    for (const engine of ["auto", "mathpix", "claude", "gemini", "fake"]) {
      assert.equal(ok({ v: 1, engine, strokes: one }).engine, engine);
    }
    for (const engine of ["", "Fake", "openai", 1]) err({ v: 1, engine, strokes: one }, MESSAGES.engine);
    // null counts as omitted (a JSON encoder may write absent optionals as null).
    assert.equal(ok({ v: 1, engine: null, strokes: one }).engine, "auto");
  });

  it("locale: default 'ko', 'ko' or 'en'", () => {
    assert.equal(ok({ v: 1, strokes: one }).locale, "ko");
    assert.equal(ok({ v: 1, locale: "en", strokes: one }).locale, "en");
    for (const locale of ["ja", "", "KO", 3]) err({ v: 1, locale, strokes: one }, MESSAGES.locale);
    assert.equal(ok({ v: 1, locale: null, strokes: one }).locale, "ko");
  });

  it("strokes or pngBase64 is required", () => {
    err({ v: 1 }, MESSAGES.noInput);
    err({ v: 1, engine: "fake", locale: "en" }, MESSAGES.noInput);
  });

  it("unknown top-level keys are ignored and not passed on", () => {
    const r = ok({ v: 1, strokes: one, extra: { a: 1 }, v2Field: true });
    assert.deepEqual(Object.keys(r).sort(), ["engine", "locale", "strokes", "v"]);
  });

  it("both inputs are checked and kept", () => {
    const r = ok({ v: 1, strokes: one, pngBase64: png() });
    assert.deepEqual(r.strokes, one);
    assert.equal(r.pngBase64, png());
  });
});

describe("parseRequest — strokes.x / strokes.y", () => {
  it("must be number[][] of the same shape", () => {
    for (const strokes of [
      null,
      [],
      "x",
      { x: [[1]] },
      { y: [[1]] },
      { x: [1, 2], y: [1, 2] },
      { x: [[1, 2]], y: [[1]] },
      { x: [[1], [2]], y: [[1]] },
      { x: [["1"]], y: [[1]] },
      { x: [[NaN]], y: [[1]] },
      { x: [[Infinity]], y: [[1]] },
      { x: [[1]], y: [[null]] },
    ]) {
      err({ v: 1, strokes }, MESSAGES.strokesShape);
    }
  });

  it("1..2000 strokes", () => {
    err({ v: 1, strokes: { x: [], y: [] } }, MESSAGES.strokesShape);
    ok({ v: 1, strokes: grid(1, 1) });
    ok({ v: 1, strokes: grid(LIMITS.maxStrokes, 1) });
    err({ v: 1, strokes: grid(LIMITS.maxStrokes + 1, 1) }, MESSAGES.strokesShape);
  });

  it("1..10000 points per stroke", () => {
    err({ v: 1, strokes: { x: [[1], []], y: [[1], []] } }, MESSAGES.strokesShape);
    ok({ v: 1, strokes: grid(1, LIMITS.maxPointsPerStroke) });
    err({ v: 1, strokes: grid(1, LIMITS.maxPointsPerStroke + 1) }, MESSAGES.strokesShape);
  });

  it("values are not range-checked (page pt, negative allowed)", () => {
    ok({ v: 1, strokes: { x: [[-5000.5, 1e7]], y: [[-0.1, 0]] } });
  });

  it("only x, y and t go on", () => {
    const r = ok({ v: 1, strokes: { ...one, pressure: [[1, 1]] } });
    assert.deepEqual(r.strokes, one);
  });
});

describe("parseRequest — strokes.t", () => {
  it("same shape as x", () => {
    for (const t of [[[0]], [[0, 1], [2]], [0, 1], "t", null]) {
      err({ v: 1, strokes: { ...one, t } }, MESSAGES.strokesTime);
    }
  });

  it("integer ms ≥ 0, non-decreasing inside a stroke", () => {
    const two = { x: [[1, 2], [3, 4]], y: [[1, 2], [3, 4]] };
    assert.deepEqual(ok({ v: 1, strokes: { ...two, t: [[0, 0], [5, 9]] } }).strokes?.t, [
      [0, 0],
      [5, 9],
    ]);
    // A later stroke may start earlier than the last sample of the one before (only inside a
    // stroke is the order checked).
    ok({ v: 1, strokes: { ...two, t: [[10, 20], [0, 1]] } });
    err({ v: 1, strokes: { ...two, t: [[5, 4], [5, 9]] } }, MESSAGES.strokesTime);
    err({ v: 1, strokes: { ...two, t: [[-1, 0], [5, 9]] } }, MESSAGES.strokesTime);
    err({ v: 1, strokes: { ...two, t: [[0, 1.5], [5, 9]] } }, MESSAGES.strokesTime);
  });
});

describe("parseRequest — strokes size", () => {
  /** Strokes whose JSON is exactly [bytes] bytes (values 100 → 1000 add one byte each). */
  function strokesOfSize(bytes: number) {
    const s = grid(6, LIMITS.maxPointsPerStroke, 100);
    let size = Buffer.byteLength(JSON.stringify(s), "utf8");
    assert.ok(size <= bytes, `base ${size} > ${bytes}`);
    outer: for (const row of s.x) {
      for (let i = 0; i < row.length; i++) {
        if (size === bytes) break outer;
        row[i] = 1000;
        size++;
      }
    }
    assert.equal(Buffer.byteLength(JSON.stringify(s), "utf8"), bytes);
    return s;
  }

  it("JSON ≤ 524,288 bytes", () => {
    ok({ v: 1, strokes: strokesOfSize(LIMITS.strokesJsonBytes) });
    err({ v: 1, strokes: strokesOfSize(LIMITS.strokesJsonBytes + 1) }, MESSAGES.strokesSize);
  });

  it("t counts towards the size", () => {
    const s = strokesOfSize(LIMITS.strokesJsonBytes - 40);
    const t = s.x.map((row) => row.map(() => 0));
    err({ v: 1, strokes: { ...s, t } }, MESSAGES.strokesSize);
  });
});

describe("parseRequest — pngBase64", () => {
  it("a non-empty string", () => {
    for (const pngBase64 of ["", 1, null, [], {}]) err({ v: 1, pngBase64 }, MESSAGES.pngType);
  });

  it("≤ 2,097,152 characters", () => {
    // 1,572,864 bytes → exactly 2,097,152 base64 characters, no padding.
    const atLimit = png(LIMITS.pngBase64Chars * 0.75 - PNG_SIGNATURE.length);
    assert.equal(atLimit.length, LIMITS.pngBase64Chars);
    assert.equal(ok({ v: 1, pngBase64: atLimit }).pngBase64, atLimit);
    err({ v: 1, pngBase64: atLimit + "AAAA" }, MESSAGES.pngSize);
    err({ v: 1, pngBase64: atLimit + "A" }, MESSAGES.pngSize);
  });

  it("base64 characters with padding", () => {
    const good = png(2);
    assert.ok(good.endsWith("="), good);
    ok({ v: 1, pngBase64: good });
    err({ v: 1, pngBase64: good.slice(0, -1) }, MESSAGES.pngBase64); // length % 4 ≠ 0
    err({ v: 1, pngBase64: "iVBO-w0KGgo=" }, MESSAGES.pngBase64);
    err({ v: 1, pngBase64: "iVBORw0K Ggo=" }, MESSAGES.pngBase64);
    err({ v: 1, pngBase64: "iVBORw0KGg==AAAA" }, MESSAGES.pngBase64);
  });

  it("decodes to the PNG signature", () => {
    err({ v: 1, pngBase64: Buffer.from("GIF89a-not-a-png").toString("base64") }, MESSAGES.png);
    err({ v: 1, pngBase64: Buffer.from(PNG_SIGNATURE.slice(0, 7)).toString("base64") }, MESSAGES.png);
    ok({ v: 1, pngBase64: Buffer.from(PNG_SIGNATURE).toString("base64") });
  });
});
