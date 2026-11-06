// lib/src/platform/web_locks_factory.dart (conditional export, m5-7/06-pdf 6.10.2, 6.18) —
// declares:
//
//   /// Web: navigator.locks (web_locks_browser.dart — unavailable when the browser has none).
//   /// Else: no Web Locks (web_locks_stub.dart — the 'recently updated' time rule only).
//   WebLocks createPlatformWebLocks();
export 'web_locks_stub.dart'
    if (dart.library.js_interop) 'web_locks_browser.dart';
