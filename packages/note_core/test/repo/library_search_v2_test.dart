// CORE T34 — searchLibrary v2 (m5-7/02-core 6.10.4 'searchLibrary', contract 7.2.5
// LibrarySearchResult): the 1차 folder / note title results are unchanged by content hits (the
// 1차 cases stay in test/shared/library_contract.dart, run on both stores), `pages` holds the
// content hits (≤ 100, apart from `limit`), `pagesTruncated` when there are more, trashed notes
// leave both lists and come back on restore — on the fake store and the real one, which give
// the same result for the same writes.
@TestOn('vm')
library;

import 'package:clock/clock.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' show createFakeNoteStore;
import 'package:note_core/testing_vm.dart';
import 'package:test/test.dart';

const String _asset =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

/// A note whose pages hold one text box each with [bodies].
Future<(Note, List<PageId>)> textNote(
  NoteStore store,
  String title,
  List<String> bodies, {
  FolderId? folderId,
}) async {
  final note = await store.library.createNote(
    title: title,
    folderId: folderId,
    pages: [for (final _ in bodies) PageDraft.blankA4],
  );
  final pages = [for (final p in await store.content.pagesOf(note.id)) p.id];
  final session = await store.openSession(note.id);
  for (final (i, body) in bodies.indexed) {
    await session.openPage(pages[i]);
    await session
        .execute(
          AddObjects(
            pageId: pages[i],
            objects: [
              TextBoxObject(
                id: store.ids.newId(),
                pageId: pages[i],
                frame: ElementFrame(PageRect(10, 10.0 + i, 300, 50)),
                text: body,
                style: const TextBoxStyle(),
                createdAt: 1,
              ),
            ],
          ),
        )
        .persisted;
  }
  await session.close();
  return (note, pages);
}

/// A note of [count] pages showing PDF pages 0..count-1 of [_asset], each indexed with [body].
Future<Note> pdfNote(
  NoteStore store,
  String title,
  int count,
  String body,
) async {
  final note = await store.library.createNote(
    title: title,
    pages: [
      for (var i = 0; i < count; i++)
        PageDraft(
          size: PageSize.a4Portrait,
          background: PdfBackground(assetId: _asset, pdfPageIndex: i),
        ),
    ],
  );
  for (var i = 0; i < count; i++) {
    await store.search.replaceUnits(SearchSource.pdf, '$_asset#$i', [
      SearchUnitDraft(body: '$body $i'),
    ], sourceRev: 'r1');
  }
  return note;
}

void defineLibrarySearchV2(Future<NoteStore> Function() open) {
  late NoteStore store;
  setUp(() async => store = await open());
  tearDown(() => store.close());

  test('titles as in 1차; content hits only in pages', () async {
    final folder = await store.library.createFolder(name: '강의 자료');
    final (titled, titledPages) = await textNote(store, '강의 노트', const [
      '오늘의 요약',
    ]);
    final (other, otherPages) = await textNote(store, '다른 노트', const [
      '강의 내용',
      '관계없음',
    ], folderId: folder.id);
    final r = await store.library.searchLibrary('강의');
    expect(r.query, '강의');
    expect(r.folders.map((f) => f.id), [folder.id]);
    expect(r.notes.map((n) => n.id), [
      titled.id,
    ]); // not 'other' — its title has no '강의'
    expect(r.pages.map((h) => (h.noteId, h.pageId)), [
      (other.id, otherPages.first),
    ]);
    expect(r.pages.single.source, SearchSource.text);
    expect(r.pages.single.snippet, '강의 내용');
    expect(r.pagesTruncated, isFalse);
    expect(titledPages, hasLength(1));
    // A query only the content has: no title result, the page result.
    final content = await store.library.searchLibrary('요약');
    expect(content.notes, isEmpty);
    expect(content.folders, isEmpty);
    expect(content.pages.map((h) => h.pageId), titledPages);
  });

  test('limit is for folders and notes; pages up to 100', () async {
    for (var i = 0; i < 4; i++) {
      await textNote(store, 'note $i', ['note body $i']);
    }
    final r = await store.library.searchLibrary('note', limit: 2);
    expect(r.notes, hasLength(2));
    expect(r.pages, hasLength(4));
    expect(r.pagesTruncated, isFalse);
  });

  test('more than 100 pages: 100 and pagesTruncated', () async {
    await pdfNote(store, 'big', 101, '교재 본문');
    final r = await store.library.searchLibrary('교재');
    expect(r.notes, isEmpty);
    expect(r.pages, hasLength(100));
    expect(r.pagesTruncated, isTrue);
    expect(r.pages.every((h) => h.source == SearchSource.pdf), isTrue);
    // '7' (one code point) must also be on the page: 7, 17 … 97 and 70 … 79.
    final exact = await store.library.searchLibrary('교재 본문 7');
    expect(exact.pages, hasLength(19));
    expect(exact.pagesTruncated, isFalse);
  });

  test(
    'a trashed note leaves notes and pages; restore brings both back',
    () async {
      final (note, pages) = await textNote(store, '복원 노트', const ['복원 본문']);
      var r = await store.library.searchLibrary('복원');
      expect(r.notes.map((n) => n.id), [note.id]);
      expect(r.pages.map((h) => h.pageId), pages);
      await store.library.trashItems([NoteRef(note.id)]);
      r = await store.library.searchLibrary('복원');
      expect(r.notes, isEmpty);
      expect(r.pages, isEmpty);
      expect(r.pagesTruncated, isFalse);
      await store.trash.restore([NoteRef(note.id)]);
      r = await store.library.searchLibrary('복원');
      expect(r.notes.map((n) => n.id), [note.id]);
      expect(r.pages.map((h) => h.pageId), pages);
    },
  );

  test('an empty or blank query: nothing', () async {
    await textNote(store, 'x', const ['본문']);
    for (final q in ['', '   ', '\n']) {
      final r = await store.library.searchLibrary(q);
      expect(r.folders, isEmpty);
      expect(r.notes, isEmpty);
      expect(r.pages, isEmpty);
      expect(r.pagesTruncated, isFalse);
    }
  });
}

