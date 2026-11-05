// lib/src/ui/eraser/eraser_popup.dart — 04-editor 6.6.4 #5, 6.9.
//
// E-09: clearing the current page (confirmation dialog → EditorCommands).
// E-15: the eraser popup panel (mode, size, filter, return to the previous
// tool); its "현재 페이지 지우기" button and the more menu item (E-13) both
// call [confirmClearCurrentPage].
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../commands/editor_commands.dart';
import '../../scope/editor_scope.dart';
import '../../state/popup.dart';
import '../../tools/tool_controller.dart';
import '../../tools/tool_state.dart';
import '../editor_strings.dart';
import '../popup_host.dart';

/// The confirmation title for the eraser [filter] (6.6.4 #5).
String clearPageTitleFor(core.StrokeFilter filter) => switch (filter) {
  core.StrokeFilter.all => EditorStrings.clearPageTitle,
  core.StrokeFilter.highlighterOnly =>
    EditorStrings.clearPageTitleHighlighterOnly,
  core.StrokeFilter.exceptHighlighter =>
    EditorStrings.clearPageTitleExceptHighlighter,
};

/// Asks "이 페이지의 필기를 모두 지울까요?" (worded by [filter]) and, when the
/// user confirms, runs [EditorCommands.clearCurrentPage] — one
/// core.ClearPage(current page, eraser filter) step through _runAsync. INK
/// clearPage is not used (contract 7.2.15). Returns true when the user
/// confirmed.
Future<bool> confirmClearCurrentPage(
  BuildContext context, {
  required EditorCommands commands,
  required core.StrokeFilter filter,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ClearPageDialog(filter: filter),
  );
  if (confirmed != true) return false;
  await commands.clearCurrentPage();
  return true;
}

/// The confirmation dialog of [confirmClearCurrentPage]: pops true on
/// [EditorStrings.clearPageConfirm], false on [EditorStrings.cancel].
class ClearPageDialog extends StatelessWidget {
  const ClearPageDialog({super.key, required this.filter});

  final core.StrokeFilter filter;

  /// Key of the confirm button.
  static const confirmKey = ValueKey('editor.clearPage.confirm');

  /// Key of the cancel button.
  static const cancelKey = ValueKey('editor.clearPage.cancel');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(clearPageTitleFor(filter)),
      content: const Text(EditorStrings.clearPageBody),
      actions: [
        TextButton(
          key: cancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(EditorStrings.cancel),
        ),
        FilledButton(
          key: confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(EditorStrings.clearPageConfirm),
        ),
      ],
    );
  }
}

/// Eraser diameter slider: diameter = 1 + 99 · t² (fine control at small
/// sizes), snapped to 0.5 pt (EraserSettings.snapDiameter).
abstract final class EraserSizeMapping {
  static double diameterAt(double t) {
    final tc = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    return EraserSettings.snapDiameter(
      EraserSettings.minDiameter +
          (EraserSettings.maxDiameter - EraserSettings.minDiameter) * tc * tc,
    );
  }

  static double positionOf(double diameter) {
    final d = diameter.clamp(
      EraserSettings.minDiameter,
      EraserSettings.maxDiameter,
    );
    return math
        .sqrt(
          (d - EraserSettings.minDiameter) /
              (EraserSettings.maxDiameter - EraserSettings.minDiameter),
        )
        .clamp(0.0, 1.0);
  }
}

/// Eraser settings popup panel (6.9.3 end, 300 wide): SegmentedButton[획 |
/// 부분] (ink.EraserMode) · size slider + circle preview (diameter × zoom,
/// at most [maxPreviewPx]) · SegmentedButton[전체 | 형광펜만 | 형광펜 제외]
/// (core.StrokeFilter) · "지운 뒤 이전 도구로 돌아가기" · '현재 페이지 지우기' in
/// the error colour (disabled on a read-only note).
class EraserSettingsPanel extends ConsumerWidget {
  const EraserSettingsPanel({super.key});

