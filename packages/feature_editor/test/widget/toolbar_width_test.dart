// 04-editor 19.1: the toolbar row at every width with every optional button
// on (image insert, insert items, mic, math pen, text pen, sync badge) plus
// the [⌃] slot (19) and the [🔍] (18) — no overflow, no sideways scroll above
// EditorToolbar.scrollWidth.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/ui/chrome/editor_chrome.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/mic_button.dart';
import 'package:feature_editor/src/ui/toolbar/sync_badge_icon.dart';
import 'package:feature_editor/src/ui/toolbar/zoom_chip.dart';
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
  // The widths the toolbar meets (split screen, Android portrait ≈ 800,
  // iPad portrait 820 / 834, landscape 1032 / 1280 …) and the edges of
  // foldWidth / titleMinWidth.
  for (final width in const [
    720.0,
    800.0,
    820.0,
    852.0,
    900.0,
    EditorToolbar.foldWidth - 1,
    EditorToolbar.foldWidth,
    960.0,
    999.0,
    EditorToolbar.titleMinWidth,
    1024.0,
    1032.0,
    1044.0,
    1048.0,
    1080.0,
    1280.0,
  ]) {
    testWidgets('$width px, every optional button on: no overflow, no '
        'scroll, [🔍] in the row, the tools reachable', (tester) async {
      final h = await _pumpAll(tester, width);
      // (v2.14-ui) The zoom chip shows only off 100 %: zoom in so it is on.
      h.container.read(editorCommandsProvider).zoomIn();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(ZoomChip.chipKey), findsOneWidget);
      expect(find.byKey(EditorSyncBadgeIcon.iconKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.byKey(EditorToolbar.scrollKey), findsNothing);
      expect(_needed(tester), lessThanOrEqualTo(width));
      expect(
        find.byKey(EditorToolbar.noteSearchKey).hitTestable(),
        findsOneWidget,
      );
      final folded = width < EditorToolbar.foldWidth;
      expect(
        find.byKey(EditorToolbar.overflowToolsKey),
        folded ? findsOneWidget : findsNothing,
      );
      for (final key in [
        EditorToolbar.shapeKey,
        EditorToolbar.textKey,
        EditorToolbar.mathKey,
        EditorToolbar.textPenKey,
        InsertMenu.buttonKey,
        MicButton.micKey,
      ]) {
        expect(
          find.byKey(key),
          folded ? findsNothing : findsOneWidget,
          reason: '$key',
        );
      }
      // [⌃] in the row where it fits, else in ⋯ (never an overflow).
      // With the title (19.1): [⌃] only while the title keeps
      // titleLeastWidth. (v2.14-ui) Without [✋] the fixed row is 48 px
      // shorter (≈ 900 px), so [⌃] fits from about 1000.
      if (width >= 1048) {
        expect(find.byKey(MenuHideButton.buttonKey), findsOneWidget);
      } else if (width >= EditorToolbar.titleMinWidth) {
        final slot = tester.getSize(find.byKey(EditorToolbar.titleSlotKey));
        expect(
          find.byKey(MenuHideButton.buttonKey),
          slot.width >= MenuHideButton.width + EditorToolbar.titleLeastWidth
              ? findsOneWidget
              : findsNothing,
        );
      }
      // (19.1 review) From titleMinWidth the title keeps real room: [⌃] and
      // [🔍] together squeezed it to 3.6 px at 1000, 27.6 at 1024.
      final title = find.byKey(EditorToolbar.titleKey);
      if (width >= EditorToolbar.titleMinWidth) {
        expect(
          tester.getSize(title).width,
          greaterThanOrEqualTo(EditorToolbar.titleLeastWidth),
        );
      } else {
        expect(title, findsNothing);
      }
    });
  }
}
