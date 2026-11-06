// lib/src/platform/page_events_factory.dart (conditional export, m5-7/06-pdf 6.8.3, 6.8.4, 6.18) —
// declares:
//
//   /// Web: document visibility, pagehide, navigator.wakeLock (page_events_browser.dart).
//   /// Else: always visible, no wake lock (page_events_stub.dart).
//   PageEvents createPlatformPageEvents();
export 'page_events_stub.dart'
    if (dart.library.js_interop) 'page_events_browser.dart';
