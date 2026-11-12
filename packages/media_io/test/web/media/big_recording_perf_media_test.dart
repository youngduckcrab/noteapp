@Tags(['media'])
@TestOn('browser')
library;

// The 3-hour recording in Chrome (m5-7/06-pdf 6.6.5 · 6.17 · 9.5; 8.2 T41 — P-B, D19): an 86 MB
// synthetic WebM draft (test/support/webm_builder.dart — 360 Clusters × 500 Opus blocks 60 ms
// apart, the size of 3 h at 64 kbit/s) written through the recorder service's DraftWriter in
// 1 MiB chunks, then (a) stopped and (b) left by a closed tab and recovered by a second service.
// Both paths keep at most two full-size buffers at once (BufferLedger peakCount ≤ 2 — M-4), end
// with nothing held, store the patched file (Info > Duration = the timeline) and print the time
// and, where Chrome has it, performance.memory (progress log, B-13). No microphone: the engine is
// test/support/fake_engines.dart FakeRecorderEngine (web-like chunks); the recording clock is a
// FakeStopwatch moved by hand (3 h of active time), the services' wall clock is shifted by hand
// past the 10 s recent-update window for the recovery.
//
// `media` tag (`ws test --package media_io --platform chrome --run-skipped -t media` — the heavy
// test lock): CORE's REAL web store (openWebTestNoteStore) and CORE's fake store (media_world.dart
// mediaStoreTest).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/media_io.dart';
import 'package:media_io/src/record/buffer_ledger.dart';
import 'package:media_io/src/record/recorder_service.dart';
import 'package:media_io/src/record/recording_output.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:note_core/note_core.dart' as core;

import '../../support/fake_engines.dart';
import '../../support/fake_stopwatch.dart';
import '../../support/webm_builder.dart';
import 'media_world.dart';

const int _clusters = 360; // × 30 s = 3 h
const int _blocksPerCluster = 500; // 60 ms apart
const int _filler =
    472; // bytes per Opus packet after the TOC — ≈ 86.4 MB in all
const int _chunk = 1024 * 1024;

/// ≈ 86 MB, 3 hours. The 500 blocks have relative timecodes, so every Cluster reuses them.
Uint8List threeHourWebm() {
  final oneCluster = blocks(_blocksPerCluster, filler: _filler);
  return webmFile(
    clusters: [
      for (var c = 0; c < _clusters; c++) cluster(c * 30000, oneCluster),
    ],
  );
}

/// The draft store with an append counter (the test feeds the next chunk after the last one is
/// durable, as the 1-second timeslice does in a real recording).
final class _CountingDrafts implements core.RecordingDraftStore {
  _CountingDrafts(this.inner);
  final core.RecordingDraftStore inner;
  int appends = 0;

  @override
  Future<core.RecordingDraft> begin({
    required core.RecordingId recordingId,
    required core.NoteId noteId,
    required String mimeType,
    required core.EpochMillis startedAt,
  }) => inner.begin(
    recordingId: recordingId,
    noteId: noteId,
    mimeType: mimeType,
    startedAt: startedAt,
  );

  @override
  Future<void> append(
    String draftId,
    Uint8List chunk, {
    required int activeMs,
  }) async {
    await inner.append(draftId, chunk, activeMs: activeMs);
    appends++;
  }

  @override
  Future<List<core.RecordingDraft>> listDrafts() => inner.listDrafts();

  @override
  Future<Uint8List> readAll(String draftId) => inner.readAll(draftId);

  @override
  Future<void> discard(String draftId) => inner.discard(draftId);
}

/// One recorder service (one tab) on [store].
final class _Tab {
  _Tab(core.NoteStore store, this.clock)
    : drafts = _CountingDrafts(store.recordingDrafts) {
    service = MediaRecorderService(
      stores: () => RecorderStores(
        drafts: drafts,
        assets: store.assets,
        recordings: store.recordings,
        settings: store.settings,
      ),
      now: () => DateTime.now().add(clock.shift),
      config: const MediaIoConfig(),
      engine: engine,
      stopwatch: () => FakeStopwatch(() => clock.active),
      ledger: ledger,
    );
  }

  final _Clock clock;
  final _CountingDrafts drafts;
  final FakeRecorderEngine engine = FakeRecorderEngine();
  final BufferLedger ledger = BufferLedger();
  late final MediaRecorderService service;

