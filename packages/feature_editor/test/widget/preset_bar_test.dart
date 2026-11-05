// E-16: the preset bar, the save dialog and the manager sheet (04-editor
// 6.10, 5.1.5) on the fake store's preset repository (wrapped to record the
// calls): the 5 default presets, the group filter (editor.presetBar), tap →
// applyStyle, the active border (core.StrokeStyle ==), drag → one
// reorderPresets with the full order, the save dialog (default name, 1–20
// characters, group, pinned → createPreset), the manager sheet (name, group,
// pinned, update with the current pen, delete, order → CORE), the empty bar,
// a read-only note and a failed write.
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/preset_bar.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/pen/pen_settings_popup.dart';
import 'package:feature_editor/src/ui/popup_host.dart';
import 'package:feature_editor/src/ui/presets/preset_bar_view.dart';
import 'package:feature_editor/src/ui/presets/preset_chip.dart';
import 'package:feature_editor/src/ui/presets/preset_manager_sheet.dart';
import 'package:feature_editor/src/ui/presets/save_preset_dialog.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

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

Future<_Env> _pump(WidgetTester tester, {bool seedPresets = true}) async {
  final store = createFakeNoteStore(seedDefaultPenPresets: seedPresets);
  addTearDown(store.close);
  final presets = _RecordingPresets(store.penPresets);
  final h = await pumpEditor(
    tester,
    store: store,
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

/// The names on the bar, left to right.
List<String> _bar(WidgetTester tester) => [
  for (final c in tester.widgetList<PresetChip>(find.byType(PresetChip)))
    c.preset.name,
];

Future<List<core.PenPreset>> _core(_Env env) => env.presets.inner.getPresets();

Future<core.PenPreset> _named(_Env env, String name) async =>
    (await _core(env)).singleWhere((p) => p.name == name);

PresetChip _chip(WidgetTester tester, String id) =>
    tester.widget<PresetChip>(find.byKey(PresetBarView.chipKey(id)));

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
  await tester.tap(find.byKey(PresetBarView.addKey));
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
  await tester.tap(find.byKey(PresetBarView.manageKey));
  await tester.pump();
  expect(find.byKey(PresetManagerSheet.panelKey), findsOneWidget);
}

/// Opens the bar's group menu and picks [item] (onPressed runs after the
/// next frame, the bar rebuilds in the one after).
Future<void> _pickGroup(WidgetTester tester, Key item) async {
  await tester.tap(find.byKey(PresetBarView.groupMenuKey));
  await tester.pump();
  await tester.tap(find.byKey(item));
  await tester.pump();
  await tester.pump();
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
  testWidgets('the 5 default presets of the fake store, 44 px under the '
      'toolbar, in CORE order', (tester) async {
    final env = await _pump(tester);
    expect(_bar(tester), ['볼펜', '만년필', '형광펜', '연필', '마커']);
    final bar = tester.getRect(find.byKey(PresetBarView.barKey));
    final toolbar = tester.getRect(find.byType(EditorToolbar));
    expect(bar.height, PresetBarView.height);
    expect(bar.top, toolbar.bottom);
    final chip = tester.getSize(find.byType(PresetChip).first);
    expect(chip, const Size(PresetChip.width, PresetChip.touchHeight));
    // The chips show the CORE values: colour + opacity in the circle, the
    // width dot 4 + 16·sqrt(width / 30).
    for (final p in await _core(env)) {
      final chipFinder = find.byKey(PresetBarView.chipKey(p.id));
      final circle = tester.widget<DecoratedBox>(
        find.descendant(
          of: chipFinder,
          matching: find.byKey(PresetChip.circleKey),
        ),
      );
      expect(
        (circle.decoration as BoxDecoration).color,
        Color(p.style.colorArgb).withValues(alpha: p.style.opacity),
      );
      final dot = tester.getSize(
        find.descendant(
          of: chipFinder,
          matching: find.byKey(PresetChip.dotKey),
        ),
      );
      expect(dot.width, closeTo(PresetChip.dotDiameter(p.style.width), 1e-9));
    }
    expect(PresetChip.dotDiameter(30), 20);
    expect(PresetChip.dotDiameter(7.5), 12);
    // No group yet → no group menu.
    expect(find.byKey(PresetBarView.groupMenuKey), findsNothing);
    expect(env.presets.calls, isEmpty, reason: 'EDITOR only reads');
  });

  testWidgets('tap → applyStyle; the active border follows the pen style '
      '(StrokeStyle ==) while the pen is active', (tester) async {
    final env = await _pump(tester);
    final h = env.h;
    final all = await _core(env);
    // Default pen = StrokeStyle.defaultsFor(ballpoint) = the 볼펜 preset.
    expect(_tools(h).currentPen, all[0].style);
    expect(_chip(tester, all[0].id).active, isTrue);
    expect([
      for (final p in all.skip(1)) _chip(tester, p.id).active,
    ], everyElement(isFalse));

    await tester.tap(find.byKey(PresetBarView.chipKey(all[2].id))); // 형광펜
    await tester.pump();
    expect(_tools(h).activeTool, EditorTool.pen);
    expect(_tools(h).penType, core.PenTool.highlighter);
    expect(_tools(h).currentPen, all[2].style);
    expect(_chip(tester, all[2].id).active, isTrue);
    expect(_chip(tester, all[0].id).active, isFalse);

    // A changed width → no preset matches.
    h.container.read(editorToolProvider.notifier).setWidth(20);
    await tester.pump();
    expect([
      for (final p in all) _chip(tester, p.id).active,
    ], everyElement(isFalse));

    // Tapping 마커 from the eraser selects the pen with the preset style.
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.eraser);
    await tester.pump();
    await tester.tap(find.byKey(PresetBarView.chipKey(all[4].id)));
    await tester.pump();
    expect(_tools(h).activeTool, EditorTool.pen);
    expect(_tools(h).currentPen, all[4].style);
    expect(_chip(tester, all[4].id).active, isTrue);

    // The eraser active → no border, even with the same pen style.
    h.container.read(editorToolProvider.notifier).selectTool(EditorTool.eraser);
    await tester.pump();
    expect(_chip(tester, all[4].id).active, isFalse);
    expect(env.presets.calls, isEmpty);
  });

  testWidgets('group filter: pinned presets of the group, 모든 그룹, stored in '
      'editor.presetBar (device) and restored', (tester) async {
    final env = await _pump(tester);
    final h = env.h;
    await _group(tester, env);
    // Unpinned 연필 is never on the bar.
    expect(_bar(tester), ['볼펜', '만년필', '형광펜', '마커']);
    expect(find.byKey(PresetBarView.groupMenuKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(PresetBarView.groupMenuKey),
        matching: find.text(EditorStrings.presetAllGroups),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(PresetBarView.groupMenuKey));
    await tester.pump();
    expect(find.byKey(PresetBarView.groupItemKey('수업용')), findsOneWidget);
    expect(find.byKey(PresetBarView.groupItemKey('필기')), findsOneWidget);
    await tester.tap(find.byKey(PresetBarView.groupItemKey('수업용')));
    await tester.pump();
    await tester.pump();
    expect(_bar(tester), ['형광펜', '마커']);
    expect(h.container.read(editorPresetBarProvider).groupFilter, '수업용');
    expect(
      find.descendant(
        of: find.byKey(PresetBarView.groupMenuKey),
        matching: find.text('수업용'),
      ),
      findsOneWidget,
    );

    // editor.presetBar is written 500 ms later.
    await tester.pump(const Duration(milliseconds: 499));
    expect(
      await h.store.settings.get(EditorSettingKeys.presetBar),
      isNot(containsPair('group', '수업용')),
    );
    await tester.pump(const Duration(milliseconds: 1));
    expect(await h.store.settings.get(EditorSettingKeys.presetBar), {
      'v': 1,
      'group': '수업용',
    });

    await _pickGroup(tester, PresetBarView.groupItemKey('필기'));
    expect(_bar(tester), ['볼펜']);

    await _pickGroup(tester, PresetBarView.allGroupsKey);
    expect(_bar(tester), ['볼펜', '만년필', '형광펜', '마커']);
    expect(h.container.read(editorPresetBarProvider).groupFilter, isNull);

    // The filter is restored by a new container (another app start).
    await _pickGroup(tester, PresetBarView.groupItemKey('수업용'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(await h.store.settings.get(EditorSettingKeys.presetBar), {
      'v': 1,
      'group': '수업용',
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [core.noteStoreProvider.overrideWithValue(h.store)],
        child: MaterialApp(
          home: EditorScreen(noteId: h.noteId, onClose: () {}),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(_bar(tester), ['형광펜', '마커']);
  });

  testWidgets('long press + drag → one reorderPresets with the full order '
      '(the hidden presets keep their slots); CORE order shown', (
    tester,
  ) async {
    final env = await _pump(tester);
    final all = await _core(env);
    // Hide 만년필: the bar is 볼펜 형광펜 연필 마커.
    await env.presets.inner.updatePreset(all[1].copyWith(pinned: false));
    await _settle(tester);
    expect(_bar(tester), ['볼펜', '형광펜', '연필', '마커']);

    // 볼펜 → after 연필 (index 2 of the bar).
    final start = tester.getCenter(
      find.byKey(PresetBarView.chipKey(all[0].id)),
    );
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 600)); // long press 500 ms
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(14, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(env.presets.calls, ['reorderPresets']);
    final ids = {for (final p in all) p.name: p.id};
    expect(env.presets.reorders.single, [
      ids['형광펜'],
      ids['만년필'], // not on the bar: its slot is kept
      ids['연필'],
      ids['볼펜'],
      ids['마커'],
    ]);
    expect((await _core(env)).map((p) => p.name), [
      '형광펜',
      '만년필',
      '연필',
      '볼펜',
      '마커',
    ]);
    expect(_bar(tester), ['형광펜', '연필', '볼펜', '마커']);
    // A tap is not a drag.
    expect(_tools(env.h).penType, core.PenTool.ballpoint);
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
    expect(_chip(tester, saved.id).active, isTrue);

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

  testWidgets('[프리셋으로 저장] in the pen settings panel opens the save dialog', (
    tester,
  ) async {
    final env = await _pump(tester);
    await tester.tap(find.byKey(EditorToolbar.penKey)); // the active pen
    await tester.pump();
    expect(find.byKey(PenSettingsPanel.panelKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(PenSettingsPanel.saveAsPresetKey));
    await tester.pump();
    await tester.tap(find.byKey(PenSettingsPanel.saveAsPresetKey));
    await tester.pump();
    expect(find.byKey(PenSettingsPanel.panelKey), findsNothing);
    expect(find.byKey(SavePresetDialog.panelKey), findsOneWidget);
    await tester.tap(find.byKey(SavePresetDialog.saveKey));
    await _settle(tester);
    expect(env.presets.created.single.name, '볼펜 1.6pt');
    // A tap on the scrim closes the dialog without saving.
    await _openSaveDialog(tester);
    await tester.tapAt(const Offset(40, 1300));
    await tester.pump();
    expect(find.byKey(SavePresetDialog.panelKey), findsNothing);
    expect(env.presets.created, hasLength(1));
  });

  testWidgets('empty bar: the hint and [현재 펜 저장]', (tester) async {
    final env = await _pump(tester, seedPresets: false);
    expect(find.byType(PresetChip), findsNothing);
    expect(find.text(EditorStrings.presetEmpty), findsOneWidget);
    await tester.tap(find.byKey(PresetBarView.emptySaveKey));
    await tester.pump();
    expect(find.byKey(SavePresetDialog.panelKey), findsOneWidget);
    await tester.tap(find.byKey(SavePresetDialog.saveKey));
    await _settle(tester);
    expect(_bar(tester), ['볼펜 1.6pt']);
    expect(find.text(EditorStrings.presetEmpty), findsNothing);
    expect((await _core(env)).single.style, _tools(env.h).currentPen);
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

  testWidgets('a read-only note: the bar is disabled', (tester) async {
    final env = await _pump(tester);
    final h = env.h;
    final all = await _core(env);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await _settle(tester);
    expect(h.container.read(editorReadOnlyProvider), isTrue);
    expect(_bar(tester), hasLength(5), reason: 'still shown');
    await tester.tap(
      find.byKey(PresetBarView.chipKey(all[2].id)),
      warnIfMissed: false,
    );
    await tester.tap(find.byKey(PresetBarView.addKey), warnIfMissed: false);
    await tester.tap(find.byKey(PresetBarView.manageKey), warnIfMissed: false);
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
      'keeps the toolbar popups on their buttons', (tester) async {
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
    final pen = tester.getRect(find.byKey(EditorToolbar.penKey));
    final panel = tester.getRect(find.byKey(PenSettingsPanel.panelKey));
    expect(panel.left, closeTo(pen.left, 1));
    expect(panel.top, closeTo(pen.bottom + 6, 1));
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    expect(find.byKey(PopupHost.barrierKey), findsNothing);
    unawaited(h.container.read(editorCommandsProvider).flushAll());
    await tester.pump(const Duration(seconds: 1));
  });
}
