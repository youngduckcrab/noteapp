// lib/src/ui/recording_panel.dart — RecordingPanel (contract 7.2.12, m5-7/06-pdf 4.2.5, 6.13).
//
// 2차 foundation step R2-B4 (T30, contract 7.6.2): a placeholder — the title '녹음' and a
// close button that calls onClose. It reads no provider yet. PDF T33–T35 build the panel of
// 6.13 (recording / playback rows, recordings list, sheets).
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'strings_ko.dart';

/// Recording + playback panel for EditorExtensions.recordingPanel (INFRA adapts EditorPanelContext).
/// Record / pause / stop, recordings list (rename, delete, size), play / pause, ±10 s, speed
/// 0.5–2.0, scrubber, tap-to-seek toggle, consent notice on first record (F-16), web hidden-tab notice,
/// '복구된 녹음' badge on recordings made by recoverDraft().
class RecordingPanel extends ConsumerWidget {
  const RecordingPanel({
    super.key,
    required this.noteId,
    required this.tapToSeek,
    required this.onTapToSeekChanged,
    required this.onClose,
  });
  final String noteId;
  final ValueListenable<bool> tapToSeek;
  final ValueChanged<bool> onTapToSeekChanged;
  final VoidCallback onClose;

  /// R2-B4: the title and the close button only.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  MediaStringsKo.panelTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: MediaStringsKo.close,
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
