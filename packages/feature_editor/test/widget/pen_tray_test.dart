// (v2.15-ui, m5-7/04-editor 23.3) The pen tray (it replaced E-16's preset
// row — the same stored presets and pinned flag), the save dialog and the
// manager sheet (04-editor 6.10, 5.1.5) on the fake store's preset repository
// (wrapped to record the calls): the 5 default presets as pen drawings in
// CORE order, tap → applyStyle, the lifted pen (core.StrokeStyle ==), '지금
// 펜', the lifted pen → the picker, long press → the quick pen (트레이에서
// 빼기, 순서 바꾸기), [트레이에 꽂기] (and the 8-pen limit), the group filter no
// longer hiding pens, the save dialog, the manager sheet, the empty tray, a
// read-only note and a failed write.
import 'dart:async';

import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/preset_bar.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/color/basic_colors_row.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_art_view.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/pen/pen_tray.dart';
import 'package:feature_editor/src/ui/pen/quick_pen_popup.dart';
import 'package:feature_editor/src/ui/popup_host.dart';
import 'package:feature_editor/src/ui/presets/preset_manager_sheet.dart';
import 'package:feature_editor/src/ui/presets/save_preset_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';
import 'package:ui_kit/ui_kit.dart';

import '../helpers/pump_editor.dart';

/// Records the calls that reach CORE's preset repository, then delegates.
/// [failNext] makes the next write fail with that error (CORE not touched).
final class _RecordingPresets implements core.PenPresetRepository {
  _RecordingPresets(this.inner);
  final core.PenPresetRepository inner;

  final List<String> calls = [];
  final List<
    ({String name, core.StrokeStyle style, String? group, bool pinned})
  >
  created = [];
  final List<List<String>> reorders = [];
  final List<core.PenPreset> updates = [];
  Object? _failNext;

  void failNext(Object error) => _failNext = error;

  Future<T> _write<T>(String call, Future<T> Function() run) {
    calls.add(call);
    final error = _failNext;
    _failNext = null;
    if (error != null) return Future<T>.error(error);
    return run();
  }

  @override
  Stream<List<core.PenPreset>> watchPresets() => inner.watchPresets();
  @override
  Future<List<core.PenPreset>> getPresets() => inner.getPresets();
  @override
  Future<core.PenPreset> createPreset({
    required String name,
    required core.StrokeStyle style,
    String? group,
    bool pinned = true,
    core.PresetId? after,
  }) => _write('createPreset', () {
    created.add((name: name, style: style, group: group, pinned: pinned));
    return inner.createPreset(
      name: name,
      style: style,
      group: group,
      pinned: pinned,
      after: after,
    );
  });
  @override
  Future<void> updatePreset(core.PenPreset preset) =>
      _write('updatePreset', () {
        updates.add(preset);
        return inner.updatePreset(preset);
      });
  @override
  Future<void> reorderPreset(
    core.PresetId id, {
    core.PresetId? after,
    core.PresetId? before,
  }) => _write(
    'reorderPreset',
    () => inner.reorderPreset(id, after: after, before: before),
  );
  @override
  Future<void> reorderPresets(List<core.PresetId> orderedIds) =>
      _write('reorderPresets', () {
        reorders.add(List.of(orderedIds));
        return inner.reorderPresets(orderedIds);
      });
  @override
  Future<void> deletePreset(core.PresetId id) =>
      _write('deletePreset', () => inner.deletePreset(id));
  @override
  Future<void> ensureDefaults() => inner.ensureDefaults();
}

typedef _Env = ({EditorTestHandles h, _RecordingPresets presets});

Future<_Env> _pump(
  WidgetTester tester, {
  bool seedPresets = true,
  Size size = const Size(1032, 1376),
  AppStyle? appStyle,
}) async {
  final store = createFakeNoteStore(seedDefaultPenPresets: seedPresets);
  addTearDown(store.close);
  final presets = _RecordingPresets(store.penPresets);
  final h = await pumpEditor(
    tester,
    store: store,
    logicalSize: size,
    theme: appStyle == null
        ? null
        : buildStyleTheme(appStyle, Brightness.light),
    overrides: [core.penPresetRepositoryProvider.overrideWithValue(presets)],
  );
  await _settle(tester);
  return (h: h, presets: presets);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// Lets a snack bar (4 s) and its animations finish.
Future<void> _settleSnackBar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

/// The names of the tray's pinned pens, left to right.
List<String> _bar(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(PenTray)),
  );
  final all = container.read(core.penPresetsProvider).value ?? const [];
  final shown =
      [
        for (final p in all)
          if (find.byKey(PenTray.slotKey(p.id)).evaluate().isNotEmpty) p,
      ]..sort(
        (x, y) => tester
            .getCenter(find.byKey(PenTray.slotKey(x.id)))
            .dx
            .compareTo(tester.getCenter(find.byKey(PenTray.slotKey(y.id))).dx),
      );
  return [for (final p in shown) p.name];
}

