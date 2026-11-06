// V16 (contract 7.7.2, m5-7/06-pdf 8.2 T39 — 6.10, D13, M-2, M-4) with Chrome's fake microphone:
// the REAL mediaIoOverrides() recorder records 3 s in one container ('tab A'), a second container
// on the same store ('tab B') does not offer that draft while it is being written (6.10 ③ recent
// update, ④ its Web Lock), then tab A is closed WITHOUT dispose — what the browser does with a
// closing tab: the MediaRecorder and the tracks stop with nothing listening, and its lock goes
// (taken away with navigator.locks steal) — B still leaves the draft out (recent), the recorder
// clock (clockProvider) moves past the recent window (10 s), and a new container on the same
// store name ('the next start') finds exactly that draft in pendingDrafts() and recoverDraft()s it
// without asking: asset + Recording row, the original recordingId, title '복구된 녹음', a length of
// ≥ 2 s from the file's timeline (the last ≤ 1 s chunk may be lost), the draft gone.
//
// Runs only with `ws test --package media_io --platform chrome --run-skipped -t media` (the media
// tag skips it elsewhere; ws starts Chrome through tool/chrome-fakemedia). Store: mediaStoreTest
// (media_world.dart) — the real web store variant (the one V16 is judged on: IndexedDB + the drift
// worker, a reopened store) waits for CORE T31; the fake store variant runs now. The recorder
// clock is a FakeAsync clock moved by hand, so the recent-update window needs no real waiting.
@TestOn('browser')
@Tags(['media'])
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/platform/web_locks.dart';
import 'package:media_io/src/record/recorder_engine_browser.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:media_io/src/tuning.dart';
import 'package:media_io/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'media_world.dart';

void main() {
  // just_audio's AudioPlayer (the playback provider is not read here, but the container may).
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(registerMediaWebPlugins);

  mediaStoreTest(
    'V16: a tab closed while recording → the next start recovers the draft without asking; '
    'a second recorder leaves the draft being written out',
    prefix: 'v16',
    (stores) async {
      // the recorders' clock: moved by hand past the recent-update window
      final time = FakeAsync();
      final clock = time.getClock(DateTime.now());
      List<Override> overridesFor(core.NoteStore s) => [
        core.noteStoreProvider.overrideWithValue(s),
        core.clockProvider.overrideWithValue(clock),
        ...mediaIoOverrides(),
      ];

      var store = await stores.open();
      final tabA = ProviderContainer(overrides: overridesFor(store));
      final a =
          tabA.read(core.audioRecorderServiceProvider) as MediaRecorderService;
      ProviderContainer? tabB;
      ProviderContainer? next;
      addTearDown(() async {
        next?.dispose();
        tabB?.dispose();
        // tab A was never disposed during the test (a closed tab); clean up its timers now
        try {
          await a.dispose();
        } on Object {
          // its store may be closed already (the real store was reopened)
        }
        tabA.dispose();
        await stores.close(store);
      });

      // ① tab A records 3 s (three 1 s chunks in the draft)
      expect(
        await a.checkSupport(requestPermission: true),
        core.AudioSupport.supported,
      );
      final note = await store.library.createNote(title: 'Lecture');
      final id = store.ids.newId();
      await a.start(recordingId: id, noteId: note.id);
      expect(a.status.phase, core.RecorderPhase.recording);
      await until(() => (a.offsetNowMs() ?? 0) >= 3000, 'recording for 3 s');
      await untilAsync(() async {
        final drafts = await store.recordingDrafts.listDrafts();
        return drafts.length == 1 && drafts.single.chunkCount >= 3;
      }, 'three chunks in the draft');
      final draft = (await store.recordingDrafts.listDrafts()).single;
      expect(draft.recordingId, id);
      expect(draft.noteId, note.id);
      expect(draft.bytes, greaterThan(0));
      final lockName = recordingLockName(draft.draftId);
      expect(await heldLockNames(), contains(lockName));

      // ② tab B (same store) does not offer the draft being written
      final secondTab = tabB = ProviderContainer(
        overrides: overridesFor(store),
      );
      final b = secondTab.read(core.audioRecorderServiceProvider);
      expect(await b.pendingDrafts(), isEmpty);

      // ③ tab A closes without dispose: the capture stops with nothing listening, the lock goes
      final capture = (a.engine as BrowserRecorderEngine).lastCapture!;
      capture
        ..detach()
        ..stop()
        ..stopTracks();
      await stealLock(lockName);
      expect(await heldLockNames(), isNot(contains(lockName)));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await store.recordingDrafts.listDrafts(), hasLength(1));
      // still inside the recent-update window: B leaves it out (another tab may be writing)
      expect(await b.pendingDrafts(), isEmpty);
      secondTab.dispose();
      tabB = null;

      // ④ past the window; the same store name in a new container (the next start)
      time.elapse(
        Duration(
          milliseconds:
              MediaTuning.recentDraftWindowMs(
                const MediaIoConfig().webDraftChunkMs,
              ) +
              20000,
        ),
      );
      store = await stores.reopen(store);
      final nextStart = next = ProviderContainer(
        overrides: overridesFor(store),
      );
      final recorder = nextStart.read(
        core.audioRecorderServiceProvider,
      ) as MediaRecorderService;
      final pending = await recorder.pendingDrafts();
      expect([for (final d in pending) d.draftId], [draft.draftId]);
      expect(pending.single.recordingId, id);

      // ⑤ recovered without asking: asset + row, the original id, '복구된 녹음', ≥ 2 s
      final recovered = await recorder.recoverDraft(draft.draftId);
      expect(recovered, isNotNull);
      expect(recovered!.id, id);
      expect(recovered.noteId, note.id);
      expect(recovered.title, '복구된 녹음');
      expect(recovered.durationMs, greaterThanOrEqualTo(2000));
      final bytes = (await store.assets.readBytes(recovered.assetId))!;
      final timeline = WebmTimeline.measure(bytes)!;
      expect(recovered.durationMs, timeline.endMs);
      expect(webmInfoDurationMs(bytes), recovered.durationMs);
      expect(recorder.diagnostics.recovered, 1);
      expect(await store.recordings.recordingsOf(note.id), [recovered]);
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
      expect(await recorder.pendingDrafts(), isEmpty);
      // ignore: avoid_print
      print(
        'V16 (${stores.label}): recovered=${recovered.durationMs} ms '
        'draft=${draft.chunkCount} chunks ${draft.bytes} B '
        'activeMs=${draft.activeMs} ms bytes=${bytes.length}',
      );
    },
  );
}
