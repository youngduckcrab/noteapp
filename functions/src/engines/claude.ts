// The Claude adapter (docs/plans/m5-7/07-sync.md 6.8.6, P-C, CP-S5). The official SDK
// (@anthropic-ai/sdk 1.1.0, contract 7.5) behind a thin seam, ClaudeMessagesClient, that tests
// replace. Everything comes through the constructor — the registry passes MATH_API_KEY and
// CLAUDE_MODEL (default '' → notConfigured before an engine is ever built, C23-02) — so this module
// names no model and never reads the params (SYNC-M7). It never logs: what is worth logging goes in
// EngineOutput.logInfo.
//
// One request per call: the PNG as a base64 image block plus a locale hint, structured output
// (JSON schema {latex, confidence, alternatives}), low effort (one formula), no sampling
// parameters, and the server-side refusal fallback (`fallbacks: "default"` with its beta header).
// engineVersion = the response `model` — the model that actually answered, which differs from
// the requested one when the fallback ran (contract 7.2.13); the log says so (`fallback`).
//
// Strokes are not accepted (an image engine). Errors: a refusal → refused; no text block, not JSON,
// or not the schema → badResponse; SDK errors by class (classify()).

import Anthropic from "@anthropic-ai/sdk";
import { EngineError, type EngineInput, type EngineOutput, type MathEngine } from "./engine.js";
import type { Locale } from "../protocol.js";

export type BetaMessageCreateParamsNonStreaming = Anthropic.Beta.Messages.MessageCreateParamsNonStreaming;
export type BetaMessage = Anthropic.Beta.Messages.BetaMessage;

/** The seam over `client.beta.messages` (tests pass a fake). */
export interface ClaudeMessagesClient {
  create(params: BetaMessageCreateParamsNonStreaming, opts: { signal: AbortSignal }): Promise<BetaMessage>;
}

export interface ClaudeEngineOptions {
  apiKey: string;
  /** CLAUDE_MODEL — never empty here (the registry answers notConfigured first). */
  model: string;
  /** Test seam: defaults to the SDK client (no retries — the caller's signal bounds the call). */
  client?: ClaudeMessagesClient;
}

/** The server-side fallback on a refusal ('default' routes by refusal category). */
export const FALLBACK_BETA = "server-side-fallback-2026-07-01";
/** The SDK's own deadline; the handler's signal (ENGINE_TIMEOUT_MS) normally fires first. */
export const SDK_TIMEOUT_MS = 25_000;
export const MAX_TOKENS = 16_000;

/** Structured output: every key required, nothing else (structured outputs need both). */
export const LATEX_SCHEMA = {
  type: "object",
  properties: {
    latex: { type: "string", description: "The formula as LaTeX, without $ or \\[ \\] delimiters." },
    confidence: { type: "number", description: "How sure the transcription is, from 0 to 1." },
    alternatives: {
      type: "array",
      items: { type: "string" },
      description: "Up to 5 other plausible readings as LaTeX, most likely first; [] when none.",
    },
  },
  required: ["latex", "confidence", "alternatives"],
  additionalProperties: false,
} as const;

export const SYSTEM_PROMPT = [
  "You transcribe handwritten mathematics from an image into LaTeX for a note-taking app.",
  "The image holds one formula, or a few lines of one derivation, written with a stylus.",
  "Write exactly what is written: do not solve, simplify, complete or correct it.",
  "Return the LaTeX without math delimiters, with \\\\ between lines.",
  "When a symbol is ambiguous, pick the reading that fits the rest of the formula and lower the",
  "confidence; list the other readings in alternatives.",
].join(" ");

export function localeHint(locale: Locale): string {
  return locale === "ko"
    ? "The handwriting may contain Korean words; write each one inside \\text{…}."
    : "The handwriting may contain English words; write each one inside \\text{…}.";
}

export class ClaudeEngine implements MathEngine {
  readonly name = "claude" as const;
  readonly accepts = { strokes: false, png: true } as const;

  private readonly model: string;
  private readonly client: ClaudeMessagesClient;

  constructor(opts: ClaudeEngineOptions) {
    this.model = opts.model;
    this.client = opts.client ?? sdkMessagesClient(opts.apiKey);
  }

