# media_io — third-party notices

`media_io` (PDF area — recording, playback and image import; plan
[docs/plans/m5-7/06-pdf.md](../../docs/plans/m5-7/06-pdf.md) 7.2 · 7.3) ships no third-party
source code of its own. It depends on the pub packages below; their licence texts come with the
packages, and the app's licence screen shows them (Flutter collects every package's `LICENSE` —
INFRA's about screen). Versions are the workspace's pinned ones (contract 7.5).

## Direct dependencies

| Package | Version | Licence | Used in | Notes |
|---|---|---|---|---|
| `record` | 7.1.2 | BSD-3-Clause (openapi4j authors) | `lib/src/record/recorder_engine_native.dart` | Native recording only (AAC-LC in `.m4a`). Federated: `record_android` 2.2.0, `record_ios` 2.1.1 (BSD-3-Clause, same authors) |
| `just_audio` | 0.10.6 | MIT (Ryan Heise and contributors) | `lib/src/playback/player_port.dart`, `duration_probe.dart` | Playback on every platform |
| `audio_session` | 0.2.4 | MIT (Ryan Heise and contributors) | `lib/src/record/audio_session_native.dart` | iOS / Android audio session for recording |
| `flutter_foreground_task` | 11.0.3 | MIT (Dev-hwang) | `lib/src/record/foreground_service_native.dart` | Android foreground service while recording |
| `image_picker` | 1.2.4 | BSD-3-Clause (The Flutter Authors) | `lib/src/image/image_picker_port.dart` | With `image_picker_for_web` 3.1.1 and `image_picker_ios` 0.8.13+13 (BSD-3-Clause, The Flutter Authors) |
| `path_provider` | 2.1.6 | BSD-3-Clause (The Flutter Authors) | `*_native.dart` | Recording and playback cache files |
| `image` | 4.12.0 | MIT (Brendan Duncan) | `lib/src/image/image_codec_io.dart` | Decode, orient, resize and encode on the VM / native (in an isolate) |
| `record_web` | 2.1.3 | BSD-3-Clause (openapi4j authors) | `testing.dart` web side (`registerMediaWebPlugins`) | Registered for tests only — web recording does not use it (below) |
| `just_audio_web` | 0.4.16 | MIT (Ryan Heise and contributors) | `testing.dart` web side (`registerMediaWebPlugins`); the web player | |
| `record_platform_interface` | 2.1.0 | BSD-3-Clause (openapi4j authors) | `testing.dart` (`FakeRecordPlatform`, VM) | |
| `just_audio_platform_interface` | 4.6.0 | MIT (Ryan Heise and contributors) | `testing.dart` (`FakeJustAudioPlatform`, VM) | |
| `image_picker_platform_interface` | 2.11.2 | BSD-3-Clause (The Flutter Authors) | `testing.dart` (`FakeImagePickerPlatform`, VM) | |
| `flutter_web_plugins` | Flutter SDK | BSD-3-Clause (The Flutter Authors) | `testing.dart` web side | `webPluginRegistrar` |
| `web`, `flutter_riverpod`, `material_ui`, `meta`, `collection`, `note_core` | workspace pins | see each package | | `web` only in `*_browser.dart` |
| dev: `fake_async` | 1.3.3 | BSD-3-Clause (Dart project authors) | `test/` | |

## Written anew, not copied

- **Web recording** (`lib/src/record/recorder_engine_browser.dart`, `web_mime.dart`) drives the
  browser's `MediaRecorder` directly (D13). Its MIME candidate table and its order were written
  for this package after reading how `record_web` picks a type; no `record_web` code is in it.
- **WebM duration** (`lib/src/record/webm_timeline.dart`) walks the file's Clusters and Blocks
  and writes `Segment > Info > Duration` into the head itself (06-pdf 6.8.7). It was written for
  this package after reading `record_web`'s WebM duration fix-up; no code was taken from it.
- **MP4 duration** (`lib/src/record/mp4_duration.dart`) reads `mvhd` / `mehd` / `trun` from the
  ISO base media file format as specified; no third-party code.

Should code from `record_web` (BSD-3-Clause) ever be copied in, its licence text has to be added
here verbatim with the file it went into (06-pdf 7.3).
