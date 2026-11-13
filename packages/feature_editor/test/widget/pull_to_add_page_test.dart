// Pull to add a page (04-editor 6.11.7): at the document end a finger pan
// held past the end shows '당겨서 페이지 추가' / '놓으면 페이지 추가' in the
// revealed strip; released past the threshold it runs the '+ 페이지' command
// once (a page like the last one, one undo step) with a light haptic and
// shows the new page; below the threshold, after a fling, with the stylus
// and on a read-only note nothing is added. Vertical scroll and horizontal
// paged mode. Finger input goes PointerDriver → InputRouter →
// InteractionHost → ViewportController (pen-only mode, so fingers navigate).
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/pull_to_add_page_indicator.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:feature_editor/src/viewport/viewport_camera.dart';
import 'package:feature_editor/src/viewport/viewport_constants.dart';
import 'package:feature_editor/src/viewport/viewport_controller.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';

const _penOnly = EditorSettings(inputMode: InputMode.penOnly);
const _paged = EditorSettings(
  inputMode: InputMode.penOnly,
  pageFlipMode: PageFlipMode.horizontalPaged,
);

/// Finger travel giving a shown pull of [shown] px.
double _travelFor(double shown) =>
    shown / ViewportConstants.pullToAddResistance;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Scrolls to the very end (panBy clamps at the content end).
Future<void> _toEnd(WidgetTester tester, EditorTestHandles h) async {
  await h.viewport.jumpToPage(h.session.pages.length - 1, animate: false);
  h.viewport.panBy(const Offset(100000, 100000));
  await _settle(tester);
}

Offset _areaCentre(EditorTestHandles h) =>
    h.viewportOrigin + h.viewport.viewportSize.center(Offset.zero);

/// Down at the area centre, a slow drag by [delta], held still, (released
/// unless [release] is false). [check] runs while still held.
Future<void> _pull(
  WidgetTester tester,
  EditorTestHandles h,
  Offset delta, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
  Future<void> Function()? check,
}) async {
  final from = _areaCentre(h);
  final d = h.driver;
  await d.down(11, from, kind: kind);
  const steps = 20;
  for (var i = 1; i <= steps; i++) {
    await d.wait(const Duration(milliseconds: 16));
    await d.move(11, from + delta * (i / steps));
  }
  await d.wait(const Duration(milliseconds: 120)); // held still
  if (check != null) await check();
  await d.up(11);
}

/// Records HapticFeedback calls.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

List<String> _commandCalls(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (!c.startsWith('openPage:') && !c.startsWith('closePage:')) c,
];

