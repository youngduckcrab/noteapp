// lib/src/platform/page_events.dart — the page events port of the web recorder (m5-7/06-pdf 6.8.3,
// 6.8.4): document visibility, pagehide and the Screen Wake Lock. Internal. Bodies:
// page_events_browser.dart (document.visibilityState, visibilitychange, pagehide,
// navigator.wakeLock — PDF T32b) and page_events_stub.dart (always visible, no wake lock — native
// and the VM: the app life cycle is the native engine's business). Chrome tests drive the browser
// body by redefining document.visibilityState and dispatching visibilitychange (a headless tab
// cannot really be hidden).

abstract interface class PageEvents {
  /// document.visibilityState == 'hidden' now.
  bool get hidden;

  /// Every visibilitychange: the new [hidden] value. Broadcast.
  Stream<bool> get visibilityChanges;

  /// pagehide (tab closed, reloaded, navigated away). Broadcast.
  Stream<void> get pageHides;

  /// navigator.wakeLock exists here.
  bool get wakeLockAvailable;

  /// navigator.wakeLock.request('screen'); `null` when missing or refused (developer overlay
  /// 'wake lock: none' — 6.8.4). Never throws.
  Future<ScreenWakeLock?> requestWakeLock();
}

/// One held screen wake lock (WakeLockSentinel).
abstract interface class ScreenWakeLock {
  /// Released by [release] or by the system.
  bool get released;

  /// The system let it go (the sentinel's release event while this side still held it) — the
  /// recorder asks once more while recording and visible (6.8.4). Not fired by [release].
  Stream<void> get systemReleases;

  /// Lets it go; a second call is a no-op. Never throws.
  Future<void> release();
}
