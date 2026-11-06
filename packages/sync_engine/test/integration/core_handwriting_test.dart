// T16-v2 (integration stage 3 — 07-sync 6.7.2, 6.2.2, 6.2.5, 6.2.6): handwriting results
// (HandwritingRepository.put — the recognizer's write) between two real CORE stores. What
// only real CORE shows: its remote-apply write hook indexes a received result (02-core 6.13 —
// B finds the page by a word of it), and stalePages: a result received with the strokes it
// was made from is fresh (its sourceRev matches), so B does not recognize the page again.
//
// H1 A puts → B forPage = A's result, B's search finds the page, no stale page on B. H2 A and
// B, offline, each put the page's result → one id hw_P, the later write wins. H3 A deletes a
// page whose only change on B is a new result (B offline): the page stays deleted (a result
// is no evidence — 6.2.6), the result row stays. H4 the note is purged → forPage null on both
// and the word finds nothing.
//
// CORE milestones (6.7.2 table): H1 T32 · T28 · T33b, H2 · H3 T32 · T28, H4 T29 · T33b.
@Tags(['integration'])
@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/sync_engine.dart';

import 'support/core_sync_device.dart';

List<String> _linesOf(HandwritingText? value) => [
  for (final l in value!.lines) l.text,
];

/// The pages [d]'s search finds for [word].
Future<List<PageId>> _hits(CoreSyncDevice d, String word) async => [
  for (final h in await d.store.search.searchPages(word)) h.pageId,
];

/// A note with one page and three strokes on A, known to B too.
Future<(NoteId, PageId)> _notePage(
  CoreScenario s,
  CoreSyncDevice a,
  CoreSyncDevice b,
  String title,
) async {
  final note = (await a.store.library.createNote(title: title)).id;
  final page = (await a.pageIdsOf(note)).single;
  for (var i = 0; i < 3; i++) {
    await a.core.addStroke(page, seed: i);
  }
  await s.converge([a, b], [note]);
  return (note, page);
}

void main() {
  coreScenario(
    'H1 A\'s result reaches B: the same value, B\'s search finds the '
    'page, the page is not stale on B',
    (s) async {
      final a = await s.device('A');
      final b = await s.device('B');
      final (note, page) = await _notePage(s, a, b, 'H1');

      final put = await a.core.putHandwriting(page, ['미분 계수', '도함수']);
      await s.until(
        'the result on B',
        () async => await b.store.handwriting.forPage(page) != null,
      );
      await s.converge([a, b], [note]);
      final onB = (await b.store.handwriting.forPage(page))!;
      expect(onB.toJson(), (await a.store.handwriting.forPage(page))!.toJson());
      expect(onB.sourceRev, put.sourceRev);
      expect(_linesOf(onB), ['미분 계수', '도함수']);
      await s.until(
        'B\'s index to find the page',
        () async => (await _hits(b, '도함수')).contains(page),
      );
      expect(await b.store.handwriting.stalePages(note), isEmpty);
      expect(await a.store.handwriting.stalePages(note), isEmpty);
    },
  );

  coreScenario('H2 A and B, offline, each put the page\'s result: one id hw_P, '
      'the later write wins', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final (note, page) = await _notePage(s, a, b, 'H2');
    await a.core.putHandwriting(page, ['미분']);
    await s.converge([a, b], [note]);

    a.goOffline();
    b.goOffline();
    await a.core.putHandwriting(page, ['미분 계수', '도함수']);
    await nextMillisecond();
    await b.core.putHandwriting(page, ['미분법']); // later
    a.goOnline();
    b.goOnline();
    await s.converge([a, b], [note]);
    for (final d in [a, b]) {
      final value = await d.store.handwriting.forPage(page);
      expect(value!.id, HandwritingText.idFor(page), reason: d.name);
      expect(_linesOf(value), ['미분법'], reason: d.name);
    }
  });

  coreScenario('H3 page deleted on A vs only a new result on B (offline): the '
      'page stays deleted, the result row stays', (s) async {
    final a = await s.device('A');
    final b = await s.device('B');
    final restored = listenNotices<PageRestored>([a, b]);
    final note = (await a.store.library.createNote(
      title: 'H3',
      pages: const [PageDraft.blankA4, PageDraft.blankA4],
    )).id;
    final page = (await a.pageIdsOf(note)).last;
    await a.core.addStroke(page);
    await a.core.putHandwriting(page, ['적분']);
    await s.converge([a, b], [note]);

    b.goOffline();
    await a.core.deletePages(note, [page]);
    await s.settle([a]);
    await nextMillisecond();
    await b.core.putHandwriting(page, ['정적분']);
    b.goOnline();

    final hw = EntityRef(EntityKind.handwriting, HandwritingText.idFor(page));
    await s.converge(
      [a, b],
      [note],
      extra: [EntityRef(EntityKind.page, page), hw],
    );
    for (final d in [a, b]) {
      expect(
        (await d.store.content.getPage(page))!.isDeleted,
        isTrue,
        reason: d.name,
      );
      expect(await d.pageIdsOf(note), isNot(contains(page)), reason: d.name);
      final row = (await d.jsonOf(hw.kind, hw.id))!;
      expect(row['deletedAt'], isNull, reason: d.name);
      expect(
        [for (final l in row['lines']! as List) (l as Map)['text']],
        ['정적분'],
        reason: d.name,
      );
    }
    expect(restored.seen, isEmpty);
    await restored.cancel();
  });

  coreScenario(
    'H4 the note is purged: no result on either side, the word finds '
    'nothing',
    (s) async {
      final a = await s.device('A');
      final b = await s.device('B');
      final (note, page) = await _notePage(s, a, b, 'H4');
      await a.core.putHandwriting(page, ['극한값']);
      await s.converge([a, b], [note]);
      await s.until(
        'both indexes to find the page',
        () async =>
            (await _hits(a, '극한값')).contains(page) &&
            (await _hits(b, '극한값')).contains(page),
      );

      await a.core.trashAndPurge(note);
      final hw = EntityRef(EntityKind.handwriting, HandwritingText.idFor(page));
      await s.until('the purge on B', () async {
        if (!a.idle || !b.idle) return false;
        return await b.store.library.getNote(note) == null;
      });
      for (final d in [a, b]) {
        expect(await d.store.handwriting.forPage(page), isNull, reason: d.name);
        expect(await d.read(hw.kind, hw.id), isNull, reason: d.name);
        expect(await _hits(d, '극한값'), isEmpty, reason: d.name);
      }
    },
  );
}
