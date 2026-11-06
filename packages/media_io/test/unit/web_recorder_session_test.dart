// The web recorder session's rules in fake time (m5-7/06-pdf 6.8.2–6.8.4, 6.8.6 — 8.2 T32b), over
// a hand-driven capture and page (test/support/fake_web_capture.dart): chunks in order and empty
// ones dropped, the watchdog (2.5 × timeslice, 'timeslice ignored' after three), pause asks for
// data first, the hidden pause and no automatic resume (M-2), resume refused while hidden, the
// microphone rules (ended, mute while visible, mute while hidden ignored, the 3 s unmute grace —
// S-6), the wake lock (request / release / one more after a system release), pagehide, stop with
// the last chunk and the 3 s flush limit, abandon, cancel. The Chrome binding is
// web/recorder_engine_browser_test.dart.
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/record/recorder_engine.dart';
import 'package:media_io/src/record/web_mime.dart';
import 'package:media_io/src/record/web_recorder_session.dart';

import '../support/fake_web_capture.dart';

const _opus = WebMimeChoice(
  mimeType: 'audio/webm;codecs=opus',
  crossPlatformPlayable: false,
  extension: '.webm',
);

final class _World {
  _World({bool hidden = false, int timesliceMs = 1000}) {
    page.hidden = hidden;
    session = WebRecorderSession(
      capture: capture,
      page: page,
      choice: _opus,
      timesliceMs: timesliceMs,
      onChunk: chunks.add,
      counters: counters,
      onEnded: () => ended++,
    );
    session.events.listen(events.add, onDone: () => eventsDone = true);
  }

  bool eventsDone = false;

  final capture = FakeWebCapture();
  final page = FakePageEvents();
  final counters = WebRecorderCounters();
  final chunks = <Uint8List>[];
  final events = <RecorderEngineEvent>[];
  late final WebRecorderSession session;
  int ended = 0;

  List<String> get calls => capture.calls;
}

Matcher _paused(MediaErrorCode reason) => isA<EnginePaused>()
    .having((e) => e.bySystem, 'bySystem', isTrue)
    .having((e) => e.reason, 'reason', reason);

