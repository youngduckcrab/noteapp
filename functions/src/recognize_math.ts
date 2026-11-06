// The callable recognizeMath (contract 00-overview 7.2.13, docs/plans/m5-7/07-sync.md 4.5, 6.8.2).
// The body is createRecognizeMathHandler (no firebase-functions request types — unit-testable);
// the onCall wiring at the bottom is the only part the emulator needs.
//
// Order (6.8.2): sign-in → owner list → request check → engine and its input → daily cap (right
// before the engine: a bad request never uses a count) → engine call under the deadline signal →
// output check → one log line per call (6.8.10 — sizes, engine, outcome, ms; never content).
// The onCall wiring reads QUOTA_STORE on the first call (quotaStoreFor): Firestore through the
// Admin SDK in production, memory in the emulator demo (.env.demo-noteapp).

import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall, type CallableFunction, type FunctionsErrorCode } from "firebase-functions/https";
import { isOwner, parseOwnerUids } from "./access.js";
import { EngineError, type EngineInput, type EngineOutput, type EngineRegistry } from "./engines/engine.js";
import { registryFromParams } from "./engines/registry.js";
import { httpsErrorOf } from "./errors.js";
import { functionsLogger, inputSizeFields, withEngineInfo, type LogFields, type LogValue, type Logger } from "./log.js";
import { DAILY_CAP, MATH_API_KEY, OWNER_UIDS, QUOTA_STORE } from "./params.js";
import { LIMITS, parseRequest, type RecognizeMathResult } from "./protocol.js";
import { quotaStoreFor, seoulDayKey, type QuotaStore } from "./quota.js";

export interface HandlerDeps {
  /** OWNER_UIDS, comma separated, trimmed; empty → nobody. */
  ownerUids(): readonly string[];
  engines: EngineRegistry;
  quota: QuotaStore;
  /** DAILY_CAP (≤ 0 → no cap). */
  dailyCap(): number;
  /** Epoch ms. */
  now(): number;
  /** (v2.1, SYNC-M7) The engine-call deadline signal. Production: AbortSignal.timeout(ms).
   *  Tests pass a function returning their own AbortController's signal and abort() it —
   *  AbortSignal.timeout does not follow node:test mock timers. */
  engineSignal(ms: number): AbortSignal;
  log: Logger;
}

/** The engine call is cut at 25 s so the function's own 30 s limit is not reached. */
export const ENGINE_TIMEOUT_MS = 25_000;

/** The log message of every call. */
export const LOG_MESSAGE = "recognizeMath";

/** The callable body without firebase-functions types (unit-testable). Throws HttpsError. */
export function createRecognizeMathHandler(
  deps: HandlerDeps,
): (req: { auth?: { uid: string } | null; data: unknown }) => Promise<RecognizeMathResult> {
  return async (req) => {
    const t0 = deps.now();
    const fields: Record<string, LogValue> = {};
    let engineInfo: LogFields | undefined;
    const finish = (outcome: "ok" | FunctionsErrorCode): void => {
      const line = withEngineInfo({ ...fields, outcome, ms: deps.now() - t0 }, engineInfo);
      if (outcome === "ok") deps.log.info(LOG_MESSAGE, line);
      else if (outcome === "unavailable" || outcome === "internal") deps.log.error(LOG_MESSAGE, line);
      else deps.log.warn(LOG_MESSAGE, line);
    };
    try {
      const result = await handle(deps, req, t0, fields, (info) => (engineInfo = info));
      finish("ok");
      return result;
    } catch (e) {
      const error = e instanceof HttpsError ? e : new HttpsError("internal", "recognizeMath failed");
      finish(error.code);
      throw error;
    }
  };
}

