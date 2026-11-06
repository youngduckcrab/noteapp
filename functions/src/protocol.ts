// The callable format of recognizeMath (contract 00-overview 7.2.13), version 1.
// docs/plans/m5-7/07-sync.md 4.5, 6.8.3.
//
// Coordinates are page pt and not range-checked (a formula may run off the page); `t` is integer
// ms from the first sample of the first stroke, non-decreasing inside a stroke (CP-L8).

export const PROTOCOL_VERSION = 1 as const;

export type EngineName = "auto" | "mathpix" | "claude" | "gemini" | "fake";
export type Locale = "ko" | "en";

/** Page pt with 1 decimal; t: integer ms from the first sample of the first stroke (CP-L8). */
export interface StrokesInput {
  x: number[][];
  y: number[][];
  t?: number[][];
}

/** After parseRequest: defaults filled. */
export interface RecognizeMathRequest {
  v: 1;
  engine: EngineName;
  strokes?: StrokesInput;
  pngBase64?: string;
  locale: Locale;
}

export interface RecognizeMathResult {
  latex: string;
  confidence?: number;
  alternatives?: string[];
  engine: string;
  engineVersion: string;
  ms: number;
}

export const LIMITS = {
  /** JSON.stringify(strokes) UTF-8 bytes (≤ 512 KB). */
  strokesJsonBytes: 524288,
  /** ≤ 2 MB of base64 text. */
  pngBase64Chars: 2097152,
  maxStrokes: 2000,
  maxPointsPerStroke: 10000,
  /** = CORE PageObjectLimits.maxLatexLength. */
  latexChars: 4000,
  alternatives: 5,
} as const;

const ENGINE_NAMES: readonly EngineName[] = ["auto", "mathpix", "claude", "gemini", "fake"];
const LOCALES: readonly Locale[] = ["ko", "en"];

/** The first 8 bytes of every PNG file. */
export const PNG_SIGNATURE: readonly number[] = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

/** Standard base64 with padding (what the app's base64Encode writes). */
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/;

export const MESSAGES = {
  notObject: "data must be an object",
  version: "unsupported protocol version",
  engine: "unknown engine",
  locale: "unknown locale",
  noInput: "strokes or pngBase64 is required",
  strokesShape: "strokes.x/y must be number[][] of the same shape",
  strokesTime: "strokes.t must be non-decreasing integer ms",
  strokesSize: "strokes is larger than 512 KB",
  pngType: "pngBase64 must be a non-empty string",
  pngSize: "pngBase64 is larger than 2 MB",
  pngBase64: "pngBase64 is not base64",
  png: "pngBase64 is not a PNG",
} as const;

/** Checks shape and limits (6.8.3). Unknown top-level keys are ignored (v1 is additive). */
export function parseRequest(data: unknown): RecognizeMathRequest | { error: string } {
  if (!isRecord(data)) return { error: MESSAGES.notObject };
  if (data.v !== PROTOCOL_VERSION) return { error: MESSAGES.version };

  const engine = data.engine ?? "auto";
  if (!ENGINE_NAMES.includes(engine as EngineName)) return { error: MESSAGES.engine };
  const locale = data.locale ?? "ko";
  if (!LOCALES.includes(locale as Locale)) return { error: MESSAGES.locale };

  const request: RecognizeMathRequest = {
    v: PROTOCOL_VERSION,
    engine: engine as EngineName,
    locale: locale as Locale,
  };
  if (data.strokes === undefined && data.pngBase64 === undefined) {
    return { error: MESSAGES.noInput };
  }
  if (data.strokes !== undefined) {
    const strokes = strokesOf(data.strokes);
    if (typeof strokes === "string") return { error: strokes };
    request.strokes = strokes;
  }
  if (data.pngBase64 !== undefined) {
    const error = pngError(data.pngBase64);
    if (error !== undefined) return { error };
    request.pngBase64 = data.pngBase64 as string;
  }
  return request;
}

/** Only the known keys go on (x, y, t); the size limit counts what goes on. */
function strokesOf(value: unknown): StrokesInput | string {
  if (!isRecord(value)) return MESSAGES.strokesShape;
  const { x, y, t } = value;
  if (!isNumberRows(x) || !isNumberRows(y) || !sameShape(x, y)) return MESSAGES.strokesShape;
  if (x.length < 1 || x.length > LIMITS.maxStrokes) return MESSAGES.strokesShape;
  if (x.some((row) => row.length < 1 || row.length > LIMITS.maxPointsPerStroke)) {
    return MESSAGES.strokesShape;
  }
  const strokes: StrokesInput = { x, y };
  if (t !== undefined) {
    if (!isNumberRows(t) || !sameShape(x, t)) return MESSAGES.strokesTime;
    for (const row of t) {
      for (let i = 0; i < row.length; i++) {
        const ms = row[i];
        if (!Number.isInteger(ms) || ms < 0 || (i > 0 && ms < row[i - 1])) return MESSAGES.strokesTime;
      }
    }
    strokes.t = t;
  }
  if (Buffer.byteLength(JSON.stringify(strokes), "utf8") > LIMITS.strokesJsonBytes) {
    return MESSAGES.strokesSize;
  }
  return strokes;
}

function pngError(value: unknown): string | undefined {
  if (typeof value !== "string" || value.length === 0) return MESSAGES.pngType;
  if (value.length > LIMITS.pngBase64Chars) return MESSAGES.pngSize;
  if (value.length % 4 !== 0 || !BASE64.test(value)) return MESSAGES.pngBase64;
  // Only the head is decoded here; the handler decodes the whole text for the engine.
  const head = Buffer.from(value.slice(0, 12), "base64");
  if (head.length < PNG_SIGNATURE.length) return MESSAGES.png;
  for (let i = 0; i < PNG_SIGNATURE.length; i++) {
    if (head[i] !== PNG_SIGNATURE[i]) return MESSAGES.png;
  }
  return undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNumberRows(value: unknown): value is number[][] {
  return (
    Array.isArray(value) &&
    value.every(
      (row) => Array.isArray(row) && row.every((n) => typeof n === "number" && Number.isFinite(n)),
    )
  );
}

function sameShape(a: number[][], b: number[][]): boolean {
  return a.length === b.length && a.every((row, i) => row.length === b[i].length);
}
