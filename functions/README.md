# functions — owned by SYNC: the server function `recognizeMath`

Node 22 + TypeScript, not a Dart workspace member. Plan: [docs/plans/m5-7/07-sync.md](../docs/plans/m5-7/07-sync.md) 3.2, 3.4, 4.5, 6.8; contract: [00-overview](../docs/plans/m5-7/00-overview.md) 7.2.13 (callable format), 7.4.7 (rules), 7.6 (fake engine).

Status: R2-B7b skeleton. The callable checks sign-in, the owner list and the request shape, then calls the deterministic fake engine. The daily cap, full input limits, real engines and emulator tests come in S2-10a to S2-13.

## Commands (cwd `functions/`)

| Command | What it does |
|---|---|
| `npm ci` | Installs the exact versions of `package-lock.json`. |
| `npm run build` | `tsc --strict` into `lib/` (git-ignored). |
| `npm test` | Build, then the unit tests (`node --test` on `lib/test/**` and `lib/tool/test/**`). |
| `npm run test:emulator` | Build, then `scripts/emulator_suite.sh`: the functions and auth emulators (`demo-noteapp`, `--config ../app/firebase.json`) around `lib/test-emulator/**/*.emulator.test.js`, under INFRA's heavy test lock (`dart run tool/ws.dart with-heavy-lock`; not in CI). `-- --with-dart` also runs LIBRARY's Dart `emulator` tests in the same run. |

A test run counts only when it ran at least one test: `node --test` exits 0 on a glob that matches nothing, so check the `# tests N` line (piped output is TAP).

## Parameters

The emulator reads the committed demo values of `.env.demo-noteapp` (never secrets). `.env.local`, `.secret.local`, `lib/`, `node_modules/` and `eval-out/` are not committed.

| Name | Kind | Default | Demo |
|---|---|---|---|
| `MATH_API_KEY` | secret | — | none (empty value and a warning; the fake engine uses no key) |
| `OWNER_UIDS` | string, comma separated | `''` (nobody) | `owner-uid` |
| `MATH_ENGINE` | string | `none` | `fake` |
| `ALLOW_FAKE_ENGINE` | boolean | `false` | `true` |
| `QUOTA_STORE` / `DAILY_CAP` | string / int (S2-10b) | `firestore` / `200` | `memory` / `1000` |

## Fake engine (contract 7.6)

`engine: "fake"`, `engineVersion: "1"`. Strokes (S strokes, P points) → `\frac{S}{P}`, alternatives `["S/P"]`; PNG only (B decoded bytes) → `\sqrt{B}`, alternatives `[]`; confidence 1. First point of the first stroke (-1,-1) → `unavailable`, (-2,-2) → `internal`, (-3,-3) → `unavailable`.

## Emulator conventions (07-sync 6.8.11)

Function URL `http://127.0.0.1:5001/demo-noteapp/asia-northeast3/recognizeMath`. Users `owner-uid` / `stranger-uid` (`<uid>@example.test`, password `test-password`), created through the Auth emulator admin REST with `Authorization: Bearer owner` and `localId`; if a user already exists, sign in.
