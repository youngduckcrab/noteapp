// The fake store v2 (m5-7/02-core 6.17): note copy with objects, recordings and handwriting
// (6.14.1), purge of the new kinds and their search owners (6.14.2), backup with the new kinds
// (6.14.4), the content reader's objects, the v1 copy API of a store without a copy (C22-01 —
// moved here from the B2-α fake test). Web-safe.
import 'dart:convert';
import 'dart:typed_data';

import 'package:note_core/dev_tools.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
import 'package:test/test.dart';

void main() {
  late NoteStore store;
  late Note note;
  late PageId pageId;
  late Recording recording;
  late Recording deletedRecording;
  late List<Stroke> strokes;

  setUp(() async {
    store = createFakeNoteStore();
    note = await store.library.createNote(title: '원본');
    pageId = (await store.content.pagesOf(note.id)).single.id;
    final audio = await store.assets.put(
      Uint8List.fromList([1, 2, 3]),
      type: AssetType.audio,
      mimeType: 'audio/mp4',
    );
    recording = await store.recordings.createRecording(
      id: 'rec-1',
      noteId: note.id,
      assetId: audio.id,
      durationMs: 3000,
      startedAt: 10,
      title: '강의',
    );
    deletedRecording = await store.recordings.createRecording(
      id: 'rec-2',
      noteId: note.id,
      assetId: audio.id,
      durationMs: 1000,
      startedAt: 20,
    );
    await store.recordings.deleteRecording('rec-2');
    final session = await store.openSession(note.id);
    await session.openPage(pageId);
    strokes = [
      StrokeFixtures.synthetic(
        pageId: pageId,
        ids: store.ids,
        createdAt: 5,
      ).copyWith(recordingId: 'rec-1', recordingOffsetMs: 100),
      StrokeFixtures.synthetic(
        pageId: pageId,
        ids: store.ids,
        seed: 1,
        createdAt: 6,
      ).copyWith(recordingId: 'rec-2', recordingOffsetMs: 200),
      StrokeFixtures.synthetic(
        pageId: pageId,
        ids: store.ids,
        seed: 2,
        createdAt: 7,
        tool: PenTool.highlighter,
      ),
    ];
    await session
        .execute(
          CompositeCommand([
            AddStrokes(pageId: pageId, strokes: strokes),
            AddObjects(
              pageId: pageId,
              objects: [
                PageObjectFixtures.textBox(
                  pageId: pageId,
                  text: '복사 시험',
                  createdAt: 3,
                  id: 'tb',
                ),
                PageObjectFixtures.shape(
                  pageId: pageId,
                  createdAt: 4,
                  id: 'sh',
                ),
                PageObjectFixtures.unknown(pageId: pageId, id: 'uk'),
              ],
            ),
          ]),
        )
        .persisted;
    await session.close();
    await store.handwriting.put(
      HandwritingText(
        noteId: note.id,
        pageId: pageId,
        engineId: 'fake/1:ko',
        sourceRev: '0000000000000000',
        lines: [
          HandwritingLine(
            text: '손글씨 줄',
            rect: const PageRect(0, 0, 10, 10),
            strokeIds: [strokes[0].id, strokes[1].id, 'not-copied'],
          ),
        ],
        createdAt: 1,
      ),
    );
  });
  tearDown(() => store.close());

  test(
    'copyItems: recordings, remapped strokes, objects, handwriting (6.14.1)',
    () async {
      final copied = (await store.library.copyItems([
        NoteRef(note.id),
      ], targetFolderId: null)).single;
      final copyPage = (await store.content.pagesOf(copied.id)).single.id;
      // ① recordings: new ids, the same asset, title and timing; deleted ones are not copied.
      final recs = await store.recordings.recordingsOf(copied.id);
      expect(recs, hasLength(1));
      final copy = recs.single;
      expect(copy.id, isNot(recording.id));
      expect(
        [copy.assetId, copy.title, copy.durationMs, copy.startedAt],
        [recording.assetId, '강의', 3000, 10],
      );
      // ② strokes: the copied recording's id; a deleted recording's link stays as it was.
      final content = await store.content.loadPage(copyPage);
      final byOffset = {
        for (final s in content.strokes) s.recordingOffsetMs: s,
      };
      expect(byOffset[100]!.recordingId, copy.id);
      expect(byOffset[200]!.recordingId, deletedRecording.id);
      // ③ objects: new ids, the original createdAt, the same body.
      expect(content.objects, hasLength(3));
      expect(
        content.objects.map((o) => o.id).toSet().intersection({
          'tb',
          'sh',
          'uk',
        }),
        isEmpty,
      );
      expect(content.objects.map((o) => o.createdAt).toList(), [1, 3, 4]);
      expect(content.objects.whereType<TextBoxObject>().single.text, '복사 시험');
      expect(content.objects.every((o) => o.pageId == copyPage), isTrue);
      // ④ handwriting: the new note / page, mapped stroke ids, the copied strokes' sourceRev.
      final hw = (await store.handwriting.forPage(copyPage))!;
      expect(hw.noteId, copied.id);
      final copiedIds = {for (final s in content.strokes) s.id};
      expect(hw.lines.single.strokeIds, hasLength(2));
      expect(copiedIds.containsAll(hw.lines.single.strokeIds), isTrue);
      expect(
        hw.sourceRev,
        HandwritingText.sourceRevOf(
          content.strokes.where(HandwritingText.isRecognitionInput),
        ),
      );
      // ⑤ the copy is searchable at once (text and ink).
      expect(
        (await store.search.searchPages('복사')).map((h) => h.pageId).toSet(),
        {pageId, copyPage},
      );
      expect(
        (await store.search.searchPages('손글씨')).map((h) => h.pageId).toSet(),
        {pageId, copyPage},
      );
    },
  );

  test(
    'purge removes objects, recordings, handwriting and search owners (6.14.2)',
    () async {
      final draft = await store.recordingDrafts.begin(
        recordingId: 'rec-9',
        noteId: note.id,
        mimeType: 'audio/mp4',
        startedAt: 1,
      );
      // An owner without units (an empty text box) goes with the note too.
      final session = await store.openSession(note.id);
      await session.openPage(pageId);
      await session
          .execute(
            AddObjects(
              pageId: pageId,
              objects: [
                PageObjectFixtures.textBox(
                  pageId: pageId,
                  text: '   ',
                  id: 'tb-empty',
                ),
              ],
            ),
          )
          .persisted;
      await session.close();
      expect((await store.search.sourceRevs(SearchSource.text)).keys.toSet(), {
        'tb',
        'tb-empty',
      });
      expect((await store.search.sourceRevs(SearchSource.ink)).keys, [
        HandwritingText.idFor(pageId),
      ]);
      // A pdf owner belongs to its asset, not to a note: it stays.
      final pdfKey = '${'a' * 64}#0';
      await store.search.replaceUnits(SearchSource.pdf, pdfKey, const [
        SearchUnitDraft(body: '피디에프'),
      ], sourceRev: 'r');
      await store.library.trashItems([NoteRef(note.id)]);
      await store.trash.purge([NoteRef(note.id)]);
      expect(await store.recordings.getRecording('rec-1'), isNull);
      expect(await store.handwriting.forPage(pageId), isNull);
      expect(await store.recordingDrafts.listDrafts(), isEmpty);
      expect(store.recordingDrafts.readAll(draft.draftId), throwsStateError);
      expect(await store.search.searchPages('복사'), isEmpty);
      expect(await store.search.searchPages('손글씨'), isEmpty);
      expect(await store.search.sourceRevs(SearchSource.text), isEmpty);
      expect(await store.search.sourceRevs(SearchSource.ink), isEmpty);
      expect(await store.search.sourceRevs(SearchSource.pdf), {pdfKey: 'r'});
    },
  );

  test(
    'the v1 database copy API: the fake has no copy (dev_tools.dart, C22-01)',
    () async {
      expect(await v1DatabaseCopyInfo(store), isNull);
      expect(readV1DatabaseCopy(store).toList(), throwsStateError);
      await deleteV1DatabaseCopy(store); // nothing to delete
    },
  );

  test(
    'backup: the new kinds after the v1.4 ones, id order (6.14.4)',
    () async {
      final text = utf8.decode(await store.exportBackupJson());
      final doc = jsonDecode(text) as Map<String, Object?>;
      final kinds = [
        for (final e in doc['entities']! as List)
          (e as Map<String, Object?>)['kind']! as String,
      ];
      final order = [for (final k in EntityKind.values) k.name];
      final seen = kinds.toSet().toList()
        ..sort((a, b) => order.indexOf(a) - order.indexOf(b));
      expect(
        kinds.toSet().toList(),
        seen,
        reason: 'grouped in EntityKind order',
      );
      expect(kinds.where((k) => k == 'pageObject'), hasLength(3));
      expect(kinds.where((k) => k == 'handwriting'), hasLength(1));
      expect(kinds.where((k) => k == 'recording'), hasLength(2));
      final rec = (doc['entities']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((e) => e['kind'] == 'recording');
      expect((rec['data']! as Map<String, Object?>)['title'], '강의');
    },
  );
}
