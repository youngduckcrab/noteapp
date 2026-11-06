// (v2) The '노트 내용' group of the search results (05-library 6.1.3–6.1.6, 8 L2-02):
// source badges, the snippet highlight, 3 hits per note + '더 보기', page numbers,
// notes in the trash / gone, the previous result while CORE is asked again, the order
// between sources (one test — CP-14), the truncated hint, the empty state and 100 hits.
import 'dart:async';

import 'package:feature_library/feature_library.dart' show LibraryScreen;
import 'package:feature_library/src/l10n/library_strings.dart';
import 'package:feature_library/src/model/content_hits.dart';
import 'package:feature_library/src/state/providers.dart';
import 'package:feature_library/src/ui/content/content_hits_view.dart';
import 'package:feature_library/src/ui/content/search_results_view.dart';
import 'package:feature_library/src/ui/top_bar/library_search_field.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart' show PageObjectFixtures;

import '../support/fake_library_backend.dart';
import '../support/fixtures.dart';
import '../support/library_test_harness.dart';

final Finder searchInput = find.descendant(
  of: find.byType(LibrarySearchField),
  matching: find.byType(TextField),
);

Finder hitRows() => find.byType(ContentHitRow);
Finder noteHeader(String title) => find.ancestor(
  of: find.textContaining(title, findRichText: true),
  matching: find.byType(ContentNoteHeader),
);

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(LibraryScreen)));

/// The (source label, page label, snippet) of every visible hit row, top to
/// bottom.
List<String> rowTexts(WidgetTester tester) {
  final rows = tester.widgetList<ContentHitRow>(hitRows()).toList();
  return [
    for (final row in rows)
      '${LibraryStrings.sourceLabel(row.hit.source)} ${row.hit.snippet}',
  ];
}

/// The parts drawn bold (w700) in the SnippetText of [row], with colors.
List<(String, Color?)> boldParts(WidgetTester tester, Finder row) {
  final text = tester.widget<Text>(
    find.descendant(
      of: find.descendant(of: row, matching: find.byType(SnippetText)),
      matching: find.byType(Text),
    ),
  );
  final parts = <(String, Color?)>[];
  text.textSpan!.visitChildren((span) {
    if (span is TextSpan && span.style?.fontWeight == FontWeight.w700) {
      parts.add((span.text!, span.style!.color));
    }
    return true;
  });
  return parts;
}

PageSearchHit fakeHit(
  NoteId note,
  PageId page, {
  SearchSource source = SearchSource.text,
  String snippet = '회의 메모',
  (int, int) range = (0, 2),
}) => PageSearchHit(
  noteId: note,
  pageId: page,
  source: source,
  snippet: snippet,
  matchRange: range,
  score: 1,
);

