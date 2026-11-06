// lib/src/ui/toolbar/dev_menu.dart — 04-editor 6.12.4 (EDITOR-S1): the more
// menu's '개발자 메뉴', shown while the developer overlay is visible.
// (v2, E2-01) m5-7/04-editor 6.20: '텍스트 상자 시험' (6.11.1) and, on the
// web only, '텍스트 입력 방식' (6.11.6 — EditorDeviceState.webTextInput).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/dev_tools.dart' as dev;
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../../state/settings/editor_device_state.dart';
import '../../text/text_box_placement.dart';
import '../../text/text_edit_session.dart';
import '../dev/dev_metrics.dart';
import '../editor_strings.dart';

/// 합성 노트 만들기 (core seedSyntheticNote: 'perf-test', 50 pages × 300
/// strokes → snack bar) · 현재 페이지에 합성 획 1,000개 / 3,000개
/// (EditorCommands.addSyntheticStrokes — one undo step, disabled on a
/// read-only note) · 진단 초기화 (InkDiagnostics.reset + DevMetrics.reset).
/// (v2) 텍스트 상자 시험 (a new-box session at the centre of the visible part
/// of the current page — disabled on a read-only note) · 텍스트 입력 방식
/// (web only: inline / sheet; textarea stays disabled until E2-11, P-C).
/// Only dev_tools libraries (web safe), never testing.dart.
class EditorDevMenu extends ConsumerWidget {
  const EditorDevMenu({super.key});

  static const menuKey = ValueKey('editor.more.devMenu');
  static const seedNoteKey = ValueKey('editor.devMenu.seedNote');
  static const resetKey = ValueKey('editor.devMenu.resetDiagnostics');
  static ValueKey<String> strokesKey(int count) =>
      ValueKey('editor.devMenu.strokes.$count');

  /// (v2) Appendix C keys.
  static const textBoxProbeKey = ValueKey('editor.dev.textBoxProbe');
  static const textInputModeKey = ValueKey('editor.dev.textInputMode');
  static ValueKey<String> textInputModeItemKey(WebTextInputMode mode) =>
      ValueKey('editor.dev.textInputMode.${mode.name}');

  /// The synthetic stroke counts offered.
  static const List<int> strokeCounts = [1000, 3000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The submenu is gone when MenuItemButton runs onPressed (after the
    // menu closes): everything the items need is taken here.
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final store = ref.watch(core.noteStoreProvider);
    final diagnostics = ref.watch(ink.inkDiagnosticsProvider);
    final metrics = ref.watch(editorDevMetricsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final viewport = ref.watch(editorViewportProvider);
    final textEdit = ref.read(editorTextEditProvider.notifier);
    final ids = ref.watch(core.idGeneratorProvider);
    final clock = ref.watch(core.clockProvider);
    final webTextInput = ref.watch(
      editorDeviceStateProvider.select((s) => s.webTextInput),
    );
    final device = ref.read(editorDeviceStateProvider.notifier);
    return SubmenuButton(
      key: menuKey,
      menuChildren: [
        MenuItemButton(
          key: textBoxProbeKey,
          onPressed: readOnly
              ? null
              : () => startTextBoxProbe(
                  viewport: viewport,
                  notifier: textEdit,
                  newId: ids.newId,
                  now: clock.now().millisecondsSinceEpoch,
                ),
          child: const Text(EditorStrings.devTextBoxProbe),
        ),
        if (TextEditNotifier.isWeb)
          SubmenuButton(
            key: textInputModeKey,
            menuChildren: [
              for (final mode in WebTextInputMode.values)
                RadioMenuButton<WebTextInputMode>(
                  key: textInputModeItemKey(mode),
                  value: mode,
                  groupValue: webTextInput,
                  // textarea (fallback B) is built only if B-2 fails both
                  // inline and sheet (E2-11, P-C).
                  onChanged: mode == WebTextInputMode.textarea
                      ? null
                      : (m) => device.setWebTextInput(m ?? mode),
                  child: Text(mode.name),
                ),
            ],
            child: const Text(EditorStrings.devTextInputMode),
          ),
        MenuItemButton(
          key: seedNoteKey,
          onPressed: () => unawaited(seedPerfNote(store, messenger)),
          child: const Text(EditorStrings.seedSyntheticNote),
        ),
        for (final count in strokeCounts)
          MenuItemButton(
            key: strokesKey(count),
            onPressed: readOnly
                ? null
                : () => unawaited(commands.addSyntheticStrokes(count)),
            child: Text(EditorStrings.syntheticStrokes(count)),
          ),
        MenuItemButton(
          key: resetKey,
          onPressed: () {
            diagnostics.reset();
            metrics.reset();
          },
          child: const Text(EditorStrings.resetDiagnostics),
        ),
      ],
      child: const Text(EditorStrings.devMenu),
    );
  }
}

/// seedSyntheticNote(store, title: 'perf-test', pages: 50, strokesPerPage:
/// 300) → "합성 노트를 만들었어요 …"; a failure is reported and shows
/// '실행하지 못했어요'.
Future<void> seedPerfNote(
  core.NoteStore store,
  ScaffoldMessengerState? messenger,
) async {
  var message = EditorStrings.seedSyntheticNoteDone;
  try {
    await dev.seedSyntheticNote(
      store,
      title: 'perf-test',
      pages: 50,
      strokesPerPage: 300,
    );
  } on Object catch (error, stack) {
    message = EditorStrings.commandFailed;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'feature_editor',
        context: ErrorDescription('while seeding a synthetic note'),
      ),
    );
  }
  if (messenger != null && messenger.mounted) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
