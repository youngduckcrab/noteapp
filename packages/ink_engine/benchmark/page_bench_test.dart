// B3 page acceptance, B8 chunk re-record, B11 InkPageContent.fromCore
// (03-ink 9.1, T22). Run: flutter test benchmark/.
@Tags(['bench'])
library;

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart';
import 'package:ink_engine/src/render/ink_page_controller.dart'
    show inkChunkCacheOf, inkPageRenderOf;
import 'package:ink_engine/testing.dart';
import 'package:note_core/note_core.dart' as core;

import 'support/bench.dart';
import 'support/workloads.dart';

/// One inkBase paint of [c] at view scale 1 (what the first frame does).
void _paintInkBase(InkPageController c) {
  final recorder = ui.PictureRecorder();
  inkPageRenderOf(c).paint(ui.Canvas(recorder), InkRenderLayer.inkBase, 1);
  recorder.endRecording().dispose();
}

void main() {
  test('B3 page acceptance: 2000 strokes × 150 points '
      '(updateContent + outlines + chunk recording)', () {
    final source = handwriting(count: 2000, points: 150);
    late InkPageContent content;
    late InkPageController c;
    var chunks = 0;
    final stats = measure(
      () {
        c.updateContent(content);
        _paintInkBase(c);
      },
      setUp: () {
        // a fresh controller (empty outline pool) and fresh CORE objects
        content = pageOf(freshCopies(source));
        c = createTestPageController();
      },
      warmup: 2,
      runs: 8,
    );
    chunks = inkChunkCacheOf(c).chunkCount;
    expect(inkChunkCacheOf(c).loadingCount, 0);
    c.dispose();
    report(
      'B3',
      'page acceptance 2000 × 150 pt',
      stats,
      criteria: {'median_ms': 500},
      extra: {'chunks': chunks},
    );
  });

  test('B8 chunk re-record: one chunk of 1000 strokes', () {
    // Synthetic strokes on a 240 pt square: all of them in chunk (0, 0).
    final strokes = synthetic(1000, pageSize: const core.PageSize(240, 240));
    final full = pageOf(strokes);
    final without = pageOf([...strokes]..removeAt(500), revision: 2);
    final c = createTestPageController();
    c.updateContent(full);
    _paintInkBase(c);
    final cache = inkChunkCacheOf(c);
    expect(cache.strokeCountOf(0), 1000);
    c.updateContent(without);
    _paintInkBase(c);
    expect(cache.strokeCountOf(0), 999, reason: 'the removal re-records');
    var flip = true;
    final stats = measure(
      () {
        // remove / re-insert a stroke in the middle of the z order → the
        // chunk is dirty → recorded again (outlines are in the pool)
        c.updateContent(flip ? without : full);
        _paintInkBase(c);
      },
      setUp: () => flip = !flip,
      warmup: 4,
      runs: 30,
    );
    // every run re-recorded the chunk with the content it set
    expect(cache.strokeCountOf(0), flip ? 999 : 1000);
    expect(cache.dirtyCount, 0);
    c.dispose();
    report(
      'B8',
      'chunk re-record 1000 strokes',
      stats,
      criteria: {'median_ms': 8},
    );
  });

  test('B11 InkPageContent.fromCore: 10 000 strokes (sorted)', () {
    final source = synthetic(10000);
    late List<core.Stroke> input;
    final page = SyntheticInk.page();
    late InkPageContent content;
    final stats = measure(
      () => content = InkPageContent.fromCore(
        page: page,
        strokes: input,
        revision: 1,
      ),
      setUp: () => input = freshCopies(source),
      warmup: 3,
      runs: 20,
    );
    expect(content.strokes, hasLength(10000));
    report('B11', 'fromCore 10 000 strokes', stats, criteria: {'median_ms': 5});
  });
}
