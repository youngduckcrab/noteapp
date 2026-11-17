// One-shot events for snackbars (INFRA, M4).
import 'package:note_core/note_core.dart';

sealed class SyncNotice {
  const SyncNotice({required this.at});
  final EpochMillis at;
}

final class FolderCycleResolved extends SyncNotice {
  const FolderCycleResolved({
    required super.at,
    required this.folderId,
    required this.cycle,
  });

  /// Moved to top level.
  final FolderId folderId;
  final List<FolderId> cycle;
}

final class PageRestored extends SyncNotice {
  const PageRestored({required super.at, required this.pageId, this.noteId});
  final PageId pageId;
  final NoteId? noteId;
}

final class NoteRecoveredFromPurge extends SyncNotice {
  const NoteRecoveredFromPurge({
    required super.at,
    required this.purgedNoteId,
    required this.copyNoteId,
  });
  final NoteId purgedNoteId;
  final NoteId copyNoteId;
}

/// (v2.17-md, C217M-07) A received MD 문서 text and an unsent local one differed: the
/// losing text was kept as the MD 문서 [copyNoteId] ('다른 기기에서 고친 글을 사본으로
/// 남겼어요' — 08-markdown 5.3).
final class MarkdownConflictCopied extends SyncNotice {
  const MarkdownConflictCopied({
    required super.at,
    required this.noteId,
    required this.copyNoteId,
  });
  final NoteId noteId;
  final NoteId copyNoteId;
}

final class InitialSyncCompleted extends SyncNotice {
  const InitialSyncCompleted({
    required super.at,
    required this.records,
    required this.took,
  });
  final int records;
  final Duration took;
}
