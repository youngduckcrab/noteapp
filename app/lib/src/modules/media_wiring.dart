/// media_io → editor slots (docs/plans/m5-7/01-infra.md 4.6.5, 6.5.2, 6.7;
/// contract 7.3.3 rows of MediaModule and FeatureWiringModule).
library;

import 'package:feature_editor/feature_editor.dart'
    show DevOverlaySection, EditorImageImporter, EditorPanelContext;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:media_io/media_io.dart'
    show
        RecordingPanel,
        importImageForNote,
        mediaDevOverlayLinesProvider,
        supportedImageSources;
import 'package:note_core/note_core.dart' as core;

import '../errors/app_error_log.dart';

/// (ctx, panel) => RecordingPanel(noteId: panel.noteId, tapToSeek:
/// panel.tapToSeek, onTapToSeekChanged: panel.setTapToSeek, onClose:
/// panel.close)
Widget mediaRecordingPanel(BuildContext context, EditorPanelContext panel) =>
    RecordingPanel(
      noteId: panel.noteId,
      tapToSeek: panel.tapToSeek,
      onTapToSeekChanged: panel.setTapToSeek,
      onClose: panel.close,
    );

/// (v2.1, D2-15) sources = supportedImageSources(); empty → null (E-7 hides
/// image insert / image page); else EditorImageImporter(sources: sources,
/// pick: importImageForNote). FeatureWiringModule's default — not gated by
/// FEATURE_MEDIA, not tied to MediaModule's start.
EditorImageImporter? mediaImageImporterOrNull() {
  final sources = supportedImageSources();
  if (sources.isEmpty) return null;
  return EditorImageImporter(
    sources: Set.unmodifiable(sources),
    pick: importImageForNote,
  );
}

/// DevOverlaySection(id: 'media', title: '녹음', lines:
/// ref.watch(mediaDevOverlayLinesProvider))
DevOverlaySection mediaDevOverlaySection(Ref ref) => DevOverlaySection(
  id: 'media',
  title: '녹음',
  lines: ref.watch(mediaDevOverlayLinesProvider),
);

/// pendingDrafts() → recoverDraft() one by one, oldest first (6.5.2).
/// Returns the number recovered. Never asks (contract 7.2.12): which drafts
/// to recover is pendingDrafts()' decision alone — status.isActive is not
/// read. A failing draft is logged (source module) and the next one runs.
Future<int> recoverPendingRecordings(
  core.AudioRecorderService recorder,
  AppErrorLog errorLog,
) async {
  final drafts = [...await recorder.pendingDrafts()]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  var recovered = 0;
  for (final draft in drafts) {
    try {
      if (await recorder.recoverDraft(draft.draftId) != null) recovered++;
    } on Object catch (error, stackTrace) {
      final record = AppErrorRecord.fromError(
        error,
        stackTrace,
        source: AppErrorSource.module,
      );
      errorLog.add(
        AppErrorRecord(
          time: record.time,
          source: record.source,
          summary: 'recoverDraft ${draft.draftId} failed: ${record.summary}',
          stackTrace: record.stackTrace,
        ),
      );
    }
  }
  return recovered;
}
