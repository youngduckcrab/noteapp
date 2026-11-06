// CORE T29 (in part) — copyNote v2 (m5-7/02-core 6.14.1), the path of copyItems and
// duplicateNoteForRecovery: after the 1st-round note → pages → strokes copy, ① the note's
// active recordings under new ids (same asset / title / timing; deleted ones are not
// copied), ② copied strokes linked to a copied recording get its new id (others keep their
// id — R-7), ③ active page objects under new ids with the same asset and createdAt, ④ each
// page's handwriting result for the new note / page with strokeIds mapped (ids not copied
// dropped) and the sourceRev of the copied input strokes — the copy has no stale page —
// and ⑤ the copy is searchable at once. Shared by the fake and the real store (the library
// contract body runs on both — test/shared/library_contract.dart); duplicateNoteForRecovery
// and the outbox entries on the real store only (the fake SyncStore does not have it).
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart'
    show PageObjectFixtures, StrokeFixtures, createFakeNoteStore;
import 'package:test/test.dart';

import '../storage/storage_support.dart';

const String _image =
    '2222222222222222222222222222222222222222222222222222222222222222';

/// What the tests seed: a note whose first page holds five strokes (0 → recording A,
/// 1 → recording B (deleted), 2 → none, 3 a highlighter, 4 erased), five objects (one removed
/// again), a handwriting result over strokes 0, 1, 2 and 4, and a blank second page; the
/// note has a third recording C with no strokes.
typedef Seeded = ({
  Note note,
  PageId page,
  List<Stroke> strokes, // active, by createdAt
  ElementId erased,
  List<PageObject> objects, // active, Stroke.compareOrder
  Recording recA,
  Recording recC,
  RecordingId recB,
  HandwritingText handwriting,
});

Future<Seeded> seed(NoteStore store) async {
  final audio = await store.assets.put(
    Uint8List.fromList(List.filled(64, 7)),
    type: AssetType.audio,
    mimeType: 'audio/mp4',
  );
  final ids = [for (var i = 0; i < 3; i++) store.ids.newId()];
  final (recAId, recBId, recCId) = (ids[0], ids[1], ids[2]);
  const draftPage = 'draft-page';
  Stroke stroke(int i, {RecordingId? rec, PenTool tool = PenTool.ballpoint}) {
    final s = StrokeFixtures.synthetic(
      pageId: draftPage,
      ids: store.ids,
      seed: i,
      tool: tool,
      createdAt: 100 + i,
    );
    return rec == null
        ? s
        : Stroke(
            id: s.id,
            pageId: s.pageId,
            style: s.style,
            points: s.points,
            recordingId: rec,
            recordingOffsetMs: 1000 * (i + 1),
            createdAt: s.createdAt,
          );
  }

  final note = await store.library.createNote(
    title: '원본',
    pages: [
      PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        strokes: [
          stroke(0, rec: recAId),
          stroke(1, rec: recBId),
          stroke(2),
          stroke(3, tool: PenTool.highlighter),
          stroke(4),
        ],
        objects: [
          PageObjectFixtures.shape(pageId: draftPage, createdAt: 10),
          PageObjectFixtures.textBox(
            pageId: draftPage,
            text: '복사 텍스트',
            createdAt: 11,
          ),
          PageObjectFixtures.image(
            pageId: draftPage,
            assetId: _image,
            createdAt: 12,
          ),
          PageObjectFixtures.math(pageId: draftPage, createdAt: 13),
          PageObjectFixtures.unknown(pageId: draftPage),
        ],
      ),
      PageDraft.blankA4,
    ],
  );
  final page = (await store.content.pagesOf(note.id)).first.id;
  final before = await store.content.loadPage(page);
  final byCreated = {for (final s in before.strokes) s.createdAt: s};
  final erased = byCreated[104]!.id;
  final removedObject = before.objects.firstWhere((o) => o is ShapeObject).id;
  final session = await store.openSession(note.id);
  await session.openPage(page);
  await session
      .execute(
        RemoveElements(pageId: page, elementIds: [erased, removedObject]),
      )
      .persisted;
  await session.close();

  Future<Recording> record(RecordingId id, int startedAt, String? title) =>
      store.recordings.createRecording(
        id: id,
        noteId: note.id,
        assetId: audio.id,
        durationMs: 5000 + startedAt,
        startedAt: startedAt,
        title: title,
      );
  final recA = await record(recAId, 2000, '강의 1');
  await record(recBId, 3000, null);
  await store.recordings.deleteRecording(recBId);
  final recC = await record(recCId, 4000, null);

  final handwriting = HandwritingText(
    noteId: note.id,
    pageId: page,
    engineId: 'fake/1:ko',
    sourceRev: '0000000000000000',
    lines: [
      HandwritingLine(
        text: '복사 손글씨',
        rect: const PageRect(10, 10, 200, 40),
        strokeIds: [byCreated[100]!.id, byCreated[101]!.id, erased],
        languageTag: 'ko',
      ),
      HandwritingLine(
        text: '둘째 줄',
        alternatives: const ['둘째 즐'],
        rect: const PageRect(10, 50, 200, 80),
        strokeIds: [byCreated[102]!.id],
        languageTag: 'ko',
      ),
    ],
    createdAt: 5,
  );
  await store.handwriting.put(handwriting);
  final content = await store.content.loadPage(page);
  return (
    note: (await store.library.getNote(note.id))!,
    page: page,
    strokes: [...content.strokes]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
    erased: erased,
    objects: content.objects,
    recA: recA,
    recC: recC,
    recB: recBId,
    handwriting: (await store.handwriting.forPage(page))!,
  );
}