void main() {
  testWidgets('pull past the threshold: the labels, then exactly one page '
      'like the last, a light haptic, the new page shown, one undo step', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    final h = await pumpEditor(tester, pages: 2, settings: _penOnly);
    final template = core.TemplateBackground(
      template: core.PageTemplate.defaults(core.PageTemplateKind.lined),
      paperColorArgb: core.PaperColors.ivory,
    );
    h.session.execute(
      core.SetPageBackground(pageIds: [h.pageId(1)], background: template),
    );
    await tester.pump();
    await _toEnd(tester, h);
    h.recorder!.clearCalls();
    final indicator = find.byKey(PullToAddPageIndicator.indicatorKey);
    expect(indicator, findsNothing);

    // Short of the threshold while held.
    await _pull(
      tester,
      h,
      Offset(0, -_travelFor(40)),
      check: () async {
        expect(indicator, findsOneWidget);
        expect(find.text(EditorStrings.pullToAddPage), findsOneWidget);
        expect(h.viewport.pullPhase.value, PullToAddPhase.pulling);
      },
    );
    await _settle(tester);
    expect(h.session.pages, hasLength(2));
    expect(indicator, findsNothing);

    // Past it.
    final semantics = tester.ensureSemantics();
    await _pull(
      tester,
      h,
      Offset(0, -_travelFor(ViewportConstants.pullToAddThreshold + 30)),
      check: () async {
        expect(find.text(EditorStrings.releaseToAddPage), findsOneWidget);
        expect(
          find.bySemanticsLabel(EditorStrings.releaseToAddPage),
          findsOneWidget,
        );
        // The strip is at the bottom edge of the page area.
        final area = tester.getRect(find.byType(PageViewport));
        expect(
          tester.getRect(indicator).bottom,
          lessThanOrEqualTo(area.bottom),
        );
        expect(tester.getRect(indicator).top, greaterThan(area.center.dy));
        expect(haptics, isEmpty);
      },
    );
    semantics.dispose();
    await tester.pump();
    await _settle(tester);

    expect(_commandCalls(h), ['executeAsync:insert-pages']);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    final pages = h.session.pages;
    expect(pages, hasLength(3));
    expect(pages.last.size, pages[1].size);
    expect(pages.last.background, template);
    expect(h.viewport.currentPageIndex.value, 2);
    final newPage = h.viewport.pageRectOnScreen(2);
    expect(newPage.top, inInclusiveRange(0, 40), reason: 'its top in view');
    expect(indicator, findsNothing);
    expect(h.viewport.pullPhase.value, PullToAddPhase.idle);

    // One undo step removes it.
    await tester.tap(find.byKey(UndoRedoButtons.undoKey));
    await tester.pump();
    await _settle(tester);
    expect(h.session.pages, hasLength(2));
  });

  testWidgets('below the threshold: nothing added, springs back to the end', (
    tester,
  ) async {
    final haptics = _recordHaptics(tester);
    final h = await pumpEditor(tester, pages: 2, settings: _penOnly);
    await _toEnd(tester, h);
    final end = h.viewport.camera;
    h.recorder!.clearCalls();
    await _pull(
      tester,
      h,
      Offset(0, -_travelFor(ViewportConstants.pullToAddThreshold - 20)),
      check: () async {
        expect(h.viewport.pullExtent, greaterThan(0));
        expect(find.text(EditorStrings.pullToAddPage), findsOneWidget);
      },
    );
    await _settle(tester);
    expect(h.session.pages, hasLength(2));
    expect(_commandCalls(h), isEmpty);
    expect(haptics, isEmpty);
    expect(h.viewport.camera, end);
    expect(find.byKey(PullToAddPageIndicator.indicatorKey), findsNothing);
  });

  testWidgets('a fling that ends at the document end adds nothing', (
    tester,
  ) async {
    final h = await pumpEditor(tester, pages: 2, settings: _penOnly);
    await _settle(tester);
    h.recorder!.clearCalls();
    final from = _areaCentre(h);
    await h.driver.fingerDrag(
      from,
      from - const Offset(0, 400),
      steps: 5,
      interval: const Duration(milliseconds: 8),
    );
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final v = h.viewport;
    final maxY =
        v.layout.contentSize.height - v.viewportSize.height / v.camera.scale;
    expect(v.camera.origin.dy, closeTo(maxY, 1e-6), reason: 'at the end');
    expect(h.session.pages, hasLength(2));
    expect(_commandCalls(h), isEmpty);
    expect(v.pullPhase.value, PullToAddPhase.idle);
  });

  testWidgets('a stylus drag past the end writes, never pulls', (tester) async {
    final h = await pumpEditor(tester, pages: 2, settings: _penOnly);
    await _toEnd(tester, h);
    final end = h.viewport.camera;
    await _pull(
      tester,
      h,
      Offset(0, -_travelFor(ViewportConstants.pullToAddThreshold + 30)),
      kind: PointerDeviceKind.stylus,
      check: () async {
        expect(h.viewport.pullPhase.value, PullToAddPhase.idle);
        expect(find.byKey(PullToAddPageIndicator.indicatorKey), findsNothing);
      },
    );
    await _settle(tester);
    expect(h.session.pages, hasLength(2));
    expect(h.viewport.camera, end);
  });

  testWidgets('read-only note: no pull, nothing added', (tester) async {
    final h = await pumpEditor(tester, pages: 2, settings: _penOnly);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await _toEnd(tester, h); // after the banner took its height
    final end = h.viewport.camera;
    await _pull(
      tester,
      h,
      Offset(0, -_travelFor(ViewportConstants.pullToAddThreshold + 30)),
      check: () async {
        expect(h.viewport.pullPhase.value, PullToAddPhase.idle);
        expect(h.viewport.camera, end, reason: 'clamped as before');
        expect(find.byKey(PullToAddPageIndicator.indicatorKey), findsNothing);
      },
    );
    await _settle(tester);
    expect(h.session.pages, hasLength(2));
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('horizontal paged mode: pulling left past the last page adds '
      'one and flips to it', (tester) async {
    final haptics = _recordHaptics(tester);
    final h = await pumpEditor(tester, pages: 2, settings: _paged);
    await h.viewport.jumpToPage(1, animate: false);
    await _settle(tester);
    h.recorder!.clearCalls();
    final indicator = find.byKey(PullToAddPageIndicator.indicatorKey);
    // The trailing room after the centred last page comes first (no pull).
    double slack() {
      final v = h.viewport;
      final bound = CameraMath.clamp(
        v.camera.pannedBy(const Offset(-1e6, 0)),
        v.layout,
        v.viewportSize,
        v.fitScale,
      );
      return (bound.origin.dx - v.camera.origin.dx) * v.camera.scale;
    }

    await _pull(
      tester,
      h,
      Offset(
        -slack() - _travelFor(ViewportConstants.pullToAddThreshold + 30),
        0,
      ),
      check: () async {
        expect(find.text(EditorStrings.releaseToAddPage), findsOneWidget);
        // The strip is at the right edge of the page area.
        final area = tester.getRect(find.byType(PageViewport));
        expect(tester.getRect(indicator).left, greaterThan(area.center.dx));
      },
    );
    await tester.pump();
    await _settle(tester);
    expect(_commandCalls(h), ['executeAsync:insert-pages']);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    expect(h.session.pages, hasLength(3));
    expect(h.viewport.currentPageIndex.value, 2);
    final rect = h.viewport.pageRectOnScreen(2);
    final centre = h.viewport.viewportSize.center(Offset.zero);
    expect(rect.center.dx, closeTo(centre.dx, 0.5), reason: 'centred');
    expect(indicator, findsNothing);

    // Below the threshold at the (new) last page: snaps back, nothing added.
    await _pull(
      tester,
      h,
      Offset(
        -slack() - _travelFor(ViewportConstants.pullToAddThreshold - 20),
        0,
      ),
      check: () async {
        expect(h.viewport.pullPhase.value, PullToAddPhase.pulling);
      },
    );
    await _settle(tester);
    expect(h.session.pages, hasLength(3));
    expect(h.viewport.pageRectOnScreen(2).center.dx, closeTo(centre.dx, 0.5));
  });
}
