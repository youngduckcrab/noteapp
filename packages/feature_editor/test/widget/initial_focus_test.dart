// E2-19 (m5-7/04-editor 6.16, 8.2): EditorScreen(initialPageId,
// initialFocusRectPt) — the start camera shows that page with the rect on
// screen (before the last position), then FocusFlash (`editor.focusFlash`):
// the rect inflated by 6 px, 0.4 s on → 0.3 s off → 0.4 s on → 0.5 s fade
// (1.6 s), in screen coordinates (it follows the camera), gone at once on
// input. An unknown page or no initialPageId → the rect is ignored. The
// extension menu's navigateToPage(id, rect) flashes the same way.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/overlays/focus_flash.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

/// Lower half of an A4 page (595 × 842 pt): below the fold at fit width on
/// the 1032 × 1376 screen, so the start camera has to move to show it.
const _rect = Rect.fromLTWH(300, 760, 160, 40);

final _flash = find.byKey(FocusFlash.flashKey);

FocusFlashController _controller(EditorTestHandles h) =>
    h.container.read(editorFocusFlashProvider);

/// [rectPt] on page [index] in global coordinates.
Rect _global(EditorTestHandles h, int index, Rect rectPt) => Rect.fromPoints(
  h.toGlobal(index, rectPt.topLeft),
  h.toGlobal(index, rectPt.bottomRight),
);

bool _onScreen(EditorTestHandles h, int index, Rect rectPt) {
  final r = Rect.fromPoints(
    h.viewport.pageToScreen(index, rectPt.topLeft),
    h.viewport.pageToScreen(index, rectPt.bottomRight),
  );
  final view = Offset.zero & h.viewport.viewportSize;
  return r.left >= view.left - 0.5 &&
      r.top >= view.top - 0.5 &&
      r.right <= view.right + 0.5 &&
      r.bottom <= view.bottom + 0.5;
}

double _opacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(of: _flash, matching: find.byType(AnimatedOpacity)),
    )
    .opacity;

void _expectFlashOn(WidgetTester tester, EditorTestHandles h, int index) {
  expect(_flash, findsOneWidget);
  expect(_opacity(tester), 1);
  final expected = _global(h, index, _rect).inflate(FocusFlash.inflatePx);
  final shown = tester.getRect(_flash);
  expect(shown.left, closeTo(expected.left, 0.01));
  expect(shown.top, closeTo(expected.top, 0.01));
  expect(shown.right, closeTo(expected.right, 0.01));
  expect(shown.bottom, closeTo(expected.bottom, 0.01));
}

/// Opens a 6-page note at page [page] with [rect] (default [_rect]) and
/// pumps one more frame (the flash starts once the first camera is placed).
Future<EditorTestHandles> _open(
  WidgetTester tester, {
  required int page,
  Rect rect = _rect,
}) async {
  final h = await pumpEditor(
    tester,
    pages: 6,
    initialPageIndex: page,
    initialFocusRectPt: rect,
  );
  await tester.pump();
  return h;
}

