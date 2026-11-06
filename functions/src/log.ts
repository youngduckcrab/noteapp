// Structured logs of recognizeMath (docs/plans/m5-7/07-sync.md 6.8.10): sizes, engine, outcome
// and time only. Logged: uid, engine name and version, stroke / point / PNG byte counts, the
// outcome code, ms, the daily count used, and the engine's own logInfo (e.g. Claude token counts,
// fallback). Never logged: stroke coordinates, the PNG, the LaTeX result, keys.

import * as logger from "firebase-functions/logger";
import type { RecognizeMathRequest } from "./protocol.js";

export type LogValue = string | number | boolean;
export type LogFields = Readonly<Record<string, LogValue>>;

export interface Logger {
  info(message: string, fields: LogFields): void;
  warn(message: string, fields: LogFields): void;
  error(message: string, fields: LogFields): void;
}

/** firebase-functions/logger (Cloud Logging structured entries). */
export const functionsLogger: Logger = {
  info: (message, fields) => logger.info(message, fields),
  warn: (message, fields) => logger.warn(message, fields),
  error: (message, fields) => logger.error(message, fields),
};

/** The size of the request input — never its content. */
export function inputSizeFields(request: RecognizeMathRequest): LogFields {
  const fields: Record<string, LogValue> = { locale: request.locale, requestedEngine: request.engine };
  if (request.strokes !== undefined) {
    fields.strokes = request.strokes.x.length;
    fields.points = request.strokes.x.reduce((sum, stroke) => sum + stroke.length, 0);
  }
  if (request.pngBase64 !== undefined) fields.pngBytes = base64DecodedLength(request.pngBase64);
  return fields;
}

/** Decoded byte count of a (checked) base64 string, without decoding it. */
function base64DecodedLength(text: string): number {
  const padding = text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0;
  return (text.length / 4) * 3 - padding;
}

/** [base] plus the engine's [extra] fields; a key of [base] is never replaced. */
export function withEngineInfo(base: LogFields, extra: LogFields | undefined): LogFields {
  if (extra === undefined) return base;
  const out: Record<string, LogValue> = {};
  for (const [key, value] of Object.entries(extra)) {
    if (!(key in base) && isLogValue(value)) out[key] = value;
  }
  return { ...out, ...base };
}

function isLogValue(value: unknown): value is LogValue {
  return typeof value === "string" || typeof value === "boolean" || (typeof value === "number" && Number.isFinite(value));
}
