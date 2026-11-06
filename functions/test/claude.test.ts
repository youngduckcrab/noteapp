// The Claude adapter (07-sync 6.8.6, CP-S5) with a fake ClaudeMessagesClient — no network: the
// request (configured model, max_tokens, the fallback beta and `fallbacks: "default"`, low effort,
// the JSON schema, the base64 PNG and the locale hint, the caller's signal, no sampling parameters),
// the answer (first text block, JSON, schema), engineVersion = the response model and the log's
// `fallback` (SYNC-M7), a refusal, and the SDK error classes → EngineError kinds. The last block
// runs the real SDK client on an injected fetch to see the HTTP request it builds (beta header,
// body) and that it does not retry.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import Anthropic from "@anthropic-ai/sdk";
import {
  ClaudeEngine,
  FALLBACK_BETA,
  LATEX_SCHEMA,
  MAX_TOKENS,
  SYSTEM_PROMPT,
  classify,
  localeHint,
  sdkMessagesClient,
  type BetaMessage,
  type BetaMessageCreateParamsNonStreaming,
  type ClaudeMessagesClient,
} from "../src/engines/claude.js";
import { EngineError, type EngineInput } from "../src/engines/engine.js";

const MODEL = "model-under-test"; // a placeholder: no model name in code or tests (C23-02)
const KEY = "test-key";
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 7, 7]);
const input: EngineInput = { png: PNG, locale: "ko" };

function message(over: Partial<BetaMessage> & { text?: string } = {}): BetaMessage {
  const { text, ...rest } = over;
  return {
    id: "msg_1",
    type: "message",
    role: "assistant",
    model: MODEL,
    content: [
      { type: "thinking", thinking: "", signature: "s" },
      { type: "text", text: text ?? JSON.stringify({ latex: "\\frac{a}{b}", confidence: 0.8, alternatives: ["a/b"] }) },
    ],
    stop_reason: "end_turn",
    stop_sequence: null,
    usage: { input_tokens: 1200, output_tokens: 40, iterations: null },
    ...rest,
  } as unknown as BetaMessage;
}

interface Seen {
  params: BetaMessageCreateParamsNonStreaming;
  signal: AbortSignal;
}

function rig(answer: (seen: Seen) => BetaMessage | Promise<BetaMessage>) {
  const seen: Seen[] = [];
  const client: ClaudeMessagesClient = {
    create: async (params, opts) => {
      const s = { params, signal: opts.signal };
      seen.push(s);
      return answer(s);
    },
  };
  return { engine: new ClaudeEngine({ apiKey: KEY, model: MODEL, client }), seen };
}

const signal = () => new AbortController().signal;

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

describe("ClaudeEngine request", () => {
  it("one call: the configured model, the fallback beta, low effort, the schema, the image and the hint", async () => {
    const { engine, seen } = rig(() => message());
    const s = signal();
    await engine.recognize(input, s);
    assert.equal(seen.length, 1);
    const { params, signal: passed } = seen[0];
    assert.equal(passed, s);
    assert.equal(params.model, MODEL);
    assert.equal(params.max_tokens, MAX_TOKENS);
    assert.deepEqual(params.betas, [FALLBACK_BETA]);
    assert.equal(FALLBACK_BETA, "server-side-fallback-2026-07-01");
    assert.equal(params.fallbacks, "default");
    assert.deepEqual(params.output_config, {
      effort: "low",
      format: { type: "json_schema", schema: LATEX_SCHEMA },
    });
    assert.equal(params.system, SYSTEM_PROMPT);
    assert.deepEqual(params.messages, [
      {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: "image/png", data: PNG.toString("base64") } },
          { type: "text", text: localeHint("ko") },
        ],
      },
    ]);
    for (const k of ["temperature", "top_p", "top_k", "thinking", "stream"]) {
      assert.ok(!(k in params), `no ${k}`);
    }
  });

  it("the locale hint follows the request locale", async () => {
    const { engine, seen } = rig(() => message());
    await engine.recognize({ png: PNG, locale: "en" }, signal());
    const content = seen[0].params.messages[0].content as { type: string; text?: string }[];
    assert.equal(content[1].text, localeHint("en"));
    assert.notEqual(localeHint("en"), localeHint("ko"));
    assert.match(localeHint("ko"), /Korean/);
  });

  it("the schema asks for latex, confidence and alternatives and nothing else", () => {
    assert.deepEqual([...LATEX_SCHEMA.required], ["latex", "confidence", "alternatives"]);
    assert.equal(LATEX_SCHEMA.additionalProperties, false);
    assert.deepEqual(Object.keys(LATEX_SCHEMA.properties).sort(), ["alternatives", "confidence", "latex"]);
  });

  it("images only: strokes → unsupportedInput without a call", async () => {
    const { engine, seen } = rig(() => message());
    assert.deepEqual(engine.accepts, { strokes: false, png: true });
    assert.equal(engine.name, "claude");
    assert.equal(
      await kindOf(engine.recognize({ strokes: { x: [[1]], y: [[1]] }, locale: "en" }, signal())),
      "unsupportedInput",
    );
    assert.equal(seen.length, 0);
  });
});

