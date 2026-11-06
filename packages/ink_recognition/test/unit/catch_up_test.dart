// 6.9.5 catch-up (m5-7/05-library 8.2 L2-10b; contract 7.2.5
// notesWithStalePages v2.1): one notesWithStalePages() (most recently
// updated note first), then stalePages per note in that order, a yield
// between notes, the pages at the back of the queue in page order; again
// whenever `enabled` turns true; at start() when enabled; dirty pages are
// left to their quiet time; disabling stops it.
@TestOn('vm')
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_recognition/ink_recognition.dart';
import 'package:ink_recognition/src/indexer/handwriting_indexer.dart'
    show IndexerTuning;

import '../support/indexer_harness.dart';

void indexerTest(String name, void Function(FakeAsync async) body) =>
    test(name, () => fakeAsync(body));

void main() {
  indexerTest('notesWithStalePages once, stalePages note by note (newest '
      'first, a yield between notes), pages queued in that order', (async) {
    final h = IndexerHarness(async, enabled: false, pages: 2);
    final a = h.note.id;
    final [a1, a2] = h.pageIds;
    final (b, [b1]) = h.newNote('B');
    final (c, [c1]) = h.newNote('C');
    h.addStrokes(h.lines(pageId: a2), pageId: a2); // a2 before a1 in time
    h.elapse(const Duration(seconds: 1));
    h.addStrokes(h.lines(pageId: a1, seed: 2), pageId: a1);
    h.elapse(const Duration(seconds: 1));
    h.addStrokes(
      h.lines(pageId: b1, seed: 3),
      pageId: b1,
      noteId: b.id,
    );
    h.elapse(const Duration(seconds: 1));
    h.addStrokes(
      h.lines(pageId: c1, seed: 4),
      pageId: c1,
      noteId: c.id,
    );
    h.elapse(const Duration(minutes: 1));
    expect(h.recognizer.calls, isEmpty); // disabled: nothing indexed
    h.store.calls.clear();

    h.foreground.value = false; // no job yet: only the catch-up runs
    h.enabled.value = true;
    async.flushMicrotasks(); // up to the first yield
    expect(h.store.calls, ['notesWithStalePages', 'stalePages:${c.id}']);
    h.settle();
    expect(h.store.calls, [
      'notesWithStalePages',
      'stalePages:${c.id}',
      'stalePages:${b.id}',
      'stalePages:$a',
    ]);
    expect(h.status.queuedPages, 4);
    expect(h.phase, HandwritingIndexerPhase.paused);

    h.store.calls.clear();
    h.foreground.value = true;
    h.settle();
    expect(
      [
        for (final call in h.store.calls)
          if (call.startsWith('loadPage:')) call.substring(9),
      ],
      [c1, b1, a1, a2], // note order, then page order — no quiet time
    );
    expect(h.status.indexedPages, 4);
    expect(h.phase, HandwritingIndexerPhase.idle);
    h.dispose();
  });

  indexerTest('again whenever enabled turns true; nothing stale → nothing '
      'queued', (async) {
    final h = IndexerHarness(async);
    expect(h.store.count('notesWithStalePages'), 1); // start() while enabled
    h.addStrokes(h.lines());
    h.elapse(IndexerTuning.localQuiet);
    expect(h.store.count('update:'), 1);

    h.enabled.value = false;
    h.settle();
    h.addStrokes(h.lines(seed: 9)); // ignored while disabled
    h.elapse(const Duration(minutes: 1));
    expect(h.recognizer.calls, hasLength(3));

    h.enabled.value = true;
    h.settle();
    expect(h.store.count('notesWithStalePages'), 2);
    expect(h.store.count('update:'), 2); // the catch-up found the page
    expect(h.stored()!.sourceRev, h.revOf());

    h.enabled.value = false;
    h.enabled.value = true;
    h.settle();
    expect(h.store.count('notesWithStalePages'), 3);
    expect(h.status.queuedPages, 0);
    expect(h.store.count('update:'), 2);
    h.dispose();
  });

  indexerTest('start() while enabled: stale pages run without a quiet time', (
    async,
  ) {
    final h = IndexerHarness(async, start: false);
    h.addStrokes(h.lines());
    h.indexer.start();
    h.settle();
    expect(h.store.calls.first, 'notesWithStalePages');
    expect(h.recognizer.calls, hasLength(3));
    expect(h.store.count('update:'), 1);
    h.dispose();
  });

  indexerTest('a dirty page waits for its quiet time; disabling stops the '
      'catch-up between notes', (async) {
    final h = IndexerHarness(async, enabled: false);
    final (b, [b1]) = h.newNote('B');
    h.addStrokes(h.lines());
    h.elapse(const Duration(seconds: 1));
    h.addStrokes(
      h.lines(pageId: b1, seed: 2),
      pageId: b1,
      noteId: b.id,
    );
    h.store.calls.clear();

    h.foreground.value = false; // the catch-up alone
    h.enabled.value = true;
    async.flushMicrotasks();
    expect(h.store.calls, ['notesWithStalePages', 'stalePages:${b.id}']);
    h.enabled.value = false; // before the yield
    h.settle();
    expect(h.store.count('stalePages:'), 1);
    expect(h.status.queuedPages, 0);

    // Dirty while enabled: the catch-up leaves it to the timer.
    h.enabled.value = true;
    h.addStrokes(h.lines(seed: 5).take(3).toList());
    h.foreground.value = true;
    h.settle();
    expect(h.store.count('loadPage:${h.pageId}'), 0);
    h.elapse(IndexerTuning.localQuiet);
    expect(h.store.count('loadPage:${h.pageId}'), 1);
    h.dispose();
  });
}
