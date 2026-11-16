// (v2.13-search) m5-7/04-editor 17: '노트에서 찾기' — the in-note search.
//
// The user: "노트에서 검색기능 … 정작 노트안에서 필기를 검색하는 기능이 안보여.
// pdf 만 검색하는 기능만 있는거로 보임." Before this, the only search inside a
// note was pdf_io's 'PDF에서 찾기' (PDF text only). These tests open the
// search from the more menu (and the toolbar on a wide screen), find
// recognised handwriting (Korean spacing-tolerant, like the library), text
// boxes and formulas of THIS note in page order, go to a result with its
// matched rects highlighted, and show the library's handwriting hint
// (editorInkSearchProvider).
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/note_search.dart';
import 'package:feature_editor/src/ui/overlays/focus_flash.dart';
import 'package:feature_editor/src/ui/overlays/note_search_highlight.dart';
import 'package:feature_editor/src/ui/search/note_search_panel.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/fake_math_pen.dart';
import '../helpers/fake_text_pen.dart';
import '../helpers/pump_editor.dart';

/// Recognised handwriting on page 2 (index 1), low on the page.
const _inkRect = core.PageRect(120, 700, 320, 740);

/// A text box on page 3 (index 2).
const _textRect = core.PageRect(100, 300, 400, 340);

Future<EditorTestHandles> _open(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Size logicalSize = const Size(1032, 1376),
  String inkText = '회의록 정리',
}) async {
  final h = await pumpEditor(
    tester,
    pages: 4,
    logicalSize: logicalSize,
    overrides: overrides,
    objectsByPageIndex: {
      2: [
        PageObjectFixtures.textBox(
          pageId: 'x',
          text: '다음 회의 일정',
          rect: _textRect,
        ),
      ],
      3: [PageObjectFixtures.math(pageId: 'x', latex: r'\frac{a}{b}')],
    },
    beforePump: (store, noteId, pageId) => store.handwriting.put(
      core.HandwritingText(
        noteId: noteId,
        pageId: pageId(1),
        engineId: 'test',
        sourceRev: 'e3b0c44298fc1c14',
        lines: [
          core.HandwritingLine(text: inkText, rect: _inkRect, strokeIds: []),
        ],
        createdAt: 1,
      ),
    ),
  );
  return h;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openFromMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EditorMoreMenu.noteSearchKey));
  await tester.pump();
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(NoteSearchPanel.fieldKey), query);
  await tester.pump(kNoteSearchDebounce);
  await _settle(tester);
}

NoteSearchState _state(EditorTestHandles h) =>
    h.container.read(editorNoteSearchProvider);

/// The primary focus is the query field's.
bool _fieldFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.findAncestorWidgetOfExactType<TextField>()?.key ==
      NoteSearchPanel.fieldKey;
}

/// Counts searchPages calls; everything else goes to [inner].
final class _CountingIndex implements core.SearchIndex {
  _CountingIndex(this.inner);

  final core.SearchIndex inner;
  // Closed in the test's tear-down.
  // ignore: close_sinks
  final StreamController<core.SearchIndexStatus> statuses =
      StreamController.broadcast();
  int searches = 0;

  @override
  Future<List<core.PageSearchHit>> searchPages(
    String query, {
    int limit = 100,
    core.NoteId? withinNote,
  }) {
    searches++;
    return inner.searchPages(query, limit: limit, withinNote: withinNote);
  }

  @override
  Stream<core.SearchIndexStatus> get status async* {
    yield const core.SearchIndexStatus();
    yield* statuses.stream;
  }

  @override
  Future<void> rebuild({Set<core.SearchSource>? sources}) =>
      inner.rebuild(sources: sources);

  @override
  Future<String?> sourceRevOf(core.SearchSource source, String ownerKey) =>
      inner.sourceRevOf(source, ownerKey);

  @override
  Future<Map<String, String>> sourceRevs(core.SearchSource source) =>
      inner.sourceRevs(source);

  @override
  Future<void> replaceUnits(
    core.SearchSource source,
    String ownerKey,
    List<core.SearchUnitDraft> units, {
    required String sourceRev,
  }) => inner.replaceUnits(source, ownerKey, units, sourceRev: sourceRev);

  @override
  Future<void> removeOwner(core.SearchSource source, String ownerKey) =>
      inner.removeOwner(source, ownerKey);
}

