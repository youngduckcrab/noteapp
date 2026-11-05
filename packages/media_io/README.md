# media_io — owned by PDF: recording, playback and image import services. Plan: [docs/plans/m5-7/06-pdf.md](../../docs/plans/m5-7/06-pdf.md)

Skeleton created by INFRA in the 2차 foundation step R2-B1 (contract [00-overview 7.6.2](../../docs/plans/m5-7/00-overview.md)); PDF fills it from R2-B4 on.

- **Entry points**: `package:media_io/media_io.dart` (web-safe barrel, contract 7.2.12) and `package:media_io/testing.dart` (tests only, contract 7.6).
- **Service package** (contract 7.1 rules 4–5): depends on `note_core` only; feature packages never import it and it imports none of them. The app shell wires it (`mediaIoOverrides()`).
- **Web / native boundary** (contract 7.4.1): `package:flutter_foreground_task/` and `package:path_provider/` only in `*_native.dart`, `dart:js_interop` / `package:web/` only in `*_browser.dart`, platform files only through conditional imports with a stub. No `dart:io` `Platform` anywhere — use `kIsWeb` + `defaultTargetPlatform`.
- **Tests**: `ws test --package media_io`; Chrome fake microphone tests are tagged `media` and run with `ws test --package media_io --platform chrome --run-skipped -t media` (`ws` uses `tool/chrome-fakemedia` and the heavy test lock by itself — contract 7.4.6).
