# media_io — owned by PDF: recording, playback and image import services. Plan: [docs/plans/m5-7/06-pdf.md](../../docs/plans/m5-7/06-pdf.md)

Skeleton created by INFRA in the 2차 foundation step R2-B1 (contract [00-overview 7.6.2](../../docs/plans/m5-7/00-overview.md)); PDF filled the contract surface in R2-B4 (06-pdf 8.1 T30) and the services in the concurrent stage (06-pdf 8.2 T31a–T41).

## Entry points

- `package:media_io/media_io.dart` — web-safe barrel, exactly the seven names of contract 7.2.12:
  - `initializeMediaIo(config)` — once at start-up (the web MIME table, the Android foreground-service set-up, the left-over recording file clean-up); the first config stays.
  - `MediaIoConfig` — bit rate, web chunk length and the other settings of a build (tuning values in `lib/src/tuning.dart`).
  - `mediaIoOverrides()` — the two real overrides for the app's root scope: CORE's `audioRecorderServiceProvider` (the recorder service — web: our own `MediaRecorder` engine, Web Locks, Wake Lock, page events; native: `record`, the audio session, the Android foreground service) and `audioPlaybackServiceProvider` (just_audio). Without them CORE's 'not supported' ports stay.
  - `supportedImageSources()` / `importImageForNote(context, source)` — the image import (gallery, camera, files; on the web the clipboard when the browser has it): started synchronously from the tap, normalized (EXIF orientation, ≤ 2048 px long side, ≤ 8 MiB — M-3) and stored as an image asset.
  - `RecordingPanel` — the panel EDITOR shows under the editor (≤ 40 % of the height): record / pause / stop, the status line, the recording list with rename and delete, playback with speed and ±10 s, the line for drafts that could not be recovered and the web 'download as a file' fallback.
  - `mediaDevOverlayLinesProvider` — the developer overlay lines (recorder state, encoder, last recording and its duration source, stuck drafts, locks, buffers).
- `package:media_io/testing.dart` — tests only (contract 7.6): `registerMediaWebPlugins` (Chrome tests call it — the test binding runs no plugin registrant) and the VM-only platform fakes `FakeRecordPlatform`, `FakeJustAudioPlatform`, `FakeImagePickerPlatform`, `installFakeMediaPlatforms` → `MediaFakePlatforms` (a temporary directory; `dispose` restores the previous platform instances and removes it). They are plain `extends` of the platform classes (no `MockPlatformInterfaceMixin`) and assert `!kIsWeb`; on them the real `mediaIoOverrides()` services record, stop, play and import on the VM. In Chrome and in other areas' tests use CORE's `FakeAudioRecorder` / `FakeAudioPlayback`.

## Rules

- **Service package** (contract 7.1 rules 4–5): depends on `note_core` only; feature packages never import it and it imports none of them. The app shell wires it (`mediaIoOverrides()`, INFRA's `MediaModule`).
- **Nothing is lost** (contract 7.3.2 M-1, M-4; 06-pdf 6.6, 6.10): the asset is written before the `Recording` row and the draft is discarded last; a closed tab's draft is recovered without asking (at most twice — `media.recoverAttempts`), never while another tab of the same origin still records it (Web Locks + the 10 s recent-update window); stop and recovery hold at most two full-size copies of a recording at once (`BufferLedger`).
- **Web / native boundary** (contract 7.4.1, 06-pdf 3.5): `dart:io`, `package:flutter_foreground_task/`, `package:path_provider/`, `package:record/` and `package:audio_session/` only in `*_native.dart`; `dart:js_interop`, `package:web/` and the web plugins only in `*_browser.dart`; platform files only through conditional exports (`*_factory.dart`) with a stub. No `dart:io` `Platform` anywhere — use `kIsWeb` + `defaultTargetPlatform`. `test/unit/no_platform_imports_test.dart` checks these rules.

## Tests

Tags are declared in `dart_test.yaml` (`media`, `integration`, `perf` — all skipped by default).

| Command (from the workspace root) | What runs |
|---|---|
| `dart run tool/ws.dart test --package media_io` | VM: the pure parts (clock, draft writer, WebM timeline, MP4 duration, MIME table, image header and normalizer), the recorder service on CORE's fake store with a fake engine and fake time, the native engine / audio session / foreground service on the platform fakes, playback, image import, the panel widgets (iPad Pro 13" portrait and landscape), the developer overlay lines, `testing.dart` |
| `dart run tool/ws.dart test --package media_io --platform chrome` | Chrome (`test/web/`): the web recorder engine without a microphone (MIME, visibility, `mute` order, Wake Lock, watchdog, real `navigator.locks`), the canvas image codec and the clipboard, Blob playback, file download, the plugin registrar. `ws` first runs `tool/prepare_web_test.dart`, which calls CORE's `tool/prepare_web_test.dart --out test/web` (drift worker + sqlite3.wasm for `openWebTestNoteStore`; both files are git-ignored) |
| `dart run tool/ws.dart test --package media_io --platform chrome --run-skipped -t media` | Chrome with a fake microphone (`test/web/media/`): V8 record → pause → stop → play (file timeline vs clock), V16 recovery after a closed tab, the hidden-tab pause, and the 3-hour (86 MB) draft's stop and recovery (`big_recording_perf_media_test` — at most two full-size buffers; time and heap printed). Each on CORE's real web store (skipped at run time until CORE T31) and on CORE's fake store. `ws` uses `tool/chrome-fakemedia` and the heavy test lock by itself (contract 7.4.6) — do not set `CHROME_EXECUTABLE` to the wrapper |
| `dart run tool/ws.dart test --package media_io --run-skipped -t integration` | Integration stage (4-d): the recorder on CORE's real file store (`integration/media_real_core_test` — skipped at run time until CORE T30/T31; the same scenarios run on the fake store in every VM run) |
| `dart run tool/ws.dart test --package media_io --run-skipped -t perf` | Performance on the VM (wall clock, by hand): `offsetNowMs()` 100 000 calls ≤ 200 ms (≈ 1 µs each), a 4000 × 3000 JPEG normalized to 2048 × 1536 in an isolate ≤ 2 s (`perf/media_perf_test`) |
| `dart run tool/ws.dart test --package media_io --platform chrome --run-skipped -t perf` | Performance in Chrome: the canvas normalizer on the same JPEG ≤ 1 s, the draft chunk append latency (median ≤ 30 ms on the real web store — skipped until CORE T31; printed on the fake store) (`web/media_perf_browser_test`) |

The perf and `media` tests print their values (time, buffers, heap) into the `ws test` log; to run one file alone use `flutter test --platform chrome -r expanded` from `packages/media_io` after `dart run tool/prepare_web_test.dart` (for `media` files: `dart run ../../tool/ws.dart with-heavy-lock -- env CHROME_EXECUTABLE=<work tree>/tool/chrome-fakemedia NOTEAPP_REAL_CHROME=/usr/local/bin/chrome-nosandbox flutter test --platform chrome --run-skipped -t media -r expanded test/web/media/`).

Conventions: no wall-clock assertions outside the `perf` and `media` tags (fake time — `fake_async`, `FakeStopwatch`); test code uses no network; Chrome tests call `registerMediaWebPlugins()` first.

## Third-party notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): the pub packages and their licences (the app's licence screen collects their `LICENSE` files), and the parts written anew after reading `record_web` (the web MIME table and the WebM duration patch — no code copied).
