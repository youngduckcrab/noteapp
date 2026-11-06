// E2-01 (m5-7/04-editor 6.11.1, 6.11.3, 6.11.5, 6.20): the inline text
// editor over its box, on the editor screen (fake store, R2-B3 INK).
// - 개발자 메뉴 '텍스트 상자 시험' → a new-box session at the centre of the
//   visible part of the current page (tap rule), the editor has the focus;
// - the editor TextField uses INK's own text style and strut, zero padding;
// - a Korean composing value (V1 — TextInput update with a composing range)
//   → a tap on the toolbar (tapOutside) → one AddObjects, '안녕' stored;
// - an existing rotated box on a zoomed camera: the editor sits on the
//   rotated frame, the same style, one UpdateObjects;
// - iOS: double tap → word selected and AdaptiveTextSelectionToolbar, a tap
//   on its Copy keeps the session (V6 ④);
// - Esc and a focus loss end the session (escape / focusLost).
import 'dart:math' as math;

import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/state/settings/editor_device_state.dart';
import 'package:feature_editor/src/text/text_box_editor.dart';
import 'package:feature_editor/src/text/text_box_placement.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/ui/toolbar/dev_menu.dart';
import 'package:feature_editor/src/ui/toolbar/editor_toolbar.dart';
import 'package:feature_editor/src/ui/toolbar/more_menu.dart';
import 'package:feature_editor/src/viewport/page_viewport.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:ink_engine/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';

const _devOn = EditorSettings(showDevOverlay: true);

final _editor = find.byKey(textEditorKey);

Future<void> _startProbe(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EditorDevMenu.menuKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(EditorDevMenu.textBoxProbeKey));
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester) => tester.widget<TextField>(_editor);

List<String> _executes(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

/// V1: what the platform sends while a Korean IME is composing.
void _composeKorean(WidgetTester tester, String text) {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange(start: text.length - 1, end: text.length),
    ),
  );
}