void main() {
  testWidgets('the more menu offers 노트에서 찾기 first; it opens the panel '
      'with the field focused', (tester) async {
    final h = await _open(tester);
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    final item = find.byKey(EditorMoreMenu.noteSearchKey);
    expect(item, findsOneWidget);
    expect(
      find.descendant(of: item, matching: find.text('노트에서 찾기')),
      findsOneWidget,
    );
    await tester.tap(item);
    await tester.pump();
    await tester.pump();
    expect(h.container.read(editorNoteSearchProvider).isOpen, isTrue);
    expect(find.byKey(NoteSearchPanel.panelKey), findsOneWidget);
    await tester.pumpAndSettle();
    // (review) Really focused — the canvas (EditorCanvasFocus) held focus in
    // the same scope, so autofocus alone left it there.
    expect(_fieldFocused(), isTrue);
    expect(find.byKey(NoteSearchPanel.emptyKey), findsOneWidget);
    await tester.tap(find.byKey(NoteSearchPanel.closeKey));
    await tester.pump();
    expect(find.byKey(NoteSearchPanel.panelKey), findsNothing);
  });

  testWidgets('a wide toolbar has the 🔍 button; a narrow one does not', (
    tester,
  ) async {
    await _open(tester, logicalSize: const Size(1376, 1032));
    final button = find.byKey(EditorToolbar.noteSearchKey);
    expect(button, findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(find.byKey(NoteSearchPanel.panelKey), findsOneWidget);
    await tester.tap(button);
    await tester.pump();
    expect(find.byKey(NoteSearchPanel.panelKey), findsNothing);
  });

  testWidgets('narrower than the title width (834, iPad 11" portrait): no '
      'toolbar button (the menu has it)', (tester) async {
    await _open(tester, logicalSize: const Size(834, 1194));
    expect(find.byKey(EditorToolbar.noteSearchKey), findsNothing);
  });

  testWidgets('finds recognised handwriting and text boxes of this note, in '
      'page order, with the source and the snippet', (tester) async {
    final h = await _open(tester);
    await _openFromMenu(tester);
    await _type(tester, '회의');
    final results = _state(h).results;
    expect([for (final r in results) r.pageIndex], [1, 2]);
    expect(results[0].source, core.SearchSource.ink);
    expect(results[0].snippet, contains('회의록'));
    expect(results[1].source, core.SearchSource.text);
    expect(find.byKey(NoteSearchPanel.countKey), findsOneWidget);
    expect(find.text('2쪽에서 찾았어요'), findsOneWidget);
    expect(find.text('2쪽 · 손글씨'), findsOneWidget);
    expect(find.text('3쪽 · 텍스트'), findsOneWidget);
    expect(find.byKey(NoteSearchPanel.resultKey(h.pageId(1))), findsOneWidget);
  });

  testWidgets('handwriting matches with the library\'s spacing tolerance '
      '(회의 록 → 회의록)', (tester) async {
    final h = await _open(tester);
    await _openFromMenu(tester);
    await _type(tester, '회의 록');
    final results = _state(h).results;
    expect(results, hasLength(1));
    expect(results.single.pageId, h.pageId(1));
    expect(results.single.source, core.SearchSource.ink);
  });

  testWidgets('formulas are found by their LaTeX', (tester) async {
    final h = await _open(tester);
    await _openFromMenu(tester);
    await _type(tester, 'frac');
    final results = _state(h).results;
    expect(results, hasLength(1));
    expect(results.single.pageIndex, 3);
    expect(results.single.source, core.SearchSource.math);
  });

  testWidgets('no result → 찾는 내용이 없어요', (tester) async {
    final h = await _open(tester);
    await _openFromMenu(tester);
    await _type(tester, '없는말');
    expect(_state(h).results, isEmpty);
    expect(find.text('찾는 내용이 없어요'), findsOneWidget);
  });

  testWidgets('tapping a result goes to its page, flashes it and keeps the '
      'matched rects highlighted until the search closes', (tester) async {
    final h = await _open(tester);
    await _openFromMenu(tester);
    await _type(tester, '회의록');
    expect(h.viewport.currentPageIndex.value, 0);
    await tester.tap(find.byKey(NoteSearchPanel.resultKey(h.pageId(1))));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(h.viewport.currentPageIndex.value, 1);
    expect(_state(h).selectedPageId, h.pageId(1));

    // The highlight sits on the line's rect, in screen coordinates.
    final mark = find.byKey(NoteSearchHighlight.rectKey(h.pageId(1), 0));
    expect(mark, findsOneWidget);
    final r = const Rect.fromLTRB(120, 700, 320, 740);
    final expected = Rect.fromPoints(
      h.toGlobal(1, r.topLeft),
      h.toGlobal(1, r.bottomRight),
    ).inflate(NoteSearchHighlight.inflatePx);
    final shown = tester.getRect(mark);
    expect(shown.left, closeTo(expected.left, 0.5));
    expect(shown.top, closeTo(expected.top, 0.5));
    expect(shown.width, closeTo(expected.width, 0.5));
    expect(shown.height, closeTo(expected.height, 0.5));
    // The selected result has the border.
    final box = tester.widget<DecoratedBox>(mark);
    expect((box.decoration as BoxDecoration).border, isNotNull);

    // Closing the search removes the highlight.
    await tester.tap(find.byKey(NoteSearchPanel.closeKey));
    await tester.pump();
    expect(mark, findsNothing);
    expect(find.byKey(FocusFlash.flashKey), findsNothing);
  });

  testWidgets('new handwriting of the note shows up while the search is open '
      '(asked again after the change)', (tester) async {
    final h = await _open(tester);
    await _openFromMenu(tester);
    await _type(tester, '숙제');
    expect(_state(h).results, isEmpty);
    await h.store.handwriting.put(
      core.HandwritingText(
        noteId: h.noteId,
        pageId: h.pageId(0),
        engineId: 'test',
        sourceRev: 'e3b0c44298fc1c14',
        lines: const [
          core.HandwritingLine(
            text: '수학 숙제',
            rect: core.PageRect(50, 50, 200, 90),
            strokeIds: [],
          ),
        ],
        createdAt: 2,
      ),
    );
    await tester.pump(kNoteSearchRequeryQuiet);
    await _settle(tester);
    expect([for (final r in _state(h).results) r.pageIndex], [0]);
  });

  group('the handwriting hint (editorInkSearchProvider)', () {
    testWidgets('opening and every applied query ask this note first', (
      tester,
    ) async {
      final slot = _FakeInkSearch();
      final h = await _open(
        tester,
        overrides: [editorInkSearchProvider.overrideWithValue(slot)],
      );
      await _openFromMenu(tester);
      expect(slot.opened, [h.noteId]);
      await _type(tester, '회의');
      expect(slot.opened, [h.noteId, h.noteId]);
    });

    testWidgets('ready → no line', (tester) async {
      final slot = _FakeInkSearch();
      await _open(
        tester,
        overrides: [editorInkSearchProvider.overrideWithValue(slot)],
      );
      await _openFromMenu(tester);
      expect(find.byKey(NoteSearchInkHint.hintKey), findsNothing);
    });

    testWidgets('auto indexing off → the library sentence and [켜기]', (
      tester,
    ) async {
      final slot = _FakeInkSearch()
        ..set(
          const EditorInkSearchState(phase: EditorInkSearchPhase.autoIndexOff),
        );
      await _open(
        tester,
        overrides: [editorInkSearchProvider.overrideWithValue(slot)],
      );
      await _openFromMenu(tester);
      expect(find.text("손글씨도 검색하려면 '검색용 자동 인식'을 켜 주세요"), findsOneWidget);
      await tester.tap(find.byKey(NoteSearchInkHint.actionKey));
      await tester.pump();
      expect(slot.turnedOn, 1);
    });

    testWidgets('model missing → [지금 받기] (a cellular download asks twice)', (
      tester,
    ) async {
      final slot = _FakeInkSearch()
        ..set(
          const EditorInkSearchState(
            phase: EditorInkSearchPhase.modelMissing,
            confirmCellularFirst: true,
          ),
        );
      await _open(
        tester,
        overrides: [editorInkSearchProvider.overrideWithValue(slot)],
      );
      await _openFromMenu(tester);
      expect(find.text('손글씨를 검색하려면 인식 모델(약 20MB)을 받아야 해요'), findsOneWidget);
      await tester.tap(find.byKey(NoteSearchInkHint.actionKey));
      await tester.pump();
      expect(slot.downloads, isEmpty);
      expect(find.text('셀룰러 데이터로 받아요(약 20MB). 한 번 더 누르면 받아요.'), findsOneWidget);
      await tester.tap(find.byKey(NoteSearchInkHint.actionKey));
      await tester.pump();
      expect(slot.downloads, [true]);
    });

    testWidgets('indexing → this note\'s pages left; the line follows the '
        'slot', (tester) async {
      final slot = _FakeInkSearch()
        ..set(
          const EditorInkSearchState(
            phase: EditorInkSearchPhase.indexing,
            remainingPages: 3,
          ),
        );
      await _open(
        tester,
        overrides: [editorInkSearchProvider.overrideWithValue(slot)],
      );
      await _openFromMenu(tester);
      expect(find.text('이 노트의 손글씨를 읽는 중이에요 (3쪽 남음)'), findsOneWidget);
      slot.set(const EditorInkSearchState(phase: EditorInkSearchPhase.ready));
      await tester.pump();
      expect(find.byKey(NoteSearchInkHint.hintKey), findsNothing);
    });

    testWidgets('unsupported / downloading / failed', (tester) async {
      final slot = _FakeInkSearch()
        ..set(
          const EditorInkSearchState(phase: EditorInkSearchPhase.unsupported),
        );
      await _open(
        tester,
        overrides: [editorInkSearchProvider.overrideWithValue(slot)],
      );
      await _openFromMenu(tester);
      expect(find.text('이 기기에서는 손글씨 검색을 쓸 수 없어요'), findsOneWidget);
      expect(find.byKey(NoteSearchInkHint.actionKey), findsNothing);
      slot.set(
        const EditorInkSearchState(
          phase: EditorInkSearchPhase.modelDownloading,
        ),
      );
      await tester.pump();
      expect(find.text('손글씨 인식 모델을 받는 중이에요'), findsOneWidget);
      slot.set(
        const EditorInkSearchState(phase: EditorInkSearchPhase.modelFailed),
      );
      await tester.pump();
      expect(find.text('손글씨 인식 모델을 받지 못했어요'), findsOneWidget);
      expect(find.byKey(NoteSearchInkHint.actionKey), findsOneWidget);
    });
  });

  group('review fixes', () {
    testWidgets('a hit on the right of a portrait page is not under the '
        'panel: the panel sits beside the pages', (tester) async {
      final h = await pumpEditor(
        tester,
        pages: 3,
        objectsByPageIndex: {
          1: [
            PageObjectFixtures.textBox(
              pageId: 'x',
              text: '오른쪽 회의록',
              rect: const core.PageRect(430, 300, 570, 340),
            ),
          ],
        },
      );
      final before = h.viewport.viewportSize.width;
      await _openFromMenu(tester);
      await tester.pumpAndSettle();
      final panel = tester.getRect(find.byKey(NoteSearchPanel.panelKey));
      expect(panel.width, NoteSearchPanel.widthFor(before));
      expect(h.viewport.viewportSize.width, closeTo(before - panel.width, 1));
      await _type(tester, '회의록');
      await tester.tap(find.byKey(NoteSearchPanel.resultKey(h.pageId(1))));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      final mark = tester.getRect(
        find.byKey(NoteSearchHighlight.rectKey(h.pageId(1), 0)),
      );
      expect(mark.overlaps(panel), isFalse, reason: '$mark under $panel');
      expect(mark.right, lessThanOrEqualTo(panel.left));
      // Closing gives the pages the whole width back.
      await tester.tap(find.byKey(NoteSearchPanel.closeKey));
      await tester.pumpAndSettle();
      expect(h.viewport.viewportSize.width, before);
    });

    testWidgets('the toolbar 🔍 also focuses the field', (tester) async {
      await _open(tester, logicalSize: const Size(1376, 1032));
      await tester.tap(find.byKey(EditorToolbar.noteSearchKey));
      await tester.pumpAndSettle();
      expect(_fieldFocused(), isTrue);
    });

    testWidgets('tapping a result takes the focus (and the keyboard) away '
        'from the field', (tester) async {
      final h = await _open(tester);
      await _openFromMenu(tester);
      await tester.pumpAndSettle();
      await _type(tester, '회의록');
      expect(_fieldFocused(), isTrue);
      await tester.tap(find.byKey(NoteSearchPanel.resultKey(h.pageId(1))));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(_fieldFocused(), isFalse);
      expect(_state(h).isOpen, isTrue);
    });

    testWidgets('system back closes the open search first; the next back '
        'leaves the note', (tester) async {
      var closed = 0;
      final h = await pumpEditor(tester, pages: 2, onClose: () => closed++);
      await _openFromMenu(tester);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_state(h).isOpen, isFalse);
      expect(find.byKey(NoteSearchPanel.panelKey), findsNothing);
      expect(closed, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(closed, 1);
    });

    testWidgets('an Android tablet in portrait (800 wide, folded toolbar) '
        'has the 🔍 without an overflow, every slot set', (tester) async {
      for (final width in [
        EditorToolbar.foldedSearchMinWidth,
        800.0,
        EditorToolbar.foldWidth - 1,
      ]) {
        await pumpEditor(
          tester,
          logicalSize: Size(width, 1280),
          overrides: [
            core.syncBadgeProvider.overrideWith(
              (ref) => Stream.value(
                const core.SyncBadge(display: core.SyncDisplayState.done),
              ),
            ),
          ],
          extensions: EditorExtensions(
            textPen: FakeTextPen().slot,
            mathPen: FakeMathPen().slot,
            recordingPanel: (context, panel) => const SizedBox(),
            insertMenuItems: [
              EditorInsertMenuItem(
                id: 'x',
                label: 'x',
                icon: Icons.add,
                onSelected: (context, insert) async {},
              ),
            ],
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'width $width');
        expect(find.byKey(EditorToolbar.scrollKey), findsNothing);
        expect(
          find.byKey(EditorToolbar.noteSearchKey),
          findsOneWidget,
          reason: 'width $width',
        );
      }
    });

    testWidgets('more matches than the limit: the best ones, with a line '
        'saying so', (tester) async {
      NoteSearchNotifier.limit = 1;
      addTearDown(() => NoteSearchNotifier.limit = kNoteSearchLimit);
      final h = await _open(tester);
      await _openFromMenu(tester);
      await _type(tester, '회의');
      expect(_state(h).results, hasLength(1));
      expect(_state(h).truncated, isTrue);
      expect(find.byKey(NoteSearchPanel.truncatedKey), findsOneWidget);
      expect(find.text('결과가 많아서 가장 잘 맞는 1쪽만 보여요'), findsOneWidget);
      NoteSearchNotifier.limit = kNoteSearchLimit;
      await _type(tester, '회의 ');
      expect(_state(h).truncated, isFalse);
      expect(find.byKey(NoteSearchPanel.truncatedKey), findsNothing);
    });

    testWidgets('index status: only fewer pending owners or the end of a '
        'rebuild asks again (not the replayed value, not a growing count)', (
      tester,
    ) async {
      late _CountingIndex index;
      final h = await _open(
        tester,
        overrides: [
          core.searchIndexProvider.overrideWith((ref) {
            index = _CountingIndex(ref.watch(core.noteStoreProvider).search);
            addTearDown(index.statuses.close);
            return index;
          }),
        ],
      );
      await _openFromMenu(tester);
      await _type(tester, '회의');
      expect(_state(h).results, isNotEmpty);
      final after = index.searches;
      await tester.pump(kNoteSearchRequeryQuiet * 2);
      expect(index.searches, after, reason: 'the replayed status');
      index.statuses.add(const core.SearchIndexStatus(pendingOwners: 3));
      await tester.pump(kNoteSearchRequeryQuiet * 2);
      expect(index.searches, after, reason: 'a growing catch-up');
      index.statuses.add(const core.SearchIndexStatus(pendingOwners: 2));
      await tester.pump(kNoteSearchRequeryQuiet * 2);
      await _settle(tester);
      expect(index.searches, after + 1);
      index.statuses.add(
        const core.SearchIndexStatus(pendingOwners: 2, rebuilding: true),
      );
      await tester.pump(kNoteSearchRequeryQuiet * 2);
      expect(index.searches, after + 1);
      index.statuses.add(const core.SearchIndexStatus(pendingOwners: 2));
      await tester.pump(kNoteSearchRequeryQuiet * 2);
      await _settle(tester);
      expect(index.searches, after + 2);
    });

    testWidgets('a PDF note with no result points to PDF에서 찾기', (tester) async {
      final h = await _open(tester);
      await _openFromMenu(tester);
      await _type(tester, '없는말');
      expect(find.byKey(NoteSearchPanel.pdfTipKey), findsNothing);
      h.session.execute(
        core.SetPageBackground(
          pageIds: [h.pageId(0)],
          background: const core.PdfBackground(
            assetId: 'asset-pdf',
            pdfPageIndex: 0,
          ),
        ),
      );
      await tester.pump();
      await _type(tester, '없는 말');
      expect(find.byKey(NoteSearchPanel.pdfTipKey), findsOneWidget);
    });
  });
}

final class _FakeInkSearch implements EditorInkSearch {
  final ValueNotifier<EditorInkSearchState> _state = ValueNotifier(
    const EditorInkSearchState(),
  );
  final List<String> opened = [];
  final List<bool> downloads = [];
  int turnedOn = 0;

  void set(EditorInkSearchState state) => _state.value = state;

  @override
  Listenable get changes => _state;

  @override
  EditorInkSearchState stateOf(String noteId) => _state.value;

  @override
  Future<void> turnOnAutoIndex() async => turnedOn++;

  @override
  Future<void> downloadModel({bool cellular = false}) async =>
      downloads.add(cellular);

  @override
  void searchOpened(String noteId) => opened.add(noteId);
}
