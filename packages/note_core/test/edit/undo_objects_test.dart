// CORE T27 — undo / redo of page object edits on the SQLite store (m5-7/02-core 6.4.3): only
// the JSON keys that really differ get the new HLC and go to the outbox (C-11 — a text-only
// UpdateObjects undone writes {text}); strokes and objects transformed together are one
// commit and one history step; 100 object steps undone give back the initial page in memory
// and stored (and redone, the edited one); an object changed remotely since is skipped (6.7.3).
// R-8 (contract 7.2.4 — 02-core 6.1, 6.4.3, 6.6, 6.9.4, 9.3), on the fake and the real store:
// recordings and handwriting results are outside the undo history — creating, renaming and
// deleting a recording and put / update / removeForPage of a handwriting result while a
// session with undo and redo steps is open leave its history and its page alone, and that
// session's undo / redo (of the strokes drawn while recording, too) leaves them as they are.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/outbox_writer.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

import '../storage/storage_support.dart' show openStore;
import 'undo_support.dart';

/// [o]'s JSON without the keys an undo / redo restamps.
Map<String, Object?> _content(PageObject o) => Map.of(o.toJson())
  ..remove('updatedAt')
  ..remove('version');

List<Object?> _contents(List<PageObject> objects) => [
  for (final o in objects) _content(o),
];

List<PageObject> _initialObjects(PageId pageId) => [
  PageObjectFixtures.shape(pageId: pageId, id: 'shape', createdAt: 10),
  PageObjectFixtures.textBox(pageId: pageId, id: 'text', createdAt: 11),
  PageObjectFixtures.math(pageId: pageId, id: 'math', createdAt: 12),
  PageObjectFixtures.image(
    pageId: pageId,
    id: 'image',
    assetId: 'asset-1',
    createdAt: 13,
  ),
  PageObjectFixtures.unknown(pageId: pageId, id: 'unknown'),
];

/// One stroke (a draft's stroke ids are not kept — the tests read it back by `ink()`).
List<Stroke> _initialStrokes(PageId pageId) => [
  Stroke(
    id: 'ink',
    pageId: pageId,
    style: StrokeStyle.defaultsFor(PenTool.ballpoint),
    points: StrokePoints.fromList([
      for (var k = 0; k < 8; k++) StrokePoint(10.0 + k, 20.0 + k, widthQ: 0.5),
    ]),
    createdAt: 5,
  ),
];