/// The result with ids replaced by titles / page positions (the stores make their own ids).
Future<List<Object>> canonical(NoteStore store, LibrarySearchResult r) async {
  Future<String> pageName(NoteId noteId, PageId pageId) async {
    final note = await store.library.getNote(noteId);
    final pages = await store.content.pagesOf(noteId);
    return '${note!.title}#${pages.indexWhere((p) => p.id == pageId)}';
  }

  return [
    [for (final f in r.folders) f.name],
    [for (final n in r.notes) n.title],
    [
      // Lists, not records: the matcher compares lists element by element.
      for (final h in r.pages)
        [
          await pageName(h.noteId, h.pageId),
          h.source,
          h.snippet,
          [h.matchRange.$1, h.matchRange.$2],
          h.rects,
          h.score,
        ],
    ],
    r.pagesTruncated,
  ];
}

void main() {
  group('fake', () {
    defineLibrarySearchV2(
      () async => createFakeNoteStore(seedDefaultPenPresets: false),
    );
  });
  group('real', () {
    defineLibrarySearchV2(
      () => openTestNoteStore(seedDefaultPenPresets: false),
    );
  });

  test(
    'the fake and the real store give the same result for the same writes',
    () async {
      // One fixed clock and sequential ids (the fake's default) on both: equal scores then
      // have equal note times too and are ordered by page id the same way (creation order).
      // With the wall clock the order depended on whether two notes were written in the same
      // millisecond (CI run 43157220645: the fake was, the real store was not).
      final clock = Clock.fixed(DateTime.utc(2026, 11, 12, 9));
      final fake = createFakeNoteStore(
        seedDefaultPenPresets: false,
        clock: clock,
      );
      final real = await openTestNoteStore(
        seedDefaultPenPresets: false,
        ids: SequentialIdGenerator(),
        clock: clock,
      );
      addTearDown(fake.close);
      addTearDown(real.close);
      for (final s in [fake, real]) {
        final folder = await s.library.createFolder(name: '수학 강의');
        await textNote(s, '수학 강의 1', const [
          '미분 강의 정리',
          '적분 meeting',
        ], folderId: folder.id);
        await textNote(s, '노트 b', const ['강의 meeting notes', '수학']);
        await pdfNote(s, '교재', 120, '수학 강의 교재');
      }
      for (final q in ['강의', '수학', 'meet', '교재 1', '정', '없는말']) {
        expect(
          await canonical(real, await real.library.searchLibrary(q)),
          await canonical(fake, await fake.library.searchLibrary(q)),
          reason: q,
        );
      }
    },
  );
}
