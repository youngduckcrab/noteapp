// lib/src/ui/toolbar/mic_button.dart — m5-7/04-editor 6.13.1 [🎤], 6.15.4
// (E2-16 puts it in front of the 1st-round undo button; E2-13 only moves it
// to the toolbar v2 layout).
//
// Shown only when EditorExtensions.recordingPanel is set (the toolbar checks).
// Tap → opens / closes the bottom panel slot (editorPanelProvider). While this
// note records (recording or paused) the icon is `mic` with a red dot — also
// with the panel closed; while another note records, a grey dot and the
// tooltip '다른 노트에서 녹음 중이에요'.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../scope/editor_scope.dart';
import '../../state/panel.dart';
import '../editor_strings.dart';
import 'tool_glyph.dart';

class MicButton extends ConsumerWidget {
  const MicButton({super.key = micKey});

  static const micKey = ValueKey('editor.toolbar.mic');

  /// The dot while this note records.
  static const recordingDotKey = ValueKey('editor.toolbar.mic.recording');

  /// The dot while another note records.
  static const otherNoteDotKey = ValueKey('editor.toolbar.mic.otherNote');

  /// The red of the recording dot.
  static const recordingDotColor = Color(0xFFE53935);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final noteId = ref.watch(editorNoteIdProvider);
    final open = ref.watch(editorPanelProvider);
    final indicator = micIndicatorOf(
      ref.watch(editorRecorderStatusProvider).value,
      noteId,
    );
    final scheme = Theme.of(context).colorScheme;
    final dot = switch (indicator) {
      MicIndicator.none => null,
      MicIndicator.thisNote => const _Dot(
        key: recordingDotKey,
        color: recordingDotColor,
      ),
      MicIndicator.otherNote => _Dot(
        key: otherNoteDotKey,
        color: scheme.outline,
      ),
    };
    final button = IconButton(
      isSelected: open,
      onPressed: ref.read(editorPanelProvider.notifier).toggle,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          ToolGlyph(
            indicator == MicIndicator.thisNote
                ? AppIconKind.micOn
                : AppIconKind.mic,
            semanticLabel: EditorStrings.recording,
          ),
          if (dot != null) Positioned(right: -2, top: -2, child: dot),
        ],
      ),
    );
    if (indicator != MicIndicator.otherNote) {
      return HoverName(name: EditorStrings.recording, child: button);
    }
    // A state, not a name: also on a long press (HoverNames makes plain
    // tooltips hover-only).
    return Tooltip(
      message: EditorStrings.recordingInOtherNote,
      triggerMode: TooltipTriggerMode.longPress,
      child: button,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: const SizedBox(width: 8, height: 8),
  );
}