void main() {
  testWidgets('page 30 + rect: page 30 is the current page, the rect is on '
      'screen, and it flashes for 1.6 s (on / off / on / fade)', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      pages: 40,
      initialPageIndex: 30,
      initialFocusRectPt: _rect,
    );
    await tester.pump();

    expect(h.viewport.currentPageIndex.value, 30);
    expect(h.container.read(editorCurrentPageIndexProvider), 30);
    expect(_onScreen(h, 30, _rect), isTrue);
    // The rect was below the fold of the page-top start: the camera moved
    // but kept the fit-width zoom (it fits).
    expect(h.viewport.zoom, closeTo(1, 1e-9));

    final flash = _controller(h);
    expect(flash.target, FocusFlashTarget(pageId: h.pageId(30), rectPt: _rect));
    expect(flash.phase, FocusFlashPhase.on);
    _expectFlashOn(tester, h, 30);
    final decoration =
        tester.widget<DecoratedBox>(_flash).decoration as BoxDecoration;
    final tertiary = Theme.of(tester.element(_flash)).colorScheme.tertiary;
    expect(decoration.color, tertiary.withValues(alpha: 0.2));
    expect(decoration.border, Border.all(color: tertiary, width: 2));
    expect(decoration.borderRadius, BorderRadius.circular(6));

    await tester.pump(const Duration(milliseconds: 399));
    expect(flash.phase, FocusFlashPhase.on);
    await tester.pump(const Duration(milliseconds: 2)); // 401 ms
    expect(flash.phase, FocusFlashPhase.off);
    expect(_flash, findsOneWidget); // stays, invisible
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 300)); // 701 ms
    expect(flash.phase, FocusFlashPhase.on);
    expect(_opacity(tester), 1);
    await tester.pump(const Duration(milliseconds: 400)); // 1101 ms
    expect(flash.phase, FocusFlashPhase.fading);
    expect(_opacity(tester), 0);
    final fade = tester.widget<AnimatedOpacity>(
      find.ancestor(of: _flash, matching: find.byType(AnimatedOpacity)),
    );
    expect(fade.duration, const Duration(milliseconds: 500));
    expect(_flash, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 498)); // 1599 ms
    expect(_flash, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2)); // 1601 ms
    expect(flash.target, isNull);
    expect(_flash, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the flash follows the camera (screen coordinates)', (
    tester,
  ) async {
    final h = await _open(tester, page: 2);
    _expectFlashOn(tester, h, 2);
    h.viewport.panBy(const Offset(-40, 90));
    await tester.pump();
    _expectFlashOn(tester, h, 2);
    h.viewport.zoomBy(1.5, h.viewport.viewportSize.center(Offset.zero));
    await tester.pump();
    _expectFlashOn(tester, h, 2);
  });

  group('input ends the flash at once', () {
    testWidgets('a pointer down (finger on the page)', (tester) async {
      final h = await _open(tester, page: 1);
      expect(_flash, findsOneWidget);
      await h.driver.down(1, h.toGlobal(1, const Offset(100, 100)));
      await tester.pump();
      expect(_controller(h).target, isNull);
      expect(_flash, findsNothing);
      await h.driver.up(1);
      await tester.pump(const Duration(seconds: 2));
      expect(_flash, findsNothing);
    });

    testWidgets('a pointer down outside the page area (toolbar)', (
      tester,
    ) async {
      final h = await _open(tester, page: 1);
      await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
      await tester.pump();
      expect(_controller(h).target, isNull);
      expect(_flash, findsNothing);
    });

    testWidgets('a wheel scroll', (tester) async {
      final h = await _open(tester, page: 1);
      await h.driver.wheel(
        h.viewportToGlobal(h.viewport.viewportSize.center(Offset.zero)),
        const Offset(0, 40),
      );
      await tester.pump();
      expect(_controller(h).target, isNull);
    });

    testWidgets('a key down', (tester) async {
      final h = await _open(tester, page: 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_controller(h).target, isNull);
      expect(_flash, findsNothing);
    });
  });

  testWidgets('an unknown page + rect → ignored (last position, no flash)', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      pages: 5,
      initialPageId: 'no-such-page',
      initialFocusRectPt: _rect,
    );
    await tester.pump();
    expect(h.viewport.currentPageIndex.value, 0);
    expect(_controller(h).target, isNull);
    expect(_flash, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(_flash, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no initialPageId + rect → ignored (page 0, no flash)', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 5, initialFocusRectPt: _rect);
    await tester.pump();
    expect(h.container.read(editorInitialFocusRectProvider), _rect);
    expect(h.viewport.currentPageIndex.value, 0);
    expect(h.viewport.zoom, closeTo(1, 1e-9));
    expect(_controller(h).target, isNull);
    expect(_flash, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(_flash, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rect off the page → the page opens, no flash', (tester) async {
    final h = await _open(
      tester,
      page: 2,
      rect: const Rect.fromLTWH(5000, 5000, 10, 10),
    );
    expect(h.viewport.currentPageIndex.value, 2);
    expect(_controller(h).target, isNull);
    expect(_flash, findsNothing);
  });

  testWidgets('a rect partly off the page flashes the part on the page', (
    tester,
  ) async {
    const size = core.PageSize.a4Portrait;
    final h2 = await pumpEditor(
      tester,
      pages: 3,
      initialPageIndex: 1,
      initialFocusRectPt: Rect.fromLTWH(size.width - 50, 100, 400, 60),
    );
    await tester.pump();
    expect(
      _controller(h2).target?.rectPt,
      Rect.fromLTWH(size.width - 50, 100, 50, 60),
    );
  });

  testWidgets('the extension menu navigateToPage(id, rect) flashes too; '
      'without a rect it does not', (tester) async {
    EditorMenuContext? menu;
    final h = await pumpEditor(
      tester,
      pages: 6,
      extensions: EditorExtensions(
        moreMenuItems: [
          EditorMenuItem(
            id: 'test.search',
            label: '찾기',
            icon: Icons.search,
            onSelected: (context, m) async => menu = m,
          ),
        ],
      ),
    );
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorMoreMenu.itemKey('test.search')));
    await tester.pumpAndSettle();
    expect(_flash, findsNothing);

    menu!.navigateToPage(h.pageId(4), null);
    await tester.pumpAndSettle();
    expect(h.viewport.currentPageIndex.value, 4);
    expect(_controller(h).target, isNull);

    menu!.navigateToPage(h.pageId(2), _rect);
    await tester.pump();
    expect(
      _controller(h).target,
      FocusFlashTarget(pageId: h.pageId(2), rectPt: _rect),
    );
    // The camera animates to the rect; the flash follows it.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(h.viewport.currentPageIndex.value, 2);
    expect(_onScreen(h, 2, _rect), isTrue);
    expect(_controller(h).phase, FocusFlashPhase.on);
    _expectFlashOn(tester, h, 2);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(_flash, findsNothing);

    // A second navigation while one flashes starts over.
    menu!.navigateToPage(h.pageId(1), _rect);
    await tester.pump(const Duration(milliseconds: 1000));
    menu!.navigateToPage(h.pageId(3), _rect);
    await tester.pump(const Duration(milliseconds: 1000));
    expect(_controller(h).target?.pageId, h.pageId(3));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_flash, findsNothing);

    // An unknown page → nothing.
    menu!.navigateToPage('no-such-page', _rect);
    await tester.pump();
    expect(_controller(h).target, isNull);
  });
}
