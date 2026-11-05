// E-15: the eraser popup panel (04-editor 6.9.3 end): SegmentedButton[획 |
// 부분] → ink.EraserMode, size (diameter = 1 + 99 t², 0.5 pt) with the circle
// preview (diameter × zoom, at most 80 px), SegmentedButton[전체 | 형광펜만 |
// 형광펜 제외] → core.StrokeFilter, "지운 뒤 이전 도구로 돌아가기", the red
// '현재 페이지 지우기', and editor.eraser (synced) storing the choice.
import 'package:feature_editor/src/state/popup.dart';
import 'package:feature_editor/src/state/settings/editor_setting_keys.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/eraser/eraser_popup.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

EraserSettings _eraser(EditorTestHandles h) =>
    h.container.read(editorToolProvider).eraser;

Future<EditorTestHandles> _open(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, highlighterStroke],
    },
  );
  await tester.tap(find.byKey(EditorToolbar.eraserKey)); // select
  await tester.pump();
  await tester.tap(find.byKey(EditorToolbar.eraserKey)); // active → popup
  await tester.pump();
  expect(find.byKey(EraserSettingsPanel.panelKey), findsOneWidget);
  return h;
}

void main() {
  group('EraserSizeMapping', () {
    test('diameter = 1 + 99 t², snapped to 0.5; ends 1 and 100', () {
      expect(EraserSizeMapping.diameterAt(0), EraserSettings.minDiameter);
      expect(EraserSizeMapping.diameterAt(1), EraserSettings.maxDiameter);
      expect(EraserSizeMapping.diameterAt(0.5), 26); // 25.75 → 26.0
      expect(EraserSizeMapping.diameterAt(0.3), 10); // 9.91 → 10.0
      expect(EraserSizeMapping.diameterAt(-1), 1);
      expect(EraserSizeMapping.diameterAt(double.nan), 1);
    });

    test('every 0.5 step round-trips', () {
      for (var i = 2; i <= 200; i++) {
        final d = i / 2;
        expect(
          EraserSizeMapping.diameterAt(EraserSizeMapping.positionOf(d)),
          d,
          reason: '$d',
        );
      }
    });
  });

  testWidgets('300 wide; mode segments set ink.EraserMode', (tester) async {
    final h = await _open(tester);
    expect(
      tester.getSize(find.byKey(EraserSettingsPanel.panelKey)).width,
      EraserSettingsPanel.width,
    );
    expect(_eraser(h).mode, ink.EraserMode.partial); // default
    await tester.tap(
      find.byKey(EraserSettingsPanel.modeSegmentKey(ink.EraserMode.stroke)),
    );
    await tester.pump();
    expect(_eraser(h).mode, ink.EraserMode.stroke);
    await tester.tap(
      find.byKey(EraserSettingsPanel.modeSegmentKey(ink.EraserMode.partial)),
    );
    await tester.pump();
    expect(_eraser(h).mode, ink.EraserMode.partial);
  });

  testWidgets('size slider + circle preview (diameter × zoom, ≤ 80 px)', (
    tester,
  ) async {
    final h = await _open(tester);
    final scale = h.viewport.settledScale.value;
    Size preview() =>
        tester.getSize(find.byKey(EraserSettingsPanel.previewKey));
    expect(_eraser(h).diameter, 12);
    expect(preview().width, closeTo(12 * scale, 1e-6));
    expect(find.text('크기 12 pt'), findsOneWidget);

    tester.widget<Slider>(find.byKey(EraserSettingsPanel.sizeKey)).onChanged!(
      0.3,
    );
    await tester.pump();
    expect(_eraser(h).diameter, 10);
    expect(preview().width, closeTo(10 * scale, 1e-6));

    final rect = tester.getRect(find.byKey(EraserSettingsPanel.sizeKey));
    await tester.tapAt(rect.centerRight - const Offset(2, 0));
    await tester.pump();
    expect(_eraser(h).diameter, 100);
    expect(preview().width, EraserSettingsPanel.maxPreviewPx);
    await tester.tapAt(rect.centerLeft + const Offset(2, 0));
    await tester.pump();
    expect(_eraser(h).diameter, 1);
  });

  testWidgets('filter segments set core.StrokeFilter; the switch sets '
      'returnToPreviousTool; editor.eraser (synced) stores them', (
    tester,
  ) async {
    final h = await _open(tester);
    for (final filter in [
      core.StrokeFilter.highlighterOnly,
      core.StrokeFilter.exceptHighlighter,
      core.StrokeFilter.all,
      core.StrokeFilter.highlighterOnly,
    ]) {
      await tester.tap(
        find.byKey(EraserSettingsPanel.filterSegmentKey(filter)),
      );
      await tester.pump();
      expect(_eraser(h).filter, filter);
    }
    expect(_eraser(h).returnToPreviousTool, isFalse);
    await tester.ensureVisible(find.byKey(EraserSettingsPanel.returnKey));
    await tester.pump();
    await tester.tap(find.byKey(EraserSettingsPanel.returnKey));
    await tester.pump();
    expect(_eraser(h).returnToPreviousTool, isTrue);

    await tester.pump(const Duration(milliseconds: 600)); // 500 ms debounce
    expect(EditorSettingKeys.eraser.scope, core.SettingScope.synced);
    final stored = await h.store.settings.get(EditorSettingKeys.eraser);
    expect(stored['filter'], 'highlighterOnly');
    expect(stored['returnToPrevious'], isTrue);
  });

  testWidgets('the chosen filter reaches the eraser: highlighter only keeps '
      'the ballpoint stroke', (tester) async {
    final h = await _open(tester);
    await tester.tap(
      find.byKey(
        EraserSettingsPanel.filterSegmentKey(core.StrokeFilter.highlighterOnly),
      ),
    );
    await tester.pump();
    h.container.read(editorPopupProvider.notifier).close();
    await tester.pump();
    // One pass over both strokes (strokeA y = 150, highlighter y = 300).
    final path = [
      for (var y = 120.0; y <= 330; y += 10) h.toGlobal(0, Offset(160, y)),
    ];
    await h.driver.stylusStroke(path);
    await tester.pump();
    final page = h.session.pageIfLoaded(h.pageId(0))!;
    expect(page.strokeById(strokeA.id), isNotNull);
    // Erased or split (both remove the original id).
    expect(page.strokeById(highlighterStroke.id), isNull);
  });

  testWidgets('현재 페이지 지우기 is in the error colour and asks first', (
    tester,
  ) async {
    await _open(tester);
    final button = find.byKey(EraserSettingsPanel.clearPageKey);
    await tester.ensureVisible(button);
    await tester.pump();
    final style = tester.widget<TextButton>(button).style!;
    final context = tester.element(button);
    expect(
      style.foregroundColor!.resolve(const {}),
      Theme.of(context).colorScheme.error,
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(ClearPageDialog), findsOneWidget);
    await tester.tap(find.byKey(ClearPageDialog.cancelKey));
    await tester.pumpAndSettle();
  });
}
