# functions — owned by SYNC: the server function `recognizeMath`

Node 22 + TypeScript, not a Dart workspace member. Plan: [docs/plans/m5-7/07-sync.md](../docs/plans/m5-7/07-sync.md) 3.2, 3.4, 4.5, 6.8; contract: [00-overview](../docs/plans/m5-7/00-overview.md) 7.2.13 (callable format), 7.4.7 (rules), 7.6 (fake engine).

Status: S2-14. The callable checks sign-in, the owner list (`src/access.ts`) and every input limit of 07-sync 6.8.3 (`src/protocol.ts`), resolves the engine through the registry (`src/engines/registry.ts` — the only reader of `src/params.ts` besides the onCall wiring), takes one count of the daily cap right before the engine (`src/quota.ts` — per uid and Seoul day; `DAILY_CAP` ≤ 0 means no cap), calls the engine under a 25 s deadline signal, checks its output and writes one structured log line per call with sizes only (`src/log.ts` — never strokes, PNG or LaTeX). The deployed wiring counts in Firestore (`FirestoreQuotaStore`: collection `fnQuota`, document `<uid>_<yyyymmdd>` = `{count, uid, day, expireAt, updatedAt}`, one Admin SDK transaction per call; turn on a TTL policy on `expireAt` when deploying) unless `QUOTA_STORE=memory` (the emulator demo); `QUOTA_STORE` is read on the first call, and an unknown value makes every call `unavailable`. The emulator tests E1–E10 (`test-emulator/`) call the function over HTTP. Engines: the deterministic fake (demo project only), Mathpix (`src/engines/mathpix.ts` — built-in fetch, strokes or image, `MATHPIX_APP_ID` + `MATH_API_KEY`) and Claude (`src/engines/claude.ts` — `@anthropic-ai/sdk`, image only, `CLAUDE_MODEL` + `MATH_API_KEY`, structured JSON output, the server-side refusal fallback; `engineVersion` is the model that answered). The adapters take everything through their constructors and are tested on injected fakes only; real calls wait for the accounts (U6).

## Commands (cwd `functions/`)

| Command | What it does |
|---|---|
| `npm ci` | Installs the exact versions of `package-lock.json`. |
| `npm run build` | `tsc --strict` into `lib/` (git-ignored). |
| `npm test` | Build, then the unit tests (`node --test` on `lib/test/**` and `lib/tool/test/**`). |
| `npm run test:emulator` | Build, then `scripts/emulator_suite.sh`: the functions and auth emulators (`demo-noteapp`, `--config ../app/firebase.json`) around `lib/test-emulator/**/*.emulator.test.js`, under INFRA's heavy test lock (`dart run tool/ws.dart with-heavy-lock`; not in CI). `-- --with-dart` also runs LIBRARY's Dart `emulator` tests in the same run. |
| `npm run test:rules` | Build, then `scripts/rules_suite.sh`: SYNC's security rules (`packages/sync_engine/firebase/*.rules`, copied with `test-emulator/firebase.rules-test.json` into a temporary directory — firebase-tools refuses rules outside the config's directory) in the Auth + Firestore + Storage emulators, checked by `lib/test-emulator/rules.emulator.test.js` (R1–R11) with Auth emulator ID tokens over REST. Java and the emulator jars (downloaded on first use); manual, under the heavy test lock, not in CI (07-sync 6.10 L4, Q6). `npm run test:emulator` skips that file (no Firestore / Storage emulator there). |
| `npm run eval:math -- [flags]` | The engine comparison tool (07-sync 6.9, `tool/math_eval.ts`): every `*.json` fixture under `--fixtures` (default `tool/fixtures/math`, format in its README) × each of `--engines fake,mathpix,claude` (default `fake`) → `eval-out/<date>/results.jsonl` and `summary.md` (`--out`). Keys only from `MATHPIX_APP_ID` / `MATHPIX_APP_KEY` / `ANTHROPIC_API_KEY`; Claude also needs `--claude-model` (no default). An engine without its key or model is listed as not configured. With a paid engine the tool prints the largest cost estimate and calls nothing unless `--confirm-cost` is given, and never more than `--limit` (default 60) paid calls; two calls at a time, each under the server's 25 s signal. `--claude-price <in>,<out>` (USD per million tokens) replaces the built-in price. |

