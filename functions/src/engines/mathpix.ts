// The Mathpix adapter (docs/plans/m5-7/07-sync.md 6.8.6, P-C). Node's built-in fetch — Mathpix has
// no official Node SDK. Everything comes through the constructor (the registry or the comparison
// tool passes it); this module never reads the params (SYNC-M7) and never logs. The request shapes
// follow the plan's reading of the Mathpix docs and are checked against real calls only once the
// account exists (U6):
//
//   strokes → POST https://api.mathpix.com/v3/strokes  {"strokes": {"strokes": {"x": [[…]], "y": [[…]]}}}
//   png     → POST https://api.mathpix.com/v3/text     {"src": "data:image/png;base64,…",
//                                                       "formats": ["latex_styled"]}
//   headers app_id, app_key (the key never goes into an error message or the log)
//   answer  latex_styled → latex, confidence when present; an `error` field → badResponse
//
// HTTP 401/403 → notConfigured, 429 → rateLimited, other statuses and connection failures →
// upstream, the signal aborted → timeout. engineVersion 'v3' (the API version).

import { EngineError, type EngineInput, type EngineOutput, type MathEngine } from "./engine.js";

export const MATHPIX_API_BASE = "https://api.mathpix.com/v3";
export const MATHPIX_ENGINE_VERSION = "v3";

export interface MathpixEngineOptions {
  appId: string;
  apiKey: string;
  /** Test seam: defaults to the global fetch. */
  fetch?: typeof fetch;
}

export class MathpixEngine implements MathEngine {
  readonly name = "mathpix" as const;
  readonly accepts = { strokes: true, png: true } as const;

  private readonly appId: string;
  private readonly apiKey: string;
  private readonly fetchFn: typeof fetch;

  constructor(opts: MathpixEngineOptions) {
    this.appId = opts.appId;
    this.apiKey = opts.apiKey;
    this.fetchFn = opts.fetch ?? ((input, init) => fetch(input, init));
  }

  async recognize(input: EngineInput, signal: AbortSignal): Promise<EngineOutput> {
    let endpoint: "strokes" | "text";
    let body: unknown;
    if (input.strokes !== undefined) {
      endpoint = "strokes";
      body = { strokes: { strokes: { x: input.strokes.x, y: input.strokes.y } } };
    } else if (input.png !== undefined) {
      endpoint = "text";
      body = { src: `data:image/png;base64,${input.png.toString("base64")}`, formats: ["latex_styled"] };
    } else {
      throw new EngineError("unsupportedInput", "mathpix: neither strokes nor an image");
    }

    let response: Response;
    try {
      response = await this.fetchFn(`${MATHPIX_API_BASE}/${endpoint}`, {
        method: "POST",
        headers: { "content-type": "application/json", app_id: this.appId, app_key: this.apiKey },
        body: JSON.stringify(body),
        signal,
      });
    } catch (e) {
      if (signal.aborted) throw new EngineError("timeout", "mathpix: the call was cut off");
      throw new EngineError("upstream", `mathpix: connection failed (${errorName(e)})`);
    }

    if (!response.ok) {
      // Not read: an error body may echo request headers.
      const status = response.status;
      if (status === 401 || status === 403) {
        throw new EngineError("notConfigured", `mathpix: HTTP ${status} (app id or key refused)`);
      }
      if (status === 429) throw new EngineError("rateLimited", "mathpix: HTTP 429");
      throw new EngineError("upstream", `mathpix: HTTP ${status}`);
    }

    let json: unknown;
    try {
      json = await response.json();
    } catch (e) {
      if (signal.aborted) throw new EngineError("timeout", "mathpix: the call was cut off");
      throw new EngineError("badResponse", "mathpix: the answer is not JSON");
    }
    return {
      ...parseAnswer(json),
      version: MATHPIX_ENGINE_VERSION,
      logInfo: { endpoint },
    };
  }
}

function parseAnswer(json: unknown): Pick<EngineOutput, "latex" | "confidence"> {
  if (typeof json !== "object" || json === null || Array.isArray(json)) {
    throw new EngineError("badResponse", "mathpix: the answer is not an object");
  }
  const answer = json as Record<string, unknown>;
  if (answer.error !== undefined && answer.error !== null && answer.error !== "") {
    const info = typeof answer.error_info === "object" && answer.error_info !== null
      ? (answer.error_info as Record<string, unknown>).id
      : undefined;
    throw new EngineError("badResponse", `mathpix: error ${typeof info === "string" ? info : "in the answer"}`);
  }
  const latex = answer.latex_styled;
  if (typeof latex !== "string" || latex.trim() === "") {
    throw new EngineError("badResponse", "mathpix: no latex_styled in the answer");
  }
  const confidence = answer.confidence;
  return typeof confidence === "number" && Number.isFinite(confidence) && confidence >= 0 && confidence <= 1
    ? { latex, confidence }
    : { latex };
}

function errorName(e: unknown): string {
  return e instanceof Error ? e.name : typeof e;
}
