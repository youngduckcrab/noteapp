// E-17: the document-end '+ 페이지' button (04-editor 6.4.3, 6.11.4): built
// only while the spot after the last page is on screen, moves with the
// camera, adds a page like the last one at the end (a PDF page → a blank
// page of its paper colour) and goes to it; hidden on a read-only note; its
// tap never reaches the input router.
import 'package:feature_editor/src/ui/overlays/add_page_button.dart';
import 'package:feature_editor/src/ui/overlays/page_indicator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls to the very end (panBy clamps at the content end).
Future<void> _toEnd(WidgetTester tester, EditorTestHandles h) async {
  await h.viewport.jumpToPage(h.session.pages.length - 1, animate: false);
  h.viewport.panBy(const Offset(0, 100000));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

List<String> _commandCalls(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (!c.startsWith('openPage:') && !c.startsWith('closePage:')) c,
];

void main() {
  testWidgets('only at the document end, under the last page, following '
      'the camera', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    expect(find.byKey(AddPageButton.buttonKey), findsNothing);
    await _toEnd(tester, h);
    final button = find.byKey(AddPageButton.buttonKey);
    expect(button, findsOneWidget);
    final last = h.session.pages.length - 1;
    final size = h.session.pages[last].size;
    final pageBottom = h.toGlobal(last, Offset(size.width / 2, size.height));
    final centre = tester.getCenter(button);
    expect(centre.dx, closeTo(pageBottom.dx, 1));
    expect(centre.dy, greaterThan(pageBottom.dy));

    // Scrolling moves it with the page.
    h.viewport.panBy(const Offset(0, -100)); // content moves down
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(button).dy, closeTo(centre.dy + 100, 1));
    await _settle(tester);
  });

  testWidgets('tap → a page like the last one at the end, then the viewport '
      'goes to it; the tap draws nothing', (tester) async {
    final h = await pumpEditor(tester, pages: 2);
    final template = core.TemplateBackground(
      template: core.PageTemplate.defaults(core.PageTemplateKind.dotted),
      paperColorArgb: core.PaperColors.gray,
    );
    h.session.execute(
      core.SetPageBackground(pageIds: [h.pageId(1)], background: template),
    );
    await tester.pump();
    await _toEnd(tester, h);
    h.recorder!.clearCalls();
    final strokes = h.session.pageIfLoaded(h.pageId(1))!.strokeCount;
    final at = tester.getCenter(find.byKey(AddPageButton.buttonKey));
    await h.driver.stylusStroke([at, at]); // a stylus tap
    await tester.pump();
    await _settle(tester);
    expect(_commandCalls(h), ['executeAsync:insert-pages']);
    final pages = h.session.pages;
    expect(pages, hasLength(3));
    expect(pages.last.size, pages[1].size);
    expect(pages.last.background, template);
    expect(h.viewport.currentPageIndex.value, 2);
    expect(h.session.pageIfLoaded(h.pageId(1))!.strokeCount, strokes);
    expect(find.text('3 / 3'), findsOneWidget, reason: 'page indicator');
    expect(find.byKey(PageIndicator.indicatorKey), findsOneWidget);
  });

  testWidgets('after a PDF page: a blank page of its paper colour', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 1);
    h.session.execute(
      core.SetPageBackground(
        pageIds: [h.pageId(0)],
        background: const core.PdfBackground(
          assetId: 'asset-pdf',
          pdfPageIndex: 0,
          paperColorArgb: core.PaperColors.ivory,
        ),
      ),
    );
    await tester.pump();
    await _toEnd(tester, h);
    await tester.tap(find.byKey(AddPageButton.buttonKey));
    await tester.pump();
    await _settle(tester);
    expect(
      h.session.pages.last.background,
      const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
    );
  });

  testWidgets('hidden on a read-only note', (tester) async {
    final h = await pumpEditor(tester, pages: 1);
    await _toEnd(tester, h);
    expect(find.byKey(AddPageButton.buttonKey), findsOneWidget);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(find.byKey(AddPageButton.buttonKey), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });
}
