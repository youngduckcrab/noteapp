// lib/src/platform/web_locks.dart — (v2.1, PDF-M5) the recording lock port (m5-7/06-pdf 6.10.2,
// 7.4.2 '같은 출처 두 탭'). Internal. The recording tab holds the exclusive Web Lock
// 'noteapp-rec-<draftId>' from start until stop / cancel / abandon (the browser lets it go when
// the tab closes); pendingDrafts() leaves out drafts whose lock is held. Bodies:
// web_locks_browser.dart (navigator.locks — PDF T32b) and web_locks_stub.dart (no Web Locks:
// the 'recently updated' time rule only — developer overlay `locks=none`).

/// The Web Lock name of a recording draft.
String recordingLockName(String draftId) => 'noteapp-rec-$draftId';

abstract interface class WebLocks {
  /// false: no Web Locks here (stub, old browser) — [acquire] gives `null` and [heldNames]
  /// `null`.
  bool get available;

  /// Takes the exclusive lock [name] and holds it until [WebLockHold.release]. `null` when Web
  /// Locks are missing or the request failed (recording goes on with the time rule only).
  Future<WebLockHold?> acquire(String name);

  /// The names held by any context of this origin (`navigator.locks.query().held`); `null` =
  /// unknown.
  Future<Set<String>?> heldNames();
}

abstract interface class WebLockHold {
  String get name;

  /// Lets the lock go; a second call is a no-op.
  void release();
}
