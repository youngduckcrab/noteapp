// The server-side engine port (docs/plans/m5-7/07-sync.md 4.5, 6.8.4). The callable reaches an
// engine only through this port, so changing the engine on the server never changes the app.

import type { EngineName, Locale, StrokesInput } from "../protocol.js";

export interface EngineInput {
  strokes?: StrokesInput;
  png?: Buffer;
  locale: Locale;
}

export interface EngineOutput {
  latex: string;
  confidence?: number;
  alternatives?: string[];
  /** (v2.1, contract 7.2.13) The engine / model that actually answered → engineVersion
   *  (Claude: the response `model` — a server-side fallback may switch it). */
  version: string;
  /** Logged only (never returned): e.g. Claude fallback happened, token counts. */
  logInfo?: Record<string, string | number | boolean>;
}

export interface MathEngine {
  readonly name: Exclude<EngineName, "auto">;
  readonly accepts: { strokes: boolean; png: boolean };
  recognize(input: EngineInput, signal: AbortSignal): Promise<EngineOutput>;
}

export type EngineErrorKind =
  | "notConfigured"
  | "unsupportedInput"
  | "rateLimited"
  | "upstream"
  | "timeout"
  | "refused"
  | "badResponse";

export class EngineError extends Error {
  constructor(
    readonly kind: EngineErrorKind,
    message: string,
  ) {
    super(message);
    this.name = "EngineError";
  }
}

export interface EngineRegistry {
  /** 'auto' → MATH_ENGINE; 'fake' only with ALLOW_FAKE_ENGINE; else EngineError. */
  resolve(requested: EngineName): MathEngine | EngineError;
}
