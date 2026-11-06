// lib/src/testing_web_factory.dart — (m5-7/06-pdf 4.3.2, 6.18) the body of
// registerMediaWebPlugins: testing_web_browser.dart in the browser (registers the
// just_audio_web and record_web plugins), testing_web_stub.dart elsewhere (does nothing).
// testing.dart only.
export 'testing_web_stub.dart'
    if (dart.library.js_interop) 'testing_web_browser.dart';
