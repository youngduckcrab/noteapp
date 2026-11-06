// m5-7/04-editor 8.2 E2-07b, 6.7.1 · 6.7.3: the selection menu v2 through
// the whole editor (fake CORE, R2-B3 INK). The bar is [잘라내기] [복사] [삭제]
// [색 ●] [⋯]; '⋯' holds 복제 · 90° 돌리기 · (단일 텍스트) 편집 · 선택 해제. A
// read-only note disables everything that changes the note (복사 and 선택 해제
// stay); '색' is hidden for images / unknown objects only, '90° 돌리기' for
// unknown objects only. 잘라내기 = the clipboard content + ONE remove step;
// 복제 = ONE step (a composite for strokes + objects) and the copies
// selected.
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/text/text_edit_session.dart';
import 'package:feature_editor/src/tools/element_clipboard.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/selection_menu_model.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:feature_editor/src/ui/editor_strings.dart';
import 'package:feature_editor/src/ui/overlays/selection_menu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;
import 'package:note_core/testing.dart';

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

final core.ShapeObject _shape = PageObjectFixtures.shape(
  pageId: 'x',
  id: 'shape-1',
  rect: const core.PageRect(300, 120, 420, 200),
  createdAt: 5,
);

final core.TextBoxObject _text = PageObjectFixtures.textBox(
  pageId: 'x',
  id: 'text-1',
  rect: const core.PageRect(300, 300, 480, 340),
  createdAt: 6,
);

final core.ImageObject _image = PageObjectFixtures.image(
  pageId: 'x',
  id: 'image-1',
  assetId: 'asset-7',
  rect: const core.PageRect(300, 450, 450, 560),
  createdAt: 7,
);

final core.UnknownObject _unknown = PageObjectFixtures.unknown(
  pageId: 'x',
  id: 'unknown-1',
  rect: const core.PageRect(120, 650, 200, 720),
);

Future<EditorTestHandles> _pump(WidgetTester tester) async {
  final h = await pumpEditor(
    tester,
    strokesByPageIndex: {
      0: [strokeA, strokeB],
    },
    objectsByPageIndex: {
      0: [_shape, _text, _image, _unknown],
    },
  );
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  await tester.pump();
  return h;
}

Future<void> _select(
  WidgetTester tester,
  EditorTestHandles h,
  Set<String> ids,
) async {
  h.container
      .read(editorSelectionProvider.notifier)
      .select(h.pageId(0), ids, origin: SelectionOrigin.lasso);
  await tester.pump();
}

List<String> _edits(EditorTestHandles h) => [
  for (final c in h.recorder!.calls)
    if (c.startsWith('execute')) c,
];

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

core.PageContent _page(EditorTestHandles h) =>
    h.session.pageIfLoaded(h.pageId(0))!;

/// Whether the button at [key] (the keyed widget or the button inside it)
/// can be pressed.
bool _enabled(WidgetTester tester, Key key) {
  final at = find.byKey(key);
  final styled = find.descendant(
    of: at,
    matching: find.bySubtype<ButtonStyleButton>(),
    matchRoot: true,
  );
  if (styled.evaluate().isNotEmpty) {
    return tester.widget<ButtonStyleButton>(styled.first).enabled;
  }
  final icon = find.descendant(
    of: at,
    matching: find.byType(IconButton),
    matchRoot: true,
  );
  return tester.widget<IconButton>(icon).onPressed != null;
}

Future<void> _openMore(WidgetTester tester) async {
  await tester.tap(find.byKey(SelectionMenu.moreKey));
  await tester.pump();
}

Future<void> _tapMore(WidgetTester tester, Key item) async {
  await _openMore(tester);
  expect(find.byKey(item), findsOneWidget);
  await tester.tap(find.byKey(item));
  await tester.pump();
  await tester.pump();
}

int _dotColour(WidgetTester tester) {
  final box = tester.widget<Container>(find.byKey(SelectionMenu.colorDotKey));
  return (box.decoration! as BoxDecoration).color!.toARGB32();
}

