// 04-editor 19.1: the hidden menu / floating pen palette (19) together with
// '노트에서 찾기' (18): one ordered system back (search → palette → menu →
// leave), the floating layer over the page area only (never over the search
// panel; the palette and the pill stay left of it), and the search reachable
// while the menu is hidden (the restore pill's [🔍]).
import 'package:feature_editor/src/state/note_search.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/ui/chrome/editor_chrome.dart';
import 'package:feature_editor/src/ui/chrome/floating_layer.dart';
import 'package:feature_editor/src/ui/chrome/pen_palette.dart';
import 'package:feature_editor/src/ui/search/note_search_panel.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/pump_editor.dart';

/// Tablet landscape.
const Size _landscape = Size(1280, 800);

Finder get _pill => find.byKey(MenuRestorePill.pillKey);
Finder get _paletteButton => find.byKey(PenPalette.buttonKey);
Finder get _palettePanel => find.byKey(PenPalette.panelKey);
Finder get _searchPanel => find.byKey(NoteSearchPanel.panelKey);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

bool _searchOpen(EditorTestHandles h) =>
    h.container.read(editorNoteSearchProvider).isOpen;

Future<EditorTestHandles> _pump(
  WidgetTester tester, {
  EditorDeviceState device = const EditorDeviceState(),
  Size size = _landscape,
}) => pumpEditor(
  tester,
  logicalSize: size,
  beforePump: (store, _, _) =>
      store.settings.set(EditorSettingKeys.deviceState, device.toJson()),
);

