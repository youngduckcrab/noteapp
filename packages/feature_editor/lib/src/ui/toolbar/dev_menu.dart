// lib/src/ui/toolbar/dev_menu.dart — 04-editor 6.12.4 (EDITOR-S1): the more
// menu's '개발자 메뉴', shown while the developer overlay is visible.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/dev_tools.dart' as dev;
import 'package:note_core/note_core.dart' as core;

import '../../scope/editor_scope.dart';
import '../dev/dev_metrics.dart';
import '../editor_strings.dart';

/// 합성 노트 만들기 (core seedSyntheticNote: 'perf-test', 50 pages × 300
/// strokes → snack bar) · 현재 페이지에 합성 획 1,000개 / 3,000개
/// (EditorCommands.addSyntheticStrokes — one undo step, disabled on a
/// read-only note) · 진단 초기화 (InkDiagnostics.reset + DevMetrics.reset).
/// Only dev_tools libraries (web safe), never testing.dart.
class EditorDevMenu extends ConsumerWidget {
  const EditorDevMenu({super.key});

  static const menuKey = ValueKey('editor.more.devMenu');
  static const seedNoteKey = ValueKey('editor.devMenu.seedNote');
  static const resetKey = ValueKey('editor.devMenu.resetDiagnostics');
  static ValueKey<String> strokesKey(int count) =>
      ValueKey('editor.devMenu.strokes.$count');

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
    return SubmenuButton(
      key: menuKey,
      menuChildren: [
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
