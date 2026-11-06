// CORE T29 (in part) — permanent delete v2 (m5-7/02-core 6.14.2): purging a trash group
// (purge, emptyTrash, purgeExpired) or a RemotePurge also deletes the notes' page objects and
// handwriting results with their outbox entries, their own search owners / units / FTS rows,
// and their recording draft rows — the draft chunks and meta after the commit; pdf search
// owners (per asset) stay, and other notes keep everything. The fake store does the same
// (fake_note_store.dart _purgeGroup — the content checks run on both).
@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:note_core/note_core.dart';
import 'package:note_core/src/storage/drift_note_store.dart';
import 'package:note_core/testing.dart'
    show PageObjectFixtures, createFakeNoteStore, newerVersionWinsPolicy;
import 'package:test/test.dart';

import '../storage/storage_support.dart';

const String _asset =
    '1111111111111111111111111111111111111111111111111111111111111111';

/// What a note leaves behind, through the public API (both stores).
typedef Left = ({
  int objects,
  bool handwriting,
  int textHits,
  int inkHits,
  int drafts,
  String? pdfRev,
});

/// A note with a text box, a handwriting result, a recording draft (two chunks) and a page
/// showing PDF page 0 of [_asset] (indexed); returns the note and its first page.
Future<(Note, PageId)> fullNote(NoteStore store, String word) async {
  final note = await store.library.createNote(
    title: 'purge $word',
    pages: [
      PageDraft(
        size: PageSize.a4Portrait,
        background: const BlankBackground(),
        objects: [PageObjectFixtures.textBox(pageId: 'x', text: '$word 텍스트')],
      ),
      const PageDraft(
        size: PageSize.a4Portrait,
        background: PdfBackground(assetId: _asset, pdfPageIndex: 0),
      ),
    ],
  );
  final page = (await store.content.pagesOf(note.id)).first.id;
  await store.handwriting.put(
    HandwritingText(
      noteId: note.id,
      pageId: page,
      engineId: 'fake/1:ko',
      sourceRev: '0000000000000000',
      lines: [
        HandwritingLine(
          text: '$word 손글씨',
          rect: const PageRect(10, 10, 100, 30),
          strokeIds: const ['s1'],
          languageTag: 'ko',
        ),
      ],
      createdAt: 1,
    ),
  );
  final draft = await store.recordingDrafts.begin(
    recordingId: store.ids.newId(),
    noteId: note.id,
    mimeType: 'audio/webm',
    startedAt: 1,
  );
  await store.recordingDrafts.append(
    draft.draftId,
    Uint8List.fromList([1, 2, 3]),
    activeMs: 10,
  );
  await store.recordingDrafts.append(
    draft.draftId,
    Uint8List.fromList([4, 5]),
    activeMs: 20,
  );
  await store.search.replaceUnits(SearchSource.pdf, '$_asset#0', const [
    SearchUnitDraft(body: '공유 교재'),
  ], sourceRev: 'pdf-1');
  return (note, page);
}

