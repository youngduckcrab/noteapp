// lib/src/ui/stuck_drafts_row.dart — the '복구하지 못한 녹음이 있어요' line (m5-7/06-pdf 6.10.3,
// 6.13.2 last row; PDF T36b). Internal. One line per draft of this note at recoverMaxAttempts:
// [다시 시도] (attempts back to 0 → pendingDrafts → recoverDraft once) and [⋯] (web: 파일로
// 내려받기 · 지우기).
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import 'strings_ko.dart';

class StuckDraftRow extends StatelessWidget {
  const StuckDraftRow({
    super.key,
    required this.draft,
    required this.busy,
    required this.onRetry,
    required this.onMenu,
  });

  final core.RecordingDraft draft;
  final bool busy;
  final VoidCallback onRetry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: ValueKey('stuck-${draft.draftId}'),
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            MediaStringsKo.stuckDrafts,
            style: theme.textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: busy ? null : onRetry,
          child: const Text(MediaStringsKo.retry),
        ),
        IconButton(
          tooltip: MediaStringsKo.draftActions,
          icon: const Icon(Icons.more_horiz),
          onPressed: busy ? null : onMenu,
        ),
      ],
    );
  }
}
