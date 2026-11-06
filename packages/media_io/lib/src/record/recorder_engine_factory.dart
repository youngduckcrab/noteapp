// lib/src/record/recorder_engine_factory.dart (conditional export, m5-7/06-pdf 6.6.2, 6.18) —
// declares:
//
//   /// The platform's recorder engine: native / VM = record + file (recorder_engine_native.dart,
//   /// T33), web = own MediaRecorder (recorder_engine_browser.dart, T32b — [config] picks the MIME
//   /// with allowNonAacOnWeb), other = none.
//   RecorderEngine createPlatformRecorderEngine(MediaIoConfig config);
//   /// initializeMediaIo's platform step (Android FlutterForegroundTask.init — 6.9.4; web: the
//   /// MIME table — 6.8.1). Sync.
//   void preparePlatformRecording(MediaIoConfig config);
//   /// The playback session set-up before the first load (native: the speech session — 6.11.1);
//   /// null where there is none.
//   Future<void> Function()? platformPlaybackSessionSetup();
export 'recorder_engine_stub.dart'
    if (dart.library.js_interop) 'recorder_engine_browser.dart'
    if (dart.library.io) 'recorder_engine_native.dart';
