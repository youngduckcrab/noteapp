// The full-size buffers of the stop and recovery paths (m5-7/06-pdf 6.6.5; M-4 '같은 녹음
// 바이트를 전체 크기로 두 벌 넘게 동시에 들지 않는다' — 8.2 T31b, P-A): a 1 MiB synthetic WebM
// draft (test/support/webm_builder.dart) through stop, recovery and a failed save. BufferLedger
// counts readAll, the unsaved join and the head patch copy: peakCount ≤ 2, nothing left after.
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_io/src/errors.dart';
import 'package:media_io/src/record/webm_timeline.dart';
import 'package:note_core/note_core.dart' as core;

import '../support/recorder_world.dart';
import '../support/webm_builder.dart';

/// About 1 MiB: 4 Clusters of 500 blocks (60 ms apart) with 512-byte packets → 2 min.
Uint8List oneMebibyteWebm() => webmFile(
  clusters: [
    for (var c = 0; c < 4; c++) cluster(c * 30000, blocks(500, filler: 512)),
  ],
);

/// [file] in 64 KiB chunks.
List<Uint8List> chunksOf(Uint8List file, {int size = 64 * 1024}) => [
  for (var o = 0; o < file.length; o += size)
    Uint8List.sublistView(
      file,
      o,
      o + size < file.length ? o + size : file.length,
    ),
];

void main() {
  final file = oneMebibyteWebm();
  final endMs = WebmTimeline.measure(file)!.endMs;

  test('the sample: about 1 MiB, ends at 3 × 30 s + 499 × 60 ms + 60 ms', () {
    expect(file.length, greaterThan(1000 * 1024));
    expect(file.length, lessThan(1100 * 1024));
    expect(endMs, 90000 + 499 * 60 + 60);
  });

  void record(RecorderTab tab) {
    final chunks = chunksOf(file);
    for (final c in chunks) {
      tab.world.async.elapse(const Duration(seconds: 7));
      tab.session.chunk(c);
    }
    tab.world.async.elapse(Duration.zero);
  }

  test('stop: peakCount ≤ 2 (readAll + the patch copy), 0 after; the patched bytes are '
      'stored', () {
    fakeAsync((async) {
      final w = RecorderWorld(async);
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      record(tab);
      final rec = tab.wait(tab.service.stop())!;
      expect(rec.durationMs, endMs);
      expect(tab.ledger.peakCount, lessThanOrEqualTo(2));
      expect(tab.ledger.peakCount, 2); // the patch copy happened
      expect(tab.ledger.peakBytes, lessThanOrEqualTo(2 * file.length + 64));
      expect(tab.ledger.count, 0);
      expect(tab.ledger.bytes, 0);
      final stored = tab.wait(w.store.assets.readBytes(rec.assetId))!;
      expect(stored.length, file.length + 11); // Info > Duration (float64)
      expect(WebmTimeline.measure(stored)!.endMs, endMs);
      w.close();
    });
  });

  test(
    'recovery: peakCount ≤ 2, 0 after; the same bytes as a stop would store',
    () {
      fakeAsync((async) {
        final w = RecorderWorld(async);
        final a = RecorderTab(w);
        a.start(w.recordingId());
        record(a);
        a.wait(a.service.dispose()); // the tab closes while recording
        expect(a.ledger.peakCount, 0);
        async.elapse(const Duration(seconds: 11));
        final b = RecorderTab(w);
        final draftId = b.wait(b.service.pendingDrafts()).single.draftId;
        final rec = b.wait(b.service.recoverDraft(draftId))!;
        expect(rec.durationMs, endMs);
        expect(b.ledger.peakCount, lessThanOrEqualTo(2));
        expect(b.ledger.count, 0);
        final stored = b.wait(w.store.assets.readBytes(rec.assetId))!;
        expect(
          stored,
          applyPatch(file, WebmTimeline.patchedHead(file, endMs)!),
        );
        w.close();
      });
    },
  );

  test('a failed save and a failed recovery also end at 0', () {
    fakeAsync((async) {
      final w = RecorderWorld(async);
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      record(tab);
      tab.recordings.createErrors.add(Exception('commit'));
      expect(
        () => tab.wait(tab.service.stop()),
        throwsA(
          isA<MediaIoException>().having(
            (e) => e.code,
            'code',
            MediaErrorCode.saveFailed,
          ),
        ),
      );
      expect(tab.ledger.peakCount, lessThanOrEqualTo(2));
      expect(tab.ledger.count, 0);
      tab.wait(tab.service.dispose());

      async.elapse(const Duration(seconds: 11));
      final b = RecorderTab(w);
      b.assets.putErrors.add(Exception('blob'));
      final draftId = b.wait(b.service.pendingDrafts()).single.draftId;
      expect(() => b.wait(b.service.recoverDraft(draftId)), throwsException);
      expect(b.ledger.peakCount, lessThanOrEqualTo(2));
      expect(b.ledger.count, 0);
      expect(
        b.wait(w.store.recordingDrafts.listDrafts()).single.recordingId,
        isA<core.RecordingId>(),
      );
      w.close();
    });
  });

  test('unsaved chunks joined on stop: still peakCount ≤ 2', () {
    fakeAsync((async) {
      final w = RecorderWorld(async);
      final tab = RecorderTab(w);
      tab.start(w.recordingId());
      final chunks = chunksOf(file);
      for (var i = 0; i < chunks.length; i++) {
        async.elapse(const Duration(seconds: 7));
        if (i == chunks.length - 1) {
          // the last chunk cannot be written, not even by drain
          tab.drafts.appendErrors.addAll([Exception('a'), Exception('b')]);
        }
        tab.session.chunk(chunks[i]);
        async.elapse(Duration.zero);
      }
      final rec = tab.wait(tab.service.stop())!;
      expect(rec.durationMs, endMs);
      expect(tab.ledger.peakCount, lessThanOrEqualTo(2));
      expect(tab.ledger.count, 0);
      w.close();
    });
  });
}