async function handle(
  deps: HandlerDeps,
  req: { auth?: { uid: string } | null; data: unknown },
  t0: number,
  fields: Record<string, LogValue>,
  setEngineInfo: (info: LogFields | undefined) => void,
): Promise<RecognizeMathResult> {
  // 1–2. Sign-in and owner list.
  if (req.auth == null) throw new HttpsError("unauthenticated", "sign-in required");
  const uid = req.auth.uid;
  fields.uid = uid;
  if (!isOwner(uid, deps.ownerUids())) {
    throw new HttpsError("permission-denied", "this account may not use recognizeMath");
  }

  // 3. Request.
  const request = parseRequest(req.data);
  if ("error" in request) throw new HttpsError("invalid-argument", request.error);
  Object.assign(fields, inputSizeFields(request));

  // 4. Engine and its input.
  const engine = deps.engines.resolve(request.engine);
  if (engine instanceof EngineError) {
    fields.engineError = engine.kind;
    throw httpsErrorOf(engine);
  }
  fields.engine = engine.name;
  const input: EngineInput = { locale: request.locale };
  if (request.strokes !== undefined && engine.accepts.strokes) input.strokes = request.strokes;
  if (request.pngBase64 !== undefined && engine.accepts.png) {
    input.png = Buffer.from(request.pngBase64, "base64");
  }
  if (input.strokes === undefined && input.png === undefined) {
    throw new HttpsError("invalid-argument", `engine ${engine.name} cannot take this input`);
  }

  // 5. Daily cap, right before the engine (the call that fails later keeps its count).
  const cap = deps.dailyCap();
  if (cap > 0) {
    let taken: { allowed: boolean; used: number };
    try {
      taken = await deps.quota.take(uid, seoulDayKey(t0), cap);
    } catch (e) {
      fields.quotaError = e instanceof Error ? e.name : "unknown";
      throw new HttpsError("unavailable", "the daily count could not be checked");
    }
    fields.quotaUsed = taken.used;
    fields.quotaCap = cap;
    if (!taken.allowed) throw new HttpsError("resource-exhausted", "the daily limit is used up");
  }

  // 6. Engine call under the deadline signal.
  const signal = deps.engineSignal(ENGINE_TIMEOUT_MS);
  let out: EngineOutput;
  try {
    out = await engine.recognize(input, signal);
  } catch (e) {
    if (e instanceof EngineError) {
      fields.engineError = e.kind;
      throw httpsErrorOf(e);
    }
    if (signal.aborted) {
      fields.engineError = "timeout";
      throw httpsErrorOf(new EngineError("timeout", "the engine did not answer in time"));
    }
    fields.engineError = "exception";
    throw new HttpsError("internal", "the engine failed");
  }
  setEngineInfo(out.logInfo);

  // 7. Output check.
  const checked = checkOutput(out);
  if (typeof checked === "string") {
    fields.outputError = checked;
    throw new HttpsError("internal", "the engine answered something unusable");
  }
  fields.engineVersion = checked.version;

  // 8. Result (engineVersion = the engine / model that actually answered — contract 7.2.13).
  const result: RecognizeMathResult = {
    latex: checked.latex,
    engine: engine.name,
    engineVersion: checked.version,
    ms: deps.now() - t0,
  };
  if (checked.confidence !== undefined) result.confidence = checked.confidence;
  if (checked.alternatives !== undefined) result.alternatives = checked.alternatives;
  return result;
}

/** 6.8.2 step 7: latex a non-empty string ≤ LIMITS.latexChars; version a non-empty string;
 *  confidence kept only when a number in [0, 1]; alternatives strings, empty ones dropped, then
 *  ≤ LIMITS.alternatives, each ≤ LIMITS.latexChars. The checked output, or why it is unusable. */
export function checkOutput(out: EngineOutput): EngineOutput | string {
  const raw = out as unknown as Record<string, unknown>;
  const latex = raw.latex;
  if (typeof latex !== "string" || latex.length === 0) return "latex is not a non-empty string";
  if (latex.length > LIMITS.latexChars) return "latex is too long";
  const version = raw.version;
  if (typeof version !== "string" || version.length === 0) return "version is not a non-empty string";
  const checked: EngineOutput = { latex, version };
  const confidence = raw.confidence;
  if (typeof confidence === "number" && Number.isFinite(confidence) && confidence >= 0 && confidence <= 1) {
    checked.confidence = confidence;
  }
  const alternatives = raw.alternatives;
  if (alternatives !== undefined) {
    if (!Array.isArray(alternatives)) return "alternatives is not an array";
    const kept: string[] = [];
    for (const a of alternatives) {
      if (typeof a !== "string") return "an alternative is not a string";
      if (a.length > LIMITS.latexChars) return "an alternative is too long";
      if (a.length > 0) kept.push(a);
    }
    if (kept.length > LIMITS.alternatives) return "too many alternatives";
    checked.alternatives = kept;
  }
  if (out.logInfo !== undefined) checked.logInfo = out.logInfo;
  return checked;
}

const handler = createRecognizeMathHandler({
  ownerUids: () => parseOwnerUids(OWNER_UIDS.value()),
  engines: registryFromParams(),
  quota: quotaStoreFor(
    () => QUOTA_STORE.value(),
    () => getFirestore(getApps()[0] ?? initializeApp()),
  ),
  dailyCap: () => DAILY_CAP.value(),
  now: () => Date.now(),
  engineSignal: (ms) => AbortSignal.timeout(ms),
  log: functionsLogger,
});

export const recognizeMath: CallableFunction<unknown, Promise<RecognizeMathResult>> = onCall(
  {
    region: "asia-northeast3",
    maxInstances: 2,
    timeoutSeconds: 30,
    memory: "256MiB",
    enforceAppCheck: false,
    secrets: [MATH_API_KEY],
  },
  (request) => handler({ auth: request.auth ?? null, data: request.data }),
);
