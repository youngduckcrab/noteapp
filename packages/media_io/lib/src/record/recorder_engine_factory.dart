// lib/src/record/recorder_engine_factory.dart (conditional export, m5-7/06-pdf 6.6.2, 6.18) —
// declares:
//
//   /// The platform's recorder engine: native / VM = record + file (recorder_engine_native.dart,
//   /// T33), web = own MediaRecorder (recorder_engine_browser.dart, PDF T32b), other = none.
//   RecorderEngine createPlatformRecorderEngine();
//   /// initializeMediaIo's platform step (Android FlutterForegroundTask.init — 6.9.4). Sync.
//   void preparePlatformRecording(MediaIoConfig config);
//   /// The playback session set-up before the first load (native: the speech session — 6.11.1);
//   /// null where there is none.
//   Future<void> Function()? platformPlaybackSessionSetup();
//
// PDF T32b adds the `if (dart.library.js_interop)` line for the browser body.
export 'recorder_engine_stub.dart'
    if (dart.library.io) 'recorder_engine_native.dart';
