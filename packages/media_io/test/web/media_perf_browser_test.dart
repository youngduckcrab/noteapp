@Tags(['perf'])
@TestOn('browser')
library;

// Performance in Chrome (m5-7/06-pdf 6.17 · 9.5; 8.2 T41 — P-C): the image normalizer's slow path
// for a 4000 × 3000 JPEG through the canvas codec (BrowserImageCodec — ≤ 1 s), and the web draft
// chunk write — RecordingDraftStore.append of 1-second WebM chunks (≈ 8 KB at 64 kbit/s), the
// latency the DraftWriter waits for — on CORE's REAL web store (IndexedDB + the drift web
// worker; median ≤ 30 ms — CORE 6.7.3's budget) and, printed only, on CORE's fake store. Until
// CORE T31 (the real draft store) the real-store case skips itself at run time. perf tag,
// skipped by default (`ws test --package media_io --platform chrome --run-skipped -t perf`).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_io/src/image/image_codec_browser.dart';
import 'package:media_io/src/image/image_normalizer.dart';
import 'package:note_core/note_core.dart' as core;

import 'media/media_world.dart';

img.Image _gradient(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    p
      ..r = p.x * 255 ~/ max(1, w - 1)
      ..g = p.y * 255 ~/ max(1, h - 1)
      ..b = 128;
  }
  return image;
}

/// [n] appends of [chunkBytes] to a new draft of [store]; their latencies in ms, sorted.
Future<List<int>> _appendLatencies(
  core.NoteStore store, {
  int n = 40,
  int chunkBytes = 8 * 1024,
}) async {
  final note = await store.library.createNote(title: 'append perf');
  final draft = await store.recordingDrafts.begin(
    recordingId: store.ids.newId(),
    noteId: note.id,
    mimeType: 'audio/webm;codecs=opus',
    startedAt: DateTime.now().millisecondsSinceEpoch,
  );
  final chunk = Uint8List(chunkBytes);
  final out = <int>[];
  for (var i = 0; i < n; i++) {
    final watch = Stopwatch()..start();
    await store.recordingDrafts.append(
      draft.draftId,
      chunk,
      activeMs: 1000 * (i + 1),
    );
    out.add(watch.elapsedMilliseconds);
  }
  await store.recordingDrafts.discard(draft.draftId);
  return out..sort();
}

void main() {
  test('image normalizer (canvas): 4000 × 3000 JPEG → 2048 × 1536 ≤ 1 s', () async {
    final jpeg = img.encodeJpg(_gradient(4000, 3000), quality: 90);
    const normalizer = ImageNormalizer(codec: BrowserImageCodec());
    await normalizer.normalize(img.encodeJpg(_gradient(400, 300))); // warm-up

    final watch = Stopwatch()..start();
    final n = await normalizer.normalize(jpeg);
    watch.stop();
    // ignore: avoid_print
    print(
      'media perf (Chrome): normalize 4000x3000 JPEG (${jpeg.length} B) → '
      '${n.width}x${n.height} ${n.mimeType} in ${watch.elapsedMilliseconds} ms',
    );
    expect((n.width, n.height), (2048, 1536));
    expect(n.path, NormalizePath.slow);
    expect(watch.elapsed, lessThanOrEqualTo(const Duration(seconds: 1)));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('draft append latency on the real web store: median ≤ 30 ms', () async {
    if (!await RealWebStores.draftsReady()) {
      markTestSkipped(coreT31Pending);
      return;
    }
    final stores = RealWebStores('append_perf');
    final store = await stores.open();
    try {
      final ms = await _appendLatencies(store);
      final median = ms[ms.length ~/ 2];
      // ignore: avoid_print
      print(
        'media perf (Chrome, real web store): append median $median ms, all $ms',
      );
      expect(median, lessThanOrEqualTo(30));
    } finally {
      await stores.close(store);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('draft append latency on the fake store (printed)', () async {
    final stores = FakeStores();
    final store = await stores.open();
    try {
      final ms = await _appendLatencies(store);
      // ignore: avoid_print
      print(
        'media perf (Chrome, CORE fake store): append median '
        '${ms[ms.length ~/ 2]} ms, all $ms',
      );
      expect(ms, hasLength(40));
    } finally {
      await stores.close(store);
    }
  });
}
