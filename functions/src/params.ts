// Function parameters and secrets (docs/plans/m5-7/07-sync.md 6.8.9). Read only by
// src/engines/registry.ts and the onCall wiring in src/recognize_math.ts.
//
// Demo values for the emulator are in the committed functions/.env.demo-noteapp. Keys are never
// in the repository or the app (F-1): MATH_API_KEY lives in Secret Manager (`.secret.local` for a
// developer's emulator run, not committed).
//
// R2-B7b skeleton: the parameters the login, owner and fake-engine path reads. DAILY_CAP and
// QUOTA_STORE (S2-10b / S2-11) and the engine settings (S2-10a / S2-12) are added later.

import { defineBoolean, defineSecret, defineString } from "firebase-functions/params";

/** The key of the engine MATH_ENGINE names (contract 7.2.13 'MATH_API_KEY (+ engine-specific)'). */
export const MATH_API_KEY = defineSecret("MATH_API_KEY");

/** Comma separated uids allowed to call; empty → nobody (closed default). */
export const OWNER_UIDS = defineString("OWNER_UIDS", { default: "" });

/** The engine 'auto' means. 'none' → unavailable. */
export const MATH_ENGINE = defineString("MATH_ENGINE", { default: "none" });

/** The fake engine may answer only where this is true (the demo project). */
export const ALLOW_FAKE_ENGINE = defineBoolean("ALLOW_FAKE_ENGINE", { default: false });