/// R-8 on the store [open] gives: one note, one page, a session on it with one undo step
/// (strokes drawn while recording 'rec-r8', linked to it) and one redo step (a text box).
void _outsideHistoryCases(String name, Future<NoteStore> Function() open) {
  group(
    'R-8 on the $name store: recordings and handwriting results are outside the '
    'undo history',
    () {
      const recordingId = 'rec-r8';
      late NoteStore store;
      late NoteId noteId;
      late PageId pageId;
      late NoteSession session;
      late HistoryState before;
      late List<HistoryState> historyEvents;
      late List<PageContentChange> pageEvents;
      final subscriptions = <StreamSubscription<Object?>>[];

      setUp(() async {
        store = await open();
        final note = await store.library.createNote(
          title: 'R-8',
          pages: const [PageDraft.blankA4],
        );
        noteId = note.id;
        pageId = (await store.content.pagesOf(noteId)).single.id;
        session = await store.openSession(noteId);
        await session.openPage(pageId);
        await session
            .execute(
              AddStrokes(
                pageId: pageId,
                strokes: [
                  for (var k = 0; k < 3; k++)
                    Stroke(
                      id: 'ink-$k',
                      pageId: pageId,
                      style: StrokeStyle.defaultsFor(PenTool.ballpoint),
                      points: StrokePoints.fromList([
                        for (var i = 0; i < 6; i++)
                          StrokePoint(40.0 + 30 * k + i, 60.0 + i, widthQ: 0.5),
                      ]),
                      recordingId: recordingId,
                      recordingOffsetMs: 500 * k,
                      createdAt: 1000 + k,
                    ),
                ],
              ),
            )
            .persisted;
        await session
            .execute(
              AddObjects(
                pageId: pageId,
                objects: [
                  PageObjectFixtures.textBox(pageId: pageId, id: 'box'),
                ],
              ),
            )
            .persisted;
        expect((await session.undo()).applied, isTrue);
        await session.flush();
        before = session.history;
        expect(
          (before.undoDepth, before.redoDepth, before.canUndo, before.canRedo),
          (1, 1, true, true),
        );
        historyEvents = [];
        pageEvents = [];
        subscriptions
          ..add(session.historyStream.listen(historyEvents.add))
          ..add(session.pageChanges(pageId).listen(pageEvents.add));
        await pumpEventQueue();
        pageEvents.clear(); // the `load` change a new listener gets first
      });

      tearDown(() async {
        for (final s in subscriptions) {
          await s.cancel();
        }
        subscriptions.clear();
        if (!session.isClosed) await session.close();
        await store.close();
      });

      /// The session's history and page are as they were in setUp.
      Future<void> expectSessionUntouched(String after) async {
        await pumpEventQueue();
        expect(session.history, before, reason: after);
        expect(historyEvents, isEmpty, reason: '$after: historyStream');
        expect(pageEvents, isEmpty, reason: '$after: pageChanges');
        final page = session.pageIfLoaded(pageId)!;
        expect(page.strokeCount, 3, reason: after);
        expect(page.objects, isEmpty, reason: after);
      }

      Future<Recording> createRecording() async {
        final audio = await store.assets.put(
          Uint8List.fromList(List.filled(48, 3)),
          type: AssetType.audio,
          mimeType: 'audio/webm',
        );
        return store.recordings.createRecording(
          id: recordingId,
          noteId: noteId,
          assetId: audio.id,
          durationMs: 4000,
          startedAt: 900,
          title: '1교시',
        );
      }

      HandwritingText result(String text) => HandwritingText(
        noteId: noteId,
        pageId: pageId,
        engineId: 'fake/1:ko',
        sourceRev: HandwritingText.sourceRevOf(
          session.pageIfLoaded(pageId)!.strokes,
        ),
        lines: [
          HandwritingLine(
            text: text,
            rect: const PageRect(40, 60, 140, 70),
            strokeIds: const ['ink-0', 'ink-1', 'ink-2'],
            languageTag: 'ko',
          ),
        ],
        createdAt: 1,
      );

      /// Undo and redo of the session apply — each a step of the session's own commands.
      Future<void> undoRedoRoundTrip() async {
        final redo = await session.redo(); // the text box comes back
        expect((redo.applied, redo.skippedEntities), (true, 0));
        expect(session.pageIfLoaded(pageId)!.objectById('box'), isNotNull);
        for (var i = 0; i < 2; i++) {
          // the text box goes, then the strokes drawn while recording go
          final undo = await session.undo();
          expect(
            (undo.applied, undo.skippedEntities),
            (true, 0),
            reason: 'undo $i',
          );
        }
        await session.flush();
        final page = session.pageIfLoaded(pageId)!;
        expect((page.strokeCount, page.objects.length), (0, 0));
        expect(
          session.history,
          isA<HistoryState>()
              .having((h) => h.undoDepth, 'undoDepth', 0)
              .having((h) => h.redoDepth, 'redoDepth', 2),
        );
      }

      test('createRecording, renameRecording and deleteRecording leave the history '
          'and the page alone; undoing the strokes drawn while recording keeps the '
          'recording', () async {
        final created = await createRecording();
        await expectSessionUntouched('createRecording');
        await store.recordings.renameRecording(recordingId, '2교시');
        await expectSessionUntouched('renameRecording');

        await undoRedoRoundTrip();
        final kept = (await store.recordings.getRecording(recordingId))!;
        expect((kept.title, kept.isDeleted), ('2교시', false));
        expect(kept.createdAt, created.createdAt);
        expect((await store.recordings.recordingsOf(noteId)).map((r) => r.id), [
          recordingId,
        ]);

        // Delete after the round trip: the session's redo stack is not touched either, and
        // redoing the strokes does not bring the recording back (R-7: they keep the id).
        final now = session.history;
        await store.recordings.deleteRecording(recordingId);
        await pumpEventQueue();
        expect(session.history, now, reason: 'deleteRecording');
        expect((await session.redo()).applied, isTrue);
        await session.flush();
        expect(
          session
              .pageIfLoaded(pageId)!
              .strokes
              .map((s) => s.recordingId)
              .toSet(),
          {recordingId},
        );
        expect(
          (await store.recordings.getRecording(recordingId))!.isDeleted,
          isTrue,
        );
        expect(await store.recordings.recordingsOf(noteId), isEmpty);
      });

      test(
        'handwriting put, update and removeForPage leave the history and the '
        'page alone; undo / redo of the strokes do not touch the stored result',
        () async {
          await store.handwriting.put(result('회의록'));
          await expectSessionUntouched('handwriting put');
          final updated = await store.handwriting.update(
            pageId,
            (current) => current!.copyWith(
              lines: [
                current.lines.single.copyWith(
                  text: '회의록 고침',
                  userConfirmed: true,
                ),
              ],
            ),
          );
          expect(updated!.lines.single.text, '회의록 고침');
          await expectSessionUntouched('handwriting update');

          await undoRedoRoundTrip();
          // The result is not undone with the strokes it came from: it is stale now (6.9.3 —
          // the recognizer catches it up), not removed.
          expect(await store.handwriting.forPage(pageId), updated);
          expect(await store.handwriting.stalePages(noteId), [pageId]);

          final now = session.history;
          await store.handwriting.removeForPage(pageId);
          await pumpEventQueue();
          expect(session.history, now, reason: 'removeForPage');
          expect((await session.redo()).applied, isTrue);
          await session.flush();
          expect(await store.handwriting.forPage(pageId), isNull);
        },
      );
    },
  );
}