A test run counts only when it ran at least one test: `node --test` exits 0 on a glob that matches nothing, so check the `# tests N` line (piped output is TAP).

## Parameters

The emulator reads the committed demo values of `.env.demo-noteapp` (never secrets). `.env.local`, `.secret.local`, `lib/`, `node_modules/` and `eval-out/` are not committed.

| Name | Kind | Default | Demo |
|---|---|---|---|
| `MATH_API_KEY` | secret | — | none (empty value and a warning; the fake engine uses no key) |
| `OWNER_UIDS` | string, comma separated | `''` (nobody) | `owner-uid` |
| `MATH_ENGINE` | string | `none` | `fake` |
| `ALLOW_FAKE_ENGINE` | boolean | `false` | `true` |
| `MATHPIX_APP_ID` | string | `''` (Mathpix not configured) | — |
| `CLAUDE_MODEL` | string | `''` (Claude not configured — contract v2.3 C23-02; no model name as a default) | — |
| `DAILY_CAP` | int (calls per uid and Seoul day; ≤ 0 → no cap) | `200` | `1000` |
| `QUOTA_STORE` | string: `firestore` or `memory` | `firestore` | `memory` |

## Fake engine (contract 7.6)

`engine: "fake"`, `engineVersion: "1"`. Strokes (S strokes, P points) → `\frac{S}{P}`, alternatives `["S/P"]`; PNG only (B decoded bytes) → `\sqrt{B}`, alternatives `[]`; confidence 1. First point of the first stroke (-1,-1) → `unavailable`, (-2,-2) → `internal`, (-3,-3) → `unavailable`.

## Emulator conventions (07-sync 6.8.11)

Function URL `http://127.0.0.1:5001/demo-noteapp/asia-northeast3/recognizeMath`. Users `owner-uid` / `stranger-uid` (`<uid>@example.test`, password `test-password`), created through the Auth emulator admin REST with `Authorization: Bearer owner` and `localId`; if a user already exists, sign in.

`test-emulator/recognize_math.emulator.test.ts` (E1–E10 of 07-sync 6.8.11) uses exactly these: no token → 401 `UNAUTHENTICATED`, `stranger-uid` → 403 `PERMISSION_DENIED`, bad requests → 400 `INVALID_ARGUMENT`, the fake engine values above with `engine` `fake` and `auto`, `gemini` → 503 `UNAVAILABLE`, the (-1,-1) / (-2,-2) failures → 503 / 500, a 2,097,153-character `pngBase64` → 400. The Functions emulator also writes the empty-default parameters into the git-ignored `.env.local` on its first run; that is harmless.

## Deploy checklist (mini round L5, 07-sync 6.10 — contract 7.4.7 order)

After the user has made the Firebase project and signed in once in the app (the uid is needed). Production never runs the fake engine (`ALLOW_FAKE_ENGINE=false`, D-S7), so the checks below do not use it.

1. **Secret**: `firebase functions:secrets:set MATH_API_KEY` (a placeholder value while no engine is chosen — the first deploy binds the secret).
2. **Production values file**: `functions/.env.<projectId>` with `OWNER_UIDS=<uid>`, `MATH_ENGINE=none`, `DAILY_CAP=200`, `QUOTA_STORE=firestore`, `ALLOW_FAKE_ENGINE=false`; commit it (a uid is not a secret; `.env.local` is never deployed).
3. **Deploy**: `firebase deploy --only functions --config app/firebase.json` (RQ-6: the `ignore` list there keeps `node_modules`, the sources, tests, scripts, `lib/test*`, `lib/tool` and `eval-out` out of the upload), then a TTL policy on the `fnQuota` collection group's `expireAt` field.
4. **Check** with `MATH_ENGINE=none`: the owner's call → 503 `UNAVAILABLE` (sign-in and owner checks passed), another Google account → 403 `PERMISSION_DENIED`, no sign-in → 401 `UNAUTHENTICATED`.
5. **After an engine is chosen** (U6): set `MATH_ENGINE` (and `MATHPIX_APP_ID` for Mathpix, or `CLAUDE_MODEL` for Claude — no default model name), the real `MATH_API_KEY`, deploy again → one real recognition.
