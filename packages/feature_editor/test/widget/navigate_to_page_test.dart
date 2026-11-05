// E-17: EditorMenuContext.navigateToPage (04-editor 6.11.6, EDITOR-M9,
// contract 7.2.17 v1.1): from an extension item, a page id → that page is
// the current page; focusRectPt (displayed page pt of the note's Page.size)
// → that rect is on screen (zoom kept when it fits); clipped to the page; an
// unknown id is ignored; the horizontal page flip mode; the page panel
// selection mode stays.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/page_panel.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/viewport/page_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_editor.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [rectPt] on page [index] in viewport coordinates.
Rect _onScreen(EditorTestHandles h, int index, Rect rectPt) => Rect.fromPoints(
  h.viewport.pageToScreen(index, rectPt.topLeft),
  h.viewport.pageToScreen(index, rectPt.bottomRight),
);

bool _inside(EditorTestHandles h, Rect screen) {
  final view = Offset.zero & h.viewport.viewportSize;
  return screen.left >= view.left - 0.5 &&
      screen.top >= view.top - 0.5 &&
      screen.right <= view.right + 0.5 &&
      screen.bottom <= view.bottom + 0.5;
}

void main() {
  testWidgets('an extension item navigates: id → current page; an unknown '
      'id is ignored', (tester) async {
    EditorMenuContext? menu;
    final h = await pumpEditor(
      tester,
      pages: 6,
      overrides: [
        editorExtensionsProvider.overrideWithValue(
          EditorExtensions(
            moreMenuItems: [
              EditorMenuItem(
                id: 'test.search',
                label: '찾기',
                icon: Icons.search,
                onSelected: (context, m) async => menu = m,
              ),
            ],
          ),
        ),
      ],
    );
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorMoreMenu.itemKey('test.search')));
    await tester.pumpAndSettle();
    expect(menu, isNotNull);

    menu!.navigateToPage(h.pageId(4), null);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 4);
    expect(h.container.read(editorCurrentPageIndexProvider), 4);

    final camera = h.viewport.camera;
    menu!.navigateToPage('no-such-page', null);
    menu!.navigateToPage('no-such-page', const Rect.fromLTWH(0, 0, 10, 10));
    await _settle(tester);
    expect(h.viewport.camera, camera);
  });

  testWidgets('focusRectPt: the rect comes on screen; zoom kept when it fits; '
      'already visible → no move', (tester) async {
    final h = await pumpEditor(tester, pages: 4);
    final commands = h.container.read(editorCommandsProvider);
    // Zoom in to 300 % around the screen centre.
    h.viewport.zoomBy(3, h.viewport.viewportSize.center(Offset.zero));
    await _settle(tester);
    final scale = h.viewport.camera.scale;

    const rect = Rect.fromLTWH(400, 700, 120, 60); // page pt, y down
    expect(_inside(h, _onScreen(h, 2, rect)), isFalse);
    commands.navigateToPage(h.pageId(2), rect);
    await _settle(tester);
    expect(_inside(h, _onScreen(h, 2, rect)), isTrue);
    expect(h.viewport.camera.scale, closeTo(scale, 1e-9));
    expect(h.viewport.currentPageIndex.value, 2);

    // Already fully visible: the camera does not move.
    final camera = h.viewport.camera;
    commands.navigateToPage(h.pageId(2), rect.deflate(10));
    await _settle(tester);
    expect(h.viewport.camera, camera);
  });

  testWidgets('a rect bigger than the screen zooms out to fit it; a rect '
      'partly off the page is clipped to the page', (tester) async {
    final h = await pumpEditor(tester, pages: 3);
    final commands = h.container.read(editorCommandsProvider);
    h.viewport.zoomBy(4, h.viewport.viewportSize.center(Offset.zero));
    await _settle(tester);
    final zoomed = h.viewport.camera.scale;

    final size = h.session.pages[1].size;
    final whole = Rect.fromLTWH(0, 0, size.width, size.height);
    commands.navigateToPage(h.pageId(1), whole);
    await _settle(tester);
    expect(h.viewport.camera.scale, lessThan(zoomed));
    expect(_inside(h, _onScreen(h, 1, whole)), isTrue);

    // Mostly outside the page → only the part on the page counts.
    h.viewport.zoomBy(4, h.viewport.viewportSize.center(Offset.zero));
    await _settle(tester);
    final scale = h.viewport.camera.scale;
    final rect = Rect.fromLTWH(size.width - 50, size.height - 40, 5000, 5000);
    commands.navigateToPage(h.pageId(2), rect);
    await _settle(tester);
    final clipped = rect.intersect(whole);
    expect(_inside(h, _onScreen(h, 2, clipped)), isTrue);
    expect(h.viewport.camera.scale, closeTo(scale, 1e-9));
  });

  testWidgets('the selection mode stays while navigating', (tester) async {
    final h = await pumpEditor(tester, pages: 4);
    final panel = h.container.read(editorPagePanelProvider.notifier)
      ..toggleOpen()
      ..setSelecting(true)
      ..toggleSelected(h.pageId(1));
    await tester.pump();
    h.container.read(editorCommandsProvider).navigateToPage(h.pageId(3), null);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 3);
    expect(h.container.read(editorPagePanelProvider).isSelecting, isTrue);
    expect(h.container.read(editorPagePanelProvider).selectedIds, {
      h.pageId(1),
    });
    panel.setSelecting(false);
  });

  testWidgets('horizontal page flip mode: flips to the page, then the rect', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 5);
    final commands = h.container.read(editorCommandsProvider)
      ..setPageFlipMode(PageFlipMode.horizontalPaged);
    await _settle(tester);
    expect(h.viewport.axis, LayoutAxis.horizontal);

    commands.navigateToPage(h.pageId(3), null);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 3);

    const rect = Rect.fromLTWH(100, 100, 80, 40);
    commands.navigateToPage(h.pageId(1), rect);
    await _settle(tester);
    expect(h.viewport.currentPageIndex.value, 1);
    expect(_inside(h, _onScreen(h, 1, rect)), isTrue);
    await tester.pump(const Duration(seconds: 3));
  });
}
