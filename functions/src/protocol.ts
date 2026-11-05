// The callable format of recognizeMath (contract 00-overview 7.2.13), version 1.
// docs/plans/m5-7/07-sync.md 4.5, 6.8.3.
//
// R2-B7b skeleton: the types, the limits and the shape checks the fake engine needs. The rest of
// the 6.8.3 table (sizes, `t` order, base64 alphabet, PNG signature) is S2-10a.

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

/** Checks shape and limits (6.8.3). Unknown top-level keys are ignored (v1 is additive). */
export function parseRequest(data: unknown): RecognizeMathRequest | { error: string } {
  if (!isRecord(data)) return { error: "data must be an object" };
  if (data.v !== PROTOCOL_VERSION) return { error: "unsupported protocol version" };

  const engine = data.engine ?? "auto";
  if (!ENGINE_NAMES.includes(engine as EngineName)) return { error: "unknown engine" };
  const locale = data.locale ?? "ko";
  if (!LOCALES.includes(locale as Locale)) return { error: "unknown locale" };

  const request: RecognizeMathRequest = {
    v: PROTOCOL_VERSION,
    engine: engine as EngineName,
    locale: locale as Locale,
  };
  if (data.strokes === undefined && data.pngBase64 === undefined) {
    return { error: "strokes or pngBase64 is required" };
  }
  if (data.strokes !== undefined) {
    const strokes = strokesOf(data.strokes);
    if (typeof strokes === "string") return { error: strokes };
    request.strokes = strokes;
  }
  if (data.pngBase64 !== undefined) {
    if (typeof data.pngBase64 !== "string" || data.pngBase64.length === 0) {
      return { error: "pngBase64 is not a PNG" };
    }
    request.pngBase64 = data.pngBase64;
  }
  return request;
}

function strokesOf(value: unknown): StrokesInput | string {
  const shapeError = "strokes.x/y must be number[][] of the same shape";
  if (!isRecord(value)) return shapeError;
  const { x, y, t } = value;
  if (!isNumberRows(x) || !isNumberRows(y) || x.length === 0 || !sameShape(x, y)) {
    return shapeError;
  }
  if (x.some((row) => row.length === 0)) return shapeError;
  const strokes: StrokesInput = { x, y };
  if (t !== undefined) {
    if (!isNumberRows(t) || !sameShape(x, t)) return "strokes.t must be non-decreasing integer ms";
    strokes.t = t;
  }
  return strokes;
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
