// The recorder service (m5-7/06-pdf 6.6, 6.10, 4.2.3; 8.2 T31b): the state machine, the stop
// path (M-1 order, timeline length, head patch, unsaved join, save failure keeps the draft), the
// busy rules of stop() (수정 2회차), media.bitRate (4.6), two services on one store (6.10.2),
// Web Locks, recovery attempts (6.10.3), permanent failures and dispose. Fake engine
// (test/support/fake_engines.dart) + CORE's fake store (contract 7.6) + fake time.
import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/config.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/platform/web_locks.dart';
import 'package:media_io/src/providers.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/record/recover_attempts.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:media_io/src/tuning.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/fake_engines.dart';
import '../support/recorder_world.dart';
import '../support/webm_builder.dart';

void fakeTest(String name, void Function(RecorderWorld w) body) {
  test(name, () {
    fakeAsync((async) {
      final w = RecorderWorld(async);
      body(w);
      w.close();
    });
  });
}

/// A 2 s Chrome-like WebM (34 blocks 60 ms apart: last block 1980 ms, file end 2040 ms) in two
/// chunks.
List<Uint8List> twoSecondWebm() {
  final file = webmFile(clusters: [cluster(0, blocks(34))]);
  final half = file.length ~/ 2;
  return [
    Uint8List.sublistView(file, 0, half),
    Uint8List.sublistView(file, half),
  ];
}

Uint8List joined(List<Uint8List> chunks) {
  final b = BytesBuilder();
  chunks.forEach(b.add);
  return b.takeBytes();
}

/// Records [chunks] one per second (clock = chunks.length s), then stops.
core.Recording? recordChunksAndStop(RecorderTab tab, List<Uint8List> chunks) {
  for (final c in chunks) {
    tab.world.async.elapse(const Duration(seconds: 1));
    tab.session.chunk(c);
  }
  return tab.wait(tab.service.stop());
}

const Set<String> m1 = {'put', 'createRecording', 'discard'};