  static const panelKey = ValueKey('editor.popup.eraserSettings');
  static const clearPageKey = ValueKey('editor.popup.eraser.clearPage');
  static const modeKey = ValueKey('editor.popup.eraser.mode');
  static const sizeKey = ValueKey('editor.popup.eraser.size');
  static const previewKey = ValueKey('editor.popup.eraser.preview');
  static const filterKey = ValueKey('editor.popup.eraser.filter');
  static const returnKey = ValueKey('editor.popup.eraser.return');

  static ValueKey<String> modeSegmentKey(ink.EraserMode mode) =>
      ValueKey('editor.popup.eraser.mode.${mode.name}');
  static ValueKey<String> filterSegmentKey(core.StrokeFilter filter) =>
      ValueKey('editor.popup.eraser.filter.${filter.name}');

  static const double width = 300;
  static const double maxPreviewPx = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(editorReadOnlyProvider);
    final commands = ref.watch(editorCommandsProvider);
    final eraser = ref.watch(editorToolProvider.select((s) => s.eraser));
    final viewport = ref.watch(editorViewportProvider);
    final tools = ref.read(editorToolProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupPanelFrame(
      key: panelKey,
      width: width,
      title: EditorStrings.eraserSettings,
      children: [
        SegmentedButton<ink.EraserMode>(
          key: modeKey,
          segments: [
            ButtonSegment(
              value: ink.EraserMode.stroke,
              label: Text(
                EditorStrings.eraserModeStroke,
                key: modeSegmentKey(ink.EraserMode.stroke),
              ),
            ),
            ButtonSegment(
              value: ink.EraserMode.partial,
              label: Text(
                EditorStrings.eraserModePartial,
                key: modeSegmentKey(ink.EraserMode.partial),
              ),
            ),
          ],
          selected: {eraser.mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              tools.updateEraser((e) => e.copyWith(mode: s.first)),
        ),
        const SizedBox(height: 12),
        Text(
          EditorStrings.eraserSizeLabel(eraser.diameter),
          style: theme.textTheme.labelLarge,
        ),
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: EditorStrings.eraserSize,
                child: Slider(
                  key: sizeKey,
                  value: EraserSizeMapping.positionOf(eraser.diameter),
                  onChanged: (t) => tools.updateEraser(
                    (e) =>
                        e.copyWith(diameter: EraserSizeMapping.diameterAt(t)),
                  ),
                ),
              ),
            ),
            SizedBox.square(
              dimension: maxPreviewPx,
              child: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: viewport.settledScale,
                  builder: (context, scale, _) {
                    final d = math.min(eraser.diameter * scale, maxPreviewPx);
                    return Container(
                      key: previewKey,
                      width: d,
                      height: d,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<core.StrokeFilter>(
          key: filterKey,
          segments: [
            for (final (filter, label) in const [
              (core.StrokeFilter.all, EditorStrings.filterAll),
              (
                core.StrokeFilter.highlighterOnly,
                EditorStrings.filterHighlighterOnly,
              ),
              (
                core.StrokeFilter.exceptHighlighter,
                EditorStrings.filterExceptHighlighter,
              ),
            ])
              ButtonSegment(
                value: filter,
                label: Text(label, key: filterSegmentKey(filter)),
              ),
          ],
          selected: {eraser.filter},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              tools.updateEraser((e) => e.copyWith(filter: s.first)),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          key: returnKey,
          contentPadding: EdgeInsets.zero,
          title: const Text(EditorStrings.returnToPreviousTool),
          value: eraser.returnToPreviousTool,
          onChanged: (v) =>
              tools.updateEraser((e) => e.copyWith(returnToPreviousTool: v)),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: clearPageKey,
          style: TextButton.styleFrom(foregroundColor: scheme.error),
          onPressed: readOnly
              ? null
              : () {
                  final filter = ref.read(editorToolProvider).eraser.filter;
                  ref.read(editorPopupProvider.notifier).close();
                  unawaited(
                    confirmClearCurrentPage(
                      context,
                      commands: commands,
                      filter: filter,
                    ),
                  );
                },
          child: const Text(EditorStrings.clearPage),
        ),
      ],
    );
  }
}
