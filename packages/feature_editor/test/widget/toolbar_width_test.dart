// 04-editor 19.1, (v2.15-ui) 22.4: the toolbar row at every width with every
// optional button on (image insert, insert items, the recording slot, math
// pen, text pen, sync badge, zoom chip) — no overflow, no sideways scroll;
// what gives way follows EditorToolbar.planFor.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/pen/pen_tray.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/mic_button.dart';
import 'package:feature_editor/src/ui/toolbar/overflow_tools_menu.dart';
import 'package:feature_editor/src/ui/toolbar/sync_badge_icon.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/fake_image_importer.dart';
import '../helpers/fake_math_pen.dart';
import '../helpers/fake_text_pen.dart';
import '../helpers/pump_editor.dart';

Future<EditorTestHandles> _pumpAll(WidgetTester tester, double width) =>
    pumpEditor(
      tester,
      logicalSize: Size(width, 800),
      imageImporter: (s) => FakeImageImporter(store: s),
      overrides: [
        core.syncBadgeProvider.overrideWith(
          (ref) => Stream.value(
            // (v2.14-ui) 'done' is hidden now: syncing keeps the badge shown.
            const core.SyncBadge(display: core.SyncDisplayState.inProgress),
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

/// The width the toolbar row's fixed children need.
double _needed(WidgetTester tester) {
  final row = find
      .descendant(of: find.byType(EditorToolbar), matching: find.byType(Row))
      .first;
  final render = tester.renderObject<RenderFlex>(row);
  var sum = 0.0;
  var child = render.firstChild;
  while (child != null) {
    final data = child.parentData! as FlexParentData;
    if ((data.flex ?? 0) == 0) sum += child.size.width;
    child = data.nextSibling;
  }
  return sum;
}

void main() {
  test('planFor: the tray 8 → 5, then the title, then [🔍], then 3 pens, '
      'then the fold', () {
    ToolbarPlan plan(double w, {bool mic = false}) =>
        EditorToolbar.planFor(w, hasInsert: true, mic: mic);
    expect(plan(1280).trayPens, 8);
    expect(plan(1280).title, isTrue);
    expect(plan(1280).search, isTrue);
    expect(plan(1032).trayPens, 5);
    expect(plan(1032).title, isTrue);
    // Android portrait ≈ 800: 5 pens, no title, [🔍] in ⋯, nothing folds.
    expect(plan(800).trayPens, 5);
    expect(plan(800).title, isFalse);
    expect(plan(800).search, isFalse);
    expect(plan(800).fold, isFalse);
    expect(plan(720).trayPens, 3);
    expect(plan(720).fold, isFalse);
    expect(plan(560).fold, isTrue);
    expect(plan(400).scroll, isTrue);
    // Detached: no tray in the row.
    expect(
      EditorToolbar.planFor(
        800,
        hasInsert: true,
        mic: false,
        detached: true,
      ).trayPens,
      0,
    );
  });

  // The widths the toolbar meets (split screen, Android portrait ≈ 800,
  // iPad portrait 820 / 834, landscape 1032 / 1280 …).
  for (final width in const [
    720.0,
    800.0,
    820.0,
    852.0,
    900.0,
    960.0,
    999.0,
    1024.0,
    1032.0,
    1044.0,
    1080.0,
    1180.0,
    1280.0,
  ]) {
    testWidgets('$width px, every optional button on: no overflow, no '
        'scroll, the tools reachable', (tester) async {
      final h = await _pumpAll(tester, width);
      // (v2.14-ui) The zoom chip shows only off 100 %: zoom in so it is on.
      h.container.read(editorCommandsProvider).zoomIn();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byKey(EditorToolbar.scrollKey), findsNothing);
      expect(_needed(tester), lessThanOrEqualTo(width));
      final plan = EditorToolbar.planFor(width, hasInsert: true, mic: false);
      expect(find.byKey(EditorToolbar.overflowToolsKey), findsNothing);
      for (final key in [
        EditorToolbar.penKey,
        EditorToolbar.eraserKey,
        EditorToolbar.lassoKey,
        EditorToolbar.shapeKey,
        EditorToolbar.textKey,
        InsertMenu.buttonKey,
      ]) {
        expect(find.byKey(key).hitTestable(), findsOneWidget, reason: '$key');
      }
      // (v2.15-ui) 수식 펜 · 텍스트 펜 · 🎤 are in [+], not in the row.
      expect(find.byKey(OverflowToolsMenu.mathKey), findsNothing);
      expect(find.byKey(OverflowToolsMenu.textPenKey), findsNothing);
      expect(find.byKey(MicButton.micKey), findsNothing);
      expect(
        find.byKey(EditorToolbar.noteSearchKey),
        plan.search ? findsOneWidget : findsNothing,
      );
      final title = find.byKey(EditorToolbar.titleKey);
      if (plan.title) {
        expect(
          tester.getSize(find.byKey(EditorToolbar.titleSlotKey)).width,
          greaterThanOrEqualTo(EditorToolbar.titleMinRoom),
        );
      } else {
        expect(title, findsNothing);
      }
      // The sync badge shows where it fits (it always does from 800).
      expect(find.byKey(EditorSyncBadgeIcon.iconKey), findsOneWidget);
    });
  }

  test('(review) planFor: the folded row counts its third │; a tray slot '
      'for 지금 펜 is planned for', () {
    // Folded: ← ▤ end + 올가미 ⋯도구 │ … │ ↶ ↷ │ ⋯ — three dividers.
    expect(
      EditorToolbar.fixedWidth(hasInsert: false, mic: false, fold: true) -
          EditorToolbar.fixedWidth(hasInsert: false, mic: false, fold: false),
      -48 + 12,
      reason: '⋯도구 replaces 도형 + 텍스트 (−48) and adds │ (+12)',
    );
    // One more slot for '지금 펜' takes room: at the 8-pen edge it gives 5.
    const edge = 1280.0;
    expect(
      EditorToolbar.planFor(edge, hasInsert: true, mic: false).trayPens,
      8,
    );
    final tight = EditorToolbar.planFor(
      EditorToolbar.fixedWidth(hasInsert: true, mic: false, fold: false) +
          PenTray.widthFor(8) +
          48 +
          EditorToolbar.titleMinRoom,
      hasInsert: true,
      mic: false,
      shownFor: (c) => c + 1,
    );
    expect(tight.trayPens, 5);
  });

  // (v2.15-ui review) Every width from the scrolling row up to a wide
  // tablet, one px apart around the fold and scroll thresholds: no overflow,
  // and [☁] stays in the row (also when it scrolls).
  for (final all in const [false, true]) {
    testWidgets('(review) width sweep 480–1300, '
        '${all ? 'every optional button' : 'the default editor'}: no '
        'overflow, [☁] always shown', (tester) async {
      final h = all
          ? await _pumpAll(tester, 1300)
          : await pumpEditor(
              tester,
              logicalSize: const Size(1300, 800),
              overrides: [
                core.syncBadgeProvider.overrideWith(
                  (ref) => Stream.value(
                    const core.SyncBadge(
                      display: core.SyncDisplayState.inProgress,
                    ),
                  ),
                ),
              ],
            );
      h.container.read(editorCommandsProvider).zoomIn();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final widths = [
        for (var w = 480; w <= 760; w++) w.toDouble(),
        for (var w = 764; w <= 1300; w += 4) w.toDouble(),
      ];
      for (final w in widths) {
        tester.view.physicalSize = Size(w, 800) * 2;
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$w px');
        expect(
          find.byKey(EditorSyncBadgeIcon.iconKey),
          findsOneWidget,
          reason: '[☁] at $w px',
        );
        if (find.byKey(EditorToolbar.scrollKey).evaluate().isEmpty) {
          expect(_needed(tester), lessThanOrEqualTo(w), reason: '$w px');
        }
      }
    });
  }
}
