// E-17: the add-page sheet (04-editor 6.11.4, EDITOR-2-3): initial values =
// the current page; 7 template cells (blank + 6), 4 paper colours, 3 size
// presets + custom; the 100–3000 pt check; orientation; the result
// (PageDraft, PagePosition) then the viewport on the new page; the preview
// cells (distinct ValueKey((choice, color, size)), content.page =
// current.copyWith(size:, background: backgroundFor(...)), no strokes,
// revision 0, new cells when the colour / orientation changes, INK
// arguments = provider values).
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pages/add_page_sheet.dart';
import 'package:feature_editor/src/ui/pages/page_choices.dart';
import 'package:feature_editor/src/ui/pages/page_panel.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

Future<void> _openSheet(WidgetTester tester, EditorTestHandles h) async {
  h.container.read(editorPopupProvider.notifier).open(const AddPagePopup());
  await tester.pump();
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await tester.pump();
}

/// The seven preview cells, in row order.
List<ink.InkPageThumbnail> _cells(WidgetTester tester) => [
  for (final choice in TemplateChoice.all)
    tester.widget<ink.InkPageThumbnail>(
      find.descendant(
        of: find.byKey(AddPageSheet.templateKey(choice)),
        matching: find.byType(ink.InkPageThumbnail),
      ),
    ),
];

/// Semantics.selected of the template cell / colour button under [key].
bool _cellSelected(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  final below = find.descendant(of: finder, matching: find.byType(Semantics));
  final above = find.ancestor(of: finder, matching: find.byType(Semantics));
  for (final f in [below, above]) {
    for (final s in tester.widgetList<Semantics>(f)) {
      final selected = s.properties.selected;
      if (selected != null) return selected;
    }
  }
  throw StateError('no selected flag for $key');
}

bool _selectedChip(WidgetTester tester, Key key) =>
    tester.widget<ChoiceChip>(find.byKey(key)).selected;

Set<T> _segmentSelection<T>(WidgetTester tester) =>
    tester.widget<SegmentedButton<T>>(find.byType(SegmentedButton<T>)).selected;