Future<Left> leftOf(
  NoteStore store,
  Note note,
  PageId page,
  String word,
) async {
  var objects = 0;
  try {
    objects = (await store.content.loadPage(page)).objects.length;
  } on EntityNotFoundException {
    // The page is gone with its note.
  }
  return (
    objects: objects,
    handwriting: await store.handwriting.forPage(page) != null,
    textHits: (await store.search.searchPages('$word 텍스트')).length,
    inkHits: (await store.search.searchPages('$word 손글씨')).length,
    drafts: [
      for (final d in await store.recordingDrafts.listDrafts())
        if (d.noteId == note.id) d,
    ].length,
    pdfRev: await store.search.sourceRevOf(SearchSource.pdf, '$_asset#0'),
  );
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

      for (final (how, purge)
          in <(String, Future<void> Function(NoteStore, Note))>[
            ('purge', (s, n) => s.trash.purge([NoteRef(n.id)])),
            ('emptyTrash', (s, n) => s.trash.emptyTrash()),
          ]) {
        test(
          '$how: objects, handwriting, search rows and drafts go; pdf stays',
          () async {
            final (gone, gonePage) = await fullNote(store, '삭제');
            final (kept, keptPage) = await fullNote(store, '유지');
            expect(await leftOf(store, gone, gonePage, '삭제'), (
              objects: 1,
              handwriting: true,
              textHits: 1,
              inkHits: 1,
              drafts: 1,
              pdfRev: 'pdf-1',
            ));
            await store.library.trashItems([NoteRef(gone.id)]);
            await purge(store, gone);
            expect(await store.library.getNote(gone.id), isNull);
            expect(await leftOf(store, gone, gonePage, '삭제'), (
              objects: 0,
              handwriting: false,
              textHits: 0,
              inkHits: 0,
              drafts: 0,
              pdfRev: 'pdf-1',
            ));
            // The other note keeps everything, and the shared PDF page still finds it.
            expect(await leftOf(store, kept, keptPage, '유지'), (
              objects: 1,
              handwriting: true,
              textHits: 1,
              inkHits: 1,
              drafts: 1,
              pdfRev: 'pdf-1',
            ));
            expect(
              [for (final h in await store.search.searchPages('교재')) h.noteId],
              [kept.id],
            );
          },
        );
      }
    });
  }

  group('real: rows, outbox, blobs', () {
    late DriftNoteStore store;
    late int nowMs;
    setUp(() async {
      nowMs = DateTime.utc(2026, 11, 6).millisecondsSinceEpoch;
      store = await openStore(
        clock: Clock(() => DateTime.fromMillisecondsSinceEpoch(nowMs)),
      );
    });
    tearDown(() => store.close());

    Future<int> count(String sql, [List<Object> args = const []]) async =>
        (await store.db
                .customSelect(
                  sql,
                  variables: [for (final a in args) Variable<Object>(a)],
                )
                .getSingle())
            .read<int>('c');

    Future<Map<String, int>> rowsOf(NoteId noteId) async => {
      'page_objects': await count(
        'SELECT count(*) AS c FROM page_objects WHERE note_id = ?',
        [noteId],
      ),
      'handwriting': await count(
        'SELECT count(*) AS c FROM handwriting WHERE note_id = ?',
        [noteId],
      ),
      'search_owners': await count(
        'SELECT count(*) AS c FROM search_owners WHERE note_id = ?',
        [noteId],
      ),
      'search_units': await count(
        'SELECT count(*) AS c FROM search_units WHERE note_id = ?',
        [noteId],
      ),
      'recording_drafts': await count(
        'SELECT count(*) AS c FROM recording_drafts WHERE note_id = ?',
        [noteId],
      ),
      'outbox': await count(
        'SELECT count(*) AS c FROM outbox WHERE note_id = ?',
        [noteId],
      ),
    };

    Future<int> ftsRows() async => count(
      "SELECT count(*) AS c FROM search_fts WHERE search_fts MATCH '\"교재\" OR \"삭제\" OR \"유지\"'",
    );

    test(
      'purgeExpired deletes the rows, the outbox entries and the draft blobs',
      () async {
        final (gone, _) = await fullNote(store, '삭제');
        final (kept, _) = await fullNote(store, '유지');
        final goneDraft = (await store.recordingDrafts.listDrafts())
            .firstWhere((d) => d.noteId == gone.id)
            .draftId;
        expect(
          await store.recordingDrafts.blobs.keys('rd/$goneDraft/'),
          isNotEmpty,
        );
        final before = await rowsOf(gone.id);
        expect(before.values.every((n) => n > 0), isTrue, reason: '$before');
        final ftsBefore = await ftsRows();
        final pdfUnits = await count(
          "SELECT count(*) AS c FROM search_units WHERE source = 'pdf'",
        );
        await store.library.trashItems([NoteRef(gone.id)]);
        expect(await store.trash.purgeExpired(), 0); // not expired yet
        expect(await store.library.getNote(gone.id), isNotNull);
        nowMs += const Duration(days: 31)
            .inMilliseconds; // past the 30-day retention
        expect(await store.trash.purgeExpired(), 1);
        expect(await rowsOf(gone.id), {for (final k in before.keys) k: 0});
        // 'text' and 'ink' units of the purged note: two FTS rows fewer.
        expect(await ftsRows(), ftsBefore - 2);
        expect(
          await count(
            "SELECT count(*) AS c FROM search_units WHERE source = 'pdf'",
          ),
          pdfUnits,
        );
        expect(
          await store.recordingDrafts.blobs.keys('rd/$goneDraft/'),
          isEmpty,
        );
        expect((await rowsOf(kept.id)).values.every((n) => n > 0), isTrue);
      },
    );

    test('RemotePurge deletes the same', () async {
      final (gone, _) = await fullNote(store, '삭제');
      final goneDraft =
          (await store.recordingDrafts.listDrafts()).single.draftId;
      final report = await store.sync.applyRemote([
        RemotePurge(EntityKind.note, gone.id),
      ], policy: newerVersionWinsPolicy);
      expect(report.purged, 1);
      expect((await rowsOf(gone.id)).values.toSet(), {0});
      expect(await store.recordingDrafts.blobs.keys('rd/$goneDraft/'), isEmpty);
      expect(
        await store.search.sourceRevOf(SearchSource.pdf, '$_asset#0'),
        'pdf-1',
      );
    });
  });
}