void main() {
  testWidgets('system back, one order: the search closes, then the palette, '
      'then the hidden menu comes back, then the note closes', (tester) async {
    final h = await _pump(tester);
    // Open the search from the toolbar, detach + expand the palette, hide
    // the menu.
    await tester.tap(find.byKey(EditorToolbar.noteSearchKey));
    await _settle(tester);
    h.container.read(editorDeviceStateProvider.notifier)
      ..setPaletteDetached(true)
      ..setToolbarHidden(true);
    await _settle(tester);
    await tester.tap(_paletteButton);
    await _settle(tester);
    expect(_searchOpen(h), isTrue);
    expect(_palettePanel, findsOneWidget);
    expect(_pill, findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_searchOpen(h), isFalse);
    expect(_searchPanel, findsNothing);
    expect(_palettePanel, findsOneWidget);
    expect(_pill, findsOneWidget);
    expect(h.closeCount, 0);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_palettePanel, findsNothing);
    expect(_paletteButton, findsOneWidget);
    expect(_pill, findsOneWidget);
    expect(h.closeCount, 0);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(_pill, findsNothing);
    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(h.closeCount, 0);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(h.closeCount, 1);
  });

  testWidgets('the palette sits over the page area, not over the search '
      'panel: a button stored at the right edge and its expanded panel stay '
      'left of the panel', (tester) async {
    await _pump(
      tester,
      device: const EditorDeviceState(
        paletteDetached: true,
        palettePosition: Offset(1, 0.3),
      ),
    );
    final before = tester.getRect(_paletteButton);
    expect(before.right, closeTo(_landscape.width - PenPalette.margin, 1));
    await tester.tap(find.byKey(EditorToolbar.noteSearchKey));
    await _settle(tester);
    final search = tester.getRect(_searchPanel);
    final button = tester.getRect(_paletteButton);
    expect(button.right, lessThanOrEqualTo(search.left));
    await tester.tap(_paletteButton);
    await _settle(tester);
    final panel = tester.getRect(_palettePanel);
    expect(panel.right, lessThanOrEqualTo(search.left));
    expect(panel.left, greaterThanOrEqualTo(0));
    // The search panel still takes taps (nothing floats over it).
    await tester.tap(find.byKey(NoteSearchPanel.closeKey));
    await _settle(tester);
    expect(_searchPanel, findsNothing);
  });

  testWidgets('menu hidden: the pill [🔍] opens and closes the search; the '
      'pill stays over the page area (left of the panel)', (tester) async {
    final h = await _pump(
      tester,
      device: const EditorDeviceState(toolbarHidden: true, restorePillX: 1),
    );
    expect(find.byType(EditorToolbar), findsNothing);
    final search = find.byKey(MenuRestorePill.searchKey);
    expect(search, findsOneWidget);
    expect(tester.getSize(search).width, greaterThanOrEqualTo(48));
    await tester.tap(search);
    await _settle(tester);
    expect(_searchOpen(h), isTrue);
    expect(_searchPanel, findsOneWidget);
    expect(
      tester.getRect(_pill).right,
      lessThanOrEqualTo(tester.getRect(_searchPanel).left),
    );
    // The field is usable while the menu is hidden.
    await tester.enterText(find.byKey(NoteSearchPanel.fieldKey), '회의');
    await _settle(tester);
    expect(h.container.read(editorNoteSearchProvider).query, '회의');
    await tester.tap(search);
    await _settle(tester);
    expect(_searchOpen(h), isFalse);
    // The menu is still hidden; the pill's middle brings it back.
    expect(find.byType(EditorToolbar), findsNothing);
    await tester.tap(find.byKey(MenuRestorePill.showKey));
    await _settle(tester);
    expect(find.byType(EditorToolbar), findsOneWidget);
    expect(h.container.read(editorDeviceStateProvider).toolbarHidden, isFalse);
    expect(EditorChrome.slide, const Duration(milliseconds: 200));
  });

  // (19.1 review) Narrow screens (Slide Over 320, 360 phones): the search
  // panel leaves the pages 176 / 198 px — the pill (208 with [🔍]) and the
  // 3-column palette panel (184) ran past the page area and were clipped.
  for (final width in const [320.0, 360.0, 400.0]) {
    testWidgets('$width px, menu hidden, search open, palette expanded at '
        'the right edge: the pill and the panel stay inside the page area, '
        'every pill target reachable', (tester) async {
      final h = await _pump(
        tester,
        size: Size(width, 780),
        device: const EditorDeviceState(
          toolbarHidden: true,
          restorePillX: 1,
          paletteDetached: true,
          palettePosition: Offset(1, 0.5),
        ),
      );
      expect(find.byKey(MenuRestorePill.searchKey), findsOneWidget);
      await tester.tap(find.byKey(MenuRestorePill.searchKey));
      await _settle(tester);
      expect(_searchOpen(h), isTrue);
      await tester.tap(_paletteButton);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      final area = tester.getRect(find.byType(EditorFloatingLayer));
      final search = tester.getRect(_searchPanel);
      expect(area.right, lessThanOrEqualTo(search.left + 0.01));
      final pill = tester.getRect(_pill);
      expect(pill.left, greaterThanOrEqualTo(area.left - 0.01));
      expect(pill.right, lessThanOrEqualTo(area.right + 0.01));
      final panel = tester.getRect(_palettePanel);
      expect(panel.left, greaterThanOrEqualTo(area.left - 0.01));
      expect(panel.right, lessThanOrEqualTo(area.right + 0.01));
      final button = tester.getRect(_paletteButton);
      expect(button.right, lessThanOrEqualTo(area.right + 0.01));
      expect(find.byKey(MenuRestorePill.showKey).hitTestable(), findsOneWidget);
      final widePill = area.width >= MenuRestorePill.width;
      expect(
        find.byKey(MenuRestorePill.searchKey),
        widePill ? findsOneWidget : findsNothing,
      );
      expect(
        pill.width,
        widePill ? MenuRestorePill.width : MenuRestorePill.compactWidth,
      );
      // The search still closes (panel close / back), the pill gets [🔍]
      // back in the full page area.
      await tester.tap(find.byKey(NoteSearchPanel.closeKey));
      await _settle(tester);
      expect(_searchOpen(h), isFalse);
      expect(find.byKey(MenuRestorePill.searchKey), findsOneWidget);
      expect(tester.getRect(_pill).right, lessThanOrEqualTo(width + 0.01));
    });
  }
}