/// A tap outside the editor's tap group with no side effect: the note title.
Future<void> _tapToolbar(WidgetTester tester) async {
  await tester.tap(find.byKey(EditorToolbar.titleKey));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await useInkTestFonts();
  });
  tearDown(() => TextEditNotifier.debugIsWebOverride = null);

  testWidgets('개발자 메뉴 텍스트 상자 시험 → a new box at the visible centre, '
      'the editor focused', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    final centre = visibleCentreOfPage(h.viewport, 0);
    await _startProbe(tester);

    final s = h.container.read(editorTextEditProvider)!;
    expect(s.isNew, isTrue);
    expect(s.pageId, h.pageId(0));
    expect(s.mode, WebTextInputMode.inline);
    final r = s.draft.frame.rect;
    expect(r.left, closeTo(centre.dx, 1e-6));
    expect(r.top, closeTo(centre.dy, 1e-6));
    expect(
      r.right - r.left,
      closeTo(
        math.min(240, core.PageSize.a4Portrait.width - centre.dx - 16),
        1e-9,
      ),
    );
    expect(_editor, findsOneWidget);
    expect(_field(tester).focusNode!.hasFocus, isTrue);
    expect(h.controllerOf(0).hiddenObjectIds, isEmpty, reason: 'a new box');
  });

  testWidgets('the editor: INK text style and strut, zero padding, collapsed', (
    tester,
  ) async {
    await pumpEditor(tester, settings: _devOn);
    await _startProbe(tester);
    final field = _field(tester);
    const style = core.TextBoxStyle();
    expect(field.style, ink.InkTextLayout.textStyleOf(style));
    expect(field.strutStyle, ink.InkTextLayout.strutStyleOf(style));
    expect(field.decoration!.contentPadding, EdgeInsets.zero);
    expect(field.decoration!.isCollapsed, isTrue);
    expect(field.maxLines, isNull);
    final limit =
        field.inputFormatters!.single as LengthLimitingTextInputFormatter;
    expect(limit.maxLength, core.PageObjectLimits.maxTextLength);
  });

  testWidgets('Korean while composing → tap on the toolbar → one AddObjects '
      'with 안녕', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _startProbe(tester);
    final id = h.container.read(editorTextEditProvider)!.boxId;
    _composeKorean(tester, '안녕');
    await tester.pump();
    expect(h.container.read(editorTextEditProvider)!.draft.text, '안녕');

    await _tapToolbar(tester);
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    await tester.pump();

    expect(_executes(h), ['execute:add-objects']);
    expect(h.session.history.undoDepth, 1);
    expect(notifier.lastEndReason, TextEditEndReason.tapOutside);
    expect(h.container.read(editorTextEditProvider), isNull);
    expect(_editor, findsNothing);
    // CORE PageContent.objects (the INK content gets objects in E2-02).
    final objects = h.session.pageIfLoaded(h.pageId(0))!.objects;
    expect(objects.single.id, id);
    expect((objects.single as core.TextBoxObject).text, '안녕');
  });

  testWidgets('an existing rotated box on a zoomed camera: the editor sits on '
      'the rotated frame, one UpdateObjects', (tester) async {
    final seeded = PageObjectFixtures.textBox(
      pageId: 'x',
      id: 'tb-1',
      text: '처음',
    );
    final rotated = seeded.copyWith(
      frame: core.ElementFrame(seeded.frame.rect, rotation: 0.4),
    );
    final h = await pumpEditor(
      tester,
      settings: _devOn,
      objectsByPageIndex: {
        0: [rotated],
      },
    );
    final viewport = h.viewport;
    viewport
      ..zoomBy(2, viewport.viewportSize.center(Offset.zero))
      ..settleNow();
    await tester.pump();
    final box =
        h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
            as core.TextBoxObject;
    // Make the box visible at this zoom (top-left of the frame at 1/4).
    viewport.panBy(
      viewport.viewportSize.center(Offset.zero) / 2 -
          viewport.pageToScreen(
            0,
            Offset(box.frame.center.x, box.frame.center.y),
          ),
    );
    viewport.settleNow();
    await tester.pump();
    h.container.read(editorTextEditProvider.notifier).start(box, isNew: false);
    await tester.pump();
    await tester.pump();

    expect(h.controllerOf(0).hiddenObjectIds, {'tb-1'});
    final field = _field(tester);
    expect(field.style, ink.InkTextLayout.textStyleOf(box.style));
    expect(field.strutStyle, ink.InkTextLayout.strutStyleOf(box.style));
    expect(field.decoration!.contentPadding, EdgeInsets.zero);
    expect(field.focusNode!.hasFocus, isTrue);
    // The editor's top-left = the rotated frame's top-left corner on screen;
    // its width = the frame width × camera scale.
    final draft = h.container.read(editorTextEditProvider)!.draft;
    final corner = draft.frame.corners.first;
    final expected = viewport.pageToScreen(0, Offset(corner.x, corner.y));
    final origin = tester.getTopLeft(find.byType(PageViewport));
    final topLeft = tester.getTopLeft(_editor) - origin;
    expect(topLeft.dx, closeTo(expected.dx, 1e-3));
    expect(topLeft.dy, closeTo(expected.dy, 1e-3));
    final editorBox = tester.renderObject<RenderBox>(_editor);
    expect(editorBox.size.width, closeTo(draft.frame.rect.width, 1e-6));
    final topRight = editorBox.localToGlobal(Offset(editorBox.size.width, 0));
    expect(
      (topRight - tester.getTopLeft(_editor)).distance,
      closeTo(draft.frame.rect.width * viewport.camera.scale, 1e-3),
    );

    _composeKorean(tester, '처음 고침');
    await tester.pump();
    await _tapToolbar(tester);
    await h.container.read(editorTextEditProvider.notifier).ending;
    await tester.pump();

    expect(_executes(h), ['execute:update-objects']);
    expect(h.session.history.undoDepth, 1);
    expect(h.controllerOf(0).hiddenObjectIds, isEmpty);
    final stored =
        h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
            as core.TextBoxObject;
    expect(stored.text, '처음 고침');
    expect(stored.frame.rotation, closeTo(0.4, 1e-9));
  });

  testWidgets(
    'iOS: double tap → word selected and the adaptive toolbar; its Copy '
    'keeps the session',
    (tester) async {
      final seeded = PageObjectFixtures.textBox(pageId: 'x', id: 'tb-1');
      final h = await pumpEditor(
        tester,
        objectsByPageIndex: {
          0: [seeded],
        },
      );
      final box =
          h.session.pageIfLoaded(h.pageId(0))!.objectById('tb-1')!
              as core.TextBoxObject;
      expect(box.text, '안녕 hello');
      h.container
          .read(editorTextEditProvider.notifier)
          .start(box, isNew: false);
      await tester.pumpAndSettle();

      final editable = tester
          .state<EditableTextState>(
            find.descendant(of: _editor, matching: find.byType(EditableText)),
          )
          .renderEditable;
      // Inside 'hello' (offsets 3…8).
      final caret = editable.getLocalRectForCaret(
        const TextPosition(offset: 5),
      );
      final at = editable.localToGlobal(caret.center);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();

      final controller = _field(tester).controller!;
      expect(
        controller.selection,
        const TextSelection(baseOffset: 3, extentOffset: 8),
      );
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(h.container.read(editorTextEditProvider), isNotNull);
      expect(_field(tester).focusNode!.hasFocus, isTrue);
      expect(_executes(h), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('Esc ends the session (escape)', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _startProbe(tester);
    _composeKorean(tester, '글');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    expect(notifier.lastEndReason, TextEditEndReason.escape);
    expect(_executes(h), ['execute:add-objects']);
  });

  testWidgets('the editor losing the focus ends the session (focusLost)', (
    tester,
  ) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await _startProbe(tester);
    _composeKorean(tester, '포커스');
    await tester.pump();
    // The iPad keyboard's hide key: the field loses the focus.
    _field(tester).focusNode!.unfocus();
    await tester.pump();
    final notifier = h.container.read(editorTextEditProvider.notifier);
    await notifier.ending;
    expect(notifier.lastEndReason, TextEditEndReason.focusLost);
    expect(_executes(h), ['execute:add-objects']);
    expect(h.container.read(editorTextEditProvider), isNull);
  });

  testWidgets('the probe is disabled on a read-only note', (tester) async {
    final h = await pumpEditor(tester, settings: _devOn);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(EditorMoreMenu.buttonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(EditorDevMenu.menuKey));
    await tester.pumpAndSettle();
    final item = tester.widget<MenuItemButton>(
      find.byKey(EditorDevMenu.textBoxProbeKey),
    );
    expect(item.onPressed, isNull);
  });
}
