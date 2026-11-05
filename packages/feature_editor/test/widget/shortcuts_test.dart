// E-12: keyboard shortcuts (04-editor 6.8): every key of the table with ⌘
// and with Ctrl, text inputs keep their own keys (a focused text field turns
// every editor Action off), P / E / L only while the canvas is the primary
// focus, and a pointer down on the canvas focuses it again.
import 'package:feature_editor/feature_editor.dart';
import 'package:feature_editor/src/input/editor_shortcuts.dart';
import 'package:feature_editor/src/scope/editor_scope.dart';
import 'package:feature_editor/src/tools/selection.dart';
import 'package:feature_editor/src/tools/stroke_clipboard.dart';
import 'package:feature_editor/src/tools/tool_controller.dart';
import 'package:feature_editor/src/tools/tool_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../helpers/pump_editor.dart';
import '../helpers/test_data.dart';

/// The command modifier of a shortcut: ⌘ (macOS, iPadOS) or Ctrl (others).
enum _Mod { meta, control }

LogicalKeyboardKey _keyOf(_Mod mod) => switch (mod) {
  _Mod.meta => LogicalKeyboardKey.metaLeft,
  _Mod.control => LogicalKeyboardKey.controlLeft,
};

/// Presses [key] with the given modifiers held, then pumps a frame.
Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  _Mod? mod,
  bool shift = false,
  PhysicalKeyboardKey? physical, // for logical keys without a physical twin
}) async {
  final held = [
    if (mod != null) _keyOf(mod),
    if (shift) LogicalKeyboardKey.shiftLeft,
  ];
  for (final m in held) {
    await tester.sendKeyDownEvent(m);
  }
  await tester.sendKeyEvent(key, physicalKey: physical);
  for (final m in held.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pump();
}

/// Lets an undo / redo, a paste or a camera animation (250 ms) finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const List<Offset> _points = [
  Offset(100, 150),
  Offset(140, 170),
  Offset(190, 185),
  Offset(240, 200),
];

FocusNode? get _primary => FocusManager.instance.primaryFocus;

bool _canvasFocused() => _primary?.debugLabel == 'EditorCanvas';

EditorSelection? _selection(EditorTestHandles h) =>
    h.container.read(editorSelectionProvider);

void _select(EditorTestHandles h, Set<String> ids) {
  h.container.read(editorCommandsProvider).selectTool(EditorTool.lasso);
  h.container.read(editorSelectionProvider.notifier).select(h.pageId(0), ids);
}

ToolState _tools(EditorTestHandles h) => h.container.read(editorToolProvider);

