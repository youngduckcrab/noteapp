// The web recorder engine in Chrome without a microphone (m5-7/06-pdf 6.8, 6.10.2 — 8.2 T32b): the
// MIME choice is Chrome's real one, checkSupport / start against Chrome's missing device
// (NotFoundError → microphoneNotFound), and on a WebAudio stream (no audio flows in a headless tab
// — the chunks are empty, the events are real): MediaRecorder starts and stops, the visibility
// imitation (document.visibilityState redefined + visibilitychange) pauses with
// EnginePaused(hiddenTab) and refuses resume, a mute while hidden is ignored and an unmute right
// after visible lets the recording go on, the Screen Wake Lock request / release (a navigator
// stub that logs on the JS side), the watchdog's requestData answered by a real dataavailable,
// the kept stream of checkSupport(requestPermission: true), and real navigator.locks (hold,
// query, release). Timers are fired by hand (test/support/manual_timers.dart). The fake
// microphone run is media/visibility_pause_media_test.dart.
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/platform/page_events_browser.dart';
import 'package:media_io/src/platform/web_locks.dart';
import 'package:media_io/src/platform/web_locks_browser.dart';
import 'package:media_io/src/platform/web_locks_factory.dart' as locks_factory;
import 'package:media_io/src/record/recorder_engine.dart';
import 'package:media_io/src/record/recorder_engine_browser.dart';
import 'package:media_io/src/record/recorder_engine_factory.dart'
    as engine_factory;
import 'package:media_io/src/record/web_mime.dart';
import 'package:media_io/src/tuning.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:web/web.dart' as web;

import '../support/manual_timers.dart';

const _config = MediaIoConfig();

/// A live audio stream without a microphone (WebAudio; suspended in a headless tab).
Future<web.MediaStream> webAudioStream() async {
  final ctx = web.AudioContext();
  final osc = ctx.createOscillator();
  final dest = ctx.createMediaStreamDestination();
  osc.connect(dest);
  osc.start();
  addTearDown(() async {
    await ctx.close().toDart;
  });
  return dest.stream;
}

RecorderEngineRequest request({void Function(Uint8List)? onChunk}) =>
    RecorderEngineRequest(
      recordingId: 'rec-1',
      noteId: 'note-1',
      config: _config,
      bitRate: 64000,
      onChunk: onChunk ?? (_) {},
    );

void setVisibility(String state) {
  final object = globalContext.getProperty<JSObject>('Object'.toJS);
  object.callMethod(
    'defineProperty'.toJS,
    web.document,
    'visibilityState'.toJS,
    JSObject()
      ..setProperty('value'.toJS, state.toJS)
      ..setProperty('configurable'.toJS, true.toJS),
  );
  web.document.dispatchEvent(web.Event('visibilitychange'));
}

void restoreVisibility() {
  (web.document as JSObject).delete('visibilityState'.toJS);
}

JSObject evalJs(String code) =>
    globalContext.callMethod<JSObject>('eval'.toJS, code.toJS);

/// navigator.wakeLock replaced by a stub that logs 'request:screen' / 'release'.
final class WakeLockStub {
  WakeLockStub() {
    _state = evalJs('''(function(){
      const calls = [];
      const sentinels = [];
      const wl = { request: function(type) {
        calls.push('request:' + type);
        const s = new EventTarget();
        s.released = false;
        s.type = type;
        s.release = function() { calls.push('release'); s.released = true; return Promise.resolve(); };
        sentinels.push(s);
        return Promise.resolve(s);
      } };
      Object.defineProperty(navigator, 'wakeLock', {value: wl, configurable: true});
      return {calls: calls, sentinels: sentinels};
    })()''');
    addTearDown(
      () => (web.window.navigator as JSObject).delete('wakeLock'.toJS),
    );
  }

  late final JSObject _state;

  List<String> get calls => [
    for (final c in _state.getProperty<JSArray<JSString>>('calls'.toJS).toDart)
      c.toDart,
  ];

  List<web.EventTarget> get sentinels =>
      _state.getProperty<JSArray<web.EventTarget>>('sentinels'.toJS).toDart;

  /// The system lets the newest lock go.
  void systemRelease() {
    final s = sentinels.last;
    (s as JSObject).setProperty('released'.toJS, true.toJS);
    s.dispatchEvent(web.Event('release'));
  }
}

Future<void> until(bool Function() ready, String what) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: what);
}

