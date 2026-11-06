// lib/src/ui/recording_list.dart — the recordings list of the panel (m5-7/06-pdf 6.13.1, PDF
// T36b). Internal.
//
// Newest first; the name is the title or '녹음 N' by startedAt order (7.2.4), a '복구됨' badge
// when the title is MediaTuning.recoveredTitle (6.10.1 — Q4 '제목 비교'), date · length · size
// (Asset.size — also without local bytes), the WebM warning (the iPad app may not play it) and
// the total (audioBytesOf). A tap opens the recording (open only — PDF-M8); [⋯] opens the
// rename / delete sheet.
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../providers.dart';
import 'format.dart';
import 'strings_ko.dart';

/// '20.6 MB', '512 KB', '900 B' — decimal units, one decimal from MB on.
String formatBytes(int bytes) {
  if (bytes < 1000) return '${bytes < 0 ? 0 : bytes} B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
  if (bytes < 1000 * 1000 * 1000) {
    return '${(bytes / (1000 * 1000)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB';
}

/// '11월 5일 14:02 · 45:00 · 20.6 MB' (local time).
String recordingSubtitle(RecordingListRow row) => [
  MediaStringsKo.dateTime(
    DateTime.fromMillisecondsSinceEpoch(row.recording.startedAt),
  ),
  formatClock(row.recording.durationMs),
  formatBytes(row.sizeBytes),
].join(' · ');

bool isWebmRow(RecordingListRow row) =>
    (row.mimeType ?? '').toLowerCase().contains('webm');

class RecordingList extends StatelessWidget {
  const RecordingList({
    super.key,
    required this.rows,
    required this.totalBytes,
    required this.openId,
    required this.canOpen,
    required this.onOpen,
    required this.onActions,
  });

  final List<RecordingListRow> rows;
  final int totalBytes;
  final core.RecordingId? openId;

  /// false while the recorder is active (the playback row is disabled then too).
  final bool canOpen;
  final ValueChanged<core.Recording> onOpen;
  final ValueChanged<RecordingListRow> onActions;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final open = row.recording.id == openId;
              return ListTile(
                key: ValueKey('recording-${row.recording.id}'),
                dense: true,
                minTileHeight: 48,
                contentPadding: const EdgeInsetsDirectional.only(start: 4),
                selected: open,
                leading: SizedBox(
                  width: 24,
                  child: open
                      ? const Icon(Icons.play_arrow, size: 20)
                      : const SizedBox.shrink(),
                ),
                horizontalTitleGap: 4,
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.recovered) ...[
                      const SizedBox(width: 8),
                      _Badge(text: MediaStringsKo.recoveredBadge),
                    ],
                  ],
                ),
                subtitle: Text(
                  isWebmRow(row)
                      ? '${recordingSubtitle(row)}\n${MediaStringsKo.webmWarning}'
                      : recordingSubtitle(row),
                  maxLines: isWebmRow(row) ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: canOpen && !open ? () => onOpen(row.recording) : null,
                trailing: IconButton(
                  tooltip: MediaStringsKo.recordingActions,
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => onActions(row),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 4,
            top: 2,
            bottom: 2,
          ),
          child: Text(
            MediaStringsKo.listTotal(rows.length, formatBytes(totalBytes)),
            style: muted,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