void main() {
  group('page objects on the real store', _pageObjectCases);
  _outsideHistoryCases('fake', () async => createFakeNoteStore());
  _outsideHistoryCases('real', openStore);
}

void _pageObjectCases() {
  late UndoFixture f;
  tearDown(() => f.close());

  Future<Map<ElementId, Set<String>>> outboxFields() async => {
    for (final e in await readOutbox(f.store.db)) e.entityId: e.changedFields,
  };

  Future<void> ack() => f.store.db.delete(f.store.db.outbox).go();

  /// The id of the initial stroke.
  ElementId ink() => f.session.pageIfLoaded(f.pageId)!.strokes.single.id;

  test('undo of a text-only UpdateObjects writes {text}; frame and style keep '
      'their versions (C-11)', () async {
    f = await UndoFixture.open(objects: _initialObjects);
    await ack();
    final added = await f.objectRow('text');
    final text = f.currentObject('text') as TextBoxObject;
    await f.run(
      UpdateObjects(
        pageId: f.pageId,
        objects: [text.copyWith(text: '고친 글')],
      ),
    );
    final edited = await f.objectRow('text');
    expect(await outboxFields(), {
      'text': {'text'},
    });
    expect(edited.versions.of('frame'), added.versions.of('frame'));
    expect(edited.versions.of('style'), added.versions.of('style'));
    expect(edited.versions.of('text'), isNot(added.versions.of('text')));
    await ack();

    await f.session.undo();
    await f.session.flush();
    final undone = await f.objectRow('text');
    expect(await outboxFields(), {
      'text': {'text'},
    });
    expect(undone.versions.of('frame'), added.versions.of('frame'));
    expect(undone.versions.of('style'), added.versions.of('style'));
    expect(
      undone.versions.of('text').compareTo(edited.versions.max),
      greaterThan(0),
    );
    expect(undone.versions.max, undone.versions.of('text'));
    expect((undone.entity as TextBoxObject).text, text.text);
    expect(
      undone.entity.version,
      f.currentObject('text').version,
      reason: 'memory = row',
    );

    await ack();
    await f.session.redo();
    await f.session.flush();
    expect(await outboxFields(), {
      'text': {'text'},
    });
    expect(((await f.objectRow('text')).entity as TextBoxObject).text, '고친 글');
  });

  test(
    'strokes and objects transformed together: one commit, one history step; '
    'its undo is one commit writing the same keys',
    () async {
      f = await UndoFixture.open(
        initial: _initialStrokes,
        objects: _initialObjects,
      );
      await ack();
      final before = f.session.pageIfLoaded(f.pageId)!;
      final depth = f.session.history.undoDepth;
      final commits = f.store.queue.debugTransactionCount;
      await f.run(
        TransformElements(
          pageId: f.pageId,
          elementIds: [ink(), 'shape', 'text', 'math', 'image', 'unknown'],
          transform: Affine2.translation(30, -12),
        ),
      );
      expect(f.store.queue.debugTransactionCount, commits + 1);
      expect(f.session.history.undoDepth, depth + 1);
      final forward = await outboxFields();
      // The unknown object is left alone (6.4.1); the others moved.
      expect(forward.keys.toSet(), {ink(), 'shape', 'text', 'math', 'image'});
      expect(forward[ink()], {'points'});
      final moved = f.session.pageIfLoaded(f.pageId)!;
      expect(moved.objectById('unknown'), same(before.objectById('unknown')));
      expect(
        (moved.objectById('text')! as TextBoxObject).frame.rect.left,
        (before.objectById('text')! as TextBoxObject).frame.rect.left + 30,
      );
      await ack();

      final undoCommits = f.store.queue.debugTransactionCount;
      final result = await f.session.undo();
      await f.session.flush();
      expect(result.applied, isTrue);
      expect(result.skippedEntities, 0);
      expect(f.store.queue.debugTransactionCount, undoCommits + 1);
      expect(await outboxFields(), forward);
      final back = f.session.pageIfLoaded(f.pageId)!;
      expect(_contents(back.objects), _contents(before.objects));
      expect(
        back
            .strokeById(ink())!
            .points
            .contentEquals(before.strokeById(ink())!.points),
        isTrue,
      );
    },
  );

  test('100 object steps undone give back the initial page, in memory and '
      'stored; redone, the edited page', () async {
    f = await UndoFixture.open(
      initial: _initialStrokes,
      objects: _initialObjects,
    );
    final initial = f.session.pageIfLoaded(f.pageId)!.objects;
    const known = ['shape', 'text', 'math', 'image'];
    final added = <ElementId>[];
    for (var step = 0; step < 100; step++) {
      final target = known[step % known.length];
      final EditCommand cmd = switch (step % 5) {
        0 => TransformElements(
          pageId: f.pageId,
          elementIds: [target],
          transform: Affine2.translation(1.5, -0.5),
        ),
        1 => UpdateObjects(
          pageId: f.pageId,
          objects: [
            switch (f.currentObject(target)) {
              final TextBoxObject t => t.copyWith(text: 'step $step'),
              final MathObject m => m.copyWith(latex: 'x^{$step}'),
              final ShapeObject s => s.copyWith(
                style: s.style.copyWith(strokeWidth: 1 + step / 10),
              ),
              final ImageObject i => i.copyWith(
                frame: ElementFrame(
                  PageRect(step.toDouble(), 400, step + 200.0, 550),
                ),
              ),
              final o => o,
            },
          ],
        ),
        2 => AddObjects(
          pageId: f.pageId,
          objects: [
            PageObjectFixtures.textBox(
              pageId: f.pageId,
              id: (added..add('add-$step')).last,
              text: 'added $step',
              createdAt: 100 + step,
            ),
          ],
        ),
        3 => RemoveElements(pageId: f.pageId, elementIds: [added.last]),
        _ => TransformElements(
          pageId: f.pageId,
          elementIds: [ink(), target, known[(step + 1) % known.length]],
          transform: Affine2.translation(-1, 2),
        ),
      };
      f.session.execute(cmd);
    }
    expect(f.session.history.undoDepth, 100);
    await f.session.flush();
    final edited = f.session.pageIfLoaded(f.pageId)!.objects;
    expect(_contents(edited), isNot(_contents(initial)));

    for (var i = 0; i < 100; i++) {
      final r = await f.session.undo();
      expect(r.applied, isTrue, reason: 'undo $i');
      expect(r.skippedEntities, 0);
    }
    await f.session.flush();
    expect(f.session.history.canUndo, isFalse);
    expect(
      _contents(f.session.pageIfLoaded(f.pageId)!.objects),
      _contents(initial),
    );
    expect(
      _contents((await f.store.content.loadPage(f.pageId)).objects),
      _contents(initial),
    );

    for (var i = 0; i < 100; i++) {
      expect((await f.session.redo()).applied, isTrue, reason: 'redo $i');
    }
    await f.session.flush();
    expect(f.session.history.canRedo, isFalse);
    expect(
      _contents(f.session.pageIfLoaded(f.pageId)!.objects),
      _contents(edited),
    );
    expect(
      _contents((await f.store.content.loadPage(f.pageId)).objects),
      _contents(edited),
    );
  });

  test('undo skips an object changed remotely since (6.7.3); the rest of the '
      'step applies', () async {
    f = await UndoFixture.open(objects: _initialObjects);
    final text = f.currentObject('text') as TextBoxObject;
    final math = f.currentObject('math') as MathObject;
    await f.run(
      UpdateObjects(
        pageId: f.pageId,
        objects: [
          text.copyWith(text: 'mine'),
          math.copyWith(latex: 'y'),
        ],
      ),
    );
    final mine = f.currentObject('text') as TextBoxObject;
    await f.remote([mine.copyWith(text: 'remote')]);
    final remoteRow = await f.objectRow('text');
    await ack();

    final result = await f.session.undo();
    await f.session.flush();
    expect(result.applied, isTrue);
    expect(result.skippedEntities, 1);
    expect(result.edit!.deltas.map((d) => d.id), ['math']);
    expect((f.currentObject('text') as TextBoxObject).text, 'remote');
    expect((f.currentObject('math') as MathObject).latex, math.latex);
    expect((await f.objectRow('text')).versions, remoteRow.versions);
    expect(await outboxFields(), {
      'math': {'latex'},
    });
  });

  test(
    'undo of an add whose object was deleted remotely: skipped as a whole',
    () async {
      f = await UndoFixture.open();
      await f.run(
        AddObjects(
          pageId: f.pageId,
          objects: [PageObjectFixtures.shape(pageId: f.pageId, id: 'gone')],
        ),
      );
      final shape = f.currentObject('gone');
      await f.remote([shape.copyWithMeta(deletedAt: 77, updatedAt: 77)]);
      final result = await f.session.undo();
      expect(result.applied, isFalse);
      expect(result.skippedEntries, 1);
      expect(f.session.history.canUndo, isFalse);
      expect((await f.objectRow('gone')).entity.deletedAt, 77);
    },
  );
}
