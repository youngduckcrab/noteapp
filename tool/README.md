# tool/ — workspace tool (INFRA)

`dart run tool/ws.dart <command>` from the repository root. `--help` lists every command and option; the plans are [docs/plans/01-infra.md](../docs/plans/01-infra.md) 4.2 and [docs/plans/m5-7/01-infra.md](../docs/plans/m5-7/01-infra.md) 4.2 / 6.13.

| Command | What it does |
|---|---|
| `list` | Members in topological order. |
| `check [--strict]` | Workspace rules R1–R16 (`tool/workspace_rules.yaml`); R11 runs `dart format`, R14 resolves the entry points (about a minute). |
| `analyze` | `flutter analyze --fatal-infos` at the root. |
| `test` | `flutter test` per member (`--package`, `--platform vm\|chrome`, `-t`, `--run-skipped`, `--affected-since <ref> [--all-if-no-base]`, `--member-timeout`). |
| `with-heavy-lock [--timeout <min>] -- <command>` | Runs a command under the heavy test lock with `NOTEAPP_HEAVY_LOCK_HELD=1`. |
| `affected`, `channel-id`, `build-info`, `finalize-web`, `web-assets`, `hosting-config` | CI helpers (1차). |

## Heavy test lock (contract 7.4.6 v2.1)

`media`- and `emulator`-tagged runs and Chrome runs without `--package` take one container-wide lock, so only one of them runs at a time whichever agent starts it:

- file `/tmp/noteapp-heavy-tests.lock` (`NOTEAPP_HEAVY_LOCK` moves it), one line `<pid> <start ISO-8601 UTC> <command>`; a dead pid is reclaimed, an unreadable file after one minute. A log of takes / releases is next to it (`noteapp-heavy-tests.log`).
- `ws test` holds it from before the first member to after the last one, retries after a time-out included; it waits up to `--heavy-lock-timeout` minutes (default 20, exit code 4), and `--no-heavy-lock` skips it.
- the holder passes `NOTEAPP_HEAVY_LOCK_HELD=1` to its children; a `ws test` / `ws with-heavy-lock` started with it does not take the lock again.
- `ws test -t media --platform chrome` starts Chrome through `tool/chrome-fakemedia` (fake microphone and camera) with the Chrome it found as `NOTEAPP_REAL_CHROME` — do not set `CHROME_EXECUTABLE` to the wrapper yourself.

Emulator tests (after `npm ci --prefix functions`; contract 7.7.1 step 8):

```bash
dart run tool/ws.dart with-heavy-lock -- \
  npx --prefix functions firebase emulators:exec --config app/firebase.json \
    --only functions,auth --project demo-noteapp \
    "dart run tool/ws.dart test --run-skipped -t emulator"
```

Media tests: `dart run tool/ws.dart test --package media_io --platform chrome --run-skipped -t media`.

## Tests

`dart test tool/test` (`-x process` skips the ones that start `dart run tool/ws.dart` as a real process).
