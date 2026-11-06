// lib/src/platform/page_events_browser.dart — the browser page events (m5-7/06-pdf 6.8.3, 6.8.4):
// document.visibilityState + visibilitychange, window pagehide, navigator.wakeLock.request
// ('screen') and the sentinel's release event. The DOM listeners are added while somebody listens
// to the broadcast streams and removed after. Internal; behind page_events_factory.dart.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'page_events.dart';

PageEvents createPlatformPageEvents() => BrowserPageEvents();

final class BrowserPageEvents implements PageEvents {
  BrowserPageEvents() {
    _visibility = StreamController<bool>.broadcast(
      onListen: () =>
          web.document.addEventListener('visibilitychange', _onVisibility),
      onCancel: () =>
          web.document.removeEventListener('visibilitychange', _onVisibility),
    );
    _pageHide = StreamController<void>.broadcast(
      onListen: () => web.window.addEventListener('pagehide', _onPageHide),
      onCancel: () => web.window.removeEventListener('pagehide', _onPageHide),
    );
  }

  late final StreamController<bool> _visibility;
  late final StreamController<void> _pageHide;

  late final JSFunction _onVisibility = ((web.Event _) {
    _visibility.add(hidden);
  }).toJS;

  late final JSFunction _onPageHide = ((web.Event _) {
    _pageHide.add(null);
  }).toJS;

  @override
  bool get hidden => web.document.visibilityState == 'hidden';

  @override
  Stream<bool> get visibilityChanges => _visibility.stream;

  @override
  Stream<void> get pageHides => _pageHide.stream;

  @override
  bool get wakeLockAvailable {
    final navigator = web.window.navigator as JSObject;
    return navigator.has('wakeLock') &&
        navigator.getProperty<JSAny?>('wakeLock'.toJS) != null;
  }

  @override
  Future<ScreenWakeLock?> requestWakeLock() async {
    if (!wakeLockAvailable) return null;
    try {
      final sentinel = await web.window.navigator.wakeLock
          .request('screen')
          .toDart;
      return _BrowserWakeLock(sentinel);
    } on Object {
      return null; // refused (hidden document, policy) — 'wake lock: none'
    }
  }
}

final class _BrowserWakeLock implements ScreenWakeLock {
  _BrowserWakeLock(this._sentinel) {
    _sentinel.addEventListener('release', _onRelease);
  }

  final web.WakeLockSentinel _sentinel;
  final StreamController<void> _system = StreamController<void>.broadcast();
  bool _releasing = false;
  bool _done = false;

  late final JSFunction _onRelease = ((web.Event _) {
    _sentinel.removeEventListener('release', _onRelease);
    if (!_releasing && !_done) {
      _done = true;
      _system.add(null);
    }
    _done = true;
  }).toJS;

  @override
  bool get released => _done || _releasing || _safeReleased();

  bool _safeReleased() {
    try {
      return _sentinel.released;
    } on Object {
      return true;
    }
  }

  @override
  Stream<void> get systemReleases => _system.stream;

  @override
  Future<void> release() async {
    if (_releasing || _done) return;
    _releasing = true;
    try {
      await _sentinel.release().toDart;
    } on Object {
      // already gone
    }
    _done = true;
    _sentinel.removeEventListener('release', _onRelease);
  }
}
