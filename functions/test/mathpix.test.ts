// The Mathpix adapter (07-sync 6.8.6) on an injected fetch — no network: the request shapes (URL,
// headers with the app id and key, body), the answer (latex_styled, confidence), the error kinds
// (401/403 notConfigured, 429 rateLimited, other statuses and connection failures upstream, the
// aborted signal timeout, an `error` field or no latex_styled badResponse) and that the key never
// reaches an error message or the log fields.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { EngineError, type EngineInput } from "../src/engines/engine.js";
import { MATHPIX_API_BASE, MathpixEngine } from "../src/engines/mathpix.js";

const APP = "noteapp-test";
const KEY = "mpx-k1"; // short on purpose: the secrets-hygiene patterns look for long keys

interface Call {
  url: string;
  init: RequestInit;
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

function rig(answer: (call: Call) => Response | Promise<Response>) {
  const calls: Call[] = [];
  const fetchFn = (async (input: string | URL | Request, init?: RequestInit) => {
    const call = { url: String(input), init: init ?? {} };
    calls.push(call);
    return answer(call);
  }) as typeof fetch;
  const engine = new MathpixEngine({ appId: APP, apiKey: KEY, fetch: fetchFn });
  return { engine, calls };
}

const strokes: EngineInput = {
  strokes: { x: [[1, 2, 3], [4, 5]], y: [[6, 7, 8], [9, 10]], t: [[0, 1, 2], [3, 4]] },
  locale: "ko",
};
const png: EngineInput = { png: Buffer.from([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]), locale: "en" };

async function kindOf(p: Promise<unknown>): Promise<string> {
  try {
    await p;
    return "ok";
  } catch (e) {
    assert.ok(e instanceof EngineError, String(e));
    assert.ok(!e.message.includes(KEY), e.message);
    return e.kind;
  }
}

const signal = () => new AbortController().signal;

describe("MathpixEngine requests", () => {
  it("strokes → POST /v3/strokes with app_id / app_key and {strokes: {strokes: {x, y}}}", async () => {
    const { engine, calls } = rig(() => json(200, { latex_styled: "x^{2}", confidence: 0.92 }));
    const s = signal();
    const out = await engine.recognize(strokes, s);
    assert.deepEqual(out, { latex: "x^{2}", confidence: 0.92, version: "v3", logInfo: { endpoint: "strokes" } });
    assert.equal(calls.length, 1);
    const [call] = calls;
    assert.equal(call.url, `${MATHPIX_API_BASE}/strokes`);
    assert.equal(call.url, "https://api.mathpix.com/v3/strokes");
    assert.equal(call.init.method, "POST");
    assert.equal(call.init.signal, s);
    const headers = call.init.headers as Record<string, string>;
    assert.equal(headers["app_id"], APP);
    assert.equal(headers["app_key"], KEY);
    assert.equal(headers["content-type"], "application/json");
    assert.deepEqual(JSON.parse(String(call.init.body)), {
      strokes: { strokes: { x: [[1, 2, 3], [4, 5]], y: [[6, 7, 8], [9, 10]] } },
    });
    assert.ok(!JSON.stringify(out).includes(KEY), "the key is not in the output or log fields");
  });

  it("an image only → POST /v3/text with a PNG data URL and formats [latex_styled]", async () => {
    const { engine, calls } = rig(() => json(200, { latex_styled: "\\sqrt{2}" }));
    const out = await engine.recognize(png, signal());
    assert.deepEqual(out, { latex: "\\sqrt{2}", version: "v3", logInfo: { endpoint: "text" } });
    assert.equal(calls[0].url, "https://api.mathpix.com/v3/text");
    assert.deepEqual(JSON.parse(String(calls[0].init.body)), {
      src: `data:image/png;base64,${png.png!.toString("base64")}`,
      formats: ["latex_styled"],
    });
  });

  it("strokes win over an image; neither → unsupportedInput without a call", async () => {
    const { engine, calls } = rig(() => json(200, { latex_styled: "y" }));
    await engine.recognize({ ...strokes, png: png.png }, signal());
    assert.equal(calls[0].url, "https://api.mathpix.com/v3/strokes");
    assert.equal(await kindOf(engine.recognize({ locale: "en" }, signal())), "unsupportedInput");
    assert.equal(calls.length, 1);
  });

  it("accepts strokes and images", () => {
    const { engine } = rig(() => json(200, {}));
    assert.equal(engine.name, "mathpix");
    assert.deepEqual(engine.accepts, { strokes: true, png: true });
  });
});

describe("MathpixEngine answers and errors", () => {
  for (const [status, kind] of [
    [401, "notConfigured"],
    [403, "notConfigured"],
    [429, "rateLimited"],
    [400, "upstream"],
    [404, "upstream"],
    [500, "upstream"],
    [502, "upstream"],
    [503, "upstream"],
  ] as const) {
    it(`HTTP ${status} → ${kind}`, async () => {
      const { engine } = rig(() => json(status, { error: `headers were app_key ${KEY}` }));
      assert.equal(await kindOf(engine.recognize(strokes, signal())), kind);
    });
  }

  it("a connection failure → upstream", async () => {
    const { engine } = rig(() => {
      throw new TypeError("fetch failed");
    });
    assert.equal(await kindOf(engine.recognize(png, signal())), "upstream");
  });

  it("the signal aborted (the handler's deadline) → timeout", async () => {
    const { engine } = rig(
      (call) =>
        new Promise<Response>((_, reject) => {
          call.init.signal!.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
        }),
    );
    const controller = new AbortController();
    const pending = engine.recognize(strokes, controller.signal);
    controller.abort();
    assert.equal(await kindOf(pending), "timeout");
  });

  it("an error field, no latex_styled, an empty latex or a body that is not JSON → badResponse", async () => {
    const bodies: (() => Response)[] = [
      () => json(200, { error: "Invalid strokes", error_info: { id: "strokes_syntax_error" } }),
      () => json(200, { text: "x" }),
      () => json(200, { latex_styled: "  " }),
      () => json(200, [1, 2]),
      () => new Response("<html>", { status: 200 }),
    ];
    for (const body of bodies) {
      const { engine } = rig(body);
      assert.equal(await kindOf(engine.recognize(strokes, signal())), "badResponse");
    }
    const { engine } = rig(() => json(200, { error: "x", error_info: { id: "image_no_content" } }));
    await assert.rejects(engine.recognize(png, signal()), /image_no_content/);
  });

  it("a confidence outside [0, 1] or not a number is left out", async () => {
    for (const confidence of [1.5, -0.1, "0.9", null]) {
      const { engine } = rig(() => json(200, { latex_styled: "z", confidence }));
      const out = await engine.recognize(strokes, signal());
      assert.equal(out.confidence, undefined, String(confidence));
      assert.equal(out.latex, "z");
    }
  });
});
