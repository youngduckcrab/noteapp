// Fakes behind the web recorder session's ports (m5-7/06-pdf 6.8 — 8.2 T32b): a MediaRecorder +
// microphone track that the test drives by hand, and the page events (visibility, pagehide,
// Screen Wake Lock). Pure Dart — the VM session test runs them in fake_async; the Chrome engine
// test reuses FakePageEvents' wake lock bookkeeping through the real browser body instead.
import 'dart:async';
import 'dart:typed_data';

import 'package:media_io/src/platform/page_events.dart';
import 'package:media_io/src/record/web_recorder_session.dart';

/// A capture without a microphone. Calls are logged in order ('start', 'pause', 'resume',
/// 'requestData', 'stop', 'stopTracks', 'detach'); state follows MediaRecorder.
final class FakeWebCapture implements WebCapture {
  FakeWebCapture({this.mimeType = 'audio/webm;codecs=opus'});

  @override
  String mimeType;

  @override
  bool trackMuted = false;

  /// 'inactive', 'recording', 'paused'.
  String state = 'inactive';

  final List<String> calls = [];

  /// start() throws this.
  Error? startError;

  /// stop(): hand these bytes as the last chunk, then the stop event (a microtask later). false:
  /// the test fires them itself (a browser that never sends stop).
  bool answersStop = true;
  Uint8List lastChunk = Uint8List.fromList([9, 9]);

  WebCaptureCallbacks? _cb;

  int timesliceMs = 0;

  int count(String call) => calls.where((c) => c == call).length;

  @override
  void listen(WebCaptureCallbacks callbacks) => _cb = callbacks;

  @override
  void start(int timesliceMs) {
    calls.add('start');
    if (startError case final e?) throw e;
    this.timesliceMs = timesliceMs;
    state = 'recording';
  }

  @override
  void pause() {
    calls.add('pause');
    if (state == 'recording') state = 'paused';
  }

  @override
  void resume() {
    calls.add('resume');
    if (state == 'paused') state = 'recording';
  }

  @override
  void requestData() {
    calls.add('requestData');
  }

  @override
  void stop() {
    calls.add('stop');
    final wasActive = state != 'inactive';
    state = 'inactive';
    if (!answersStop) return;
    scheduleMicrotask(() {
      if (wasActive) chunk(lastChunk);
      stopped();
    });
  }

  @override
  void stopTracks() => calls.add('stopTracks');

  @override
  void detach() {
    calls.add('detach');
    _cb = null;
  }

  bool get attached => _cb != null;

  // ---- what the browser would fire ----

  /// A dataavailable with [bytes] (empty → only the event).
  void chunk(List<int> bytes) {
    final cb = _cb;
    if (cb == null) return;
    cb.onDataEvent();
    if (bytes.isNotEmpty) cb.onData(Uint8List.fromList(bytes));
  }

  void stopped() {
    state = 'inactive';
    _cb?.onStopped();
  }

  void error(Object e) => _cb?.onError(e);

  void mute() {
    trackMuted = true;
    _cb?.onMute();
  }

  void unmute() {
    trackMuted = false;
    _cb?.onUnmute();
  }

  void ended() => _cb?.onEnded();
}

/// Visibility, pagehide and a wake lock the test controls.
final class FakePageEvents implements PageEvents {
  FakePageEvents({this.wakeLockAvailable = true});

  @override
  bool hidden = false;

  @override
  bool wakeLockAvailable;

  /// requestWakeLock() gives null (refused) while set.
  bool refuseWakeLock = false;

  final StreamController<bool> _visibility = StreamController.broadcast(
    sync: true,
  );
  final StreamController<void> _pageHide = StreamController.broadcast(
    sync: true,
  );

  /// Every lock handed out, in order.
  final List<FakeWakeLock> locks = [];

  int requests = 0;

  /// The newest lock that is still held.
  FakeWakeLock? get held {
    for (final l in locks.reversed) {
      if (!l.released) return l;
    }
    return null;
  }

  /// visibilitychange to [value].
  void setHidden(bool value) {
    hidden = value;
    _visibility.add(value);
  }

  void pageHide() => _pageHide.add(null);

  @override
  Stream<bool> get visibilityChanges => _visibility.stream;

  @override
  Stream<void> get pageHides => _pageHide.stream;

  @override
  Future<ScreenWakeLock?> requestWakeLock() async {
    requests++;
    if (!wakeLockAvailable || refuseWakeLock) return null;
    final lock = FakeWakeLock();
    locks.add(lock);
    return lock;
  }
}

final class FakeWakeLock implements ScreenWakeLock {
  final StreamController<void> _system = StreamController.broadcast(sync: true);

  @override
  bool released = false;

  /// release() calls (not system releases).
  int releaseCalls = 0;

  @override
  Stream<void> get systemReleases => _system.stream;

  @override
  Future<void> release() async {
    releaseCalls++;
    released = true;
  }

  /// The system let it go.
  void systemRelease() {
    if (released) return;
    released = true;
    _system.add(null);
  }
}
