// (UI stage 2, 04-editor 22) The toolbar's ui_kit line icons: the small
// names under 올가미 · 도형 · 텍스트 · 삽입 (always in 크래프트 / 스튜디오, on
// hover in 미니멀), the page button's '2 / 4', and the names on stylus hover
// over the icon-only buttons.
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/page_indicator.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/insert_menu.dart';
import 'package:feature_editor/src/ui/toolbar/tool_glyph.dart';
import 'package:feature_editor/src/ui/toolbar/undo_redo_buttons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../helpers/fake_image_importer.dart';
import '../helpers/pump_editor.dart';

const _captions = [
  EditorStrings.lasso,
  EditorStrings.shapeTool,
  EditorStrings.textTool,
  EditorStrings.insert,
];

double _opacityOf(WidgetTester tester, String caption) => tester
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byKey(ToolGlyph.captionKey(caption)),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

Future<TestGesture> _hover(WidgetTester tester, Finder target) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.stylus);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
  return gesture;
}

void main() {
  for (final style in [AppStyle.craft, AppStyle.studio]) {
    testWidgets('${style.wireName}: the four tool names always show', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        logicalSize: const Size(1280, 800),
        imageImporter: (s) => FakeImageImporter(store: s),
        theme: buildStyleTheme(style, Brightness.light),
      );
      for (final caption in _captions) {
        expect(find.byKey(ToolGlyph.captionKey(caption)), findsOneWidget);
        expect(_opacityOf(tester, caption), 1, reason: caption);
      }
      // The line icons are the ui_kit ones.
      for (final kind in [
        AppIconKind.lasso,
        AppIconKind.shape,
        AppIconKind.text,
        AppIconKind.insert,
        AppIconKind.undo,
        AppIconKind.redo,
        AppIconKind.pages,
        AppIconKind.search,
        AppIconKind.more,
        AppIconKind.back,
      ]) {
        expect(
          find.descendant(
            of: find.byType(EditorToolbar),
            matching: find.byWidgetPredicate(
              (w) => w is AppIcon && w.kind == kind,
            ),
          ),
          findsWidgets,
          reason: kind.name,
        );
      }
    });
  }

  testWidgets('calm: the names show only while a stylus hovers', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      logicalSize: const Size(1280, 800),
      imageImporter: (s) => FakeImageImporter(store: s),
      theme: buildStyleTheme(AppStyle.calm, Brightness.light),
    );
    for (final caption in _captions) {
      expect(_opacityOf(tester, caption), 0, reason: caption);
    }
    await _hover(tester, find.byKey(InsertMenu.buttonKey));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, EditorStrings.insert), 1);
    expect(_opacityOf(tester, EditorStrings.lasso), 0);
  });

  testWidgets("the page button shows '1 / 3'; the page indicator only while "
      'the menu is hidden', (tester) async {
    final h = await pumpEditor(tester, logicalSize: const Size(1280, 800));
    final count = find.byKey(EditorToolbar.pageCountKey);
    expect(count, findsOneWidget);
    expect(tester.widget<Text>(count).data, '1 / 3');
    expect(find.byKey(PageIndicator.indicatorKey), findsNothing);
    h.container.read(editorDeviceStateProvider.notifier).setToolbarHidden(true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(PageIndicator.indicatorKey), findsOneWidget);
  });

  testWidgets('below pageCountMinWidth the page button is the icon alone '
      'and the page indicator shows the count (review: never no count)', (
    tester,
  ) async {
    await pumpEditor(tester, logicalSize: const Size(740, 1000));
    expect(find.byKey(EditorToolbar.pagePanelKey), findsOneWidget);
    expect(find.byKey(EditorToolbar.pageCountKey), findsNothing);
    final indicator = find.byKey(PageIndicator.indicatorKey);
    expect(indicator, findsOneWidget);
    expect(tester.widget<Text>(indicator).data, '1 / 3');
  });

  testWidgets('calm: the name shows anywhere on the 48 px button, not only '
      'on the glyph; off with 펜을 띄우면 이름 보기 off', (tester) async {
    Future<void> pump({required bool names}) => pumpEditor(
      tester,
      logicalSize: const Size(1280, 800),
      imageImporter: (s) => FakeImageImporter(store: s),
      theme: buildStyleTheme(AppStyle.calm, Brightness.light),
      wrap: (child) => HoverNames(enabled: names, child: child),
    );
    await pump(names: true);
    // The button's corner: outside the 46×38 glyph, inside the 48×48 button.
    final lasso = tester.getRect(find.byKey(EditorToolbar.lassoKey));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.stylus);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(lasso.bottomLeft + const Offset(2, -2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, EditorStrings.lasso), 1);
    await gesture.moveTo(const Offset(640, 600));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, EditorStrings.lasso), 0);

    await pump(names: false);
    await gesture.moveTo(tester.getCenter(find.byKey(EditorToolbar.lassoKey)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_opacityOf(tester, EditorStrings.lasso), 0);
  });

  testWidgets('a hovering stylus shows the name of [↶]; it goes when the '
      'stylus leaves', (tester) async {
    await pumpEditor(tester, logicalSize: const Size(1280, 800));
    final undo = find.byKey(UndoRedoButtons.undoKey);
    final gesture = await _hover(tester, undo);
    await tester.pump(HoverName.wait + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(EditorStrings.undo), findsOneWidget);
    await gesture.moveTo(const Offset(640, 600));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(EditorStrings.undo), findsNothing);
  });
}