void main() {
  group('items (6.7.1)', () {
    testWidgets('strokes + objects: the bar is 잘라내기 · 복사 · 삭제 · 색 · ⋯, '
        '⋯ holds 복제 · 90° 돌리기 · 선택 해제', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {strokeA.id, _shape.id, _image.id});

      for (final key in [
        SelectionMenu.cutKey,
        SelectionMenu.copyKey,
        SelectionMenu.deleteKey,
        SelectionMenu.colorKey,
        SelectionMenu.moreKey,
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key');
        expect(_enabled(tester, key), isTrue, reason: '$key');
      }
      expect(find.text(EditorStrings.selectionCut), findsOneWidget);
      expect(find.text(EditorStrings.selectionColor), findsOneWidget);
      // The dot: the first recolorable element in z order (strokeA, z 1).
      expect(
        _dotColour(tester),
        0xFF000000 + strokeA.style.colorArgb % 0x1000000,
      );
      // Nothing of '⋯' before it is opened.
      expect(find.byKey(SelectionMenu.duplicateKey), findsNothing);
      expect(find.byKey(SelectionMenu.clearKey), findsNothing);

      await _openMore(tester);
      for (final key in [
        SelectionMenu.duplicateKey,
        SelectionMenu.rotate90Key,
        SelectionMenu.clearKey,
      ]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key');
        expect(_enabled(tester, key), isTrue, reason: '$key');
        expect(
          tester.getSize(find.byKey(key)).height,
          greaterThanOrEqualTo(44),
        );
      }
      expect(find.text(EditorStrings.selectionDuplicate), findsOneWidget);
      expect(find.text(EditorStrings.selectionRotate90), findsOneWidget);
      // Not a single text box: no 편집.
      expect(find.byKey(SelectionMenu.editTextKey), findsNothing);
      // ⋯ again closes it.
      await tester.tap(find.byKey(SelectionMenu.moreKey));
      await tester.pump();
      expect(find.byKey(SelectionMenu.duplicateKey), findsNothing);
      expect(_edits(h), isEmpty);
    });

    testWidgets('a read-only note: 잘라내기 · 삭제 · 색 · 복제 · 돌리기 · 편집 '
        'disabled, 복사 and 선택 해제 work', (tester) async {
      final h = await _pump(tester);
      await h.store.library.trashItems([core.NoteRef(h.noteId)]);
      await tester.pump();
      expect(h.container.read(editorReadOnlyProvider), isTrue);
      await _select(tester, h, {_text.id});
      expect(_selection(h), isNotNull);

      expect(_enabled(tester, SelectionMenu.cutKey), isFalse);
      expect(_enabled(tester, SelectionMenu.deleteKey), isFalse);
      expect(_enabled(tester, SelectionMenu.colorKey), isFalse);
      expect(_enabled(tester, SelectionMenu.copyKey), isTrue);
      expect(_enabled(tester, SelectionMenu.moreKey), isTrue);
      await _openMore(tester);
      expect(_enabled(tester, SelectionMenu.duplicateKey), isFalse);
      expect(_enabled(tester, SelectionMenu.rotate90Key), isFalse);
      expect(_enabled(tester, SelectionMenu.editTextKey), isFalse);
      expect(_enabled(tester, SelectionMenu.clearKey), isTrue);
      await tester.tap(find.byKey(SelectionMenu.moreKey));
      await tester.pump();

      // The commands refuse too (a shortcut, a stale tap).
      final commands = h.container.read(editorCommandsProvider);
      commands.cutSelection();
      commands.duplicateSelection();
      expect(commands.recolorSelection(0xFFE53935), isFalse);
      await tester.pump();
      expect(_edits(h), isEmpty);

      await tester.tap(find.byKey(SelectionMenu.copyKey));
      await tester.pump();
      final copied = h.container.read(editorClipboardProvider)!;
      expect([for (final e in copied.elements) e.id], [_text.id]);
      expect(_edits(h), isEmpty);

      await _tapMore(tester, SelectionMenu.clearKey);
      expect(_selection(h), isNull);
      expect(find.byKey(SelectionMenu.copyKey), findsNothing);
    });

    testWidgets('an image only: no 색 (INK does not recolor images); 90° '
        '돌리기 stays — image + unknown: no 색 either', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {_image.id});
      expect(find.byKey(SelectionMenu.copyKey), findsOneWidget);
      expect(find.byKey(SelectionMenu.colorKey), findsNothing);
      await _openMore(tester);
      expect(find.byKey(SelectionMenu.rotate90Key), findsOneWidget);
      await tester.tap(find.byKey(SelectionMenu.moreKey));
      await tester.pump();

      await _select(tester, h, {_image.id, _unknown.id});
      expect(_selection(h)!.elementIds, {_image.id, _unknown.id});
      expect(find.byKey(SelectionMenu.colorKey), findsNothing);
      await _openMore(tester);
      expect(find.byKey(SelectionMenu.rotate90Key), findsOneWidget);
    });

    testWidgets('unknown objects only: no 색, no 90° 돌리기; 잘라내기 · 복사 · '
        '삭제 · 복제 · 선택 해제 stay', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {_unknown.id});
      expect(_selection(h)!.elementIds, {_unknown.id});
      expect(find.byKey(SelectionMenu.colorKey), findsNothing);
      for (final key in [
        SelectionMenu.cutKey,
        SelectionMenu.copyKey,
        SelectionMenu.deleteKey,
      ]) {
        expect(_enabled(tester, key), isTrue, reason: '$key');
      }
      await _openMore(tester);
      expect(find.byKey(SelectionMenu.rotate90Key), findsNothing);
      expect(find.byKey(SelectionMenu.duplicateKey), findsOneWidget);
      expect(find.byKey(SelectionMenu.clearKey), findsOneWidget);
    });

    testWidgets('a single text box: ⋯ → 편집 starts its edit session (the '
        'selection ends, no command yet)', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {_text.id});
      await _tapMore(tester, SelectionMenu.editTextKey);

      expect(_selection(h), isNull);
      final session = h.container.read(editorTextEditProvider);
      expect(session, isNotNull);
      expect(session!.boxId, _text.id);
      expect(session.isNew, isFalse);
      expect(find.byKey(SelectionMenu.editTextKey), findsNothing); // closed
      expect(_edits(h), isEmpty);
    });

    testWidgets('the menu model: z order colour, recolor / transform flags, '
        'single object', (tester) async {
      final h = await _pump(tester);
      final page = _page(h);
      SelectionMenuModel of(Set<String> ids) =>
          SelectionMenuModel.of(page, ids);

      final mixed = of({_text.id, _shape.id, strokeB.id});
      expect(mixed.canRecolor, isTrue);
      expect(mixed.colorArgb, 0xFF000000 + strokeB.style.colorArgb % 0x1000000);
      expect(mixed.canTransform, isTrue);
      expect(mixed.single, isNull);
      expect(mixed.elementCount, 3);
      expect(of({_shape.id, _text.id}).colorArgb, 0xFF1A1A1A); // shape first
      expect(of({_text.id}).single, _page(h).objectById(_text.id));
      expect(of({_image.id}).canRecolor, isFalse);
      expect(of({_image.id}).colorArgb, isNull);
      expect(of({_image.id}).canTransform, isTrue);
      expect(of({_unknown.id}).canTransform, isFalse);
      expect(of({_unknown.id, _image.id}).canRecolor, isFalse);
      expect(of({'gone'}), SelectionMenuModel.empty);
      expect(SelectionMenuModel.of(null, {_text.id}), SelectionMenuModel.empty);
    });
  });

  group('cut · duplicate · rotate (6.7.3)', () {
    testWidgets('잘라내기: the clipboard holds the elements, ONE '
        'remove-elements step, the selection ends', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {strokeA.id, _shape.id, _text.id});
      await tester.tap(find.byKey(SelectionMenu.cutKey));
      await tester.pump();

      expect(_edits(h), ['execute:remove-elements']);
      expect(h.session.history.undoDepth, 1);
      final clipboard = h.container.read(editorClipboardProvider)!;
      expect(
        {for (final e in clipboard.elements) e.id},
        {strokeA.id, _shape.id, _text.id},
      );
      expect(clipboard.objectCount, 2);
      expect(clipboard.strokes.single.id, strokeA.id);
      final page = _page(h);
      expect(page.strokeById(strokeA.id), isNull);
      expect(page.objectById(_shape.id), isNull);
      expect(page.objectById(_text.id), isNull);
      expect(page.objectById(_image.id), isNotNull);
      expect(_selection(h), isNull);
      expect(find.byKey(SelectionMenu.cutKey), findsNothing);

      // One undo brings all three back.
      await h.container.read(editorCommandsProvider).undo();
      await tester.pump();
      expect(_page(h).strokeById(strokeA.id), isNotNull);
      expect(_page(h).objectById(_shape.id), isNotNull);
      expect(_page(h).objectById(_text.id), isNotNull);
    });

    testWidgets('잘라내기 of strokes only → remove-strokes; a rejected delete '
        'keeps the clipboard and the selection', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {strokeA.id, strokeB.id});
      h.recorder!.rejectNext(const core.ReadOnlyNoteException('race'));
      await tester.tap(find.byKey(SelectionMenu.cutKey));
      await tester.pump();

      expect(_edits(h), ['execute:remove-strokes:rejected']);
      expect(h.controllerOf(0).pendingIds, isEmpty);
      expect(h.container.read(editorClipboardProvider)!.strokes, hasLength(2));
      expect(_selection(h)!.elementIds, {strokeA.id, strokeB.id});
      expect(h.session.history.undoDepth, 0);
      await tester.pump(const Duration(seconds: 5)); // snackbar timer

      await tester.tap(find.byKey(SelectionMenu.cutKey));
      await tester.pump();
      expect(_edits(h).last, 'execute:remove-strokes');
      expect(_page(h).strokes, isEmpty);
    });

    testWidgets('복제: ONE composite step (strokes + objects), the copies '
        'selected (origin paste), the originals kept', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {strokeA.id, _shape.id, _image.id});
      await _tapMore(tester, SelectionMenu.duplicateKey);

      expect(_edits(h), ['execute:composite']);
      expect(h.session.history.undoDepth, 1);
      final page = _page(h);
      expect(page.strokes, hasLength(3));
      expect(page.objects, hasLength(6));
      final selected = _selection(h)!;
      expect(selected.origin, SelectionOrigin.paste);
      expect(selected.elementIds, hasLength(3));
      expect(
        selected.elementIds.intersection({strokeA.id, _shape.id, _image.id}),
        isEmpty,
      );
      for (final id in selected.elementIds) {
        expect(page.elementById(id), isNotNull);
      }
      final copies = [
        for (final id in selected.elementIds) page.elementById(id)!,
      ];
      expect(copies.whereType<core.Stroke>(), hasLength(1));
      expect(copies.whereType<core.ImageObject>().single.assetId, 'asset-7');
      expect(find.byKey(SelectionMenu.duplicateKey), findsNothing); // closed

      // Strokes only → add-strokes.
      await _select(tester, h, {strokeB.id});
      await _tapMore(tester, SelectionMenu.duplicateKey);
      expect(_edits(h).last, 'execute:add-strokes');
      expect(h.session.history.undoDepth, 2);
    });

    testWidgets('90° 돌리기 from ⋯ → one transform step, the same ids stay '
        'selected', (tester) async {
      final h = await _pump(tester);
      await _select(tester, h, {strokeA.id, _shape.id});
      await _tapMore(tester, SelectionMenu.rotate90Key);

      expect(_edits(h), ['execute:transform']);
      expect(h.session.history.undoDepth, 1);
      expect(_selection(h)!.elementIds, {strokeA.id, _shape.id});
      expect(find.byKey(SelectionMenu.rotate90Key), findsNothing); // closed
    });
  });
}
