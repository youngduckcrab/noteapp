// lib/src/playback/audio_source_factory.dart (conditional export, m5-7/06-pdf 6.11.3, 6.18) —
// declares:
//
//   /// Web: Blob → object URL (preload: false). Native / VM: the play cache file. Other: none.
//   AudioSourceProvider createPlatformAudioSources();
//   /// (P-B, 6.6.5 ③) Web: Blob([bytes], {type: mimeType}) for the player hand-off; else null.
//   Object? createHandoffBlob(Uint8List bytes, String mimeType);
export 'audio_source_stub.dart'
    if (dart.library.js_interop) 'audio_source_browser.dart'
    if (dart.library.io) 'audio_source_native.dart';
