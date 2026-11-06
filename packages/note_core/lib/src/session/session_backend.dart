// Internal: storage side of a SessionEngine (CORE 6.14). The DB store (CORE T10) and the
// fake store (createFakeNoteStore) implement it, so both run the same engine.
import '../common/ids.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/stroke.dart';
import '../model/sync_entity.dart';
import '../sync/outbox_types.dart';
import 'page_content.dart';

/// One session commit: entity writes of an edit / undo / redo plus local-only values.
final class SessionWrite {
  const SessionWrite({
    required this.origin,
    required this.entities,
    required this.changedFields,
    required this.localPages,
    required this.note,
  });

  /// local, undo or redo.
  final ChangeOrigin origin;

  /// Written strokes, (v2.0) page objects and pages (after values; pages carry the local
  /// contentRevision).
  final List<SyncEntity> entities;

  /// JSON keys written per entity (outbox, 6.5 / 6.7.6).
  final Map<EntityRef, Set<String>> changedFields;

  /// Pages whose only change is local (contentRevision bump, never in the outbox).
  final List<Page> localPages;

  /// The session's note: updatedAt / pageCount / firstPageId are local derived values.
  final Note note;
}

abstract interface class SessionBackend {
  /// Active strokes and (v2.0) page objects of [pageId] after every queued write is committed
  /// (6.14 openPage; m5-7/02-core 6.5 — one read).
  Future<({List<Stroke> strokes, List<PageObject> objects})> loadContent(
    PageId pageId,
  );

  /// (v2.0) false while the store has no page object rows (the real store before DB v2,
  /// m5-7/02-core 8.1): the engine rejects object writes before changing memory.
  bool get storesPageObjects;

  /// Completes after the commit (pending while a failed commit is retried, 4.5 head).
  Future<void> write(SessionWrite write);

  Future<void> flush();

  /// The last reference of the session was released.
  void sessionClosed(NoteId noteId);
}