void main() {
  late FakeLibraryBackend backend;

  setUp(() => backend = FakeLibraryBackend());
  tearDown(() => backend.dispose());

  Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  Future<LibraryTestHarness> pumpAt(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    final h = LibraryTestHarness(backend, extraOverrides: overrides);
    await h.pump(tester);
    await tester.pumpAndSettle();
    return h;
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(searchInput, text);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  int searches(String query) => backend.queries
      .where((q) => q == "searchLibrary '$query' limit:50")
      .length;

  /// A note with [n] pages, each holding one text box '<word> <k>'.
  Future<(Note, List<PageId>)> seedWordNote(
    WidgetTester tester,
    String title,
    String word,
    int n,
  ) => real(tester, () async {
    final note = await backend.seedNote(
      title,
      pages: [for (var i = 0; i < n; i++) PageDraft.blankA4],
    );
    final pages = [
      for (final p in await backend.store.content.pagesOf(note.id)) p.id,
    ];
    final session = await backend.store.openSession(note.id);
    for (final (i, page) in pages.indexed) {
      await session.openPage(page);
      await session
          .execute(
            AddObjects(
              pageId: page,
              objects: [
                PageObjectFixtures.textBox(
                  pageId: page,
                  text: '$word ${i + 1}',
                ),
              ],
            ),
          )
          .persisted;
    }
    await session.close();
    await backend.store.flush();
    return (note, pages);
  });

  group('rows', () {
    testWidgets('source badges: 손글씨 · PDF · 텍스트, then 수식', (tester) async {
      await real(tester, () => seedContentHits(backend));
      await pumpAt(tester);
      await search(tester, '회의');
      for (final label in [
        LibraryStrings.sourceInk,
        LibraryStrings.sourcePdf,
        LibraryStrings.sourceText,
      ]) {
        expect(
          find.descendant(
            of: find.byType(SourceBadge),
            matching: find.text(label),
          ),
          findsWidgets,
          reason: label,
        );
      }
      expect(find.text(LibraryStrings.sourceMath), findsNothing);
      await search(tester, 'frac');
      expect(
        find.descendant(
          of: find.byType(SourceBadge),
          matching: find.text(LibraryStrings.sourceMath),
        ),
        findsOneWidget,
      );
      // The badge colors (6.1.3).
      final badge = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(SourceBadge),
          matching: find.byType(DecoratedBox),
        ),
      );
      final scheme = Theme.of(tester.element(find.byType(SourceBadge)))
          .colorScheme;
      expect(
        (badge.decoration as BoxDecoration).color,
        scheme.secondaryContainer,
      );
    });

    testWidgets('the snippet match is bold in the primary color', (
      tester,
    ) async {
      await real(tester, () => seedContentHits(backend));
      await pumpAt(tester);
      await search(tester, '회의');
      final row = find.ancestor(
        of: find.textContaining('안건', findRichText: true),
        matching: find.byType(ContentHitRow),
      );
      final primary = Theme.of(tester.element(row)).colorScheme.primary;
      expect(boldParts(tester, row), [('회의', primary)]);
    });

    testWidgets('a match range outside the snippet → no highlight', (
      tester,
    ) async {
      final note = await real(tester, () => backend.seedNote('범위 노트'));
      await pumpAt(
        tester,
        overrides: [
          librarySearchProvider.overrideWith(
            (ref, q) async => LibrarySearchResult(
              query: q,
              folders: const [],
              notes: const [],
              pages: [fakeHit(note.id, 'p1', snippet: '짧음', range: (1, 9))],
            ),
          ),
        ],
      );
      await search(tester, '회의');
      expect(boldParts(tester, hitRows()), isEmpty);
      expect(find.textContaining('짧음', findRichText: true), findsOneWidget);
    });

    testWidgets('page number from the note order; 페이지 while unknown', (
      tester,
    ) async {
      final sample = await real(tester, () => seedContentHits(backend));
      final (_, pages) = await seedWordNote(tester, '단어 노트', '회의', 3);
      await pumpAt(tester);
      await search(tester, '회의');
      Finder rowOf(PageId page) => find.byWidgetPredicate(
        (w) => w is ContentHitRow && w.hit.pageId == page,
      );
      expect(
        find.descendant(
          of: rowOf(pages[2]),
          matching: find.text(LibraryStrings.pageLabel(3)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowOf(sample.meetingPages[1]),
          matching: find.text(LibraryStrings.pageLabel(2)),
        ),
        findsOneWidget,
      );

      // A page index that never arrives → '페이지'.
      final never = Completer<Map<PageId, int>>();
      await tester.pumpWidget(const SizedBox());
      await pumpAt(
        tester,
        overrides: [
          notePageIndexProvider.overrideWith((ref, id) => never.future),
        ],
      );
      await search(tester, '회의');
      expect(find.text(LibraryStrings.pageUnknown), findsWidgets);
      expect(find.text(LibraryStrings.pageLabel(3)), findsNothing);
    });

    testWidgets('a page CORE does not list → 페이지', (tester) async {
      final note = await real(tester, () => backend.seedNote('없는 쪽'));
      await pumpAt(
        tester,
        overrides: [
          librarySearchProvider.overrideWith(
            (ref, q) async => LibrarySearchResult(
              query: q,
              folders: const [],
              notes: const [],
              pages: [fakeHit(note.id, 'no-such-page')],
            ),
          ),
        ],
      );
      await search(tester, '회의');
      expect(
        find.descendant(
          of: hitRows(),
          matching: find.text(LibraryStrings.pageUnknown),
        ),
        findsOneWidget,
      );
    });
  });

  group('groups', () {
    testWidgets('header, location, group count; 3 per note, then 더 보기', (
      tester,
    ) async {
      final (note, _) = await seedWordNote(tester, '단어장', '회의', 5);
      await pumpAt(tester);
      await search(tester, '회의');
      expect(find.text(LibraryStrings.searchContentGroup(5)), findsOneWidget);
      expect(noteHeader('단어장'), findsOneWidget);
      expect(
        find.descendant(
          of: noteHeader('단어장'),
          matching: find.text(LibraryStrings.home),
        ),
        findsOneWidget,
      );
      expect(hitRows(), findsNWidgets(3));
      expect(find.text(LibraryStrings.contentMore(2)), findsOneWidget);
      expect(
        tester.getSize(find.byType(ContentMoreRow)).height,
        greaterThanOrEqualTo(44),
      );

      await tester.tap(find.text(LibraryStrings.contentMore(2)));
      await tester.pumpAndSettle();
      expect(hitRows(), findsNWidgets(5));
      expect(find.byType(ContentMoreRow), findsNothing);
      expect(
        tester.widgetList<ContentHitRow>(hitRows()).map((r) => r.hit.noteId),
        everyElement(note.id),
      );

      // Another query and back: collapsed again.
      await search(tester, '회');
      await search(tester, '회의');
      expect(hitRows(), findsNWidgets(3));
      expect(find.text(LibraryStrings.contentMore(2)), findsOneWidget);
    });

    testWidgets('a note in the trash or gone hides its group', (tester) async {
      final kept = await real(tester, () => backend.seedNote('남은 노트'));
      final trashed = await real(tester, () => backend.seedNote('버린 노트'));
      await real(
        tester,
        () => backend.store.library.trashItems([NoteRef(trashed.id)]),
      );
      await pumpAt(
        tester,
        overrides: [
          librarySearchProvider.overrideWith(
            (ref, q) async => LibrarySearchResult(
              query: q,
              folders: const [],
              notes: const [],
              pages: [
                fakeHit(trashed.id, 'p1', snippet: '버린 회의'),
                fakeHit('purged-note', 'p2', snippet: '지운 회의'),
                fakeHit(kept.id, 'p3', snippet: '남은 회의'),
              ],
            ),
          ),
        ],
      );
      await search(tester, '회의');
      expect(noteHeader('남은 노트'), findsOneWidget);
      expect(noteHeader('버린 노트'), findsNothing);
      expect(rowTexts(tester), ['텍스트 남은 회의']);
      expect(find.textContaining('버린 회의', findRichText: true), findsNothing);
      expect(find.textContaining('지운 회의', findRichText: true), findsNothing);
    });

    testWidgets('order: CORE order inside a note, groups by first hit — '
        'and between sources (CP-14)', (tester) async {
      final sample = await real(tester, () => seedContentHits(backend));
      await pumpAt(tester);
      await search(tester, '회의');
      final core = await real(
        tester,
        () => backend.store.library.searchLibrary('회의'),
      );
      final groups = groupContentHits(core.pages);
      expect(tester.widgetList<ContentHitRow>(hitRows()).map((r) => r.hit), [
        for (final g in groups) ...g.hits,
      ]);
      // Headers in group order, each above its rows.
      final headerY = {
        for (final g in groups)
          g.noteId: tester
              .getTopLeft(
                find.byWidgetPredicate(
                  (w) => w is ContentNoteHeader && w.noteId == g.noteId,
                ),
              )
              .dy,
      };
      final ys = [for (final g in groups) headerY[g.noteId]!];
      expect(ys, orderedEquals([...ys]..sort()));
      // CP-14 order on the fake = the real store's: text (1.0) above ink and
      // pdf (0.8) for the same match.
      expect(rowTexts(tester), [
        '텍스트 회의 안건: 예산',
        '손글씨 지난주 회의록을 정리',
        '텍스트 미분 회의 메모',
        'PDF 분기 회의 자료 정리',
      ]);
      expect(
        [for (final g in groups) g.noteId],
        [sample.meeting.id, sample.calculus.id, sample.report.id],
      );
    });
  });

  group('around the group', () {
    testWidgets('pagesTruncated → the hint below the group', (tester) async {
      final note = await real(tester, () => backend.seedNote('많은 노트'));
      await pumpAt(
        tester,
        overrides: [
          librarySearchProvider.overrideWith(
            (ref, q) async => LibrarySearchResult(
              query: q,
              folders: const [],
              notes: const [],
              pages: [fakeHit(note.id, 'p1')],
              pagesTruncated: true,
            ),
          ),
        ],
      );
      await search(tester, '회의');
      expect(find.text(LibraryStrings.contentTruncated), findsOneWidget);
      expect(find.text(LibraryStrings.searchTruncated), findsNothing);
      expect(
        tester.getTopLeft(find.text(LibraryStrings.contentTruncated)).dy,
        greaterThan(tester.getTopLeft(hitRows()).dy),
      );
    });

    testWidgets('no hit anywhere → the 1차 empty state', (tester) async {
      await real(tester, () => seedContentHits(backend));
      await pumpAt(tester);
      await search(tester, '없는 말');
      expect(find.text(LibraryStrings.emptySearch('없는 말')), findsOneWidget);
      expect(find.byType(SearchResultsView), findsNothing);
    });

    testWidgets('content only (no title match) still shows the results', (
      tester,
    ) async {
      await real(tester, () => seedContentHits(backend));
      await pumpAt(tester);
      await search(tester, '예산');
      expect(find.byType(SearchResultsView), findsOneWidget);
      expect(find.text(LibraryStrings.searchContentGroup(1)), findsOneWidget);
      expect(find.text(LibraryStrings.searchNoteGroup(1)), findsNothing);
    });

    testWidgets('100 hits over 30 notes: no overflow, rows built lazily', (
      tester,
    ) async {
      final notes = await real(tester, () async {
        return [for (var i = 0; i < 30; i++) await backend.seedNote('노트 $i')];
      });
      await pumpAt(
        tester,
        overrides: [
          librarySearchProvider.overrideWith(
            (ref, q) async => LibrarySearchResult(
              query: q,
              folders: const [],
              notes: const [],
              pages: [
                for (var i = 0; i < 100; i++)
                  fakeHit(
                    notes[i % 30].id,
                    'p$i',
                    source: SearchSource.values[i % 4],
                    snippet: '아주 긴 발췌 ' * 12 + '회의 $i',
                    range: (0, 2),
                  ),
              ],
            ),
          ),
        ],
      );
      await search(tester, '회의');
      expect(tester.takeException(), isNull);
      expect(find.text(LibraryStrings.searchContentGroup(100)), findsOneWidget);
      final built = tester.widgetList(hitRows()).length;
      expect(built, greaterThan(0));
      expect(built, lessThan(60));
      final results = find.descendant(
        of: find.byType(SearchResultsView),
        matching: find.byType(Scrollable),
      );
      await tester.drag(results, const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('asking again (6.1.6)', () {
    testWidgets('rows, scroll and expanded notes stay while CORE is asked', (
      tester,
    ) async {
      final sample = await real(tester, () => seedContentHits(backend));
      for (var i = 0; i < 6; i++) {
        await seedWordNote(tester, '긴 노트 $i', '회의', 5);
      }
      Completer<void>? gate;
      var asks = 0;
      await pumpAt(
        tester,
        overrides: [
          librarySearchProvider.overrideWith((ref, q) async {
            asks++;
            final wait = gate;
            if (wait != null) await wait.future;
            return ref.watch(libraryRepositoryProvider).searchLibrary(q);
          }),
        ],
      );
      await search(tester, '회의');
      final first = asks;
      final results = find.descendant(
        of: find.byType(SearchResultsView),
        matching: find.byType(Scrollable),
      );
      // Expand the first note with more than 3 hits, then scroll a bit.
      await tester.tap(find.text(LibraryStrings.contentMore(2)).first);
      await tester.pumpAndSettle();
      await tester.drag(results, const Offset(0, -300));
      await tester.pumpAndSettle();
      final moreRows = tester.widgetList(find.byType(ContentMoreRow)).length;
      final offset = tester.state<ScrollableState>(results).position.pixels;
      expect(offset, greaterThan(0));
      final before = rowTexts(tester);

      gate = Completer<void>();
      await real(
        tester,
        () => backend.store.handwriting.put(
          HandwritingText(
            noteId: sample.meeting.id,
            pageId: sample.meetingPages[1],
            engineId: 'fake/1:ko',
            sourceRev: '0000000000000000',
            lines: const [
              HandwritingLine(
                text: '지난주 회의록을 정리',
                rect: ContentHitsSample.inkLine1,
                strokeIds: ['seed-ink-1'],
              ),
            ],
            createdAt: 2,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 999));
      expect(asks, first);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(asks, first + 1);
      // Asking: the previous rows are still drawn, with the small mark.
      expect(rowTexts(tester), before);
      expect(
        find.descendant(
          of: find.byType(SearchGroupHeader),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.state<ScrollableState>(results).position.pixels, offset);

      gate.complete();
      gate = null;
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.state<ScrollableState>(results).position.pixels, offset);
      expect(tester.widgetList(find.byType(ContentMoreRow)).length, moreRows);
      expect(rowTexts(tester), before);
      expect(searches('회의'), greaterThanOrEqualTo(2));
    });
  });
}