describe("ClaudeEngine answer", () => {
  it("the first text block's JSON → latex, confidence, alternatives; engineVersion = the response model", async () => {
    const { engine } = rig(() => message());
    const out = await engine.recognize(input, signal());
    assert.deepEqual(out, {
      latex: "\\frac{a}{b}",
      confidence: 0.8,
      alternatives: ["a/b"],
      version: MODEL,
      logInfo: { requestedModel: MODEL, fallback: false, inTok: 1200, outTok: 40 },
    });
  });

  it("the server-side fallback answered with another model → engineVersion = that model, log fallback: true", async () => {
    const { engine } = rig(() => message({ model: "fallback-model" }));
    const out = await engine.recognize(input, signal());
    assert.equal(out.version, "fallback-model");
    assert.equal(out.logInfo?.fallback, true);
    assert.equal(out.logInfo?.requestedModel, MODEL);
  });

  it("a fallback iteration in usage counts as a fallback even with the same model name", async () => {
    const { engine } = rig(() =>
      message({
        usage: {
          input_tokens: 1,
          output_tokens: 2,
          iterations: [{ type: "fallback_message" }],
        } as unknown as BetaMessage["usage"],
      }),
    );
    const out = await engine.recognize(input, signal());
    assert.equal(out.version, MODEL);
    assert.equal(out.logInfo?.fallback, true);
  });

  it("a refusal (the whole fallback chain declined) → refused", async () => {
    const { engine } = rig(() =>
      message({
        stop_reason: "refusal",
        stop_details: { type: "refusal", category: null, explanation: null },
      } as unknown as Partial<BetaMessage>),
    );
    assert.equal(await kindOf(engine.recognize(input, signal())), "refused");
  });

  it("no text block, not JSON, or not the schema → badResponse", async () => {
    const answers: BetaMessage[] = [
      message({ content: [] }),
      message({ text: "x^2" }),
      message({ text: "[1]" }),
      message({ text: JSON.stringify({ confidence: 1, alternatives: [] }) }),
      message({ text: JSON.stringify({ latex: " ", confidence: 1, alternatives: [] }) }),
      message({ text: JSON.stringify({ latex: "x", confidence: "high", alternatives: [] }) }),
      message({ text: JSON.stringify({ latex: "x", confidence: 1, alternatives: [1] }) }),
      message({ text: JSON.stringify({ latex: "x", confidence: 1 }) }),
      message({ text: '{"latex": "x", "confi', stop_reason: "max_tokens" }),
    ];
    for (const answer of answers) {
      const { engine } = rig(() => answer);
      assert.equal(await kindOf(engine.recognize(input, signal())), "badResponse", JSON.stringify(answer.content));
    }
  });
});