  /** The request recognize() sends (exposed for tests). */
  requestFor(png: Buffer, locale: Locale): BetaMessageCreateParamsNonStreaming {
    return {
      model: this.model,
      max_tokens: MAX_TOKENS,
      betas: [FALLBACK_BETA],
      fallbacks: "default",
      output_config: {
        effort: "low",
        format: { type: "json_schema", schema: LATEX_SCHEMA },
      },
      system: SYSTEM_PROMPT,
      messages: [
        {
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: "image/png", data: png.toString("base64") } },
            { type: "text", text: localeHint(locale) },
          ],
        },
      ],
    };
  }

  async recognize(input: EngineInput, signal: AbortSignal): Promise<EngineOutput> {
    if (input.png === undefined) {
      throw new EngineError("unsupportedInput", "claude: an image is needed (strokes are not accepted)");
    }
    let res: BetaMessage;
    try {
      res = await this.client.create(this.requestFor(input.png, input.locale), { signal });
    } catch (e) {
      throw classify(e, signal);
    }
    if (res.stop_reason === "refusal") {
      throw new EngineError("refused", `claude: declined (${res.stop_details?.category ?? "no category"})`);
    }
    const text = res.content.find((b) => b.type === "text");
    if (text === undefined || text.type !== "text") {
      throw new EngineError("badResponse", `claude: no text in the answer (stop ${res.stop_reason})`);
    }
    const answer = parseAnswer(text.text, res.stop_reason);
    const fallbackRan =
      res.model !== this.model || (res.usage.iterations ?? []).some((i) => i.type === "fallback_message");
    return {
      ...answer,
      version: res.model,
      logInfo: {
        requestedModel: this.model,
        fallback: fallbackRan,
        inTok: res.usage.input_tokens,
        outTok: res.usage.output_tokens,
      },
    };
  }
}

/** The default seam: the SDK's beta messages, no retries (one attempt inside the caller's signal).
 *  [fetchImpl] lets a test see the HTTP request the SDK makes — no network. */
export function sdkMessagesClient(apiKey: string, fetchImpl?: typeof fetch): ClaudeMessagesClient {
  const anthropic = new Anthropic({
    apiKey,
    maxRetries: 0,
    timeout: SDK_TIMEOUT_MS,
    ...(fetchImpl === undefined ? {} : { fetch: fetchImpl }),
  });
  return { create: (params, opts) => anthropic.beta.messages.create(params, opts) };
}

function parseAnswer(text: string, stop: string | null): Pick<EngineOutput, "latex" | "confidence" | "alternatives"> {
  let json: unknown;
  try {
    json = JSON.parse(text);
  } catch {
    throw new EngineError("badResponse", `claude: the answer is not JSON (stop ${stop})`);
  }
  if (typeof json !== "object" || json === null || Array.isArray(json)) {
    throw new EngineError("badResponse", "claude: the answer is not an object");
  }
  const { latex, confidence, alternatives } = json as Record<string, unknown>;
  if (typeof latex !== "string" || latex.trim() === "") {
    throw new EngineError("badResponse", "claude: no latex in the answer");
  }
  if (typeof confidence !== "number" || !Number.isFinite(confidence)) {
    throw new EngineError("badResponse", "claude: confidence is not a number");
  }
  if (!Array.isArray(alternatives) || !alternatives.every((a) => typeof a === "string")) {
    throw new EngineError("badResponse", "claude: alternatives is not a list of strings");
  }
  // Range and count are the handler's output check (6.8.2 step 7): confidence outside [0, 1] is
  // dropped there, more than 5 alternatives → internal.
  return { latex, confidence, alternatives: alternatives as string[] };
}

/** SDK errors → EngineError (most specific first; APIConnectionError is an APIError subclass). */
export function classify(e: unknown, signal: AbortSignal): EngineError {
  if (e instanceof EngineError) return e;
  if (signal.aborted || e instanceof Anthropic.APIUserAbortError) {
    return new EngineError("timeout", "claude: the call was cut off");
  }
  if (e instanceof Anthropic.APIConnectionTimeoutError) {
    return new EngineError("timeout", "claude: the call timed out");
  }
  if (e instanceof Anthropic.APIConnectionError) {
    return new EngineError("upstream", "claude: connection failed");
  }
  if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) {
    return new EngineError("notConfigured", `claude: HTTP ${e.status} (the key is refused)`);
  }
  if (e instanceof Anthropic.NotFoundError) {
    return new EngineError("notConfigured", "claude: HTTP 404 (CLAUDE_MODEL is not a model of this key)");
  }
  if (e instanceof Anthropic.RateLimitError) return new EngineError("rateLimited", "claude: HTTP 429");
  if (e instanceof Anthropic.APIError) {
    return new EngineError("upstream", `claude: HTTP ${e.status ?? "?"} (${e.type ?? "error"})`);
  }
  return new EngineError("upstream", `claude: ${e instanceof Error ? e.name : typeof e}`);
}
