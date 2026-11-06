// Function parameters and secrets (docs/plans/m5-7/07-sync.md 6.8.9). Read only by
// src/engines/registry.ts and the onCall wiring in src/recognize_math.ts.
//
// Demo values for the emulator are in the committed functions/.env.demo-noteapp. Keys are never
// in the repository or the app (F-1): MATH_API_KEY lives in Secret Manager (`.secret.local` for a
// developer's emulator run, not committed).
//
// DAILY_CAP and QUOTA_STORE come with S2-10b / S2-11. No parameter has a model name or a key as
// its default (contract v2.3, C23-02): CLAUDE_MODEL is set per project in .env.<projectId>.

import { defineBoolean, defineSecret, defineString } from "firebase-functions/params";

/** The key of the engine MATH_ENGINE names (contract 7.2.13 'MATH_API_KEY (+ engine-specific)'). */
export const MATH_API_KEY = defineSecret("MATH_API_KEY");

/** Comma separated uids allowed to call; empty → nobody (closed default). */
export const OWNER_UIDS = defineString("OWNER_UIDS", { default: "" });

/** The engine 'auto' means. 'none' → unavailable. */
export const MATH_ENGINE = defineString("MATH_ENGINE", { default: "none" });

/** The fake engine may answer only where this is true (the demo project). */
export const ALLOW_FAKE_ENGINE = defineBoolean("ALLOW_FAKE_ENGINE", { default: false });

/** Mathpix app id (not secret); its app key is MATH_API_KEY. Empty → Mathpix is notConfigured. */
export const MATHPIX_APP_ID = defineString("MATHPIX_APP_ID", { default: "" });

/** The model the Claude engine asks for. Empty (the default) → Claude is notConfigured (C23-02). */
export const CLAUDE_MODEL = defineString("CLAUDE_MODEL", { default: "" });
