// lib/src/sync/outbox_types.dart — contract 00-overview 7.2.10 / CORE 4.6, 6.10.1.
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/sync_entity.dart';

const SetEquality<String> _setEq = SetEquality<String>();

enum OutboxOp { upsert, purge }

const String kAllFields = '*';

// EntityRef: value equality (==, hashCode) — SYNC uses it as a map key.
final class EntityRef {
  const EntityRef(this.kind, this.id);
  final EntityKind kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is EntityRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'EntityRef(${kind.name}, $id)';
}

/// CORE 4.6. noteId is ALWAYS set for page / stroke / recording; pageId ALWAYS for stroke.
@immutable
final class OutboxEntry {
  const OutboxEntry({
    required this.seq,
    required this.rev,
    required this.kind,
    required this.entityId,
    this.noteId,
    this.pageId,
    required this.op,
    required this.changedFields,
    required this.hlc,
    required this.enqueuedAt,
  });

  final int seq; // creation order of the first pending change (kept on merge)
  final int rev; // bumped when merged with a newer change
  final EntityKind kind;
  final String entityId;
  final NoteId? noteId; // routing hint (always for page / stroke / recording)
  final PageId? pageId; // routing hint (always for stroke)
  final OutboxOp op;
  final Set<String> changedFields; // JSON keys of the entity (6.3); {'*'} = all
  final Hlc hlc; // version of the latest merged change
  final EpochMillis enqueuedAt;

  OutboxAck get ack => OutboxAck(seq, rev);
  EntityRef get ref => EntityRef(kind, entityId);

  @override
  bool operator ==(Object other) =>
      other is OutboxEntry &&
      other.seq == seq &&
      other.rev == rev &&
      other.kind == kind &&
      other.entityId == entityId &&
      other.noteId == noteId &&
      other.pageId == pageId &&
      other.op == op &&
      _setEq.equals(other.changedFields, changedFields) &&
      other.hlc == hlc &&
      other.enqueuedAt == enqueuedAt;

  @override
  int get hashCode => Object.hash(
    seq,
    rev,
    kind,
    entityId,
    noteId,
    pageId,
    op,
    _setEq.hash(changedFields),
    hlc,
    enqueuedAt,
  );

  @override
  String toString() =>
      'OutboxEntry(#$seq r$rev ${kind.name} $entityId ${op.name} $changedFields)';
}

final class OutboxAck {
  const OutboxAck(this.seq, this.rev, {this.uploadedTextVersion});
  final int seq, rev;

  /// (v2.17-md, C217M-07) markdown records only: the `text` field version of the uploaded
  /// record — the store's base_text_version (08-markdown 5.3 (3)). The outbox entry's hlc
  /// cannot tell it: entries merge while an upload runs.
  final Hlc? uploadedTextVersion;

  @override
  bool operator ==(Object other) =>
      other is OutboxAck &&
      other.seq == seq &&
      other.rev == rev &&
      other.uploadedTextVersion == uploadedTextVersion;

  @override
  int get hashCode => Object.hash(seq, rev, uploadedTextVersion);

  @override
  String toString() =>
      'OutboxAck($seq, $rev'
      '${uploadedTextVersion == null ? '' : ', text: $uploadedTextVersion'})';
}