  /// start → [file] in 1 MiB chunks (3 h of active time) — each one durable before the next.
  Future<void> record(
    core.NoteStore store,
    core.NoteId noteId,
    Uint8List file,
  ) async {
    await service.start(recordingId: store.ids.newId(), noteId: noteId);
    final chunks = (file.length + _chunk - 1) ~/ _chunk;
    for (var i = 0; i < chunks; i++) {
      final end = (i + 1) * _chunk < file.length
          ? (i + 1) * _chunk
          : file.length;
      clock.active += Duration(milliseconds: 10800000 ~/ chunks);
      engine.session!.chunk(Uint8List.sublistView(file, i * _chunk, end));
      await until(() => drafts.appends == i + 1, 'chunk $i durable');
    }
  }
}

final class _Clock {
  Duration active = Duration.zero;
  Duration shift = Duration.zero;
}

/// performance.memory.usedJSHeapSize in MB where Chrome has it ('n/a' otherwise).
String _heapMb() {
  final memory = (globalContext['performance'] as JSObject?)?['memory'];
  if (memory == null || memory.isUndefinedOrNull) return 'n/a';
  final used = (memory as JSObject)['usedJSHeapSize'].dartify();
  return used is num ? (used / (1024 * 1024)).toStringAsFixed(0) : 'n/a';
}

void main() {
  late Uint8List file;
  late int endMs;

  setUpAll(() {
    final watch = Stopwatch()..start();
    file = threeHourWebm();
    endMs = WebmTimeline.measure(file)!.endMs;
    // ignore: avoid_print
    print(
      'big recording: sample ${file.length} B, ends at $endMs ms, built in '
      '${watch.elapsedMilliseconds} ms, heap ${_heapMb()} MB',
    );
  });

  test('the sample: ≈ 86 MB, ends at 3 h', () {
    expect(file.length, inInclusiveRange(80000000, 92000000));
    expect(endMs, (_clusters - 1) * 30000 + (_blocksPerCluster - 1) * 60 + 60);
  });

  mediaStoreTest(
    '86 MB draft: stop → peakCount ≤ 2, nothing held after, patched file stored',
    (stores) async {
      final store = await stores.open();
      try {
        final note = await store.library.createNote(title: 'big recording');
        final tab = _Tab(store, _Clock());
        await tab.record(store, note.id, file);

        final watch = Stopwatch()..start();
        final rec = (await tab.service.stop())!;
        watch.stop();
        // ignore: avoid_print
        print(
          'big recording (${stores.label}): stop → Recording in '
          '${watch.elapsedMilliseconds} ms, ledger peak ${tab.ledger.peakCount} × '
          '${tab.ledger.peakBytes} B, heap ${_heapMb()} MB',
        );
        expect(tab.ledger.peakCount, lessThanOrEqualTo(2));
        expect(tab.ledger.count, 0);
        expect(tab.ledger.bytes, 0);
        expect(rec.durationMs, endMs);
        final stored = (await store.assets.readBytes(rec.assetId))!;
        expect(stored.length, file.length + 11); // Info > Duration (float64)
        expect(WebmTimeline.measure(stored)!.endMs, endMs);
        expect(await store.recordingDrafts.listDrafts(), isEmpty);
        await tab.service.dispose();
      } finally {
        await stores.close(store);
      }
    },
    prefix: 'big_stop',
  );

  mediaStoreTest(
    '86 MB draft left by a closed tab: recovery → peakCount ≤ 2, the same file',
    (stores) async {
      final store = await stores.open();
      try {
        final note = await store.library.createNote(title: 'big recovery');
        final clock = _Clock();
        final closed = _Tab(store, clock);
        await closed.record(store, note.id, file);
        await closed.service
            .dispose(); // the tab closes while recording: the draft stays
        expect(closed.ledger.peakCount, 0);

        clock.shift = const Duration(
          seconds: 11,
        ); // past the recent-update window (6.10.1)
        final other = _Tab(store, clock);
        final pending = await other.service.pendingDrafts();
        expect(pending, hasLength(1));

        final watch = Stopwatch()..start();
        final rec = (await other.service.recoverDraft(pending.single.draftId))!;
        watch.stop();
        // ignore: avoid_print
        print(
          'big recording (${stores.label}): recovery → Recording in '
          '${watch.elapsedMilliseconds} ms, ledger peak ${other.ledger.peakCount} × '
          '${other.ledger.peakBytes} B, heap ${_heapMb()} MB',
        );
        expect(other.ledger.peakCount, lessThanOrEqualTo(2));
        expect(other.ledger.count, 0);
        expect(rec.durationMs, endMs);
        final stored = (await store.assets.readBytes(rec.assetId))!;
        expect(
          stored,
          applyPatch(file, WebmTimeline.patchedHead(file, endMs)!),
        );
        expect(await store.recordingDrafts.listDrafts(), isEmpty);
        await other.service.dispose();
      } finally {
        await stores.close(store);
      }
    },
    prefix: 'big_recover',
  );
}
