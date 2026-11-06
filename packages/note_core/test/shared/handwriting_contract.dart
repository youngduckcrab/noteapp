// Shared body (m5-7/02-core 6.9.3, 6.9.4): HandwritingRepository — put validation and upsert,
// update (read-merge-write in one write: race cases 1, 2, 4–7; case 3 needs the remote path and
// is the real store's), removeForPage, forPage / watchPage, stalePages and notesWithStalePages
// (exact answers, page / recency order), writes from inside a transform. The fake store runs
// it now (test/repo/handwriting_contract_fake_test.dart), the real store from CORE T32.
// Web-safe.
import 'dart:async';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

void defineHandwritingContract(FutureOr<NoteStore> Function() open) {
  late NoteStore store;
  late Note note;
  late List<PageId> pages;

  setUp(() async {
    store = await open();
    note = await store.library.createNote(
      title: '손글씨',
      pages: const [PageDraft.blankA4, PageDraft.blankA4, PageDraft.blankA4],
    );
    pages = [for (final p in await store.content.pagesOf(note.id)) p.id];
  });
  tearDown(() => store.close());

  HandwritingRepository get0() => store.handwriting;

  HandwritingText result(
    PageId pageId, {
    String text = '회의록',
    String sourceRev = '0000000000000000',
    NoteId? noteId,
    List<String> alternatives = const [],
    String languageTag = 'ko',
  }) => HandwritingText(
    noteId: noteId ?? note.id,
    pageId: pageId,
    engineId: 'fake/1:ko',
    sourceRev: sourceRev,
    lines: [
      HandwritingLine(
        text: text,
        alternatives: alternatives,
        rect: const PageRect(10, 10, 100, 30),
        strokeIds: const ['s1'],
        languageTag: languageTag,
      ),
    ],
    createdAt: 1,
  );

  Future<List<Stroke>> addStrokes(PageId pageId, List<PenTool> tools) async {
    final session = await store.openSession(note.id);
    await session.openPage(pageId);
    final strokes = [
      for (final (i, t) in tools.indexed)
        StrokeFixtures.synthetic(
          pageId: pageId,
          ids: store.ids,
          seed: i,
          tool: t,
          createdAt: 100 + i,
        ),
    ];
    await session
        .execute(AddStrokes(pageId: pageId, strokes: strokes))
        .persisted;
    final stored = session.pageIfLoaded(pageId)!.strokes;
    await session.close();
    return stored;
  }

  group('put / forPage / watchPage / removeForPage', () {
    test('upsert, deterministic id, updatedAt / version filled', () async {
      final batches = <ChangeBatch>[];
      final sub = store.changes.listen(batches.add);
      addTearDown(sub.cancel);
      await get0().put(result(pages[0]));
      final stored = (await get0().forPage(pages[0]))!;
      expect(stored.id, 'hw_${pages[0]}');
      expect(stored.lines.single.text, '회의록');
      expect(stored.version, isNotNull);
      await get0().put(result(pages[0], text: '두 번째'));
      expect((await get0().forPage(pages[0]))!.lines.single.text, '두 번째');
      await Future<void>.delayed(Duration.zero);
      final changes = [
        for (final b in batches)
          for (final c in b.changes)
            if (c.kind == EntityKind.handwriting) c,
      ];
      expect(changes, hasLength(2));
      expect(changes.first.noteId, note.id);
      expect(changes.first.pageId, pages[0]);
    });

    test('validation', () async {
      await expectLater(
        get0().put(result('missing-page')),
        throwsA(isA<EntityNotFoundException>()),
      );
      final other = await store.library.createNote(title: 'other');
      await expectLater(
        get0().put(result(pages[0], noteId: other.id)),
        throwsArgumentError,
      );
      await expectLater(
        get0().put(
          result(pages[0], alternatives: ['a', 'b', 'c', 'd', 'e', 'f']),
        ),
        throwsArgumentError,
      );
      await expectLater(
        get0().put(result(pages[0], languageTag: '')),
        throwsArgumentError,
      );
      expect(await get0().forPage(pages[0]), isNull);
    });

    test(
      'watchPage: now, then each change; removeForPage → null; put revives',
      () async {
        final seen = <String?>[];
        final sub = get0()
            .watchPage(pages[1])
            .listen((h) => seen.add(h?.lines.single.text));
        addTearDown(sub.cancel);
        await Future<void>.delayed(Duration.zero);
        await get0().put(result(pages[1]));
        await get0().removeForPage(pages[1]);
        await get0().removeForPage(pages[1]); // nothing left: a no-op
        await get0().removeForPage('missing'); // a no-op
        await get0().put(result(pages[1], text: '다시'));
        await Future<void>.delayed(Duration.zero);
        expect(seen, [null, '회의록', null, '다시']);
        expect((await get0().forPage(pages[1]))!.isDeleted, isFalse);
      },
    );
  });

  group('update (6.9.4 race cases)', () {
    test('1: two updates without await — the second sees the first', () async {
      final seen = <String?>[];
      final a = get0().update(pages[0], (cur) {
        seen.add(cur?.lines.single.text);
        return result(pages[0], text: 'A');
      });
      final b = get0().update(pages[0], (cur) {
        seen.add(cur?.lines.single.text);
        return result(pages[0], text: '${cur!.lines.single.text}+B');
      });
      expect((await a)!.lines.single.text, 'A');
      expect((await b)!.lines.single.text, 'A+B');
      expect(seen, [null, 'A']);
    });

    test(
      '2: put then update without await — the transform gets the put',
      () async {
        final put = get0().put(result(pages[0], text: 'P'));
        final up = get0().update(
          pages[0],
          (cur) => cur!.copyWith(engineId: 'merged'),
        );
        await put;
        final stored = (await up)!;
        expect(stored.lines.single.text, 'P');
        expect(stored.engineId, 'merged');
      },
    );

    test(
      '4: a null transform writes nothing and returns the stored value',
      () async {
        await get0().put(result(pages[0]));
        final stored = await get0().forPage(pages[0]);
        final batches = <ChangeBatch>[];
        final sub = store.changes.listen(batches.add);
        addTearDown(sub.cancel);
        expect(await get0().update(pages[0], (_) => null), stored);
        expect(await get0().update(pages[1], (_) => null), isNull);
        await Future<void>.delayed(Duration.zero);
        expect(batches, isEmpty);
      },
    );

    test('5: a throwing or invalid transform changes nothing', () async {
      await get0().put(result(pages[0]));
      final stored = await get0().forPage(pages[0]);
      await expectLater(
        get0().update(pages[0], (_) => throw const FormatException('boom')),
        throwsFormatException,
      );
      await expectLater(
        get0().update(pages[0], (_) => result(pages[0], languageTag: '')),
        throwsArgumentError,
      );
      await expectLater(
        get0().update(pages[0], (_) => result(pages[1])),
        throwsArgumentError,
        reason: 'another page',
      );
      expect(await get0().forPage(pages[0]), stored);
    });

    test('6: a deleted row → transform(null); writing revives it', () async {
      await get0().put(result(pages[0]));
      await get0().removeForPage(pages[0]);
      HandwritingText? got;
      final revived = await get0().update(pages[0], (cur) {
        got = cur;
        return result(pages[0], text: 'back');
      });
      expect(got, isNull);
      expect(revived!.isDeleted, isFalse);
      expect((await get0().forPage(pages[0]))!.lines.single.text, 'back');
    });

    test(
      '7: a missing page → EntityNotFoundException before the transform',
      () async {
        var called = false;
        await expectLater(
          get0().update('missing', (_) {
            called = true;
            return null;
          }),
          throwsA(isA<EntityNotFoundException>()),
        );
        expect(called, isFalse);
      },
    );

    test('a store write from inside the transform is a StateError', () async {
      Object? error;
      await get0().update(pages[0], (_) {
        get0().put(result(pages[1])).catchError((Object e) => error = e);
        return null;
      });
      await Future<void>.delayed(Duration.zero);
      expect(error, isA<StateError>());
    });
  });

  group('stalePages / notesWithStalePages (6.9.3)', () {
    test('input strokes vs the stored sourceRev, page order', () async {
      expect(
        await get0().stalePages(note.id),
        isEmpty,
        reason: 'no input strokes',
      );
      final ink0 = await addStrokes(pages[0], [
        PenTool.ballpoint,
        PenTool.highlighter,
      ]);
      await addStrokes(pages[2], [PenTool.pencil]);
      await addStrokes(pages[1], [PenTool.highlighter, PenTool.laser]);
      // Page 1 has only non-input strokes: not stale.
      expect(await get0().stalePages(note.id), [pages[0], pages[2]]);
      final rev0 = HandwritingText.sourceRevOf(
        ink0.where(HandwritingText.isRecognitionInput),
      );
      await get0().put(result(pages[0], sourceRev: rev0));
      expect(await get0().stalePages(note.id), [pages[2]]);
      await get0().put(result(pages[0], sourceRev: 'ffffffffffffffff'));
      expect(await get0().stalePages(note.id), [pages[0], pages[2]]);
      // A result for a page without input strokes is stale too (its rev is not the empty one).
      await get0().put(result(pages[1], sourceRev: '0000000000000000'));
      expect(await get0().stalePages(note.id), [pages[0], pages[1], pages[2]]);
      expect(await get0().stalePages('missing'), isEmpty);
    });

    test(
      'notesWithStalePages: exact, most recently updated note first',
      () async {
        final other = await store.library.createNote(title: 'other');
        final otherPage = (await store.content.pagesOf(other.id)).single.id;
        expect(await get0().notesWithStalePages(), isEmpty);
        await addStrokes(pages[0], [PenTool.ballpoint]);
        final s = await store.openSession(other.id);
        await s.openPage(otherPage);
        await s
            .execute(
              AddStrokes(
                pageId: otherPage,
                strokes: [
                  StrokeFixtures.synthetic(pageId: otherPage, ids: store.ids),
                ],
              ),
            )
            .persisted;
        final otherStrokes = s.pageIfLoaded(otherPage)!.strokes;
        await s.close();
        final noted = await store.library.getNote(note.id);
        final otherNoted = await store.library.getNote(other.id);
        final expected = [noted!, otherNoted!]
          ..sort((a, b) {
            final c = b.updatedAt.compareTo(a.updatedAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
        expect(await get0().notesWithStalePages(), [
          for (final n in expected) n.id,
        ]);
        await get0().put(
          HandwritingText(
            noteId: other.id,
            pageId: otherPage,
            engineId: 'fake/1:ko',
            sourceRev: HandwritingText.sourceRevOf(otherStrokes),
            lines: const [],
            createdAt: 1,
          ),
        );
        expect(await get0().notesWithStalePages(), [note.id]);
        await store.library.trashItems([NoteRef(note.id)]);
        expect(
          await get0().notesWithStalePages(),
          isEmpty,
          reason: 'trashed notes are out',
        );
      },
    );
  });
}