Finder get _toolbar => find.byType(EditorToolbar);

Future<List<core.PenPreset>> _core(_Env env) => env.presets.inner.getPresets();

Future<core.PenPreset> _named(_Env env, String name) async =>
    (await _core(env)).singleWhere((p) => p.name == name);

/// Whether tray pen [id] is the lifted one (the pen tool, its style).
bool _lifted(WidgetTester tester, String id) =>
    find
        .descendant(
          of: find.byKey(EditorToolbar.penKey),
          matching: find.byKey(PenTray.slotKey(id)),
        )
        .evaluate()
        .isNotEmpty &&
    ProviderScope.containerOf(tester.element(find.byType(PenTray)))
            .read(editorToolProvider)
            .activeTool ==
        EditorTool.pen;

ToolState _tools(EditorTestHandles h) => h.container.read(editorToolProvider);

EditorPopup? _popup(EditorTestHandles h) =>
    h.container.read(editorPopupProvider);

/// Groups for the filter tests: 볼펜 필기, 형광펜 수업용, 연필 수업용 (not
/// pinned), 마커 수업용.
Future<void> _group(WidgetTester tester, _Env env) async {
  final all = await _core(env);
  final repo = env.presets.inner;
  await repo.updatePreset(all[0].copyWith(group: '필기'));
  await repo.updatePreset(all[2].copyWith(group: '수업용'));
  await repo.updatePreset(all[3].copyWith(group: '수업용', pinned: false));
  await repo.updatePreset(all[4].copyWith(group: '수업용'));
  await _settle(tester);
}

Future<void> _openSaveDialog(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(PenTray)))
      .read(editorPopupProvider.notifier)
      .open(const SavePresetPopup());
  await tester.pump();
  expect(find.byKey(SavePresetDialog.panelKey), findsOneWidget);
}

String _nameField(WidgetTester tester) => tester
    .widget<TextField>(
      find.descendant(
        of: find.byKey(SavePresetDialog.nameFieldKey),
        matching: find.byType(TextField),
      ),
    )
    .controller!
    .text;

bool _saveEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(SavePresetDialog.saveKey))
        .onPressed !=
    null;

Future<void> _openManager(WidgetTester tester) async {
  await tester.longPress(find.byKey(EditorToolbar.penKey));
  await tester.pump();
  await tester.tap(find.byKey(QuickPenPanel.reorderKey));
  await tester.pump();
  expect(find.byKey(PresetManagerSheet.panelKey), findsOneWidget);
}

/// Opens the ⋯ menu of row [id] and picks [item]. MenuItemButton calls
/// onPressed after the next frame; a dialog needs one more for its route.
Future<void> _rowMenu(WidgetTester tester, String id, Key item) async {
  await tester.tap(find.byKey(PresetManagerSheet.menuKey(id)));
  await tester.pump();
  await tester.tap(find.byKey(item));
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300)); // route transition
}