/// A text field (stand-in for the HEX field of the colour picker) under its
/// own EditorShortcuts with the editor's container, in the navigator overlay.
/// Esc that went on to the text field's chain lands in [onDismiss] (the
/// route's DismissIntent action is not above an overlay entry).
/// Remove the returned entry at the end of the test body.
Future<OverlayEntry> _showTextField(
  WidgetTester tester,
  EditorTestHandles h,
  TextEditingController text, {
  required VoidCallback onDismiss,
}) async {
  final overlay = tester.state<OverlayState>(find.byType(Overlay).first);
  final entry = OverlayEntry(
    builder: (context) => UncontrolledProviderScope(
      container: h.container,
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              onDismiss();
              return null;
            },
          ),
        },
        child: EditorShortcuts(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              child: SizedBox(
                width: 200,
                child: TextField(key: const ValueKey('hex'), controller: text),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  await tester.pump();
  await tester.showKeyboard(find.byKey(const ValueKey('hex')));
  await tester.pump();
  return entry;
}

void main() {
  testWidgets('the canvas has the focus once the note is open', (tester) async {
    await pumpEditor(tester);
    await tester.pump();
    expect(_canvasFocused(), isTrue);
  });

  for (final mod in _Mod.values) {
    group('${mod.name}:', () {
      testWidgets('Z → undo, Shift+Z → redo', (tester) async {
        final h = await pumpEditor(tester);
        await h.driver.stylusStroke(pathThrough(h, 0, _points));
        expect(h.session.history.undoDepth, 1);

        await _press(tester, LogicalKeyboardKey.keyZ, mod: mod);
        await _settle(tester);
        expect(h.recorder!.countOf('undo'), 1);
        expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);

        await _press(tester, LogicalKeyboardKey.keyZ, mod: mod, shift: true);
        await _settle(tester);
        expect(h.recorder!.countOf('redo'), 1);
        expect(h.recorder!.countOf('undo'), 1);
        expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
      });

      testWidgets('C copies the selection, V pastes it at the screen centre', (
        tester,
      ) async {
        final h = await pumpEditor(
          tester,
          strokesByPageIndex: {
            0: [strokeA, strokeB],
          },
        );
        _select(h, {strokeA.id});
        await tester.pump();

        await _press(tester, LogicalKeyboardKey.keyC, mod: mod);
        expect(h.container.read(editorClipboardProvider)?.strokes, [
          isA<core.Stroke>().having((s) => s.id, 'id', strokeA.id),
        ]);
        expect(
          h.recorder!.calls.where((c) => c.startsWith('execute')),
          isEmpty,
        );

        await _press(tester, LogicalKeyboardKey.keyV, mod: mod);
        await _settle(tester);
        expect(h.recorder!.countOf('executeAsync:add-strokes'), 1);
        final strokes = h.session.pageIfLoaded(h.pageId(0))!.strokes;
        expect(strokes, hasLength(3));
        final pasted = strokes.last;
        expect(pasted.id, isNot(strokeA.id));
        expect(_selection(h)?.strokeIds, {pasted.id});
        // Centred on the screen centre (current page coordinates).
        final centre = h.viewport.screenToPage(
          0,
          h.viewport.viewportSize.center(Offset.zero),
        );
        final b = pasted.bounds;
        expect(
          Offset((b.left + b.right) / 2, (b.top + b.bottom) / 2),
          within(distance: 0.5, from: centre),
        );
      });

      testWidgets('=, Shift+= (+), + and keypad + zoom in; - zooms out; '
          '0 fits the width', (tester) async {
        final h = await pumpEditor(tester);
        final v = h.viewport;
        expect(v.zoom, closeTo(1, 1e-9));

        await _press(tester, LogicalKeyboardKey.equal, mod: mod);
        await _settle(tester);
        expect(v.zoom, closeTo(1.25, 1e-6));

        await _press(tester, LogicalKeyboardKey.equal, mod: mod, shift: true);
        await _settle(tester);
        expect(v.zoom, closeTo(1.25 * 1.25, 1e-6));

        await _press(tester, LogicalKeyboardKey.minus, mod: mod);
        await _settle(tester);
        expect(v.zoom, closeTo(1.25, 1e-6));

        await _press(tester, LogicalKeyboardKey.digit0, mod: mod);
        await _settle(tester);
        expect(v.zoom, closeTo(1, 1e-9));

        await _press(
          tester,
          LogicalKeyboardKey.add,
          mod: mod,
          physical: PhysicalKeyboardKey.equal,
        );
        await _settle(tester);
        expect(v.zoom, closeTo(1.25, 1e-6));

        await _press(tester, LogicalKeyboardKey.numpadAdd, mod: mod);
        await _settle(tester);
        expect(v.zoom, closeTo(1.25 * 1.25, 1e-6));

        await _press(tester, LogicalKeyboardKey.numpadSubtract, mod: mod);
        await _settle(tester);
        expect(v.zoom, closeTo(1.25, 1e-6));

        await _press(tester, LogicalKeyboardKey.numpad0, mod: mod);
        await _settle(tester);
        expect(v.zoom, closeTo(1, 1e-9));
      });

      testWidgets('Shift+D toggles the developer overlay setting', (
        tester,
      ) async {
        final h = await pumpEditor(tester);
        bool shown() => h.container.read(editorSettingsProvider).showDevOverlay;
        expect(shown(), isFalse);

        await _press(tester, LogicalKeyboardKey.keyD, mod: mod, shift: true);
        expect(shown(), isTrue);
        await _press(tester, LogicalKeyboardKey.keyD, mod: mod, shift: true);
        expect(shown(), isFalse);
        // Without Shift: nothing.
        await _press(tester, LogicalKeyboardKey.keyD, mod: mod);
        expect(shown(), isFalse);
        await tester.pump(const Duration(seconds: 1)); // debounced write
      });

      testWidgets('a focused text field keeps Z, C, V, Delete, Esc, Space and '
          'P to itself', (tester) async {
        final h = await pumpEditor(
          tester,
          strokesByPageIndex: {
            0: [strokeA, strokeB],
          },
        );
        await h.driver.stylusStroke(pathThrough(h, 0, _points));
        _select(h, {strokeA.id});
        await tester.pump();
        final text = TextEditingController(text: '#FF0000');
        addTearDown(text.dispose);
        var dismissed = 0;
        final entry = await _showTextField(
          tester,
          h,
          text,
          onDismiss: () => dismissed++,
        );
        expect(editorTextInputHasFocus(), isTrue);
        final camera = h.viewport.camera;

        await _press(tester, LogicalKeyboardKey.keyZ, mod: mod);
        await _press(tester, LogicalKeyboardKey.keyZ, mod: mod, shift: true);
        await _press(tester, LogicalKeyboardKey.keyC, mod: mod);
        await _press(tester, LogicalKeyboardKey.keyV, mod: mod);
        await _press(tester, LogicalKeyboardKey.equal, mod: mod);
        await _press(tester, LogicalKeyboardKey.delete);
        await _press(tester, LogicalKeyboardKey.backspace);
        await _press(tester, LogicalKeyboardKey.escape);
        await _press(tester, LogicalKeyboardKey.space);
        await _press(tester, LogicalKeyboardKey.pageDown);
        await _press(tester, LogicalKeyboardKey.keyE);
        await _settle(tester);

        expect(h.recorder!.countOf('undo'), 0);
        expect(h.recorder!.countOf('redo'), 0);
        expect(h.session.history.undoDepth, 1);
        expect(h.container.read(editorClipboardProvider), isNull);
        expect(_selection(h)?.strokeIds, {strokeA.id});
        expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(3));
        expect(h.viewport.camera, camera);
        expect(_tools(h).activeTool, EditorTool.lasso);
        expect(editorTextInputHasFocus(), isTrue);
        expect(dismissed, 1, reason: 'Esc went on to the text field chain');

        // The same keys reach the editor once the canvas has the focus again
        // (a pointer down on the page area).
        await h.driver.wait(const Duration(seconds: 1));
        await h.driver.down(
          9,
          pageCenterOf(h, 0) + const Offset(0, 300),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await h.driver.up(9);
        await tester.pump();
        expect(_canvasFocused(), isTrue);
        h.container.read(editorInteractionHostProvider).closeContextMenu();
        await _press(tester, LogicalKeyboardKey.keyZ, mod: mod);
        await _settle(tester);
        expect(h.recorder!.countOf('undo'), 1);
        expect(h.session.history.undoDepth, 0);

        entry
          ..remove()
          ..dispose();
        await tester.pump();
      });
    });
  }

  testWidgets('Ctrl+Y → redo', (tester) async {
    final h = await pumpEditor(tester);
    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    await _press(tester, LogicalKeyboardKey.keyZ, mod: _Mod.control);
    await _settle(tester);
    expect(h.recorder!.countOf('undo'), 1);

    await _press(tester, LogicalKeyboardKey.keyY, mod: _Mod.control);
    await _settle(tester);
    expect(h.recorder!.countOf('redo'), 1);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, hasLength(1));
  });

  testWidgets('Delete and Backspace delete the selection', (tester) async {
    final h = await pumpEditor(
      tester,
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    for (final key in [
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.backspace,
    ]) {
      final page = h.session.pageIfLoaded(h.pageId(0))!;
      _select(h, {page.strokes.first.id});
      await tester.pump();
      await _press(tester, key);
      expect(_selection(h), isNull);
    }
    expect(h.recorder!.countOf('execute:remove-strokes'), 2);
    expect(h.session.pageIfLoaded(h.pageId(0))!.strokes, isEmpty);

    // Nothing selected → nothing to delete.
    await _press(tester, LogicalKeyboardKey.delete);
    expect(h.recorder!.countOf('execute:remove-strokes'), 2);
  });

  testWidgets('Esc: context menu → eyedropper → selection, one per press', (
    tester,
  ) async {
    final h = await pumpEditor(
      tester,
      settings: const EditorSettings(inputMode: InputMode.penOnly),
      strokesByPageIndex: {
        0: [strokeA, strokeB],
      },
    );
    final host = h.container.read(editorInteractionHostProvider);
    _select(h, {strokeA.id});
    h.container.read(editorToolProvider.notifier).setEyedropper(true);
    // Context menu off the selection (secondary click).
    await h.driver.down(
      9,
      pageCenterOf(h, 0) + const Offset(0, 300),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await h.driver.up(9);
    await tester.pump();
    expect(host.contextMenu.value, isNotNull);
    expect(_tools(h).eyedropperActive, isTrue);
    expect(_selection(h), isNotNull);

    await _press(tester, LogicalKeyboardKey.escape);
    expect(host.contextMenu.value, isNull);
    expect(_tools(h).eyedropperActive, isTrue);
    expect(_selection(h), isNotNull);

    await _press(tester, LogicalKeyboardKey.escape);
    expect(_tools(h).eyedropperActive, isFalse);
    expect(_selection(h), isNotNull);

    await _press(tester, LogicalKeyboardKey.escape);
    expect(_selection(h), isNull);

    // Nothing left: no effect.
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_selection(h), isNull);
    expect(h.recorder!.calls.where((c) => c.startsWith('execute')), isEmpty);
  });

  testWidgets('PageDown / Space → next screen, PageUp / Shift+Space → '
      'previous screen (0.9 × viewport height)', (tester) async {
    final h = await pumpEditor(tester, pages: 5);
    final v = h.viewport;
    final step = 0.9 * v.viewportSize.height / v.camera.scale;
    final top = v.camera.origin.dy;

    await _press(tester, LogicalKeyboardKey.pageDown);
    await _settle(tester);
    expect(v.camera.origin.dy, closeTo(top + step, 1e-6));

    await _press(tester, LogicalKeyboardKey.space);
    await _settle(tester);
    expect(v.camera.origin.dy, closeTo(top + 2 * step, 1e-6));

    await _press(tester, LogicalKeyboardKey.pageUp);
    await _settle(tester);
    expect(v.camera.origin.dy, closeTo(top + step, 1e-6));

    await _press(tester, LogicalKeyboardKey.space, shift: true);
    await _settle(tester);
    expect(v.camera.origin.dy, closeTo(top, 1e-6));
  });

  testWidgets('P / E / L select pen / eraser / lasso while the canvas has '
      'the focus', (tester) async {
    final h = await pumpEditor(tester);
    expect(_canvasFocused(), isTrue);
    expect(_tools(h).activeTool, EditorTool.pen);

    await _press(tester, LogicalKeyboardKey.keyE);
    expect(_tools(h).activeTool, EditorTool.eraser);
    await _press(tester, LogicalKeyboardKey.keyL);
    expect(_tools(h).activeTool, EditorTool.lasso);
    await _press(tester, LogicalKeyboardKey.keyP);
    expect(_tools(h).activeTool, EditorTool.pen);

    // With a modifier: not a tool key.
    await _press(tester, LogicalKeyboardKey.keyE, mod: _Mod.meta);
    await _press(tester, LogicalKeyboardKey.keyE, mod: _Mod.control);
    await _press(tester, LogicalKeyboardKey.keyE, shift: true);
    expect(_tools(h).activeTool, EditorTool.pen);

    // The canvas loses the focus → P / E / L do nothing.
    _primary!.unfocus();
    await tester.pump();
    expect(_canvasFocused(), isFalse);
    await _press(tester, LogicalKeyboardKey.keyE);
    await _press(tester, LogicalKeyboardKey.keyL);
    expect(_tools(h).activeTool, EditorTool.pen);

    // A pointer down on the page area focuses it again.
    await h.driver.stylusStroke(pathThrough(h, 0, _points));
    expect(_canvasFocused(), isTrue);
    await _press(tester, LogicalKeyboardKey.keyL);
    expect(_tools(h).activeTool, EditorTool.lasso);
  });

  testWidgets('P / E / L do nothing on a read-only note', (tester) async {
    final h = await pumpEditor(tester);
    await h.store.library.trashItems([core.NoteRef(h.noteId)]);
    await tester.pump();
    expect(h.container.read(editorReadOnlyProvider), isTrue);

    await _press(tester, LogicalKeyboardKey.keyE);
    await _press(tester, LogicalKeyboardKey.keyL);
    expect(_tools(h).activeTool, EditorTool.pen);
  });

  test('every ⌘ shortcut has its Ctrl twin and the reverse', () {
    for (final entry in editorShortcutMap.entries) {
      final a = entry.key as SingleActivator;
      if (!a.meta && !a.control) continue;
      final twin = editorShortcutMap.entries.where((e) {
        final b = e.key as SingleActivator;
        return b.trigger == a.trigger &&
            b.shift == a.shift &&
            b.meta == a.control &&
            b.control == a.meta;
      });
      if (a.control && a.trigger == LogicalKeyboardKey.keyY) {
        expect(twin, isEmpty, reason: 'Ctrl+Y only (6.8 table)');
        continue;
      }
      expect(twin.map((e) => e.value), [entry.value], reason: '$a');
    }
  });
}