void main() {
  test(
    'begin: listen, start(timeslice), EngineStarted, wake lock; actual MIME',
    () {
      fakeAsync((async) {
        final w = _World(timesliceMs: 500);
        w.capture.mimeType = 'audio/webm;codecs=opus';
        w.session.begin();
        async.flushMicrotasks();
        expect(w.calls, ['start']);
        expect(w.capture.timesliceMs, 500);
        expect(w.events.single, isA<EngineStarted>());
        expect(w.session.isRecording, isTrue);
        expect(w.page.held, isNotNull);
        expect(w.counters.wakeLock, 'held');
        expect(w.session.mimeType, 'audio/webm;codecs=opus');
        expect(w.session.crossPlatformPlayable, isFalse);
        expect(w.session.backgroundCapable, isFalse);
        expect(w.session.extension, '.webm');
      });
    },
  );

  test('a capture that cannot start: begin throws, no EngineStarted', () {
    fakeAsync((async) {
      final w = _World();
      w.capture.startError = StateError('NotSupportedError');
      expect(w.session.begin, throwsStateError);
      async.flushMicrotasks();
      expect(w.events, isEmpty);
    });
  });

  group('chunks and the watchdog (6.8.2)', () {
    test('non-empty chunks in order; empty ones only reset the watchdog', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.capture.chunk([1]);
        w.capture.chunk([]);
        w.capture.chunk([2, 3]);
        expect(w.chunks.map((c) => c.toList()), [
          [1],
          [2, 3],
        ]);
      });
    });

    test(
      'no chunk for 2.5 × timeslice → requestData; chunks keep it quiet',
      () {
        fakeAsync((async) {
          final w = _World();
          w.session.begin();
          for (var i = 0; i < 5; i++) {
            async.elapse(const Duration(milliseconds: 1000));
            w.capture.chunk([i]);
          }
          expect(w.capture.count('requestData'), 0);
          async.elapse(const Duration(milliseconds: 2499));
          expect(w.capture.count('requestData'), 0);
          async.elapse(const Duration(milliseconds: 1));
          expect(w.capture.count('requestData'), 1);
          expect(w.counters.watchdog, 1);
          expect(w.counters.timesliceIgnored, isFalse);
        });
      },
    );

    test('three watchdog answers in a row → timeslice ignored', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        for (var i = 0; i < 2; i++) {
          async.elapse(const Duration(milliseconds: 2500));
          w.capture.chunk([i]); // the answer to the watchdog
        }
        // a chunk of its own breaks the streak
        async.elapse(const Duration(milliseconds: 1000));
        w.capture.chunk([7]);
        for (var i = 0; i < 2; i++) {
          async.elapse(const Duration(milliseconds: 2500));
          w.capture.chunk([i]);
        }
        expect(w.counters.timesliceIgnored, isFalse);
        async.elapse(const Duration(milliseconds: 2500));
        w.capture.chunk([3]);
        expect(w.counters.watchdog, 5);
        expect(w.counters.timesliceIgnored, isTrue);
        expect(w.counters.line, contains('timeslice ignored'));
      });
    });

    test('no watchdog while paused', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.session.pause();
        final before = w.capture.count('requestData');
        async.elapse(const Duration(seconds: 20));
        expect(w.capture.count('requestData'), before);
        expect(w.counters.watchdog, 0);
      });
    });
  });

  group('user pause / resume', () {
    test('pause: requestData first, then pause, wake lock released', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        async.flushMicrotasks();
        final lock = w.page.held!;
        w.session.pause();
        async.flushMicrotasks();
        expect(w.calls, ['start', 'requestData', 'pause']);
        expect(lock.released, isTrue);
        expect(w.counters.wakeLock, 'released');
        expect(w.session.isRecording, isFalse);
        expect(w.events, hasLength(1)); // no event for a user pause
      });
    });

    test('resume: recording again, a new wake lock', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.session.pause();
        async.flushMicrotasks();
        w.session.resume();
        async.flushMicrotasks();
        expect(w.calls.last, 'resume');
        expect(w.session.isRecording, isTrue);
        expect(w.page.locks, hasLength(2));
        expect(w.page.held, same(w.page.locks.last));
      });
    });
  });

  group('visibility (6.8.3, M-2)', () {
    test(
      'hidden while recording → requestData, pause, EnginePaused(hiddenTab)',
      () {
        fakeAsync((async) {
          final w = _World();
          w.session.begin();
          async.flushMicrotasks();
          w.page.setHidden(true);
          async.flushMicrotasks();
          expect(w.calls, ['start', 'requestData', 'pause']);
          expect(w.events.last, _paused(MediaErrorCode.hiddenTab));
          expect(w.counters.hiddenPauses, 1);
          expect(w.page.locks.single.released, isTrue);
        });
      },
    );

    test('resume while hidden → StateError; visible → no automatic resume', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.page.setHidden(true);
        Object? error;
        w.session.resume().catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isStateError);
        w.page.setHidden(false);
        async.elapse(const Duration(seconds: 10));
        expect(w.session.isRecording, isFalse);
        expect(w.capture.count('resume'), 0);
        expect(w.events, hasLength(2)); // started, paused — nothing for visible
        w.session.resume();
        async.flushMicrotasks();
        expect(w.session.isRecording, isTrue);
        expect(w.capture.count('resume'), 1);
      });
    });

    test(
      'hidden while user-paused: no event, resume possible once visible',
      () {
        fakeAsync((async) {
          final w = _World();
          w.session.begin();
          w.session.pause();
          w.page.setHidden(true);
          w.page.setHidden(false);
          async.flushMicrotasks();
          expect(w.events, hasLength(1));
          expect(w.counters.hiddenPauses, 0);
          w.session.resume();
          expect(w.session.isRecording, isTrue);
        });
      },
    );

    test('already hidden at begin → started, then the hidden pause', () {
      fakeAsync((async) {
        final w = _World(hidden: true);
        w.session.begin();
        async.flushMicrotasks();
        expect(w.events, [
          isA<EngineStarted>(),
          _paused(MediaErrorCode.hiddenTab),
        ]);
        expect(w.page.requests, 0); // no wake lock for a hidden tab
      });
    });

    test('pagehide → requestData (best effort)', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.page.pageHide();
        expect(w.capture.count('requestData'), 1);
      });
    });
  });

  group('the microphone (6.8.3, S-6)', () {
    test('track ended → EnginePaused(microphoneLost), resume refused', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.capture.ended();
        async.flushMicrotasks();
        expect(w.events.last, _paused(MediaErrorCode.microphoneLost));
        expect(w.calls, ['start', 'requestData', 'pause']);
        expect(w.session.microphoneLost, isTrue);
        Object? error;
        w.session.resume().catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isStateError);
      });
    });

    test('mute while visible and recording: lost after 1 s, an unmute before keeps it', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.capture.mute();
        expect(w.session.judgingMute, isTrue);
        async.elapse(const Duration(milliseconds: 999));
        w.capture.unmute();
        async.elapse(const Duration(seconds: 5));
        expect(w.session.microphoneLost, isFalse);
        w.capture.mute();
        async.elapse(const Duration(milliseconds: 1000));
        expect(w.session.microphoneLost, isTrue);
        expect(w.events.last, _paused(MediaErrorCode.microphoneLost));
      });
    });

    test('a mute while hidden is ignored; unmute within 3 s of visible → resumable', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.page.setHidden(true); // iOS: the app went to the background …
        w.capture.mute(); // … and the capture track was muted
        async.elapse(const Duration(seconds: 30));
        expect(w.session.microphoneLost, isFalse);
        expect(w.session.judgingMute, isFalse);
        w.page.setHidden(false);
        expect(w.session.inUnmuteGrace, isTrue);
        async.elapse(const Duration(milliseconds: 2999));
        w.capture.unmute();
        expect(w.session.inUnmuteGrace, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(w.session.microphoneLost, isFalse);
        w.session.resume();
        async.flushMicrotasks();
        expect(w.session.isRecording, isTrue);
        expect(w.events, [
          isA<EngineStarted>(),
          _paused(MediaErrorCode.hiddenTab),
        ]);
      });
    });

    test('still muted 3 s after visible → lost (while paused)', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.page.setHidden(true);
        w.capture.mute();
        w.page.setHidden(false);
        async.elapse(const Duration(milliseconds: 2999));
        expect(w.session.microphoneLost, isFalse);
        async.elapse(const Duration(milliseconds: 1));
        expect(w.session.microphoneLost, isTrue);
        expect(w.events.last, _paused(MediaErrorCode.microphoneLost));
        expect(w.capture.count('pause'), 1); // only the hidden pause
      });
    });

    test('resumed inside the grace while muted → the grace still judges', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.page.setHidden(true);
        w.capture.mute();
        w.page.setHidden(false);
        async.elapse(const Duration(milliseconds: 500));
        w.session.resume();
        async.flushMicrotasks();
        expect(w.session.isRecording, isTrue);
        expect(w.session.judgingMute, isFalse); // the grace, not the 1 s watch
        async.elapse(const Duration(milliseconds: 2500));
        expect(w.session.microphoneLost, isTrue);
        expect(w.calls.sublist(w.calls.length - 2), ['requestData', 'pause']);
      });
    });

    test(
      'mute while user-paused and visible is not judged until recording',
      () {
        fakeAsync((async) {
          final w = _World();
          w.session.begin();
          w.session.pause();
          w.capture.mute();
          async.elapse(const Duration(seconds: 5));
          expect(w.session.microphoneLost, isFalse);
          w.session.resume();
          async.elapse(const Duration(milliseconds: 1000));
          expect(w.session.microphoneLost, isTrue);
        });
      },
    );

    test('a MediaRecorder error → EngineFailed, resume refused', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.capture.error('encoder');
        async.flushMicrotasks();
        expect(w.events.last, isA<EngineFailed>());
        Object? error;
        w.session.resume().catchError((Object e) => error = e);
        async.flushMicrotasks();
        expect(error, isStateError);
      });
    });

    test('MediaRecorder stopping by itself → EngineFailed', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.capture.stopped();
        async.flushMicrotasks();
        expect(w.events.last, isA<EngineFailed>());
      });
    });
  });

  group('the wake lock (6.8.4)', () {
    test('refused or missing → none, recording goes on', () {
      fakeAsync((async) {
        final w = _World();
        w.page.refuseWakeLock = true;
        w.session.begin();
        async.flushMicrotasks();
        expect(w.counters.wakeLock, 'none');
        expect(w.session.isRecording, isTrue);
        expect(
          w.counters.line,
          startsWith('wakeLock=none watchdog=0 hidden-pauses=0'),
        );
      });
    });

    test('a system release while recording and visible → asked once more', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        async.flushMicrotasks();
        w.page.locks.single.systemRelease();
        async.flushMicrotasks();
        expect(w.page.requests, 2);
        expect(w.page.held, same(w.page.locks.last));
        expect(w.counters.wakeLock, 'held');
        // refused the second time → none, no loop
        w.page.refuseWakeLock = true;
        w.page.locks.last.systemRelease();
        async.flushMicrotasks();
        expect(w.page.requests, 3);
        expect(w.counters.wakeLock, 'none');
      });
    });

    test('a system release while hidden → not asked again', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        async.flushMicrotasks();
        final lock = w.page.locks.single;
        w.page.hidden =
            true; // the browser drops the lock before visibilitychange
        lock.systemRelease();
        w.page.setHidden(true);
        async.flushMicrotasks();
        expect(w.page.requests, 1);
      });
    });

    test('a lock granted after the pause is let go at once', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin(); // request in flight
        w.session.pause();
        async.flushMicrotasks();
        expect(w.page.locks.single.releaseCalls, 1);
        expect(w.page.held, isNull);
      });
    });
  });

  group('stop / abandon / cancel (6.8.6)', () {
    test(
      'stop: the last chunk, then tracks off, lock released, events closed',
      () {
        fakeAsync((async) {
          final w = _World();
          w.session.begin();
          async.flushMicrotasks();
          w.capture.chunk([1]);
          RecorderEngineResult? result;
          w.session.stop().then((r) => result = r);
          async.flushMicrotasks();
          expect(result, isNotNull);
          expect(result!.file, isNull);
          expect(w.chunks.map((c) => c.toList()), [
            [1],
            [9, 9],
          ]);
          expect(w.calls.sublist(1), ['stop', 'stopTracks', 'detach']);
          expect(w.page.locks.single.released, isTrue);
          expect(w.ended, 1);
          async.flushMicrotasks();
          expect(w.eventsDone, isTrue);
        });
      },
    );

    test('stop from a paused recording works the same', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.session.pause();
        var done = false;
        w.session.stop().then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(w.chunks, hasLength(1));
      });
    });

    test('no stop event: what came within 3 s is what there is; later chunks dropped', () {
      fakeAsync((async) {
        final w = _World();
        w.capture.answersStop = false;
        w.session.begin();
        var done = false;
        w.session.stop().then((_) => done = true);
        async.elapse(const Duration(milliseconds: 2000));
        w.capture.chunk([5]);
        expect(done, isFalse);
        async.elapse(const Duration(milliseconds: 1000));
        expect(done, isTrue);
        w.capture.chunk([6]); // detached: never reaches the draft
        expect(w.chunks.map((c) => c.toList()), [
          [5],
        ]);
      });
    });

    test('stop twice → the same flush; resume after stop → StateError', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        final a = w.session.stop();
        final b = w.session.stop();
        async.flushMicrotasks();
        expect(w.capture.count('stop'), 1);
        expect(a, completes);
        expect(b, completes);
        expect(w.session.resume(), throwsStateError);
        async.flushMicrotasks();
      });
    });

    test('abandon: the last chunk reaches the draft before it completes', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        var done = false;
        w.session.abandon().then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue);
        expect(w.chunks.single.toList(), [9, 9]);
        expect(w.calls, containsAllInOrder(['stop', 'stopTracks']));
      });
    });

    test('cancel: nothing more reaches the draft, tracks off', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.session.cancel();
        async.flushMicrotasks();
        expect(w.chunks, isEmpty);
        expect(w.calls, containsAll(['stop', 'stopTracks', 'detach']));
        expect(w.ended, 1);
      });
    });

    test('after the end: no system events, no watchdog', () {
      fakeAsync((async) {
        final w = _World();
        w.session.begin();
        w.session.stop();
        async.flushMicrotasks();
        final n = w.events.length;
        w.page.setHidden(true);
        w.capture.ended();
        async.elapse(const Duration(seconds: 30));
        expect(w.events, hasLength(n));
        expect(w.counters.watchdog, 0);
      });
    });
  });
}
