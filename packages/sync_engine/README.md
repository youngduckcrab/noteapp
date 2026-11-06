# sync_engine — owned by SYNC: account and sync engine core, Firebase adapter skeleton. Plan: [docs/plans/07-sync.md](../../docs/plans/07-sync.md)

2nd round (M5–M7): [docs/plans/m5-7/07-sync.md](../../docs/plans/m5-7/07-sync.md) — new kinds (page objects, handwriting results, recording titles), records of unknown kinds held until an app update (S-13), and the preparation for the live connection mini round (6.10).

## Live connection checklist (실연결 체크리스트, 07-sync 6.10)

What SYNC needs from the Firebase project once the user has made it (contract 3.3). Deployment settings are INFRA's; the files are here.

| # | Item | What to set | Source in this repository |
|---|---|---|---|
| L1 | Firestore | Native mode, location `asia-northeast3` | — |
| L1 | Firestore rules | Deploy `firebase/firestore.rules` (own `users/{uid}` tree only; chunk field checks, `su` = request time, a rewrite of the same id changes `su` only) | `firebase/firestore.rules` |
| L1 | Firestore indexes | Deploy `firebase/firestore.indexes.json`: composite `changes (scope ASC, su ASC)` for the per-scope fetch; single-field indexes off for the chunk payload fields | `firebase/firestore.indexes.json` |
| L1 | Storage | The default bucket; deploy `firebase/storage.rules` (`users/{uid}/assets/{sha256}`, custom metadata `sha256` = the name, ≤ 300 MiB, no overwrite) | `firebase/storage.rules` |
| L1 | TTL | A TTL policy on `fnQuota.expireAt` (the server function's daily counts — `functions/README.md`) | `functions/src/quota.ts` |
| L3 | Auth | Google provider on; the Hosting domain (and `localhost` for development) in the authorized domains | `lib/src/firebase/firebase_auth_backend.dart` |
| L2 | App wiring (INFRA) | `FirebaseSyncBindings(app)` → `authBackendProvider` / `syncBackendFactoryProvider` overrides, `connectivitySignalProvider` | `lib/firebase.dart`, `lib/src/providers.dart` |
| L6 | ID token for the server function (INFRA) | `RecognitionConfig.idTokenProvider = () => ref.read(authServiceProvider).idToken()` — null when signed out, never throws (CP-S7) | `lib/src/auth/auth_service.dart` |

Before the first deploy, check the rules in the emulators: `cd functions && npm run test:rules` (Auth + Firestore + Storage emulators, Java, under the heavy test lock — manual, not in CI). After the deploy, check what the emulator cannot: an upload over an existing asset is refused (the Storage emulator judges every upload as `create`) and an asset over 300 MiB is refused.

Integration tests with the real CORE store: `dart run tool/ws.dart test --package sync_engine --run-skipped -t integration` (integration stage; `test/integration/`).