/// [o]'s JSON without the keys a copy changes.
Map<String, Object?> _kept(PageObject o) => {...o.toJson()}
  ..remove('id')
  ..remove('pageId')
  ..remove('updatedAt')
  ..remove('version');

/// Checks the copy [copyId] of [src] against 6.14.1 ①~⑤.
Future<void> expectCopied(NoteStore store, Seeded src, NoteId copyId) async {
  final copy = (await store.library.getNote(copyId))!;
  expect(copy.pageCount, 2);
  final copyPage = (await store.content.pagesOf(copyId)).first.id;
  expect(copyPage, isNot(src.page));

  // ① recordings: the active ones (A, C) under new ids; B (deleted) is not copied.
  final recs = await store.recordings.recordingsOf(copyId);
  expect(recs, hasLength(2));
  for (final (r, o) in [(recs[0], src.recA), (recs[1], src.recC)]) {
    expect(r.id, isNot(o.id));
    expect(r.noteId, copyId);
    expect(r.assetId, o.assetId);
    expect(r.title, o.title);
    expect(r.durationMs, o.durationMs);
    expect(r.startedAt, o.startedAt);
    expect(r.createdAt, r.updatedAt);
    expect(r.isDeleted, isFalse);
  }
  final newA = recs[0].id;
  expect(
    [for (final r in await store.recordings.recordingsOf(src.note.id)) r.id],
    [src.recA.id, src.recC.id],
    reason: 'the original keeps its recordings',
  );

  // ② strokes: new ids, the recording link moved to the copied recording.
  final content = await store.content.loadPage(copyPage);
  final strokes = [...content.strokes]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  expect([for (final s in strokes) s.createdAt], [100, 101, 102, 103]);
  final strokeIds = <ElementId, ElementId>{};
  for (var i = 0; i < strokes.length; i++) {
    final (c, o) = (strokes[i], src.strokes[i]);
    strokeIds[o.id] = c.id;
    expect(c.id, isNot(o.id));
    expect(c.pageId, copyPage);
    expect(c.points.contentEquals(o.points), isTrue);
    expect(c.recordingOffsetMs, o.recordingOffsetMs);
  }
  expect(strokes[0].recordingId, newA, reason: 'R-6: the copied recording');
  expect(
    strokes[1].recordingId,
    src.recB,
    reason: 'a deleted recording is not copied — the link stays (R-7)',
  );
  expect(strokes[2].recordingId, isNull);

  // ③ objects: new ids on the new page, everything else (asset, createdAt) the same.
  expect(content.objects, hasLength(src.objects.length));
  for (var i = 0; i < src.objects.length; i++) {
    final (c, o) = (content.objects[i], src.objects[i]);
    expect(c.id, isNot(o.id));
    expect(c.pageId, copyPage);
    expect(c.createdAt, o.createdAt);
    expect(c.type, o.type);
    expect(_kept(c), _kept(o));
    if (c is ImageObject) expect(c.assetId, _image);
  }
  expect(content.objects.whereType<UnknownObject>(), hasLength(1));

  // ④ handwriting: the new note / page, stroke ids mapped (the erased one dropped), the
  // sourceRev of the copied input strokes (the highlighter is no input) — not stale.
  final hw = (await store.handwriting.forPage(copyPage))!;
  expect(hw.noteId, copyId);
  expect(hw.pageId, copyPage);
  expect(hw.id, HandwritingText.idFor(copyPage));
  expect(hw.engineId, src.handwriting.engineId);
  expect(hw.lines.map((l) => l.text), ['복사 손글씨', '둘째 줄']);
  expect(hw.lines[1].alternatives, ['둘째 즐']);
  expect(hw.lines[0].rect, src.handwriting.lines[0].rect);
  expect(hw.lines[0].strokeIds, [
    strokeIds[src.strokes[0].id],
    strokeIds[src.strokes[1].id],
  ]);
  expect(hw.lines[1].strokeIds, [strokeIds[src.strokes[2].id]]);
  expect(
    hw.sourceRev,
    HandwritingText.sourceRevOf(
      strokes.where(HandwritingText.isRecognitionInput),
    ),
  );
  expect(await store.handwriting.stalePages(copyId), isEmpty);
  expect(await store.handwriting.stalePages(src.note.id), [
    src.page,
  ], reason: 'the original result was stale and stays so');
  expect(await store.handwriting.forPage(src.page), src.handwriting);

  // ⑤ searchable at once: the text box and the handwriting, in both notes.
  for (final q in ['복사 텍스트', '복사 손글씨']) {
    final hits = await store.search.searchPages(q);
    expect({for (final h in hits) h.noteId}, {src.note.id, copyId}, reason: q);
    final within = await store.search.searchPages(q, withinNote: copyId);
    expect([for (final h in within) h.pageId], [copyPage], reason: q);
  }

  // The original page is untouched.
  final original = await store.content.loadPage(src.page);
  expect(original.objects, src.objects);
  expect(original.strokes, hasLength(4));
}