void main() {
  group('states (6.6.1)', () {
    fakeTest('idle → starting → recording → paused → recording → finishing → idle; the clock skips '
        'the pause; offsetNowMs only while recording', (w) {
      final tab = RecorderTab(w);
      final id = w.recordingId();
      expect(tab.service.offsetNowMs(), isNull);
      tab.start(id);
      expect(tab.service.status.phase, core.RecorderPhase.recording);
      expect(tab.service.status.recordingId, id);
      expect(tab.service.status.noteId, w.noteId);
      expect(tab.service.status.mimeType, 'audio/webm;codecs=opus');
      expect(tab.service.status.crossPlatformPlayable, isFalse);
      expect(tab.service.status.backgroundCapable, isFalse);
      tab.record(const Duration(milliseconds: 1500));
      expect(tab.service.offsetNowMs(), 1500);
      tab.wait(tab.service.pause());
      expect(tab.service.status.phase, core.RecorderPhase.paused);
      expect(tab.service.status.interrupted, isFalse);
      expect(tab.service.offsetNowMs(), isNull);
      w.async.elapse(const Duration(seconds: 5));
      tab.wait(tab.service.resume());
      expect(tab.service.offsetNowMs(), 1500);
      tab.record(const Duration(milliseconds: 500));
      expect(tab.service.offsetNowMs(), 2000);
      final rec = tab.wait(tab.service.stop());
      expect(rec, isNotNull);
      expect(tab.service.status, const core.RecorderStatus());
      final distinct = <core.RecorderPhase>[];
      for (final p in tab.phases) {
        if (distinct.isEmpty || distinct.last != p) distinct.add(p);
      }
      expect(distinct, [
        core.RecorderPhase.idle,
        core.RecorderPhase.starting,
        core.RecorderPhase.recording,
        core.RecorderPhase.paused,
        core.RecorderPhase.recording,
        core.RecorderPhase.finishing,
        core.RecorderPhase.idle,
      ]);
      // the clock follows the engine; activeMs went up while recording only
      final paused = tab.statuses.where(
        (s) => s.phase == core.RecorderPhase.paused,
      );
      expect(paused.map((s) => s.activeMs).toSet(), {1500});
      expect(tab.engine.requests.single.recordingId, id);
    });

    fakeTest(
      'start while busy (starting, recording, paused, finishing) → StateError',
      (w) {
        final tab = RecorderTab(w);
        tab.engine.startGate = Completer<void>();
        final first = tab.service.start(
          recordingId: w.recordingId(),
          noteId: w.noteId,
        );
        expect(tab.service.status.phase, core.RecorderPhase.starting);
        expect(
          () => tab.wait(
            tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
          ),
          throwsStateError,
        );
        tab.engine.startGate!.complete();
        tab.wait(first);
        expect(
          () => tab.wait(
            tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
          ),
          throwsStateError,
        );
        tab.wait(tab.service.pause());
        expect(
          () => tab.wait(
            tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
          ),
          throwsStateError,
        );
        tab.wait(tab.service.resume());
        tab.record(const Duration(seconds: 1));
        tab.session.stopGate = Completer<void>();
        final stopping = tab.service.stop();
        w.async.elapse(Duration.zero);
        expect(tab.service.status.phase, core.RecorderPhase.finishing);
        expect(
          () => tab.wait(
            tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
          ),
          throwsStateError,
        );
        tab.session.stopGate!.complete();
        expect(tab.wait(stopping), isNotNull);
        expect(tab.engine.count('start'), 1);
      },
    );

    fakeTest(
      'checkSupport != supported → UnsupportedError, no draft, status idle',
      (w) {
        for (final support in [
          core.AudioSupport.unsupported,
          core.AudioSupport.permissionDenied,
        ]) {
          final tab = RecorderTab(
            w,
            engine: FakeRecorderEngine()..support = support,
          );
          expect(
            () => tab.wait(
              tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
            ),
            throwsUnsupportedError,
          );
          expect(tab.service.status, const core.RecorderStatus());
          expect(tab.log.calls, isNot(contains('begin')));
          expect(tab.engine.count('start'), 0);
          expect(tab.wait(tab.service.checkSupport()), support);
        }
      },
    );

    fakeTest(
      'engine start fails → lock released, draft discarded, idle + error, rethrown',
      (w) {
        for (final failing in [true, false]) {
          final locks = FakeWebLocks();
          final tab = RecorderTab(w, locks: locks);
          final error = StateError('NotAllowedError');
          if (failing) {
            tab.engine.startError = error;
          } else {
            tab.engine.failInsteadOfStarted = error;
          }
          Object? thrown;
          try {
            tab.wait(
              tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
            );
          } on Object catch (e) {
            thrown = e;
          }
          expect(thrown, isNotNull);
          expect(tab.service.status.phase, core.RecorderPhase.idle);
          expect(tab.service.status.error, isNotNull);
          expect(tab.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
          expect(locks.held, isEmpty);
          expect(locks.log.first, startsWith('acquire noteapp-rec-'));
          expect(locks.log.last, startsWith('release noteapp-rec-'));
          expect(tab.log.only({'begin', 'discard'}), ['begin', 'discard']);
          expect(tab.service.offsetNowMs(), isNull);
        }
      },
    );

    fakeTest(
      'a second draft for the same recording id → start fails before the engine',
      (w) {
        final tab = RecorderTab(w);
        final id = w.recordingId();
        w.wait(
          w.store.recordingDrafts.begin(
            recordingId: id,
            noteId: w.noteId,
            mimeType: 'audio/webm',
            startedAt: 0,
          ),
        );
        expect(
          () => tab.wait(tab.service.start(recordingId: id, noteId: w.noteId)),
          throwsStateError,
        );
        expect(tab.engine.count('start'), 0);
        expect(tab.service.status.phase, core.RecorderPhase.idle);
      },
    );

    fakeTest('a hidden tab pauses (interrupted, hiddenTab); resume is refused while hidden; the '
        'user resume afterwards clears it', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      tab.record(const Duration(seconds: 1));
      tab.session.systemPause(MediaErrorCode.hiddenTab);
      w.async.elapse(Duration.zero);
      expect(tab.service.status.phase, core.RecorderPhase.paused);
      expect(tab.service.status.interrupted, isTrue);
      expect(
        (tab.service.status.error! as MediaIoException).code,
        MediaErrorCode.hiddenTab,
      );
      tab.session.hidden = true;
      expect(() => tab.wait(tab.service.resume()), throwsStateError);
      expect(tab.service.status.phase, core.RecorderPhase.paused);
      tab.session.hidden = false;
      tab.wait(tab.service.resume());
      expect(tab.service.status.phase, core.RecorderPhase.recording);
      expect(tab.service.status.interrupted, isFalse);
      expect(tab.service.status.error, isNull);
      tab.wait(tab.service.cancel());
    });

    fakeTest('a draft append failure → status.error storageFailed while recording goes on; the '
        'retry clears it', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      tab.drafts.appendErrors.add(Exception('blob write'));
      tab.record(const Duration(seconds: 1));
      expect(tab.service.status.phase, core.RecorderPhase.recording);
      expect(
        (tab.service.status.error! as MediaIoException).code,
        MediaErrorCode.storageFailed,
      );
      tab.record(
        const Duration(seconds: 1),
      ); // the next chunk writes the unsaved one first
      expect(tab.service.status.error, isNull);
      expect(tab.drafts.appends.map((a) => a.bytes), [64, 64]);
      tab.wait(tab.service.cancel());
    });
  });

  group('stop (6.6.3)', () {
    fakeTest(
      'M-1: put → createRecording → discard, then the lock goes; one recording row',
      (w) {
        final locks = FakeWebLocks();
        final tab = RecorderTab(w, locks: locks);
        final id = w.recordingId();
        tab.start(id);
        final draftId = tab
            .wait(w.store.recordingDrafts.listDrafts())
            .single
            .draftId;
        expect(locks.held, {recordingLockName(draftId)});
        final rec = recordChunksAndStop(tab, twoSecondWebm())!;
        expect(tab.log.only(m1), ['put', 'createRecording', 'discard']);
        expect(locks.held, isEmpty);
        expect(locks.log.last, 'release ${recordingLockName(draftId)}');
        expect(rec.id, id);
        expect(rec.noteId, w.noteId);
        expect(rec.title, isNull);
        expect(tab.wait(w.store.recordings.recordingsOf(w.noteId)), [rec]);
        expect(tab.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
        final asset = tab.wait(w.store.assets.getAsset(rec.assetId))!;
        expect(asset.type, core.AssetType.audio);
        expect(asset.mimeType, 'audio/webm;codecs=opus');
        expect(
          asset.fileName,
          recordingFileName(rec.startedAt, asset.mimeType),
        );
        expect(asset.fileName, endsWith('.webm'));
        expect(tab.ledger.count, 0);
      },
    );

    fakeTest('durationMs = the file timeline (last block 1980 + 60 ms), not the clock (2000); the '
        'stored WebM carries Info > Duration', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      final chunks = twoSecondWebm();
      final rec = recordChunksAndStop(tab, chunks)!;
      expect(rec.durationMs, 2040);
      final stored = tab.wait(w.store.assets.readBytes(rec.assetId))!;
      final original = joined(chunks);
      expect(
        stored,
        applyPatch(original, WebmTimeline.patchedHead(original, 2040)!),
      );
      expect(WebmTimeline.measure(stored)!.endMs, 2040);
      final last = tab.service.diagnostics.lastRecording!;
      expect(last.source, DurationSource.webm);
      expect(last.clockMs, 2000);
      expect(last.durationMs, 2040);
      expect(last.patched, isTrue);
    });

    fakeTest(
      'not WebM-parsable bytes → the clock length (src clock), no patch',
      (w) {
        final tab = RecorderTab(w);
        tab.start(w.recordingId());
        tab.record(const Duration(seconds: 3));
        final rec = tab.wait(tab.service.stop())!;
        expect(rec.durationMs, 3000);
        expect(
          tab.service.diagnostics.lastRecording!.source,
          DurationSource.clock,
        );
        expect(tab.service.diagnostics.lastRecording!.patched, isFalse);
        expect(tab.assets.putBytes.single.length, 3 * 64);
      },
    );

    fakeTest('the last chunk from the engine stop is in the recording', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      final chunks = twoSecondWebm();
      w.async.elapse(const Duration(seconds: 2));
      tab.session.chunk(chunks.first);
      tab.session.stopChunks.add(chunks.last); // the last dataavailable
      final rec = tab.wait(tab.service.stop())!;
      expect(rec.durationMs, 2040);
    });

    fakeTest('unsaved chunks: written by drain → not joined; still unsaved → joined after '
        'readAll', (w) {
      // drain wrote it: the bytes are exactly the draft (+ nothing)
      final a = RecorderTab(w);
      a.start(w.recordingId());
      a.drafts.appendErrors.add(Exception('blob write'));
      a.record(
        const Duration(seconds: 2),
      ); // chunk 1 fails, chunk 2 writes both
      expect(a.wait(a.service.stop()), isNotNull);
      expect(a.assets.putBytes.single.length, 2 * 64);

      // drain could not write it: readAll + the unsaved chunk
      final b = RecorderTab(w);
      b.start(w.recordingId());
      b.record(const Duration(seconds: 1));
      b.drafts.appendErrors.addAll([
        Exception('blob'),
        Exception('blob again'),
      ]);
      w.async.elapse(const Duration(seconds: 1));
      b.session.chunk(Uint8List.fromList(List.filled(10, 7)));
      w.async.elapse(Duration.zero);
      final rec = b.wait(b.service.stop())!;
      final put = b.assets.putBytes.single;
      expect(put.length, 64 + 10);
      expect(put.sublist(64), List.filled(10, 7));
      expect(rec.durationMs, 2000);
      expect(b.ledger.count, 0);
      expect(b.ledger.peakCount, lessThanOrEqualTo(2));
    });

    fakeTest('clock 0 → the draft is discarded, null, nothing stored', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      expect(tab.wait(tab.service.stop()), isNull);
      expect(tab.log.only(m1), ['discard']);
      expect(tab.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
      expect(tab.service.status, const core.RecorderStatus());
    });

    for (final where in ['put', 'createRecording', 'readAll']) {
      fakeTest(
        'save failure ($where) → the draft stays, idle + saveFailed, MediaIoException thrown, '
        'ledger back to 0; a later recovery stores it with the same id',
        (w) {
          final locks = FakeWebLocks();
          final tab = RecorderTab(w, locks: locks);
          final id = w.recordingId();
          tab.start(id);
          final boom = Exception('disk full');
          switch (where) {
            case 'put':
              tab.assets.putErrors.add(boom);
            case 'createRecording':
              tab.recordings.createErrors.add(boom);
            default:
              tab.drafts.readAllError = boom;
          }
          MediaIoException? thrown;
          try {
            recordChunksAndStop(tab, twoSecondWebm());
          } on MediaIoException catch (e) {
            thrown = e;
          }
          expect(thrown!.code, MediaErrorCode.saveFailed);
          expect(thrown.cause, boom);
          expect(tab.service.status.phase, core.RecorderPhase.idle);
          expect(
            (tab.service.status.error! as MediaIoException).code,
            MediaErrorCode.saveFailed,
          );
          expect(tab.service.diagnostics.lastSaveFailed, boom);
          expect(tab.ledger.count, 0);
          final drafts = tab.wait(w.store.recordingDrafts.listDrafts());
          expect(drafts.single.recordingId, id);
          expect(tab.log.calls, isNot(contains('discard')));
          // the lock stays with this page until dispose (the next start-up recovers)
          expect(locks.held, {recordingLockName(drafts.single.draftId)});
          expect(tab.wait(tab.service.pendingDrafts()), isEmpty);
          tab.wait(tab.service.dispose());
          expect(locks.held, isEmpty);

          w.async.elapse(const Duration(seconds: 11));
          final next = RecorderTab(w, locks: locks);
          final rec = next.wait(
            next.service.recoverDraft(drafts.single.draftId),
          )!;
          expect(rec.id, id);
          expect(rec.durationMs, 2040);
          expect(next.wait(w.store.recordings.recordingsOf(w.noteId)), [rec]);
        },
      );
    }

    fakeTest(
      'cancel → engine cancel, draft discarded, lock released, no recording row',
      (w) {
        final locks = FakeWebLocks();
        final tab = RecorderTab(w, locks: locks);
        tab.start(w.recordingId());
        tab.record(const Duration(seconds: 2));
        tab.wait(tab.service.cancel());
        expect(tab.engine.count('cancel'), 1);
        expect(tab.engine.count('stop'), 0);
        expect(tab.service.status, const core.RecorderStatus());
        expect(tab.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
        expect(tab.wait(w.store.recordings.recordingsOf(w.noteId)), isEmpty);
        expect(tab.log.only(m1), ['discard']);
        expect(locks.held, isEmpty);
        expect(tab.service.offsetNowMs(), isNull);
      },
    );

    group('stop() while busy (수정 2회차)', () {
      fakeTest(
        'in starting: waits for the start, then stops — clock 0 → null, draft discarded',
        (w) {
          final tab = RecorderTab(w);
          tab.engine.startGate = Completer<void>();
          final start = tab.service.start(
            recordingId: w.recordingId(),
            noteId: w.noteId,
          );
          final stop = tab.service.stop();
          w.async.elapse(Duration.zero);
          expect(tab.service.status.phase, core.RecorderPhase.starting);
          tab.engine.startGate!.complete();
          tab.wait(start);
          expect(tab.wait(stop), isNull);
          expect(tab.engine.count('stop'), 1);
          expect(tab.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
          expect(tab.service.status.phase, core.RecorderPhase.idle);
        },
      );

      fakeTest('in starting: the start goes on, 1 s passes while the engine stops → one '
          'recording', (w) {
        final tab = RecorderTab(w);
        tab.engine
          ..startGate = Completer<void>()
          ..stopGate = Completer<void>();
        final start = tab.service.start(
          recordingId: w.recordingId(),
          noteId: w.noteId,
        );
        final stop = tab.service.stop();
        w.async.elapse(Duration.zero);
        tab.engine.startGate!.complete();
        tab.wait(start);
        expect(tab.service.status.phase, core.RecorderPhase.finishing);
        tab.session.stopChunks.add(Uint8List(100)); // the last dataavailable
        w.async.elapse(const Duration(seconds: 1));
        tab.engine.stopGate!.complete();
        final rec = tab.wait(stop)!;
        expect(rec.durationMs, 1000);
        expect(tab.engine.count('stop'), 1);
        expect(tab.wait(w.store.recordings.recordingsOf(w.noteId)), [rec]);
      });

      fakeTest('in starting, the start fails → null, no engine stop', (w) {
        final tab = RecorderTab(w);
        tab.engine
          ..startGate = Completer<void>()
          ..startError = StateError('NotReadableError');
        final start = tab.service.start(
          recordingId: w.recordingId(),
          noteId: w.noteId,
        );
        final stop = tab.service.stop();
        tab.engine.startGate!.complete();
        expect(() => tab.wait(start), throwsStateError);
        expect(tab.wait(stop), isNull);
        expect(tab.engine.count('stop'), 0);
        expect(tab.engine.count('cancel'), 0);
      });

      fakeTest('two stop() in finishing → the same recording, put once', (w) {
        final tab = RecorderTab(w);
        tab.start(w.recordingId());
        tab.record(const Duration(seconds: 1));
        tab.session.stopGate = Completer<void>();
        final a = tab.service.stop();
        w.async.elapse(Duration.zero);
        expect(tab.service.status.phase, core.RecorderPhase.finishing);
        final b = tab.service.stop();
        tab.session.stopGate!.complete();
        final ra = tab.wait(a), rb = tab.wait(b);
        expect(ra, isNotNull);
        expect(rb, same(ra));
        expect(tab.log.only({'put'}), ['put']);
        expect(tab.engine.count('stop'), 1);
      });

      fakeTest('two stop() in starting → one engine stop', (w) {
        final tab = RecorderTab(w);
        tab.engine.startGate = Completer<void>();
        final start = tab.service.start(
          recordingId: w.recordingId(),
          noteId: w.noteId,
        );
        final a = tab.service.stop();
        final b = tab.service.stop();
        tab.engine.startGate!.complete();
        tab.wait(start);
        expect(tab.wait(a), isNull);
        expect(tab.wait(b), isNull);
        expect(tab.engine.count('stop'), 1);
      });
    });
  });

  group('media.bitRate (4.6)', () {
    int requested(RecorderWorld w, RecorderTab tab) {
      tab.start(w.recordingId());
      final r = tab.engine.requests.last.bitRate;
      tab.wait(tab.service.cancel());
      return r;
    }

    fakeTest('96000 → the engine is asked for 96000 (source: setting)', (w) {
      w.wait(w.store.settings.set(MediaSettingKeys.bitRate, 96000));
      final tab = RecorderTab(w);
      expect(requested(w, tab), 96000);
      expect(tab.service.diagnostics.lastBitRateSource, BitRateSource.setting);
      // read together with begin (one start, one settings read)
      expect(tab.log.only({'begin', 'settings.get'}).toSet(), {
        'begin',
        'settings.get',
      });
    });

    fakeTest(
      '0 → config.bitRate; out of range → config.bitRate (setting ignored)',
      (w) {
        final tab = RecorderTab(w, config: const MediaIoConfig(bitRate: 48000));
        expect(requested(w, tab), 48000);
        expect(tab.service.diagnostics.lastBitRateSource, BitRateSource.config);
        for (final bad in [20000, 128001, -1]) {
          w.wait(w.store.settings.set(MediaSettingKeys.bitRate, bad));
          expect(requested(w, tab), 48000);
          expect(
            tab.service.diagnostics.lastBitRateSource,
            BitRateSource.settingIgnored,
          );
        }
        for (final edge in [32000, 128000]) {
          w.wait(w.store.settings.set(MediaSettingKeys.bitRate, edge));
          expect(requested(w, tab), edge);
        }
      },
    );

    fakeTest('changed while recording → from the next recording', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      expect(tab.engine.requests.last.bitRate, 64000);
      w.wait(w.store.settings.set(MediaSettingKeys.bitRate, 96000));
      tab.record(const Duration(seconds: 1));
      tab.wait(tab.service.stop());
      expect(tab.engine.requests.single.bitRate, 64000);
      expect(requested(w, tab), 96000);
    });

    fakeTest('a failed settings read → config.bitRate, the recording starts', (
      w,
    ) {
      final tab = RecorderTab(w);
      tab.settings.failingKeys.add(MediaSettingKeys.bitRate.name);
      expect(requested(w, tab), 64000);
    });
  });

  group('two services on one store (6.10.2)', () {
    fakeTest(
      'A records → B leaves it out; A paused 15 s → still out (empty chunks); A frozen → '
      '10 s later B has it → B recovers → A\'s next append is refused → A idle + draftLost',
      (w) {
        final a = RecorderTab(w);
        final b = RecorderTab(w);
        final id = w.recordingId();
        a.start(id);
        a.record(const Duration(seconds: 3));
        expect(b.wait(b.service.pendingDrafts()), isEmpty);
        a.wait(a.service.pause());
        w.async.elapse(const Duration(seconds: 15));
        expect(b.wait(b.service.pendingDrafts()), isEmpty);
        expect(
          a.drafts.appends.where((x) => x.bytes == 0).length,
          greaterThanOrEqualTo(14),
        );
        // A freezes (its writes stop reaching the store)
        a.drafts.appendGate = Completer<void>();
        w.async.elapse(const Duration(seconds: 9));
        expect(b.wait(b.service.pendingDrafts()), isEmpty);
        w.async.elapse(const Duration(seconds: 2));
        final pending = b.wait(b.service.pendingDrafts());
        expect(pending.single.recordingId, id);
        final rec = b.wait(b.service.recoverDraft(pending.single.draftId))!;
        expect(rec.id, id);
        expect(rec.title, MediaTuning.recoveredTitle);
        expect(rec.durationMs, 3000); // zeros: the draft's activeMs
        // A wakes up: the held keep-alive append reaches a discarded draft
        a.drafts.openAppends();
        w.async.elapse(Duration.zero);
        expect(a.service.status.phase, core.RecorderPhase.idle);
        expect(a.service.status.interrupted, isTrue);
        expect(
          (a.service.status.error! as MediaIoException).code,
          MediaErrorCode.draftLost,
        );
        expect(a.engine.count('cancel'), 1);
        expect(a.service.offsetNowMs(), isNull);
        expect(a.wait(a.service.stop()), isNull);
        expect(b.wait(w.store.recordings.recordingsOf(w.noteId)), [rec]);
      },
    );

    fakeTest(
      'a Web Lock held by another context leaves the draft out at any age',
      (w) {
        final locks = FakeWebLocks();
        final a = RecorderTab(w, locks: locks);
        a.start(w.recordingId());
        a.record(const Duration(seconds: 2));
        final draftId = a
            .wait(w.store.recordingDrafts.listDrafts())
            .single
            .draftId;
        a.wait(a.service.dispose()); // lets its lock go
        expect(locks.held, isEmpty);
        w.async.elapse(const Duration(seconds: 30));
        locks.others.add(recordingLockName(draftId)); // another tab holds it
        final b = RecorderTab(w, locks: locks);
        expect(b.wait(b.service.pendingDrafts()), isEmpty);
        expect(() => b.wait(b.service.recoverDraft(draftId)), throwsStateError);
        locks.others.clear();
        expect(b.wait(b.service.pendingDrafts()).single.draftId, draftId);
        expect(b.wait(b.service.recoverDraft(draftId)), isNotNull);
      },
    );

    fakeTest('the own session is left out while starting … finishing', (w) {
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      tab.record(const Duration(seconds: 1));
      tab.wait(tab.service.pause());
      w.async.elapse(const Duration(seconds: 30));
      tab.drafts.appendGate =
          Completer<void>(); // even when not updated for long
      w.async.elapse(const Duration(seconds: 30));
      final drafts = tab.wait(w.store.recordingDrafts.listDrafts());
      expect(tab.wait(tab.service.pendingDrafts()), isEmpty);
      expect(
        () => tab.wait(tab.service.recoverDraft(drafts.single.draftId)),
        throwsStateError,
      );
      tab.drafts.openAppends();
      tab.wait(tab.service.cancel());
    });
  });

  group('recovery (6.10)', () {
    /// A records [seconds] of WebM-free zeros and is disposed; 11 s later the draft is due.
    String leftDraft(RecorderWorld w, {int seconds = 2, core.RecordingId? id}) {
      final a = RecorderTab(w);
      a.start(id ?? w.recordingId());
      a.record(Duration(seconds: seconds));
      a.wait(a.service.dispose());
      w.async.elapse(const Duration(seconds: 11));
      return a.wait(w.store.recordingDrafts.listDrafts()).last.draftId;
    }

    fakeTest(
      "recoverDraft: title '복구된 녹음', the original id and startedAt, the draft and its "
      'attempts go; calling it again gives null and still one recording',
      (w) {
        final id = w.recordingId();
        final a = RecorderTab(w);
        a.start(id);
        final startedAt = a
            .wait(w.store.recordingDrafts.listDrafts())
            .single
            .startedAt;
        for (final c in twoSecondWebm()) {
          w.async.elapse(const Duration(seconds: 1));
          a.session.chunk(c);
        }
        a.wait(a.service.dispose());
        expect(a.engine.count('abandon'), 1);
        w.async.elapse(const Duration(seconds: 11));
        final b = RecorderTab(w);
        final draftId = b.wait(b.service.pendingDrafts()).single.draftId;
        final rec = b.wait(b.service.recoverDraft(draftId))!;
        expect(rec.id, id);
        expect(rec.title, MediaTuning.recoveredTitle);
        expect(rec.startedAt, startedAt);
        expect(rec.durationMs, 2040);
        expect(b.log.only(m1), ['put', 'createRecording', 'discard']);
        expect(b.wait(RecoverAttempts(w.store.settings).read()), isEmpty);
        expect(b.service.diagnostics.recovered, 1);
        expect(b.wait(b.service.recoverDraft(draftId)), isNull);
        expect(b.wait(w.store.recordings.recordingsOf(w.noteId)), [rec]);
        expect(b.ledger.count, 0);
        expect(b.ledger.peakCount, lessThanOrEqualTo(2));
      },
    );

    fakeTest(
      'a recording row with the same id already there → that row, the draft goes',
      (w) {
        final id = w.recordingId();
        final draftId = leftDraft(w, id: id);
        final asset = w.wait(
          w.store.assets.put(
            Uint8List.fromList([1, 2, 3]),
            type: core.AssetType.audio,
            mimeType: 'audio/webm',
          ),
        );
        final existing = w.wait(
          w.store.recordings.createRecording(
            id: id,
            noteId: w.noteId,
            assetId: asset.id,
            durationMs: 1234,
            startedAt: 5,
          ),
        );
        final b = RecorderTab(w);
        expect(b.wait(b.service.recoverDraft(draftId)), existing);
        expect(b.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
        expect(b.wait(w.store.recordings.recordingsOf(w.noteId)), [existing]);
      },
    );

    fakeTest('an empty draft → discarded, null', (w) {
      final draft = w.wait(
        w.store.recordingDrafts.begin(
          recordingId: w.recordingId(),
          noteId: w.noteId,
          mimeType: 'audio/webm;codecs=opus',
          startedAt: 0,
        ),
      );
      w.async.elapse(const Duration(seconds: 11));
      final b = RecorderTab(w);
      expect(b.wait(b.service.pendingDrafts()).single.draftId, draft.draftId);
      expect(b.wait(b.service.recoverDraft(draft.draftId)), isNull);
      expect(b.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
      expect(b.log.calls, isNot(contains('put')));
      expect(b.wait(RecoverAttempts(w.store.settings).read()), isEmpty);
    });

    fakeTest('an unknown draft id → null', (w) {
      final b = RecorderTab(w);
      expect(b.wait(b.service.recoverDraft('nope')), isNull);
    });

    fakeTest('the attempt is written before trying; another failure keeps the draft and the attempt '
        'and rethrows; two attempts → out of pendingDrafts, a direct call → StateError; '
        '[다시 시도] (reset) brings it back', (w) {
      final draftId = leftDraft(w);
      final b = RecorderTab(w);
      final attempts = RecoverAttempts(w.store.settings);
      final boom = Exception('io');
      b.assets.putErrors.addAll([boom, boom]);
      for (var n = 1; n <= 2; n++) {
        expect(b.wait(b.service.pendingDrafts()).map((d) => d.draftId), [
          draftId,
        ]);
        expect(() => b.wait(b.service.recoverDraft(draftId)), throwsA(boom));
        expect(b.wait(attempts.of(draftId)), n);
        expect(b.wait(w.store.recordingDrafts.listDrafts()), hasLength(1));
        expect(b.ledger.count, 0);
      }
      expect(b.wait(b.service.pendingDrafts()), isEmpty);
      expect(b.wait(b.service.stuckDrafts()).single.draftId, draftId);
      expect(() => b.wait(b.service.recoverDraft(draftId)), throwsStateError);
      b.wait(attempts.reset(draftId));
      expect(b.wait(b.service.pendingDrafts()).single.draftId, draftId);
      expect(b.wait(b.service.recoverDraft(draftId)), isNotNull);
      expect(b.wait(attempts.read()), isEmpty);
    });

    fakeTest('the attempt entries of drafts that no longer exist are dropped', (
      w,
    ) {
      final attempts = RecoverAttempts(w.store.settings);
      w.wait(attempts.increment('gone'));
      final b = RecorderTab(w);
      b.wait(b.service.pendingDrafts());
      expect(b.wait(attempts.read()), isEmpty);
    });

    fakeTest('note missing or purged (EntityNotFoundException) → permanent failure: draft and '
        'attempts cleaned, null', (w) {
      // a draft of a note that is gone (a valid id the store does not have)
      final draft = w.wait(
        w.store.recordingDrafts.begin(
          recordingId: w.recordingId(),
          noteId: w.store.ids.newId(),
          mimeType: 'audio/webm;codecs=opus',
          startedAt: 0,
        ),
      );
      w.wait(
        w.store.recordingDrafts.append(
          draft.draftId,
          Uint8List(32),
          activeMs: 1000,
        ),
      );
      w.async.elapse(const Duration(seconds: 11));
      final b = RecorderTab(w);
      expect(b.wait(b.service.recoverDraft(draft.draftId)), isNull);
      expect(b.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
      expect(b.wait(RecoverAttempts(w.store.settings).read()), isEmpty);
      expect(b.service.diagnostics.dropped, 1);
      expect(b.ledger.count, 0);
    });

    fakeTest('a recent draft is left out; a direct call → StateError', (w) {
      final draft = w.wait(
        w.store.recordingDrafts.begin(
          recordingId: w.recordingId(),
          noteId: w.noteId,
          mimeType: 'audio/webm',
          startedAt: 0,
        ),
      );
      w.async.elapse(const Duration(seconds: 9));
      final b = RecorderTab(w);
      expect(b.wait(b.service.pendingDrafts()), isEmpty);
      expect(
        () => b.wait(b.service.recoverDraft(draft.draftId)),
        throwsStateError,
      );
      // the window follows webDraftChunkMs: 5 × 3 s = 15 s
      w.async.elapse(const Duration(seconds: 2));
      expect(b.wait(b.service.pendingDrafts()), hasLength(1));
      final slow = RecorderTab(
        w,
        config: const MediaIoConfig(webDraftChunkMs: 3000),
      );
      expect(slow.wait(slow.service.pendingDrafts()), isEmpty);
      w.async.elapse(const Duration(seconds: 4));
      expect(slow.wait(slow.service.pendingDrafts()), hasLength(1));
    });

    group('native (6.9.5)', () {
      FakeRecorderEngine native() =>
          FakeRecorderEngine(writesDraftChunks: false);

      fakeTest('stop: the draft is a row only (no append); bytes = the file, length = the probe; '
          'the file goes after the save', (w) {
        final tab = RecorderTab(w, engine: native());
        tab.start(w.recordingId());
        final file = tab.session.file!
          ..bytes = Uint8List.fromList(List.filled(500, 1))
          ..probeMs = 2987;
        tab.record(const Duration(seconds: 3));
        final rec = tab.wait(tab.service.stop())!;
        expect(rec.durationMs, 2987);
        expect(
          tab.service.diagnostics.lastRecording!.source,
          DurationSource.probe,
        );
        expect(tab.log.calls, isNot(contains('append')));
        expect(tab.log.calls, isNot(contains('readAll')));
        expect(tab.log.only(m1), ['put', 'createRecording', 'discard']);
        expect(file.deleted, isTrue);
        expect(tab.assets.putBytes.single.length, 500);
        final asset = tab.wait(w.store.assets.getAsset(rec.assetId))!;
        expect(asset.mimeType, 'audio/mp4');
        expect(asset.fileName, endsWith('.m4a'));
        // the probe failing → the clock
        final again = RecorderTab(w, engine: native());
        again.start(w.recordingId());
        again.session.file!.bytes = Uint8List(10);
        again.record(const Duration(seconds: 2));
        expect(again.wait(again.service.stop())!.durationMs, 2000);
      });

      fakeTest('recovery: the leftover file with a probe length → recording; unreadable or '
          'missing file → dropped (file and draft gone)', (w) {
        final engine = native();
        final b = RecorderTab(w, engine: engine);
        core.RecordingDraft row() => w.wait(
          w.store.recordingDrafts.begin(
            recordingId: w.recordingId(),
            noteId: w.noteId,
            mimeType: 'audio/mp4',
            startedAt: 0,
          ),
        );
        final ok = row(), broken = row(), missing = row();
        engine.files[ok.recordingId] = FakeEngineFile(
          bytes: Uint8List(400),
          probeMs: 4100,
        );
        final brokenFile = engine.files[broken.recordingId] = FakeEngineFile(
          bytes: Uint8List(400),
        );
        w.async.elapse(const Duration(seconds: 11));
        expect(b.wait(b.service.pendingDrafts()), hasLength(3));
        final rec = b.wait(b.service.recoverDraft(ok.draftId))!;
        expect(rec.durationMs, 4100);
        expect(rec.title, MediaTuning.recoveredTitle);
        expect(engine.files[ok.recordingId]!.deleted, isTrue);
        expect(b.wait(b.service.recoverDraft(broken.draftId)), isNull);
        expect(brokenFile.deleted, isTrue);
        expect(b.wait(b.service.recoverDraft(missing.draftId)), isNull);
        expect(b.wait(w.store.recordingDrafts.listDrafts()), isEmpty);
        expect(b.service.diagnostics.recovered, 1);
        expect(b.service.diagnostics.dropped, 2);
      });

      fakeTest(
        'the first pendingDrafts deletes recording files without a draft',
        (w) {
          final engine = native();
          final b = RecorderTab(w, engine: engine);
          final kept = w.wait(
            w.store.recordingDrafts.begin(
              recordingId: w.recordingId(),
              noteId: w.noteId,
              mimeType: 'audio/mp4',
              startedAt: 0,
            ),
          );
          engine.files[kept.recordingId] = FakeEngineFile();
          engine.files['orphan'] = FakeEngineFile();
          b.wait(b.service.pendingDrafts());
          expect(engine.orphanKeep, {kept.recordingId});
          expect(engine.files.keys, [kept.recordingId]);
          b.wait(b.service.pendingDrafts());
          expect(engine.count('deleteOrphanFiles'), 1);
        },
      );
    });
  });

  group('dispose (4.2.3)', () {
    fakeTest('while recording: not finished — the last chunk is written, the lock is let go, '
        'the draft stays for the next launch', (w) {
      final locks = FakeWebLocks();
      final tab = RecorderTab(w, locks: locks);
      final id = w.recordingId();
      tab.start(id);
      tab.record(const Duration(seconds: 2));
      tab.session.abandonChunks.add(Uint8List(5));
      tab.wait(tab.service.dispose());
      expect(tab.engine.count('abandon'), 1);
      expect(tab.engine.count('stop'), 0);
      expect(tab.engine.count('cancel'), 0);
      expect(tab.engine.disposed, isTrue);
      expect(locks.held, isEmpty);
      final draft = tab.wait(w.store.recordingDrafts.listDrafts()).single;
      expect(draft.recordingId, id);
      expect(draft.bytes, 2 * 64 + 5);
      expect(tab.log.only(m1), isEmpty);
      tab.wait(tab.service.dispose()); // twice is fine
      expect(tab.wait(tab.service.pendingDrafts()), isEmpty);
      expect(
        () => tab.wait(
          tab.service.start(recordingId: w.recordingId(), noteId: w.noteId),
        ),
        throwsStateError,
      );
    });

    fakeTest('in idle: only the engine goes', (w) {
      final tab = RecorderTab(w);
      tab.wait(tab.service.dispose());
      expect(tab.engine.calls, ['dispose']);
    });
  });
}