void main() {
  tearDown(restoreVisibility);

  group('MIME (6.8.1) — Chrome', () {
    test('Chrome records audio/webm;codecs=opus (mp4 without a codec is not chosen)', () {
      final table = probeBrowserMimeTable();
      expect(table.supported[webMimeCandidates[0]], isFalse);
      expect(table.supported[webMimeCandidates[3]], isTrue);
      final c = table.choose(allowNonAacOnWeb: true)!;
      expect(c.mimeType, 'audio/webm;codecs=opus');
      expect(c.crossPlatformPlayable, isFalse);
      expect(c.extension, '.webm');
      expect(table.encoderLine, 'mp4a=no mp4=yes webm/opus=yes');
      final engine = BrowserRecorderEngine(config: _config);
      expect(engine.draftMimeType, 'audio/webm;codecs=opus');
      expect(engine.writesDraftChunks, isTrue);
    });

    test('allowNonAacOnWeb false → nothing to record in Chrome', () async {
      final engine = BrowserRecorderEngine(
        config: const MediaIoConfig(allowNonAacOnWeb: false),
      );
      expect(engine.choice, isNull);
      expect(
        await engine.checkSupport(requestPermission: false),
        core.AudioSupport.unsupported,
      );
      await expectLater(engine.start(request()), throwsUnsupportedError);
    });

    test(
      'the factory gives the browser engine and the web locks on the web',
      () {
        expect(
          engine_factory.createPlatformRecorderEngine(_config),
          isA<BrowserRecorderEngine>(),
        );
        engine_factory.preparePlatformRecording(_config); // probes once, sync
        expect(engine_factory.platformPlaybackSessionSetup(), isNull);
        expect(locks_factory.createPlatformWebLocks(), isA<BrowserWebLocks>());
      },
    );
  });

  group('checkSupport / start without a microphone (4.2.3, 6.8.6)', () {
    test('no request: permissions.query is not denied → supported; denied → permissionDenied', () async {
      expect(
        await BrowserRecorderEngine(config: _config)
            .checkSupport(requestPermission: false),
        core.AudioSupport.supported,
      );
      expect(
        await queryMicrophonePermission(),
        isIn(['prompt', 'granted', 'denied', null]),
      );
      final denied = BrowserRecorderEngine(
        config: _config,
        permissionState: () async => 'denied',
      );
      expect(
        await denied.checkSupport(requestPermission: false),
        core.AudioSupport.permissionDenied,
      );
    });

    test('Chrome without a device: request → supported, start → microphoneNotFound', () async {
      final engine = BrowserRecorderEngine(config: _config);
      expect(
        await engine.checkSupport(requestPermission: true),
        core.AudioSupport.supported,
      );
      expect(engine.keepsStream, isFalse);
      await expectLater(
        engine.start(request()),
        throwsA(
          isA<MediaIoException>().having(
            (e) => e.code,
            'code',
            MediaErrorCode.microphoneNotFound,
          ),
        ),
      );
      expect(engine.session, isNull);
    });

    test(
      'NotAllowedError → permissionDenied (check) / permissionDenied (start)',
      () async {
        Future<web.MediaStream> refuse() =>
            Future.error(web.DOMException('denied', 'NotAllowedError'));
        final engine = BrowserRecorderEngine(
          config: _config,
          openStream: refuse,
        );
        expect(
          await engine.checkSupport(requestPermission: true),
          core.AudioSupport.permissionDenied,
        );
        await expectLater(
          engine.start(request()),
          throwsA(
            isA<MediaIoException>().having(
              (e) => e.code,
              'code',
              MediaErrorCode.permissionDenied,
            ),
          ),
        );
      },
    );

    test('no MediaRecorder / getUserMedia → unsupported', () async {
      final engine = BrowserRecorderEngine(
        config: _config,
        apiAvailable: false,
      );
      expect(
        await engine.checkSupport(requestPermission: true),
        core.AudioSupport.unsupported,
      );
    });

    test('the stream of checkSupport(requestPermission) is reused, then let go after 30 s', () async {
      final timers = ManualTimers();
      final streams = <web.MediaStream>[];
      final engine = BrowserRecorderEngine(
        config: _config,
        openStream: () async {
          final s = await webAudioStream();
          streams.add(s);
          return s;
        },
        timer: timers.create,
      );
      expect(
        await engine.checkSupport(requestPermission: true),
        core.AudioSupport.supported,
      );
      expect(engine.keepsStream, isTrue);
      final session = await engine.start(request());
      expect(streams, hasLength(1)); // one permission prompt
      expect(engine.keepsStream, isFalse);
      await session.cancel();

      // a kept stream nobody starts with: its tracks stop after micStreamKeepAlive
      await engine.checkSupport(requestPermission: true);
      expect(streams, hasLength(2));
      expect(timers.fire(MediaTuning.micStreamKeepAlive), 1);
      expect(engine.keepsStream, isFalse);
      expect(streams.last.getAudioTracks().toDart.single.readyState, 'ended');
    });
  });

  group('one recording on a WebAudio stream', () {
    late ManualTimers timers;
    late BrowserRecorderEngine engine;
    late WakeLockStub wakeLock;
    late RecorderEngineSession session;
    late List<RecorderEngineEvent> events;
    late web.MediaStream stream;

    setUp(() async {
      wakeLock = WakeLockStub();
      timers = ManualTimers();
      engine = BrowserRecorderEngine(
        config: _config,
        openStream: () async => stream = await webAudioStream(),
        timer: timers.create,
      );
      session = await engine.start(request());
      events = [];
      session.events.listen(events.add);
      await until(() => events.isNotEmpty, 'EngineStarted');
      addTearDown(() => session.cancel());
    });

    web.MediaStreamTrack track() => stream.getAudioTracks().toDart.single;

    test(
      'started: MediaRecorder records the chosen MIME; wake lock requested',
      () async {
        expect(events.single, isA<EngineStarted>());
        expect(engine.lastCapture!.state, 'recording');
        expect(session.mimeType, 'audio/webm;codecs=opus');
        expect(session.crossPlatformPlayable, isFalse);
        expect(session.backgroundCapable, isFalse);
        await until(() => wakeLock.calls.isNotEmpty, 'wake lock request');
        expect(wakeLock.calls, ['request:screen']);
        expect(engine.counters.wakeLock, 'held');
      },
    );

    test('user pause releases the wake lock, resume asks again', () async {
      await until(() => wakeLock.calls.isNotEmpty, 'wake lock request');
      await session.pause();
      expect(engine.lastCapture!.state, 'paused');
      await until(() => wakeLock.calls.length == 2, 'release');
      await session.resume();
      expect(engine.lastCapture!.state, 'recording');
      await until(() => wakeLock.calls.length == 3, 'request again');
      expect(wakeLock.calls, ['request:screen', 'release', 'request:screen']);
    });

    test(
      'a system release while recording and visible → one more request',
      () async {
        await until(() => wakeLock.calls.isNotEmpty, 'wake lock request');
        wakeLock.systemRelease();
        await until(() => wakeLock.calls.length == 2, 'second request');
        expect(wakeLock.calls, ['request:screen', 'request:screen']);
      },
    );

    test(
      'hidden → EnginePaused(hiddenTab), resume refused, visible → no resume',
      () async {
        await until(() => wakeLock.calls.isNotEmpty, 'wake lock request');
        setVisibility('hidden');
        await until(() => events.length == 2, 'the hidden pause');
        expect(
          events.last,
          isA<EnginePaused>()
              .having((e) => e.bySystem, 'bySystem', isTrue)
              .having((e) => e.reason, 'reason', MediaErrorCode.hiddenTab),
        );
        expect(engine.lastCapture!.state, 'paused');
        expect(engine.counters.hiddenPauses, 1);
        await expectLater(session.resume(), throwsStateError);
        await until(() => wakeLock.calls.contains('release'), 'released');

        setVisibility('visible');
        await Future<void>.delayed(Duration.zero);
        expect(
          engine.lastCapture!.state,
          'paused',
        ); // no automatic resume (M-2)
        await session.resume();
        expect(engine.lastCapture!.state, 'recording');
      },
    );

    test('a mute while hidden is ignored; unmute within the grace → recording goes on', () async {
      final s = engine.session!;
      setVisibility('hidden');
      await until(() => events.length == 2, 'the hidden pause');
      track().dispatchEvent(web.Event('mute'));
      expect(s.judgingMute, isFalse);
      expect(s.microphoneLost, isFalse);
      setVisibility('visible');
      await Future<void>.delayed(
        Duration.zero,
      ); // the page stream delivers async
      expect(s.inUnmuteGrace, isTrue);
      expect(
        timers.active(
          const Duration(milliseconds: MediaTuning.micUnmuteGraceMs),
        ),
        hasLength(1),
      );
      track().dispatchEvent(web.Event('unmute'));
      expect(s.inUnmuteGrace, isFalse);
      await session.resume();
      expect(engine.lastCapture!.state, 'recording');
      expect(s.microphoneLost, isFalse);
      expect(events, hasLength(2));
    });

    test(
      'still muted when the grace ends → microphoneLost, resume refused',
      () async {
        setVisibility('hidden');
        await until(() => events.length == 2, 'the hidden pause');
        track().dispatchEvent(web.Event('mute'));
        setVisibility('visible');
        await Future<void>.delayed(Duration.zero);
        expect(
          timers.fire(
            const Duration(milliseconds: MediaTuning.micUnmuteGraceMs),
          ),
          1,
        );
        await until(() => events.length == 3, 'microphone lost');
        expect(
          (events.last as EnginePaused).reason,
          MediaErrorCode.microphoneLost,
        );
        await expectLater(session.resume(), throwsStateError);
      },
    );

    test('the watchdog asks requestData and MediaRecorder answers', () async {
      var dataEvents = 0;
      engine.lastCapture!.recorder.addEventListener(
        'dataavailable',
        ((web.Event _) => dataEvents++).toJS,
      );
      final watchdog = Duration(
        milliseconds: MediaTuning.webRequestDataWatchdogMs(
          _config.webDraftChunkMs,
        ),
      );
      expect(timers.fire(watchdog), 1);
      expect(engine.counters.watchdog, 1);
      await until(() => dataEvents >= 1, 'dataavailable after requestData');
      expect(timers.active(watchdog), hasLength(1)); // armed again
    });

    test('pagehide → requestData', () async {
      var dataEvents = 0;
      engine.lastCapture!.recorder.addEventListener(
        'dataavailable',
        ((web.Event _) => dataEvents++).toJS,
      );
      web.window.dispatchEvent(web.Event('pagehide'));
      await until(() => dataEvents >= 1, 'dataavailable after pagehide');
    });

    test('stop: the stop event, tracks ended, the session gone, a second start works', () async {
      final result = await session.stop();
      expect(result.file, isNull);
      expect(engine.lastCapture!.state, 'inactive');
      expect(track().readyState, 'ended');
      expect(engine.session, isNull);
      await until(() => wakeLock.calls.contains('release'), 'released');
      final again = await engine.start(request());
      addTearDown(again.cancel);
      expect(engine.lastCapture!.state, 'recording');
    });

    test('a second start while recording → StateError', () async {
      await expectLater(engine.start(request()), throwsStateError);
    });

    test('dispose abandons the recording (stop event, tracks ended)', () async {
      await engine.dispose();
      expect(engine.lastCapture!.state, 'inactive');
      expect(track().readyState, 'ended');
      expect(engine.session, isNull);
      expect(
        await engine.checkSupport(requestPermission: false),
        core.AudioSupport.unsupported,
      );
    });
  });

  group('BrowserPageEvents', () {
    test('hidden follows document.visibilityState; visibilitychange and pagehide streams', () async {
      final page = BrowserPageEvents();
      expect(page.hidden, isFalse);
      final changes = <bool>[];
      var hides = 0;
      final a = page.visibilityChanges.listen(changes.add);
      final b = page.pageHides.listen((_) => hides++);
      setVisibility('hidden');
      expect(page.hidden, isTrue);
      setVisibility('visible');
      web.window.dispatchEvent(web.Event('pagehide'));
      await Future<void>.delayed(Duration.zero);
      expect(changes, [true, false]);
      expect(hides, 1);
      await a.cancel();
      await b.cancel();
    });

    test(
      'Chrome headless has navigator.wakeLock; a stub that refuses → null',
      () async {
        final page = BrowserPageEvents();
        expect(page.wakeLockAvailable, isTrue);
        evalJs('''(function(){
        Object.defineProperty(navigator, 'wakeLock', {configurable: true, value: {
          request: function() { return Promise.reject(new DOMException('no', 'NotAllowedError')); }
        }});
        return {};
      })()''');
        addTearDown(
          () => (web.window.navigator as JSObject).delete('wakeLock'.toJS),
        );
        expect(await page.requestWakeLock(), isNull);
      },
    );
  });

  group('BrowserWebLocks — real navigator.locks (6.10.2)', () {
    const locks = BrowserWebLocks();

    test(
      'hold, query, a second request for the same name is not granted, release',
      () async {
        expect(locks.available, isTrue);
        final name = recordingLockName(
          'draft-t32b-${DateTime.now().microsecondsSinceEpoch}',
        );
        final hold = await locks.acquire(name);
        expect(hold, isNotNull);
        expect(hold!.name, name);
        expect(await locks.heldNames(), contains(name));
        expect(await locks.acquire(name), isNull); // ifAvailable
        hold.release();
        hold.release(); // no-op
        Set<String>? held;
        for (var i = 0; i < 100; i++) {
          held = await locks.heldNames();
          if (!held!.contains(name)) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(held, isNot(contains(name)));
        final again = await locks.acquire(name);
        expect(again, isNotNull);
        again!.release();
      },
    );
  });
}
