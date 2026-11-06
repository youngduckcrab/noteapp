// test/support/fixtures.dart — 05-library 8 L0. Everything is created through
// the CORE API (FakeLibraryBackend.seed*), so the same fixture works on the
// fake store and on real CORE (L21).
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' show PageObjectFixtures;

import 'fake_library_backend.dart';

/// What [seedSampleLibrary] created (CORE values as returned at creation).
final class SampleLibrary {
  SampleLibrary({
    required this.homeFolders,
    required this.homeNotes,
    required this.nested,
    required this.deepNote,
  });

  /// '수학', '영어', '과학' at home (created in this order).
  final List<Folder> homeFolders;

  /// '회의록', '독서 기록', '아이디어', '일기' at home (created in this order).
  final List<Note> homeNotes;

  /// '미적분' ⊂ '수학', '극한' ⊂ '미적분', '연습 문제' ⊂ '극한' — 3 levels
  /// below a home folder.
  final List<Folder> nested;

  /// '극한 정리' in the deepest folder ('연습 문제').
  final Note deepNote;

  Folder get math => homeFolders[0];
  Folder get english => homeFolders[1];
  Folder get science => homeFolders[2];
  Folder get deepest => nested.last;
}

/// Seeds home with 3 folders and 4 notes, plus 3 levels of sub-folders under
/// '수학' with one note at the bottom. Each item is created one minute after
/// the previous one, starting at [start] (default 2026-11-01 09:00 local);
/// the backend clock is left at [after] (default 2026-11-04 14:05 local, the
/// TestClock default).
Future<SampleLibrary> seedSampleLibrary(
  FakeLibraryBackend backend, {
  DateTime? start,
  DateTime? after,
}) async {
  var at = start ?? DateTime(2026, 11, 1, 9);
  DateTime next() => at = at.add(const Duration(minutes: 1));

  final homeFolders = <Folder>[
    for (final name in const ['수학', '영어', '과학'])
      await backend.seedFolder(name, at: next()),
  ];
  final homeNotes = <Note>[
    for (final title in const ['회의록', '독서 기록', '아이디어', '일기'])
      await backend.seedNote(title, at: next()),
  ];
  final nested = <Folder>[];
  FolderId parent = homeFolders.first.id;
  for (final name in const ['미적분', '극한', '연습 문제']) {
    final folder = await backend.seedFolder(name, parentId: parent, at: next());
    nested.add(folder);
    parent = folder.id;
  }
  final deepNote = await backend.seedNote(
    '극한 정리',
    folderId: parent,
    at: next(),
  );
  backend.clock.current = after ?? DateTime(2026, 11, 4, 14, 5);
  return SampleLibrary(
    homeFolders: homeFolders,
    homeNotes: homeNotes,
    nested: nested,
    deepNote: deepNote,
  );
}

/// A PDF asset id ('<64 hex>') for [seedContentHits].
const String kContentPdfAsset =
    'c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00c0ffee00';

/// What [seedContentHits] created (ids and the rects it wrote, note page pt).
final class ContentHitsSample {
  ContentHitsSample({
    required this.work,
    required this.math,
    required this.meeting,
    required this.calculus,
    required this.report,
    required this.meetingPages,
    required this.calculusPages,
    required this.reportPage,
  });

  /// '업무' and '수학' at home.
  final Folder work;
  final Folder math;

  /// '회의록 2026-11' in '업무': page 1 text box '회의 안건: 예산' ([agendaRect]),
  /// page 2 handwriting — '지난주 회의록을 정리' ([inkLine1]) and '다음 할 일'
  /// ([inkLine2]).
  final Note meeting;

  /// '미분 방정식' in '수학': page 1 text box '미분 회의 메모' ([memoRect]),
  /// page 2 math `\frac{dy}{dx} = ky` ([mathRect]).
  final Note calculus;

  /// '분기 보고' at home: one page showing PDF page 0 of [kContentPdfAsset],
  /// whose unit is '분기 회의 자료 정리' (no boxes).
  final Note report;

  final List<PageId> meetingPages;
  final List<PageId> calculusPages;
  final PageId reportPage;

