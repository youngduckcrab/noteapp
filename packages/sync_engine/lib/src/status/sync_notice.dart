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

final class InitialSyncCompleted extends SyncNotice {
  const InitialSyncCompleted({
    required super.at,
    required this.records,
    required this.took,
  });
  final int records;
  final Duration took;
}
