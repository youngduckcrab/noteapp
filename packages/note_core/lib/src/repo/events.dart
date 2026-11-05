// lib/src/repo/events.dart — contract 00-overview 7.2.10 / 7.2.12, CORE 4.8.1.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/ids.dart';
import '../model/sync_entity.dart';
import '../session/page_content.dart';

/// CORE 4.8. (v1.1) Same hints as OutboxEntry: noteId ALWAYS set for page / stroke /
/// recording (for kind == note use id), pageId ALWAYS for stroke.
/// (v1.2) A remote orphan stroke (its page row not here yet) is listed in the batch of the
/// commit that brings its page row (applyRemote, or commitRepairs creating the row), with
/// noteId / pageId — not in the batch of its own commit.
@immutable
final class EntityChange {
  const EntityChange({
    required this.kind,
    required this.id,
    this.noteId,
    this.pageId,
    this.deleted = false,
    this.purged = false,
  });

  final EntityKind kind;
  final String id;
  // always for page / stroke / recording (local AND remote)
  final NoteId? noteId;
  final PageId? pageId; // always for stroke
  final bool deleted, purged;

  @override
  bool operator ==(Object other) =>
      other is EntityChange &&
      other.kind == kind &&
      other.id == id &&
      other.noteId == noteId &&
      other.pageId == pageId &&
      other.deleted == deleted &&
      other.purged == purged;

  @override
  int get hashCode => Object.hash(kind, id, noteId, pageId, deleted, purged);

  @override
  String toString() =>
      'EntityChange(${kind.name} $id, note: $noteId, page: $pageId'
      '${deleted ? ', deleted' : ''}${purged ? ', purged' : ''})';
}

@immutable
final class ChangeBatch {
  // one per commit
  const ChangeBatch({
    required this.origin,
    required this.changes,
    required this.committedAt,
  });

  /// local: edits, repository commands, markUploaded, duplicateNoteForRecovery · undo / redo ·
  /// remote: applyRemote, commitRepairs, reassignOwner (7.2.10 v1.1).
  final ChangeOrigin origin;

  /// A remote orphan stroke (its page row not here yet) is listed in the batch of the commit
  /// that brings its page (applyRemote, or commitRepairs creating the row), with
  /// noteId / pageId (6.10.3, 6.10.4; 7.2.10 v1.2) — so every stroke change has hints.
  final List<EntityChange> changes;
  final EpochMillis committedAt;

  @override
  bool operator ==(Object other) =>
      other is ChangeBatch &&
      other.origin == origin &&
      other.committedAt == committedAt &&
      const ListEquality<EntityChange>().equals(other.changes, changes);

  @override
  int get hashCode => Object.hash(
    origin,
    committedAt,
    const ListEquality<EntityChange>().hash(changes),
  );

  @override
  String toString() =>
      'ChangeBatch(${origin.name}, ${changes.length} changes, at $committedAt)';
}