  static const PageRect agendaRect = PageRect(100, 300, 400, 340);
  static const PageRect memoRect = PageRect(80, 120, 360, 160);
  static const PageRect mathRect = PageRect(100, 600, 260, 650);
  static const PageRect inkLine1 = PageRect(40, 100, 420, 140);
  static const PageRect inkLine2 = PageRect(40, 160, 300, 200);
}

/// 05-library 6.1.7: three notes in two folders with every content source —
/// two text boxes (session AddObjects), one math object, one handwriting page
/// (store.handwriting.put, 2 lines — seeding only; product code uses update)
/// and one pdf unit (store.search.replaceUnits on the asset a page shows).
/// Everything goes through the public CORE API, so it works on real CORE
/// (L2-I2). '회의' finds all four notes' sources except the math.
Future<ContentHitsSample> seedContentHits(FakeLibraryBackend backend) async {
  final store = backend.store;
  final work = await backend.seedFolder('업무');
  final math = await backend.seedFolder('수학');
  final meeting = await backend.seedNote(
    '회의록 2026-11',
    folderId: work.id,
    pages: const [PageDraft.blankA4, PageDraft.blankA4],
  );
  final calculus = await backend.seedNote(
    '미분 방정식',
    folderId: math.id,
    pages: const [PageDraft.blankA4, PageDraft.blankA4],
  );
  final report = await backend.seedNote(
    '분기 보고',
    pages: const [
      PageDraft(
        size: PageSize(595, 842),
        background: PdfBackground(assetId: kContentPdfAsset, pdfPageIndex: 0),
      ),
    ],
  );
  Future<List<PageId>> pagesOf(Note note) async => [
    for (final p in await store.content.pagesOf(note.id)) p.id,
  ];
  final meetingPages = await pagesOf(meeting);
  final calculusPages = await pagesOf(calculus);
  final reportPage = (await pagesOf(report)).single;

  Future<void> addObjects(NoteId noteId, PageId pageId, PageObject o) async {
    final session = await store.openSession(noteId);
    await session.openPage(pageId);
    await session.execute(AddObjects(pageId: pageId, objects: [o])).persisted;
    await session.close();
  }

  await addObjects(
    meeting.id,
    meetingPages[0],
    PageObjectFixtures.textBox(
      pageId: meetingPages[0],
      text: '회의 안건: 예산',
      rect: ContentHitsSample.agendaRect,
    ),
  );
  await addObjects(
    calculus.id,
    calculusPages[0],
    PageObjectFixtures.textBox(
      pageId: calculusPages[0],
      text: '미분 회의 메모',
      rect: ContentHitsSample.memoRect,
    ),
  );
  await addObjects(
    calculus.id,
    calculusPages[1],
    PageObjectFixtures.math(
      pageId: calculusPages[1],
      latex: r'\frac{dy}{dx} = ky',
      rect: ContentHitsSample.mathRect,
    ),
  );
  await store.handwriting.put(
    HandwritingText(
      noteId: meeting.id,
      pageId: meetingPages[1],
      engineId: 'fake/1:ko',
      sourceRev: '0000000000000000',
      lines: const [
        HandwritingLine(
          text: '지난주 회의록을 정리',
          rect: ContentHitsSample.inkLine1,
          strokeIds: ['seed-ink-1'],
        ),
        HandwritingLine(
          text: '다음 할 일',
          rect: ContentHitsSample.inkLine2,
          strokeIds: ['seed-ink-2'],
        ),
      ],
      createdAt: backend.clock.clock.now().millisecondsSinceEpoch,
    ),
  );
  await store.search.replaceUnits(
    SearchSource.pdf,
    '$kContentPdfAsset#0',
    const [SearchUnitDraft(body: '분기 회의 자료 정리')],
    sourceRev: '$kContentPdfAsset:1',
  );
  await store.flush();
  return ContentHitsSample(
    work: work,
    math: math,
    meeting: meeting,
    calculus: calculus,
    report: report,
    meetingPages: meetingPages,
    calculusPages: calculusPages,
    reportPage: reportPage,
  );
}