void main() {
  for (final (name, open) in <(String, Future<NoteStore> Function())>[
    ('fake', () async => createFakeNoteStore(seedDefaultPenPresets: false)),
    ('real', () async => openStore()),
  ]) {
    group(name, () {
      late NoteStore store;
      setUp(() async => store = await open());
      tearDown(() => store.close());

      test('copyItems(note): recordings, strokes, objects, handwriting, '
          'search (6.14.1 ①~⑤)', () async {
        final src = await seed(store);
        final out = await store.library.copyItems(
          [NoteRef(src.note.id)],
          targetFolderId: null,
          nameSuffix: ' 사본',
        );
        final copyId = out.single.id;
        expect((await store.library.getNote(copyId))!.title, '원본 사본');
        await expectCopied(store, src, copyId);
      });

      test('copyItems(folder): notes inside are copied the same way', () async {
        final f = await store.library.createFolder(name: 'f');
        final src = await seed(store);
        await store.library.moveItems([
          NoteRef(src.note.id),
        ], targetFolderId: f.id);
        final out = await store.library.copyItems([
          FolderRef(f.id),
        ], targetFolderId: null);
        final listing = await store.library
            .watchListing(LibraryQuery(folderId: out.single.id))
            .first;
        await expectCopied(store, src, listing.notes.single.id);
      });

      test('a copy of a copy maps the copied ids again', () async {
        final src = await seed(store);
        final first = (await store.library.copyItems([
          NoteRef(src.note.id),
        ], targetFolderId: null)).single.id;
        final second = (await store.library.copyItems([
          NoteRef(first),
        ], targetFolderId: null)).single.id;
        final firstPage = (await store.content.pagesOf(first)).first.id;
        final secondPage = (await store.content.pagesOf(second)).first.id;
        final firstRecs = await store.recordings.recordingsOf(first);
        final secondRecs = await store.recordings.recordingsOf(second);
        expect(secondRecs, hasLength(2));
        final strokes = (await store.content.loadPage(
          secondPage,
        )).strokes.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        expect(strokes[0].recordingId, secondRecs[0].id);
        expect(strokes[0].recordingId, isNot(firstRecs[0].id));
        final hw = (await store.handwriting.forPage(secondPage))!;
        expect(hw.noteId, second);
        expect(hw.lines[0].strokeIds, [strokes[0].id, strokes[1].id]);
        expect(await store.handwriting.stalePages(second), isEmpty);
        expect(await store.handwriting.stalePages(first), isEmpty);
        expect(firstPage, isNot(secondPage));
      });
    });
  }

  group('real: duplicateNoteForRecovery and the outbox', () {
    late NoteStore store;
    setUp(() async => store = await openStore());
    tearDown(() => store.close());

    test('a trashed note → the same copy (6.14.1 is its path too)', () async {
      final src = await seed(store);
      await store.library.trashItems([NoteRef(src.note.id)]);
      final copyId = await store.sync.duplicateNoteForRecovery(
        src.note.id,
        titleSuffix: ' (복구)',
      );
      expect(copyId, isNotNull);
      final copy = (await store.library.getNote(copyId!))!;
      expect(copy.isDeleted, isFalse);
      expect(copy.title, '원본 (복구)');
      // The original is in the trash: search finds the copy only.
      final copyPage = (await store.content.pagesOf(copyId)).first.id;
      expect(
        [for (final h in await store.search.searchPages('복사 손글씨')) h.pageId],
        [copyPage],
      );
      await store.trash.restore([NoteRef(src.note.id)]);
      await expectCopied(store, src, copyId);
    });

    test(
      'outbox: the new kinds with their note / page hints, all keys',
      () async {
        final src = await seed(store);
        await store.sync.acknowledge([
          for (final e in await store.sync.pendingChanges(limit: 100000)) e.ack,
        ]);
        final copyId = (await store.library.copyItems([
          NoteRef(src.note.id),
        ], targetFolderId: null)).single.id;
        final copyPage = (await store.content.pagesOf(copyId)).first.id;
        final pending = await store.sync.pendingChanges(limit: 100000);
        final byKind = <EntityKind, List<OutboxEntry>>{};
        for (final e in pending) {
          (byKind[e.kind] ??= []).add(e);
        }
        expect(byKind[EntityKind.recording], hasLength(2));
        expect(byKind[EntityKind.pageObject], hasLength(4));
        expect(byKind[EntityKind.handwriting], hasLength(1));
        expect(byKind[EntityKind.stroke], hasLength(4));
        for (final kind in [
          EntityKind.recording,
          EntityKind.pageObject,
          EntityKind.handwriting,
        ]) {
          for (final e in byKind[kind]!) {
            expect(e.noteId, copyId, reason: '$kind');
            expect(e.op, OutboxOp.upsert, reason: '$kind');
            expect(e.changedFields, {kAllFields}, reason: '$kind');
            if (kind != EntityKind.recording) {
              expect(e.pageId, copyPage, reason: '$kind');
            }
          }
        }
      },
    );
  });
}