describe("ClaudeEngine errors (SDK classes → kinds)", () => {
  const headers = new Headers();
  const body = (type: string) => ({ type: "error", error: { type, message: "m" } });
  const cases: [string, () => unknown, string][] = [
    ["AuthenticationError 401", () => new Anthropic.AuthenticationError(401, body("authentication_error"), "m", headers), "notConfigured"],
    ["PermissionDeniedError 403", () => new Anthropic.PermissionDeniedError(403, body("permission_error"), "m", headers), "notConfigured"],
    ["NotFoundError 404 (unknown model)", () => new Anthropic.NotFoundError(404, body("not_found_error"), "m", headers), "notConfigured"],
    ["RateLimitError 429", () => new Anthropic.RateLimitError(429, body("rate_limit_error"), "m", headers), "rateLimited"],
    ["InternalServerError 500", () => new Anthropic.InternalServerError(500, body("api_error"), "m", headers), "upstream"],
    ["overloaded 529", () => Anthropic.APIError.generate(529, body("overloaded_error"), "m", headers), "upstream"],
    ["BadRequestError 400", () => new Anthropic.BadRequestError(400, body("invalid_request_error"), "m", headers), "upstream"],
    ["APIConnectionError", () => new Anthropic.APIConnectionError({ message: "down" }), "upstream"],
    ["APIConnectionTimeoutError", () => new Anthropic.APIConnectionTimeoutError(), "timeout"],
    ["APIUserAbortError", () => new Anthropic.APIUserAbortError(), "timeout"],
    ["a TypeError", () => new TypeError("boom"), "upstream"],
  ];
  for (const [name, error, kind] of cases) {
    it(`${name} → ${kind}`, async () => {
      const { engine } = rig(() => {
        throw error();
      });
      assert.equal(await kindOf(engine.recognize(input, signal())), kind);
    });
  }

  it("the handler's signal aborted (AbortController.abort()) → timeout, whatever the SDK threw", async () => {
    const { engine } = rig(
      ({ signal: s }) =>
        new Promise<BetaMessage>((_, reject) => {
          s.addEventListener("abort", () => reject(new Error("socket hang up")));
        }),
    );
    const controller = new AbortController();
    const pending = engine.recognize(input, controller.signal);
    controller.abort();
    assert.equal(await kindOf(pending), "timeout");
  });

  it("classify keeps an EngineError", () => {
    const e = new EngineError("refused", "x");
    assert.equal(classify(e, signal()), e);
  });
});

describe("the default SDK client (sdkMessagesClient) on an injected fetch", () => {
  interface Http {
    url: string;
    headers: Headers;
    body: Record<string, unknown>;
  }

  function sdkRig(answer: () => Response) {
    const requests: Http[] = [];
    const fetchFn = (async (url: string | URL | Request, init?: RequestInit) => {
      requests.push({
        url: String(url),
        headers: new Headers(init?.headers),
        body: JSON.parse(String(init?.body)) as Record<string, unknown>,
      });
      return answer();
    }) as typeof fetch;
    const engine = new ClaudeEngine({ apiKey: KEY, model: MODEL, client: sdkMessagesClient(KEY, fetchFn) });
    return { engine, requests };
  }

  const ok = () =>
    new Response(JSON.stringify(message()), { status: 200, headers: { "content-type": "application/json" } });

  it("POST /v1/messages?beta=true; the beta goes in the anthropic-beta header, the rest in the body", async () => {
    const { engine, requests } = sdkRig(ok);
    const out = await engine.recognize(input, signal());
    assert.equal(out.latex, "\\frac{a}{b}");
    assert.equal(out.version, MODEL);
    assert.equal(requests.length, 1);
    const [r] = requests;
    assert.match(r.url, /^https:\/\/api\.anthropic\.com\/v1\/messages\?beta=true$/);
    // SDK 1.1.0 sends the key as a bearer token (older releases used x-api-key).
    assert.equal(r.headers.get("x-api-key") ?? r.headers.get("authorization")?.replace(/^Bearer /, ""), KEY);
    assert.ok((r.headers.get("anthropic-beta") ?? "").split(",").includes(FALLBACK_BETA));
    assert.ok(!("betas" in r.body));
    assert.equal(r.body.model, MODEL);
    assert.equal(r.body.fallbacks, "default");
    assert.deepEqual(r.body.output_config, { effort: "low", format: { type: "json_schema", schema: LATEX_SCHEMA } });
    assert.equal(r.body.max_tokens, MAX_TOKENS);
  });

  it("no retries: a 529 or a 429 is one request and the matching kind", async () => {
    for (const [status, type, kind] of [
      [529, "overloaded_error", "upstream"],
      [429, "rate_limit_error", "rateLimited"],
      [401, "authentication_error", "notConfigured"],
    ] as const) {
      const { engine, requests } = sdkRig(
        () =>
          new Response(JSON.stringify({ type: "error", error: { type, message: "m" } }), {
            status,
            headers: { "content-type": "application/json" },
          }),
      );
      assert.equal(await kindOf(engine.recognize(input, signal())), kind, String(status));
      assert.equal(requests.length, 1, String(status));
    }
  });
});
