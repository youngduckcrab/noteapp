// (v2.14-ui, UI stage 1 — m5-7/04-editor 'UI 정리 1단계') The document-end
// '+ 페이지' button (E-17, 04-editor 6.4.3, 6.11.4) is gone; a faint,
// non-interactive '↓ 아래로 당겨서 새 페이지' takes its spot: built only while the
// spot after the last page is on screen, moving with the camera, fading in
// (at once with reduce motion) and out while a pull runs, hidden on a
// read-only note; a tap on it adds nothing. The action the button ran —
// EditorCommands.addPageAtEndLikeLast (pull to add, '페이지가 없어요') — keeps
// its coverage here (a page like the last one; a PDF page → a blank page of
// its paper colour).
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/end_of_document_hint.dart';
import 'package:feature_editor/src/ui/overlays/page_indicator.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
  await tester.pump(const Duration(milliseconds: 300));
}

double _opacity(WidgetTester tester) {
  var value = 1.0;
  for (final o in tester.widgetList<Opacity>(
    find.ancestor(
      of: find.byKey(EndOfDocumentHint.hintKey),
      matching: find.byType(Opacity),
    ),
  )) {
    value *= o.opacity;
  }
  return value;
}

void main() {
  testWidgets('only at the document end, under the last page, following '
      'the camera; the words; no + 페이지 button', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    expect(find.byKey(EndOfDocumentHint.hintKey), findsNothing);
    expect(find.text('+ 페이지'), findsNothing);
    await _toEnd(tester, h);
    final hint = find.byKey(EndOfDocumentHint.hintKey);
    expect(hint, findsOneWidget);
    expect(find.text(EditorStrings.pullForNewPageVertical), findsOneWidget);
    expect(find.text('+ 페이지'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    final last = h.session.pages.length - 1;
    final size = h.session.pages[last].size;
    final pageBottom = h.toGlobal(last, Offset(size.width / 2, size.height));
    final centre = tester.getCenter(hint);
    expect(centre.dx, closeTo(pageBottom.dx, 1));
    expect(centre.dy, greaterThan(pageBottom.dy));
    expect(
      centre.dy - pageBottom.dy,
      lessThan(ViewportConstants.trailingPadding * h.viewport.camera.scale),
    );
    // Faint once faded in.
    await _settle(tester);
    expect(_opacity(tester), closeTo(EndOfDocumentHint.opacity, 1e-6));

    // Scrolling moves it with the page.
    h.viewport.panBy(const Offset(0, -100)); // content moves down
    await tester.pump();
    await tester.pump();
    expect(tester.getCenter(hint).dy, closeTo(centre.dy + 100, 1));
    await _settle(tester);
  });

  testWidgets('fades in over 250 ms', (tester) async {
    final h = await pumpEditor(tester, pages: 2);
    await h.viewport.jumpToPage(1, animate: false);
    h.viewport.panBy(const Offset(0, 100000));
    await tester.pump();
    await tester.pump();
    expect(_opacity(tester), lessThan(0.05));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_opacity(tester), closeTo(EndOfDocumentHint.opacity, 1e-6));
  });

  testWidgets('reduce motion: no fade, shown at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await pumpEditor(tester, pages: 2);
    await h.viewport.jumpToPage(1, animate: false);
    h.viewport.panBy(const Offset(0, 100000));
    await tester.pump();
    await tester.pump();
    expect(_opacity(tester), closeTo(EndOfDocumentHint.opacity, 1e-6));
  });

  testWidgets('a tap on it adds no page and draws nothing (not a button)', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 2);
    await _toEnd(tester, h);
    await _settle(tester);
    h.recorder!.clearCalls();
    final at = tester.getCenter(find.byKey(EndOfDocumentHint.hintKey));
    await h.driver.stylusStroke([at, at]); // a stylus tap
    await tester.pump();
    await _settle(tester);
    expect(h.session.pages, hasLength(2));
    expect(h.recorder!.countOf('executeAsync:insert-pages'), 0);
  });

  testWidgets('hidden on a read-only note', (tester) async {
    final h = await pumpEditor(tester, pages: 1);
    await _toEnd(tester, h);
    expect(find.byKey(EndOfDocumentHint.hintKey), findsOneWidget);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(find.byKey(EndOfDocumentHint.hintKey), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  group(
    'EditorCommands.addPageAtEndLikeLast (the removed button\'s action)',
    () {
      testWidgets('a page like the last one at the end, then the viewport goes '
          'to it', (tester) async {
        final h = await pumpEditor(tester, pages: 2);
        final template = core.TemplateBackground(
          template: core.PageTemplate.defaults(core.PageTemplateKind.dotted),
          paperColorArgb: core.PaperColors.gray,
        );
        h.session.execute(
          core.SetPageBackground(pageIds: [h.pageId(1)], background: template),
        );
        await tester.pump();
        h.recorder!.clearCalls();
        await h.container.read(editorCommandsProvider).addPageAtEndLikeLast();
        await tester.pump();
        await _settle(tester);
        expect(h.recorder!.countOf('executeAsync:insert-pages'), 1);
        final pages = h.session.pages;
        expect(pages, hasLength(3));
        expect(pages.last.size, pages[1].size);
        expect(pages.last.background, template);
        expect(h.viewport.currentPageIndex.value, 2);
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
        await h.container.read(editorCommandsProvider).addPageAtEndLikeLast();
        await tester.pump();
        await _settle(tester);
        expect(
          h.session.pages.last.background,
          const core.BlankBackground(paperColorArgb: core.PaperColors.ivory),
        );
      });
    },
  );
}