void main() {
  testWidgets('initial values follow the current page; rows have 7 / 4 / 3+1 '
      'choices', (tester) async {
    final h = await pumpEditor(
      tester,
      pages: 2,
      pageSize: core.PageSize.letterPortrait.landscape,
    );
    h.session.execute(
      core.SetPageBackground(
        pageIds: [h.pageId(0)],
        background: core.TemplateBackground(
          template: const core.PageTemplate(
            kind: core.PageTemplateKind.grid,
            spacing: 20,
          ),
          paperColorArgb: core.PaperColors.ivory,
        ),
      ),
    );
    await tester.pump();
    // Opened from the panel's [+].
    await tester.tap(find.byKey(EditorToolbar.pagePanelKey));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(PagePanel.addKey));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(AddPageSheet.panelKey), findsOneWidget);
    expect(find.text(EditorStrings.addPageTitle), findsWidgets);

    expect(_segmentSelection<AddPagePlacement>(tester), {
      AddPagePlacement.after,
    });
    for (final choice in TemplateChoice.all) {
      expect(find.byKey(AddPageSheet.templateKey(choice)), findsOneWidget);
    }
    expect(find.byType(ink.InkPageThumbnail).evaluate().length, greaterThan(6));
    for (final c in core.PaperColors.all) {
      expect(find.byKey(AddPageSheet.colorKey(c)), findsOneWidget);
    }
    for (final p in [...core.PageSizePreset.values, null]) {
      expect(find.byKey(AddPageSheet.sizeKey(p)), findsOneWidget);
    }
    expect(
      _selectedChip(tester, AddPageSheet.sizeKey(core.PageSizePreset.letter)),
      isTrue,
    );
    expect(_segmentSelection<bool>(tester), {true}, reason: 'landscape');
    // Template and colour: the cell of the current kind is the chosen one.
    expect(
      _cellSelected(
        tester,
        AddPageSheet.templateKey(const KindChoice(core.PageTemplateKind.grid)),
      ),
      isTrue,
    );
    expect(
      _cellSelected(tester, AddPageSheet.templateKey(const BlankChoice())),
      isFalse,
    );
    expect(
      _cellSelected(tester, AddPageSheet.colorKey(core.PaperColors.ivory)),
      isTrue,
    );
    expect(
      _cellSelected(tester, AddPageSheet.colorKey(core.PaperColors.white)),
      isFalse,
    );

    // [추가]: after the current page, the chosen values, then the viewport
    // goes to the new page.
    h.recorder!.clearCalls();
    await _tap(tester, AddPageSheet.addKey);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(AddPageSheet.panelKey), findsNothing);
    expect(h.recorder!.calls, contains('executeAsync:insert-pages'));
    final pages = h.session.pages;
    expect(pages, hasLength(3));
    expect(pages[0].id, h.pageId(0));
    expect(pages[2].id, h.pageId(1));
    final added = pages[1];
    expect(added.size, core.PageSize.letterPortrait.landscape);
    expect(
      added.background,
      core.TemplateBackground(
        template: core.PageTemplate.defaults(core.PageTemplateKind.grid),
        paperColorArgb: core.PaperColors.ivory,
      ),
      reason: 'template parameters back to the INK defaults',
    );
    expect(h.viewport.currentPageIndex.value, 1);
    expect(h.session.history.undoLabel, 'insert-pages');
  });

  testWidgets('choices change the result: blank, black paper, A4 portrait, '
      'before / at the end', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    await h.viewport.jumpToPage(1, animate: false);
    await tester.pump();
    await _openSheet(tester, h);
    await _tap(tester, AddPageSheet.placementKey(AddPagePlacement.before));
    await _tap(
      tester,
      AddPageSheet.templateKey(const KindChoice(core.PageTemplateKind.music)),
    );
    await _tap(tester, AddPageSheet.colorKey(core.PaperColors.black));
    await _tap(
      tester,
      AddPageSheet.sizeKey(core.PageSizePreset.widescreen16x9),
    );
    await _tap(tester, AddPageSheet.landscapeKey);
    await _tap(tester, AddPageSheet.addKey);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    var pages = h.session.pages;
    expect(pages.map((p) => p.id).skip(2), [h.pageId(1), h.pageId(2)]);
    expect(pages[1].size, core.PageSize.widescreen16x9);
    expect(
      pages[1].background,
      core.TemplateBackground(
        template: core.PageTemplate.defaults(core.PageTemplateKind.music),
        paperColorArgb: core.PaperColors.black,
      ),
    );
    // The viewport jumped to the new page (its top at the top of the screen;
    // the short 16:9 page is not the 'current' centre page).
    expect(h.viewport.pageToScreen(1, Offset.zero).dy, inInclusiveRange(0, 40));

    await _openSheet(tester, h);
    await _tap(tester, AddPageSheet.placementKey(AddPagePlacement.end));
    await _tap(tester, AddPageSheet.templateKey(const BlankChoice()));
    await _tap(tester, AddPageSheet.colorKey(core.PaperColors.gray));
    await _tap(tester, AddPageSheet.sizeKey(core.PageSizePreset.a4));
    await _tap(tester, AddPageSheet.portraitKey);
    await _tap(tester, AddPageSheet.addKey);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    pages = h.session.pages;
    expect(pages, hasLength(5));
    expect(pages.last.size, core.PageSize.a4Portrait);
    expect(
      pages.last.background,
      const core.BlankBackground(paperColorArgb: core.PaperColors.gray),
    );
    expect(h.viewport.currentPageIndex.value, 4);
  });

  testWidgets('custom size: 100–3000 pt, else the message and [추가] off', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 1);
    await _openSheet(tester, h);
    await _tap(tester, AddPageSheet.sizeKey(null));
    expect(find.byKey(AddPageSheet.widthFieldKey), findsOneWidget);
    expect(find.byKey(AddPageSheet.rangeErrorKey), findsNothing);
    FilledButton add() =>
        tester.widget<FilledButton>(find.byKey(AddPageSheet.addKey));
    expect(add().onPressed, isNotNull);

    Future<void> type(Key key, String text) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.enterText(find.byKey(key), text);
      await tester.pump();
    }

    for (final bad in ['99', '3001', '', '.']) {
      await type(AddPageSheet.widthFieldKey, bad);
      expect(
        find.text(EditorStrings.customSizeOutOfRange),
        findsOneWidget,
        reason: bad,
      );
      expect(add().onPressed, isNull, reason: bad);
    }
    await type(AddPageSheet.widthFieldKey, '100');
    await type(AddPageSheet.heightFieldKey, '3000');
    expect(find.byKey(AddPageSheet.rangeErrorKey), findsNothing);
    expect(add().onPressed, isNotNull);
    // Portrait is applied to the typed size (100 × 3000 stays portrait).
    await _tap(tester, AddPageSheet.addKey);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.session.pages.last.size, const core.PageSize(100, 3000));

    // Landscape turns the typed size.
    await _openSheet(tester, h);
    await _tap(tester, AddPageSheet.sizeKey(null));
    await type(AddPageSheet.widthFieldKey, '500');
    await type(AddPageSheet.heightFieldKey, '700.5');
    await _tap(tester, AddPageSheet.landscapeKey);
    await _tap(tester, AddPageSheet.placementKey(AddPagePlacement.end));
    await _tap(tester, AddPageSheet.addKey);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.session.pages.last.size, const core.PageSize(700.5, 500));
  });

  testWidgets('preview cells: one keyed widget per (choice, color, size), '
      'content from current.copyWith, provider arguments', (tester) async {
    final h = await pumpEditor(tester, pages: 2);
    await _openSheet(tester, h);
    final current = h.session.pages[0];
    const size = core.PageSize.a4Portrait;
    var cells = _cells(tester);
    expect(cells, hasLength(7));
    final keys = {for (final c in cells) c.key};
    expect(keys, hasLength(7), reason: 'distinct keys');
    for (var i = 0; i < 7; i++) {
      final choice = TemplateChoice.all[i];
      final cell = cells[i];
      expect(cell.key, ValueKey((choice, core.PaperColors.white, size)));
      expect(cell.width, 64);
      expect(
        cell.content.page,
        current.copyWith(
          size: size,
          background: backgroundFor(choice, core.PaperColors.white),
        ),
      );
      expect(cell.content.strokes, isEmpty);
      expect(cell.content.revision, 0);
      expect(
        identical(
          cell.backgroundBuilders,
          h.container.read(ink.pageBackgroundBuildersProvider),
        ),
        isTrue,
      );
      expect(
        identical(cell.pencilGrain, h.container.read(ink.pencilGrainProvider)),
        isTrue,
      );
    }
    final elementsBefore = {
      for (final choice in TemplateChoice.all)
        find
            .descendant(
              of: find.byKey(AddPageSheet.templateKey(choice)),
              matching: find.byType(ink.InkPageThumbnail),
            )
            .evaluate()
            .single,
    };

    // Colour → new keys (new cells).
    await _tap(tester, AddPageSheet.colorKey(core.PaperColors.gray));
    cells = _cells(tester);
    for (var i = 0; i < 7; i++) {
      expect(
        cells[i].key,
        ValueKey((TemplateChoice.all[i], core.PaperColors.gray, size)),
      );
      expect(
        cells[i].content.page.background,
        backgroundFor(TemplateChoice.all[i], core.PaperColors.gray),
      );
    }
    final elementsAfter = {
      for (final choice in TemplateChoice.all)
        find
            .descendant(
              of: find.byKey(AddPageSheet.templateKey(choice)),
              matching: find.byType(ink.InkPageThumbnail),
            )
            .evaluate()
            .single,
    };
    expect(elementsAfter.intersection(elementsBefore), isEmpty);

    // Orientation → the size in the key and the content.
    await _tap(tester, AddPageSheet.landscapeKey);
    cells = _cells(tester);
    expect(
      cells.first.key,
      ValueKey<(TemplateChoice, int, core.PageSize)>((
        const BlankChoice(),
        core.PaperColors.gray,
        size.landscape,
      )),
    );
    expect(cells.first.content.page.size, size.landscape);

    // [취소] closes without a command.
    h.recorder!.clearCalls();
    await _tap(tester, AddPageSheet.cancelKey);
    expect(find.byKey(AddPageSheet.panelKey), findsNothing);
    expect(h.recorder!.calls.where((c) => c.contains('insert-pages')), isEmpty);
  });

  testWidgets('the anchor of the panel ⋯ menu: initial values and position', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 3);
    h.session.execute(
      core.ResizePages(
        pageIds: [h.pageId(2)],
        size: core.PageSize.a4Portrait.landscape,
      ),
    );
    await tester.pump();
    h.container
        .read(editorPopupProvider.notifier)
        .open(
          AddPagePopup(
            initialPlacement: AddPagePlacement.before,
            anchorPageId: h.pageId(2),
          ),
        );
    await tester.pump();
    await tester.pump();
    expect(_segmentSelection<AddPagePlacement>(tester), {
      AddPagePlacement.before,
    });
    expect(_segmentSelection<bool>(tester), {true}, reason: 'anchor landscape');
    await _tap(tester, AddPageSheet.addKey);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final ids = [for (final p in h.session.pages) p.id];
    expect(ids, hasLength(4));
    expect(ids[3], h.pageId(2));
    expect(h.session.pages[2].size, core.PageSize.a4Portrait.landscape);
    expect(h.container.read(editorCurrentPageIndexProvider), 2);
  });
}
