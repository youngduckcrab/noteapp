// test/helpers/fake_extensions.dart — m5-7/04-editor 5.5, 8.2 E2-00.
//
// Test items for the extension slots of EditorExtensions (contract 7.2.10):
// a selection-menu item and an insert-menu item that record what they get
// and may run one command through the context's `execute`, and a minimal
// recording panel (tap-to-seek switch + close button).
import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

/// One recorded onSelected call of a test item.
final class ExtensionCall<C> {
  ExtensionCall(this.context, this.menu, this.index)
    : contextMounted = context.mounted;
  final BuildContext context;
  final C menu;
  final int index;

  /// [context].mounted at the moment onSelected was called.
  final bool contextMounted;
}

/// Shared behaviour of the two recording items.
abstract class _RecordingItem<C> {
  _RecordingItem({
    required this.id,
    required this.label,
    this.icon = Icons.star,
  });

  final String id;
  final String label;
  final IconData icon;

  final List<ExtensionCall<C>> calls = [];

  /// Runs synchronously inside onSelected (before any await) — a test checks
  /// here whether the menu is still open.
  void Function(ExtensionCall<C> call)? onRun;

  /// The next call throws synchronously from onSelected / completes its
  /// Future with this error.
  Object? throwSync;
  Object? throwAsync;

  /// When set, the next call waits for it before finishing (and before it
  /// executes its command).
  Completer<void>? holdNext;

  /// Errors the context's `execute` threw (a read-only note rethrows).
  final List<Object> executeErrors = [];

  core.EditCommand? Function(C menu)? _command;
  void Function(C menu)? _afterExecute;

  void Function(core.EditCommand) _executeOf(C menu);

  Future<void> _run(BuildContext context, C menu) {
    final call = ExtensionCall<C>(context, menu, calls.length);
    calls.add(call);
    onRun?.call(call);
    final sync = throwSync;
    if (sync != null) {
      throwSync = null;
      Error.throwWithStackTrace(sync, StackTrace.current);
    }
    return _finish(menu);
  }

  Future<void> _finish(C menu) async {
    final hold = holdNext;
    holdNext = null;
    if (hold != null) await hold.future;
    final error = throwAsync;
    if (error != null) {
      throwAsync = null;
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    final command = _command?.call(menu);
    if (command != null) {
      try {
        _executeOf(menu)(command);
      } catch (e) {
        executeErrors.add(e);
        rethrow;
      }
    }
    _afterExecute?.call(menu);
  }
}

/// A selection-menu test item. [command] (optional) builds the one command
/// it runs through EditorSelectionContext.execute.
class RecordingSelectionItem extends _RecordingItem<EditorSelectionContext> {
  RecordingSelectionItem({
    super.id = 'test.selection',
    super.label = '시험 항목',
    super.icon,
    core.EditCommand? Function(EditorSelectionContext selection)? command,
    this._isVisible,
  }) {
    _command = command;
  }

  final bool Function(EditorSelectionContext selection)? _isVisible;

  /// How often isVisible ran.
  int visibleCalls = 0;

  @override
  void Function(core.EditCommand) _executeOf(EditorSelectionContext menu) =>
      menu.execute;

  /// The slot item; the same instance every time (stable provider value).
  late final EditorSelectionMenuItem item = EditorSelectionMenuItem(
    id: id,
    label: label,
    icon: icon,
    onSelected: _run,
    isVisible: _isVisible == null ? null : _visible,
  );

  bool _visible(EditorSelectionContext selection) {
    visibleCalls++;
    return _isVisible!(selection);
  }
}

/// An insert-menu test item. [command] builds the one command it runs
/// through EditorInsertContext.execute; with [selectAfter] it then calls
/// selectObject on that id.
class RecordingInsertItem extends _RecordingItem<EditorInsertContext> {
  RecordingInsertItem({
    super.id = 'test.insert',
    super.label = '시험 삽입',
    super.icon,
    core.EditCommand? Function(EditorInsertContext insert)? command,
    String? selectAfter,
  }) {
    _command = command;
    if (selectAfter != null) {
      _afterExecute = (insert) => insert.selectObject(selectAfter);
    }
  }

  @override
  void Function(core.EditCommand) _executeOf(EditorInsertContext menu) =>
      menu.execute;

  late final EditorInsertMenuItem item = EditorInsertMenuItem(
    id: id,
    label: label,
    icon: icon,
    onSelected: _run,
  );
}

/// Keys of [TestRecordingPanel].
const testPanelKey = ValueKey('test.panel');
const testPanelTapToSeekKey = ValueKey('test.panel.tapToSeek');
const testPanelCloseKey = ValueKey('test.panel.close');

/// The recording panel builder of the tests: `(context, panel) =>
/// TestRecordingPanel(panel)`. [panelContexts] records every build.
class TestRecordingPanelBuilder {
  final List<EditorPanelContext> panelContexts = [];

  /// The next build throws this (E-7: the slot shows one line).
  Object? throwNext;

  late final EditorPanelBuilder builder = _build;

  Widget _build(BuildContext context, EditorPanelContext panel) {
    final error = throwNext;
    if (error != null) {
      throwNext = null;
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    panelContexts.add(panel);
    return TestRecordingPanel(panel);
  }
}

/// A small panel: a tap-to-seek switch bound to the editor's notifier and a
/// close button.
class TestRecordingPanel extends StatelessWidget {
  const TestRecordingPanel(this.panel, {super.key = testPanelKey});
  final EditorPanelContext panel;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Row(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: panel.tapToSeek,
          builder: (context, on, _) => Switch(
            key: testPanelTapToSeekKey,
            value: on,
            onChanged: panel.setTapToSeek,
          ),
        ),
        IconButton(
          key: testPanelCloseKey,
          icon: const Icon(Icons.close),
          onPressed: panel.close,
        ),
      ],
    ),
  );
}