void main() {
  testWidgets('the 5 default presets stand in the tray as pen drawings in '
      'their ink colour, CORE order, the eraser at the right end; no row '
      'under the toolbar', (tester) async {
    final env = await _pump(tester);
    final all = await _core(env);
    expect(_bar(tester), ['볼펜', '만년필', '형광펜', '연필', '마커']);
    final tray = tester.getRect(find.byKey(PenTray.trayKey));
    final toolbar = tester.getRect(find.byType(EditorToolbar));
    final tokens = StyleTokens.of(tester.element(find.byType(PenTray)));
    final slotHeight = PenTray.slotHeightOf(tokens);
    expect(tray.height, slotHeight + 2);
    // (v2.15-ui review) The bar is the style's height and the pens stand
    // tall in it.
    expect(toolbar.height, EditorToolbar.heightOf(tester.element(_toolbar)));
    expect(slotHeight, greaterThanOrEqualTo(PenTray.height));
    expect(tray.top, greaterThan(toolbar.top));
    expect(tray.bottom, lessThan(toolbar.bottom));
    for (final p in all) {
      final art = tester.widget<PenArt>(
        find.descendant(
          of: find.byKey(PenTray.slotKey(p.id)),
          matching: find.byType(PenArt),
        ),
      );
      expect(art.tool, p.style.tool);
      expect(art.color, penArtColorOf(p.style));
      expect(
        tester.getSize(find.byKey(PenTray.slotKey(p.id))),
        Size(PenTray.slotWidth, slotHeight),
      );
    }
    final eraser = tester.getRect(find.byKey(EditorToolbar.eraserKey));
    expect(
      eraser.left,
      greaterThan(
        tester.getRect(find.byKey(PenTray.slotKey(all.last.id))).right,
      ),
    );
    expect(find.byKey(PenTray.looseKey), findsNothing);
    expect(env.presets.calls, isEmpty, reason: 'EDITOR only reads');
  });

  testWidgets('tap → applyStyle and the pen lifts; a pen in no tray slot is '
      '지금 펜 at the end; the lifted pen again → the pen picker', (tester) async {
    // 1280 wide: the tray takes 8 pens, so 지금 펜 hides none.
    final env = await _pump(tester, size: const Size(1280, 800));
    final h = env.h;
    final all = await _core(env);
    expect(_tools(h).currentPen, all[0].style);
    expect(_lifted(tester, all[0].id), isTrue);
    final down = tester.getTopLeft(
      find.descendant(
        of: find.byKey(PenTray.slotKey(all[2].id)),
        matching: find.byType(PenArt),
      ),
    );
    final up = tester.getTopLeft(
      find.descendant(
        of: find.byKey(PenTray.slotKey(all[0].id)),
        matching: find.byType(PenArt),
      ),
    );
    expect(up.dy, lessThan(down.dy), reason: 'the current pen is lifted');

    await tester.tap(find.byKey(PenTray.slotKey(all[2].id))); // 형광펜
    await tester.pump();
    expect(_tools(h).activeTool, EditorTool.pen);
    expect(_tools(h).currentPen, all[2].style);
    expect(_lifted(tester, all[2].id), isTrue);
    expect(_lifted(tester, all[0].id), isFalse);
    expect(_popup(h), isNull);

    // A changed width → no preset matches: 지금 펜 stands last, lifted.
    h.container.read(editorToolProvider.notifier).setWidth(20);
    await tester.pump();
    expect(find.byKey(PenTray.looseKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(EditorToolbar.penKey),
        matching: find.byKey(PenTray.looseKey),
      ),
      findsOneWidget,
    );
    expect(_bar(tester), ['볼펜', '만년필', '형광펜', '연필', '마커']);
    expect(
      tester.getCenter(find.byKey(PenTray.looseKey)).dx,
      greaterThan(tester.getCenter(find.byKey(PenTray.slotKey(all[4].id))).dx),
    );

    // The lifted pen again → the picker.
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    expect(_popup(h), const PenSettingsPopup());
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();

    // The eraser: tap → the eraser (it lifts, no pen does); again → its popup.
    await tester.tap(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    expect(_tools(h).activeTool, EditorTool.eraser);
    expect([for (final p in all) _lifted(tester, p.id)], everyElement(isFalse));
    await tester.tap(find.byKey(EditorToolbar.eraserKey));
    await tester.pump();
    expect(_popup(h), const EraserSettingsPopup());
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();

    // 지금 펜 from the eraser → the pen tool with that pen.
    await tester.tap(find.byKey(PenTray.looseKey));
    await tester.pump();
    expect(_tools(h).activeTool, EditorTool.pen);
    expect(_tools(h).currentPen.width, 20);
    expect(env.presets.calls, isEmpty);
  });

  testWidgets('long press → the quick pen for that pen (switched to it): a '
      'colour and a width change the pen; 트레이에서 빼기 unpins it', (tester) async {
    final env = await _pump(tester);
    final h = env.h;
    final all = await _core(env);
    await tester.longPress(find.byKey(PenTray.slotKey(all[1].id))); // 만년필
    await tester.pump();
    expect(_tools(h).currentPen, all[1].style);
    expect(_popup(h), isA<QuickPenPopup>());
    expect((_popup(h)! as QuickPenPopup).presetId, all[1].id);
    expect(find.byKey(QuickPenPanel.panelKey), findsOneWidget);
    // Under the pressed pen, inside the screen.
    final panel = tester.getRect(find.byKey(QuickPenPanel.panelKey));
    final slot = tester.getRect(find.byKey(PenTray.slotKey(all[1].id)));
    expect(panel.top, greaterThan(slot.bottom));
    expect(panel.right, lessThanOrEqualTo(1032));

    await tester.tap(find.byKey(QuickPenPanel.colorKey(6))); // 빨강
    await tester.pump();
    expect(_tools(h).currentPen.colorArgb & 0xFFFFFF, 0xE53935);
    final widths = penWidthChoices(core.PenTool.fountain);
    await tester.tap(find.byKey(QuickPenPanel.widthKey(4)));
    await tester.pump();
    expect(_tools(h).currentPen.width, widths[4]);
    expect(env.presets.calls, isEmpty, reason: 'the preset stays as it was');

    await tester.tap(find.byKey(QuickPenPanel.unpinKey));
    await _settle(tester);
    expect(_popup(h), isNull);
    expect(env.presets.updates.single.id, all[1].id);
    expect(env.presets.updates.single.pinned, isFalse);
    expect(_bar(tester), ['볼펜', '형광펜', '연필', '마커']);
    await _settleSnackBar(tester);

    // 펜 고르기 › opens the picker.
    await tester.longPress(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    expect(
      find.byKey(QuickPenPanel.unpinKey),
      findsNothing,
      reason: '지금 펜 is not in the tray',
    );
    await tester.tap(find.byKey(QuickPenPanel.pickerKey));
    await tester.pump();
    expect(_popup(h), const PenSettingsPopup());
  });

  testWidgets('[트레이에 꽂기] pins the current pen (disabled while it is in '
      'the tray; at 8 pinned pens the tray is full)', (tester) async {
    final env = await _pump(tester, size: const Size(1280, 800));
    final h = env.h;
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    FilledButton pin() =>
        tester.widget<FilledButton>(find.byKey(PenSettingsPanel.pinKey));
    expect(pin().onPressed, isNull, reason: '볼펜 is in the tray');
    expect(find.text(EditorStrings.pinnedInTray), findsOneWidget);

    h.container.read(editorToolProvider.notifier).setWidth(3);
    await tester.pump();
    expect(pin().onPressed, isNotNull);
    await tester.tap(find.byKey(PenSettingsPanel.pinKey));
    await _settle(tester);
    expect(env.presets.created.single.pinned, isTrue);
    expect(env.presets.created.single.style, _tools(h).currentPen);
    expect(env.presets.created.single.name, '볼펜 3.0pt');
    expect(_bar(tester).last, '볼펜 3.0pt');
    expect(pin().onPressed, isNull);
    await _settleSnackBar(tester);

    // Fill the tray to 8, then try a 9th.
    for (var i = 0; i < 2; i++) {
      await env.presets.inner.createPreset(
        name: 'p$i',
        style: core.StrokeStyle.defaultsFor(core.PenTool.marker)
            .copyWith(width: 6.0 + i),
      );
    }
    await _settle(tester);
    expect(_bar(tester), hasLength(kTrayMaxPens));
    h.container.read(editorToolProvider.notifier).setWidth(9);
    await tester.pump();
    await tester.tap(find.byKey(PenSettingsPanel.pinKey));
    await tester.pump();
    expect(find.text(EditorStrings.trayFull(kTrayMaxPens)), findsOneWidget);
    expect(env.presets.created, hasLength(1));
    await _settleSnackBar(tester);
  });

  // (v2.15-ui review) Findings: bigger pens that stay in the bar, no pen
  // pushed out by an edit, colour names, pins past the tray.
  for (final style in AppStyle.values) {
    testWidgets('(review) ${style.name}: a resting pen shows ≥ 40 px (well '
        'styles), the lifted pen and the lifted eraser stay ≥ 4 px inside '
        'the toolbar', (tester) async {
      final env = await _pump(
        tester,
        size: const Size(1280, 800),
        appStyle: style,
      );
      final all = await _core(env);
      final toolbar = tester.getRect(_toolbar);
      Rect art(Key slot) => tester.getRect(
        find.descendant(
          of: find.byKey(slot),
          matching: find.byKey(PenTray.artKey),
        ),
      );
      final tray = tester.getRect(find.byKey(PenTray.trayKey));
      final tokens = StyleTokens.of(tester.element(find.byType(PenTray)));
      if (PenTrayStyle.of(tokens).hasWell) {
        final resting = art(PenTray.slotKey(all[2].id));
        expect(tray.bottom - resting.top, greaterThanOrEqualTo(40));
        expect(resting.width, greaterThanOrEqualTo(26));
      }
      final lifted = art(PenTray.slotKey(all[0].id));
      expect(lifted.top, greaterThanOrEqualTo(toolbar.top + 4));
      env.h.container
          .read(editorCommandsProvider)
          .selectTool(EditorTool.eraser);
      await tester.pump(const Duration(milliseconds: 300));
      final eraser = art(EditorToolbar.eraserKey);
      expect(eraser.top, greaterThanOrEqualTo(toolbar.top + 4));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('(review) 8 pinned pens: a quick-pen edit or another pen type '
      'adds 지금 펜 and pushes no pinned pen out', (tester) async {
    final env = await _pump(tester, size: const Size(1280, 800));
    final h = env.h;
    for (var i = 0; i < 3; i++) {
      await env.presets.inner.createPreset(
        name: 'p$i',
        style: core.StrokeStyle.defaultsFor(core.PenTool.marker)
            .copyWith(width: 6.0 + i),
      );
    }
    await _settle(tester);
    final all = await _core(env);
    expect(_bar(tester), hasLength(kTrayMaxPens));
    await tester.longPress(find.byKey(PenTray.slotKey(all[1].id)));
    await tester.pump();
    await tester.tap(find.byKey(QuickPenPanel.colorKey(6))); // 빨강
    await tester.pump();
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    for (final p in all) {
      expect(find.byKey(PenTray.slotKey(p.id)), findsOneWidget, reason: p.name);
    }
    expect(find.byKey(PenTray.looseKey), findsOneWidget);
    h.container
        .read(editorToolProvider.notifier)
        .selectPenType(core.PenTool.crayon);
    await tester.pump();
    for (final p in all) {
      expect(find.byKey(PenTray.slotKey(p.id)), findsOneWidget, reason: p.name);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('(review) the stock pens are named by colour (not HEX) and '
      'their colour is ringed in the quick pen and the picker', (tester) async {
    final env = await _pump(tester, size: const Size(1280, 800));
    final all = await _core(env);
    final fountain = all.firstWhere(
      (p) => p.style.tool == core.PenTool.fountain,
    );
    expect(penLabelOf(fountain.style), startsWith('만년필 · 남색'));
    await tester.longPress(find.byKey(PenTray.slotKey(fountain.id)));
    await tester.pump();
    InkDot dot(Key key) => tester.widget<InkDot>(find.byKey(key));
    expect(dot(QuickPenPanel.colorKey(2)).selected, isTrue, reason: '남색');
    expect(
      [for (var i = 0; i < QuickPenPanel.colorsShown; i++) i]
          .where((i) => dot(QuickPenPanel.colorKey(i)).selected),
      [2],
    );
    // A yellow highlighter: 노랑 takes the last place, ringed.
    final hl = all.firstWhere((p) => p.style.tool == core.PenTool.highlighter);
    env.h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    await tester.longPress(find.byKey(PenTray.slotKey(hl.id)));
    await tester.pump();
    final last = dot(QuickPenPanel.colorKey(QuickPenPanel.colorsShown - 1));
    expect(last.label, '노랑');
    expect(last.selected, isTrue);
  });

  testWidgets('(review) a 9th pinned preset is not "in the tray"; the '
      'manager says the tray shows the first 8', (tester) async {
    final env = await _pump(tester, size: const Size(1280, 800));
    final h = env.h;
    late core.StrokeStyle ninth;
    for (var i = 0; i < 4; i++) {
      ninth = core.StrokeStyle.defaultsFor(core.PenTool.marker)
          .copyWith(width: 6.0 + i);
      await env.presets.inner.createPreset(name: 'p$i', style: ninth);
    }
    await _settle(tester);
    h.container.read(editorToolProvider.notifier).applyStyle(ninth);
    await tester.pump();
    await tester.tap(find.byKey(EditorToolbar.penKey));
    await tester.pump();
    expect(find.text(EditorStrings.pinnedInTray), findsNothing);
    h.container
        .read(editorPopupProvider.notifier)
        .open(const PresetManagerPopup());
    await tester.pump();
    expect(find.byKey(PresetManagerSheet.trayLimitKey), findsOneWidget);
  });

  test('(review) every stock pen colour has a built-in colour name', () {
    for (final tool in core.PenTool.values) {
      final argb = core.StrokeStyle.defaultsFor(tool).colorArgb;
      final i = nearestBasicColorIndex(argb);
      expect(i, isNotNull, reason: '$tool #${argb.toRadixString(16)}');
      expect(inkColorName(argb), EditorStrings.basicColorNames[i!]);
    }
    expect(inkColorName(0xFF1B2A6B), '남색');
    expect(inkColorName(0xFFFFE600), '노랑');
    expect(inkColorName(0xFF3C3C3C), '진회색');
    expect(inkColorName(0xFFFFFFFF), '흰색');
  });

  test('(review) a stored 수식 펜 / 텍스트 펜 without its slot is the pen', () {
    expect(
      penToolActive(EditorTool.math, hasMathPen: false, hasTextPen: true),
      isTrue,
    );
    expect(
      penToolActive(EditorTool.math, hasMathPen: true, hasTextPen: true),
      isFalse,
    );
    expect(
      penToolActive(EditorTool.textPen, hasMathPen: true, hasTextPen: false),
      isTrue,
    );
    expect(
      penToolActive(EditorTool.eraser, hasMathPen: false, hasTextPen: false),
      isFalse,
    );
  });

  testWidgets('a group filter stored by the old preset row hides no tray pen', (
    tester,
  ) async {
    final env = await _pump(tester);
    final all = await _core(env);
    await env.presets.inner.updatePreset(all[0].copyWith(group: '필기'));
    await _settle(tester);
    env.h.container.read(editorPresetBarProvider.notifier).setGroupFilter('필기');
    await tester.pump();
    expect(_bar(tester), ['볼펜', '만년필', '형광펜', '연필', '마커']);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('empty tray: 지금 펜 and the eraser', (tester) async {
    await _pump(tester, seedPresets: false);
    expect(_bar(tester), isEmpty);
    expect(find.byKey(PenTray.looseKey), findsOneWidget);
    expect(find.byKey(EditorToolbar.eraserKey), findsOneWidget);
  });

  testWidgets('save dialog: default name, 1–20 characters, group, pinned → '
      'createPreset with the current pen', (tester) async {
    final env = await _pump(tester);
    final h = env.h;
    await _group(tester, env);
    h.container.read(editorToolProvider.notifier)
      ..selectPenType(core.PenTool.fountain)
      ..setWidth(3.4);
    await tester.pump();
    final pen = _tools(h).currentPen;

    await _openSaveDialog(tester);
    expect(_popup(h), const SavePresetPopup());
    // In the middle of the screen, over a scrim.
    final panel = tester.getRect(find.byKey(SavePresetDialog.panelKey));
    expect(panel.center.dx, closeTo(1032 / 2, 1));
    expect(_nameField(tester), '만년필 3.4pt');
    expect(_nameField(tester), EditorStrings.presetDefaultName(pen.tool, 3.4));
    expect(_saveEnabled(tester), isTrue);
    // No filter → 그룹 없음; pinned on.
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(PresetGroupPicker.noGroupKey))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(SavePresetDialog.pinnedKey))
          .value,
      isTrue,
    );

    // Longer input is blocked at 20 characters; blank → no save.
    final field = find.byKey(SavePresetDialog.nameFieldKey);
    await tester.enterText(field, '가나다라마바사아자차카타파하가나다라마바사아자');
    await tester.pump();
    expect(_nameField(tester).characters.length, kPresetNameMaxLength);
    await tester.enterText(field, '   ');
    await tester.pump();
    expect(_saveEnabled(tester), isFalse);
    await tester.enterText(field, '  수업 펜  ');
    await tester.pump();
    expect(_saveEnabled(tester), isTrue);

    // An existing group.
    await tester.tap(find.byKey(PresetGroupPicker.groupKey('수업용')));
    await tester.pump();
    await tester.tap(find.byKey(SavePresetDialog.saveKey));
    await tester.pump();
    await _settle(tester);
    expect(_popup(h), isNull);
    expect(env.presets.created.single, (
      name: '수업 펜',
      style: pen,
      group: '수업용',
      pinned: true,
    ));
    final saved = await _named(env, '수업 펜');
    expect(saved.style, pen);
    expect(saved.group, '수업용');
    expect(_bar(tester).last, '수업 펜');
    expect(_lifted(tester, saved.id), isTrue);

    // A new group, not pinned: in CORE, not on the bar.
    await _openSaveDialog(tester);
    await tester.tap(find.byKey(PresetGroupPicker.newGroupKey));
    await tester.pump();
    expect(_saveEnabled(tester), isFalse, reason: 'the new group has no name');
    await tester.enterText(
      find.byKey(PresetGroupPicker.newGroupFieldKey),
      ' 시험 ',
    );
    await tester.pump();
    await tester.tap(find.byKey(SavePresetDialog.pinnedKey));
    await tester.pump();
    await tester.tap(find.byKey(SavePresetDialog.saveKey));
    await _settle(tester);
    final second = env.presets.created.last;
    expect(second.name, '만년필 3.4pt');
    expect(second.group, '시험');
    expect(second.pinned, isFalse);
    expect(_bar(tester), isNot(contains('만년필 3.4pt')));
    expect(h.container.read(editorPresetGroupsProvider), ['수업용', '시험', '필기']);

    // With a group filter the dialog starts on that group.
    h.container.read(editorPresetBarProvider.notifier).setGroupFilter('필기');
    await tester.pump();
    await _openSaveDialog(tester);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(PresetGroupPicker.groupKey('필기')))
          .selected,
      isTrue,
    );
    // Cancel → nothing written.
    await tester.tap(find.byKey(SavePresetDialog.cancelKey));
    await tester.pump();
    expect(_popup(h), isNull);
    expect(env.presets.created, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('manager sheet: every preset with its INK preview; pinned, '
      'rename, group, update with the current pen, delete → CORE', (
    tester,
  ) async {
    final env = await _pump(tester);
    final h = env.h;
    final all = await _core(env);
    await _openManager(tester);
    expect(_popup(h), const PresetManagerPopup());
    for (final p in all) {
      expect(find.byKey(PresetManagerSheet.rowKey(p.id)), findsOneWidget);
      final paint = tester.widget<CustomPaint>(
        find.byKey(PresetManagerSheet.previewKey(p.id)),
      );
      final painter = paint.painter! as ink.PenPreviewPainter;
      expect(painter.style, p.style);
      expect(painter.shape, ink.PenPreviewShape.line);
      expect(
        painter.pencilGrain,
        same(h.container.read(ink.pencilGrainProvider)),
      );
    }

    // Pinned off → off the bar (the bar is under the scrim, still built).
    final fountain = all[1];
    await tester.tap(find.byKey(PresetManagerSheet.pinnedKey(fountain.id)));
    await _settle(tester);
    expect((await _named(env, '만년필')).pinned, isFalse);
    expect(_bar(tester), ['볼펜', '형광펜', '연필', '마커']);
    expect(
      tester
          .widget<Switch>(find.byKey(PresetManagerSheet.pinnedKey(fountain.id)))
          .value,
      isFalse,
    );

    // Rename (1–20 characters).
    await _rowMenu(
      tester,
      fountain.id,
      PresetManagerSheet.renameKey(fountain.id),
    );
    expect(find.byType(PresetRenameDialog), findsOneWidget);
    await tester.enterText(find.byKey(PresetRenameDialog.fieldKey), '  ');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(PresetRenameDialog.saveKey))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(PresetRenameDialog.fieldKey), ' 수업 만년필 ');
    await tester.pump();
    await tester.tap(find.byKey(PresetRenameDialog.saveKey));
    await _settle(tester);
    expect((await _core(env))[1].name, '수업 만년필');
    expect(find.text('수업 만년필'), findsOneWidget);

    // Group: a new group, then an existing one, then 그룹 없음.
    await _rowMenu(
      tester,
      fountain.id,
      PresetManagerSheet.groupKey(fountain.id),
    );
    await tester.tap(find.byKey(PresetGroupPicker.newGroupKey));
    await tester.pump();
    await tester.enterText(
      find.byKey(PresetGroupPicker.newGroupFieldKey),
      '필기',
    );
    await tester.pump();
    await tester.tap(find.byKey(PresetGroupDialog.saveKey));
    await _settle(tester);
    expect((await _core(env))[1].group, '필기');
    final marker = all[4];
    await _rowMenu(tester, marker.id, PresetManagerSheet.groupKey(marker.id));
    await tester.tap(find.byKey(PresetGroupPicker.groupKey('필기')));
    await tester.pump();
    await tester.tap(find.byKey(PresetGroupDialog.saveKey));
    await _settle(tester);
    expect((await _core(env))[4].group, '필기');
    await _rowMenu(tester, marker.id, PresetManagerSheet.groupKey(marker.id));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(PresetGroupPicker.groupKey('필기')))
          .selected,
      isTrue,
    );
    await tester.tap(find.byKey(PresetGroupPicker.noGroupKey));
    await tester.pump();
    await tester.tap(find.byKey(PresetGroupDialog.saveKey));
    await _settle(tester);
    expect((await _core(env))[4].group, isNull);

    // Update with the current pen.
    h.container.read(editorToolProvider.notifier)
      ..setWidth(7.5)
      ..setColor(0xFF2255AA);
    await tester.pump();
    final pen = _tools(h).currentPen;
    final ballpoint = all[0];
    await _rowMenu(
      tester,
      ballpoint.id,
      PresetManagerSheet.updateKey(ballpoint.id),
    );
    await _settle(tester);
    expect((await _core(env))[0].style, pen);
    expect(find.text(EditorStrings.presetUpdated), findsOneWidget);

    // Delete (confirmed; cancel first).
    final pencil = all[3];
    await _rowMenu(tester, pencil.id, PresetManagerSheet.deleteKey(pencil.id));
    expect(find.text(EditorStrings.presetDeleteTitle('연필')), findsOneWidget);
    await tester.tap(find.text(EditorStrings.cancel));
    await _settle(tester);
    expect((await _core(env)).map((p) => p.name), contains('연필'));
    await _rowMenu(tester, pencil.id, PresetManagerSheet.deleteKey(pencil.id));
    await tester.tap(find.byKey(PresetDeleteDialog.confirmKey));
    await _settle(tester);
    expect((await _core(env)).map((p) => p.name), isNot(contains('연필')));
    expect(find.byKey(PresetManagerSheet.rowKey(pencil.id)), findsNothing);
    expect(_bar(tester), ['볼펜', '형광펜', '마커']);

    expect(env.presets.calls, [
      'updatePreset', // pinned
      'updatePreset', // rename
      'updatePreset', // group 필기
      'updatePreset', // group 필기 (마커)
      'updatePreset', // 그룹 없음
      'updatePreset', // style
      'deletePreset',
    ]);
    await tester.tap(find.byKey(PresetManagerSheet.closeKey));
    await tester.pump();
    expect(_popup(h), isNull);
    await _settleSnackBar(tester);
  });

  testWidgets('manager sheet: drag handle → reorderPresets with every '
      'preset, CORE order shown', (tester) async {
    final env = await _pump(tester);
    final all = await _core(env);
    await _openManager(tester);
    // 마커 (last) → first.
    final handle = tester.getCenter(
      find.byKey(PresetManagerSheet.handleKey(all[4].id)),
    );
    final first = tester.getCenter(
      find.byKey(PresetManagerSheet.handleKey(all[0].id)),
    );
    final g = await tester.startGesture(handle);
    await tester.pump();
    final dy = first.dy - handle.dy - 20;
    for (var i = 0; i < 12; i++) {
      await g.moveBy(Offset(0, dy / 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(env.presets.calls, ['reorderPresets']);
    final order = [all[4], all[0], all[1], all[2], all[3]].map((p) => p.id);
    expect(env.presets.reorders.single, order);
    expect((await _core(env)).map((p) => p.id), order);
    expect(_bar(tester), ['마커', '볼펜', '만년필', '형광펜', '연필']);
    final rowTops = [
      for (final id in order)
        tester.getTopLeft(find.byKey(PresetManagerSheet.rowKey(id))).dy,
    ];
    expect(rowTops, orderedEquals([...rowTops]..sort()));
  });

  testWidgets('a read-only note: the tray is shown dimmed and does nothing', (
    tester,
  ) async {
    final env = await _pump(tester);
    final h = env.h;
    final all = await _core(env);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await _settle(tester);
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(_bar(tester), hasLength(5), reason: 'still shown');
    await tester.tap(
      find.byKey(PenTray.slotKey(all[2].id)),
      warnIfMissed: false,
    );
    await tester.longPress(
      find.byKey(PenTray.slotKey(all[3].id)),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(_tools(h).penType, core.PenTool.ballpoint);
    expect(_popup(h), isNull);
    expect(env.presets.calls, isEmpty);
  });

  testWidgets('a failed write is reported and shows 실행하지 못했어요', (tester) async {
    final env = await _pump(tester);
    final reports = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reports.add;
    env.presets.failNext(ArgumentError('name'));
    await _openSaveDialog(tester);
    await tester.tap(find.byKey(SavePresetDialog.saveKey));
    await tester.pump();
    await tester.pump();
    FlutterError.onError = previous;
    expect(reports, hasLength(1));
    expect(reports.single.library, 'feature_editor');
    expect(reports.single.exception, isA<ArgumentError>());
    expect(find.text(EditorStrings.commandFailed), findsOneWidget);
    expect(await _core(env), hasLength(5));
    await _settleSnackBar(tester);
  });

  testWidgets('the popup host centres the preset dialogs (no anchor) and '
      'hangs the pen picker centred under the tray, inside the screen', (
    tester,
  ) async {
    final env = await _pump(tester);
    final h = env.h;
    h.container
        .read(editorPopupProvider.notifier)
        .open(const PresetManagerPopup());
    await tester.pump();
    final sheet = tester.getRect(find.byKey(PresetManagerSheet.panelKey));
    expect(sheet.center.dx, closeTo(1032 / 2, 1));
    expect(sheet.width, PresetManagerSheet.width);
    expect(find.byKey(PopupHost.barrierKey), findsOneWidget);
    h.container
        .read(editorPopupProvider.notifier)
        .open(const PenSettingsPopup());
    await tester.pump();
    final tray = tester.getRect(find.byKey(PenTray.trayKey));
    final panel = tester.getRect(find.byKey(PenSettingsPanel.panelKey));
    expect(panel.top, closeTo(tray.bottom + 6, 1));
    expect(panel.left, greaterThanOrEqualTo(8));
    expect(panel.right, lessThanOrEqualTo(1032 - 8));
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    expect(find.byKey(PopupHost.barrierKey), findsNothing);
    unawaited(h.container.read(editorCommandsProvider).flushAll());
    await tester.pump(const Duration(seconds: 1));
  });
}
