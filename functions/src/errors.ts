// EngineError → HttpsError (docs/plans/m5-7/07-sync.md 6.8.8). An engine-side 429 is
// `unavailable`, not `resource-exhausted`: the app's text for that code says the user's own daily
// count is used up. `details` is never set (the app reads status and message only).

import { HttpsError } from "firebase-functions/https";
import type { EngineError, EngineErrorKind } from "./engines/engine.js";

const codeOf: Record<EngineErrorKind, "invalid-argument" | "unavailable" | "internal"> = {
  unsupportedInput: "invalid-argument",
  notConfigured: "unavailable",
  rateLimited: "unavailable",
  upstream: "unavailable",
  timeout: "unavailable",
  refused: "internal",
  badResponse: "internal",
};

export function httpsErrorOf(error: EngineError): HttpsError {
  return new HttpsError(codeOf[error.kind], error.message);
}
