// lib/src/platform/web_locks_browser.dart — navigator.locks (m5-7/06-pdf 6.10.2): the recording tab
// holds the exclusive lock 'noteapp-rec-<draftId>' through a request whose callback returns a
// promise that settles only on release (or when the tab goes — the browser lets it go);
// heldNames() is navigator.locks.query().held. ifAvailable: a lock somebody else holds is not
// waited for (acquire → null — a fresh draft id never collides, so that only happens by mistake).
// No navigator.locks (old browser, insecure context) → unavailable: the time rule only (developer
// overlay `locks=none`). Internal; behind web_locks_factory.dart.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_locks.dart';

WebLocks createPlatformWebLocks() => const BrowserWebLocks();

final class BrowserWebLocks implements WebLocks {
  const BrowserWebLocks();

  web.LockManager? get _manager {
    final navigator = web.window.navigator as JSObject;
    if (!navigator.has('locks')) return null;
    return navigator.getProperty<web.LockManager?>('locks'.toJS);
  }

  @override
  bool get available => _manager != null;

  @override
  Future<WebLockHold?> acquire(String name) async {
    final manager = _manager;
    if (manager == null) return null;
    final granted = Completer<bool>();
    final released = Completer<void>();
    JSAny? onGranted(web.Lock? lock) {
      if (lock == null) {
        if (!granted.isCompleted) granted.complete(false);
        return null;
      }
      if (!granted.isCompleted) granted.complete(true);
      return released.future.toJS; // held until release()
    }

    try {
      final request = manager.request(
        name,
        web.LockOptions(mode: 'exclusive', ifAvailable: true),
        onGranted.toJS,
      );
      unawaited(
        request.toDart.then<void>(
          (_) {
            if (!granted.isCompleted) granted.complete(false);
          },
          onError: (Object _) {
            if (!granted.isCompleted) granted.complete(false);
          },
        ),
      );
    } on Object {
      return null;
    }
    return await granted.future ? _BrowserLockHold(name, released) : null;
  }

  @override
  Future<Set<String>?> heldNames() async {
    final manager = _manager;
    if (manager == null) return null;
    try {
      final snapshot = await manager.query().toDart;
      return {for (final info in snapshot.held.toDart) info.name};
    } on Object {
      return null;
    }
  }
}

final class _BrowserLockHold implements WebLockHold {
  _BrowserLockHold(this.name, this._released);

  @override
  final String name;
  final Completer<void> _released;

  @override
  void release() {
    if (!_released.isCompleted) _released.complete();
  }
}
