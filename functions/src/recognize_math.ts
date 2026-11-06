// The callable recognizeMath (contract 00-overview 7.2.13, docs/plans/m5-7/07-sync.md 4.5, 6.8.2).
// The body is createRecognizeMathHandler (no firebase-functions request types — unit-testable);
// the onCall wiring at the bottom is the only part the emulator needs.
//
// R2-B7b skeleton: sign-in, owner list, request shape and the engine call with its deadline
// signal (steps 1–4 and 6 of 6.8.2). The daily cap (step 5), the output check (step 7) and the
// log (step 8) come with S2-10b, together with HandlerDeps.quota / dailyCap / log.

import { HttpsError, onCall, type CallableFunction } from "firebase-functions/https";
import { isOwner, parseOwnerUids } from "./access.js";
import { EngineError, type EngineInput, type EngineOutput, type EngineRegistry } from "./engines/engine.js";
import { registryFromParams } from "./engines/registry.js";
import { httpsErrorOf } from "./errors.js";
import { MATH_API_KEY, OWNER_UIDS } from "./params.js";
import { parseRequest, type RecognizeMathResult } from "./protocol.js";

export interface HandlerDeps {
  /** OWNER_UIDS, comma separated, trimmed; empty → nobody. */
  ownerUids(): readonly string[];
  engines: EngineRegistry;
  /** Epoch ms. */
  now(): number;
  /** (v2.1, SYNC-M7) The engine-call deadline signal. Production: AbortSignal.timeout(ms).
   *  Tests pass a function returning their own AbortController's signal and abort() it —
   *  AbortSignal.timeout does not follow node:test mock timers. */
  engineSignal(ms: number): AbortSignal;
}

/** The engine call is cut at 25 s so the function's own 30 s limit is not reached. */
export const ENGINE_TIMEOUT_MS = 25_000;

/** The callable body without firebase-functions types (unit-testable). Throws HttpsError. */
export function createRecognizeMathHandler(
  deps: HandlerDeps,
): (req: { auth?: { uid: string } | null; data: unknown }) => Promise<RecognizeMathResult> {
  return async (req) => {
    const t0 = deps.now();
    if (req.auth == null) throw new HttpsError("unauthenticated", "sign-in required");
    if (!isOwner(req.auth.uid, deps.ownerUids())) {
      throw new HttpsError("permission-denied", "this account may not use recognizeMath");
    }
    const request = parseRequest(req.data);
    if ("error" in request) throw new HttpsError("invalid-argument", request.error);

    const engine = deps.engines.resolve(request.engine);
    if (engine instanceof EngineError) throw httpsErrorOf(engine);
    const input: EngineInput = { locale: request.locale };
    if (request.strokes !== undefined && engine.accepts.strokes) input.strokes = request.strokes;
    if (request.pngBase64 !== undefined && engine.accepts.png) {
      input.png = Buffer.from(request.pngBase64, "base64");
    }
    if (input.strokes === undefined && input.png === undefined) {
      throw new HttpsError("invalid-argument", `engine ${engine.name} cannot take this input`);
    }

    const signal = deps.engineSignal(ENGINE_TIMEOUT_MS);
    let out: EngineOutput;
    try {
      out = await engine.recognize(input, signal);
    } catch (e) {
      if (e instanceof EngineError) throw httpsErrorOf(e);
      if (signal.aborted) throw httpsErrorOf(new EngineError("timeout", "the engine did not answer in time"));
      throw new HttpsError("internal", "the engine failed");
    }

    const result: RecognizeMathResult = {
      latex: out.latex,
      engine: engine.name,
      engineVersion: out.version,
      ms: deps.now() - t0,
    };
    if (out.confidence !== undefined) result.confidence = out.confidence;
    if (out.alternatives !== undefined) result.alternatives = out.alternatives;
    return result;
  };
}

const handler = createRecognizeMathHandler({
  ownerUids: () => parseOwnerUids(OWNER_UIDS.value()),
  engines: registryFromParams(),
  now: () => Date.now(),
  engineSignal: (ms) => AbortSignal.timeout(ms),
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
