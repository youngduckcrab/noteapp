// lib/src/storage/outbox_writer.dart (internal) — CORE 6.10.1 outbox records and merge.
import 'dart:convert';

import 'package:drift/drift.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../model/sync_entity.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';

/// Meta keys are never changed fields (SYNC 6.3.1: not LWW units, 6.3).
const Set<String> kMetaFields = {
  'id',
  'key',
  'version',
  'createdAt',
  'updatedAt',
};

/// Local-only and derived values (never in the outbox, 6.10.1).
const Map<EntityKind, Set<String>> kLocalOnlyFields = {
  EntityKind.note: {'pageCount', 'firstPageId', 'lastOpenedAt'},
  EntityKind.page: {'contentRevision'},
  EntityKind.stroke: {'bounds'},
  EntityKind.asset: {'hasLocalBytes'},
  // (v2.17-md, 08-markdown 4.3) md_docs columns, never entity JSON keys — listed so a
  // future toJson can never leak them.
  EntityKind.markdown: {'textBytes', 'baseTextVersion'},
};

/// The synced JSON keys of [fields]: `{*}` when it holds `*`, otherwise without the
/// meta keys and the local-only fields of [kind].
Set<String> syncedFieldsOf(EntityKind kind, Iterable<String> fields) {
  final set = fields.toSet();
  if (set.contains(kAllFields)) return const {kAllFields};
  final local = kLocalOnlyFields[kind] ?? const <String>{};
  return {
    for (final f in set)
      if (!kMetaFields.contains(f) && !local.contains(f)) f,
  };
}

String _fieldsText(Set<String> fields) => jsonEncode(fields.toList()..sort());

Set<String> _fieldsOf(String text) =>
    (jsonDecode(text) as List<Object?>).cast<String>().toSet();

/// Records one change of an entity. A pending entry of the same entity is merged:
/// seq kept, rev + 1, fields united (`*` absorbs), hlc = the new one, purge wins,
/// hints filled when given (6.10.1).
Future<void> recordOutbox(
  NoteDatabase db, {
  required EntityKind kind,
  required String id,
  NoteId? noteId,
  PageId? pageId,
  required OutboxOp op,
  required Set<String> fields,
  required Hlc hlc,
  required EpochMillis now,
}) async {
  final current =
      await (db.select(db.outbox)..where(
            (t) => t.entityKind.equals(kind.name) & t.entityId.equals(id),
          ))
          .getSingleOrNull();
  if (current == null) {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            rev: 1,
            entityKind: kind.name,
            entityId: id,
            noteId: Value(noteId),
            pageId: Value(pageId),
            op: op.name,
            changedFields: _fieldsText(
              op == OutboxOp.purge ? const {kAllFields} : fields,
            ),
            hlc: hlc.toString(),
            enqueuedAt: now,
          ),
        );
    return;
  }
  final purge = op == OutboxOp.purge || current.op == OutboxOp.purge.name;
  final before = _fieldsOf(current.changedFields);
  final merged =
      purge || before.contains(kAllFields) || fields.contains(kAllFields)
      ? const {kAllFields}
      : {...before, ...fields};
  await (db.update(db.outbox)..where((t) => t.seq.equals(current.seq))).write(
    OutboxCompanion(
      rev: Value(current.rev + 1),
      noteId: Value(noteId ?? current.noteId),
      pageId: Value(pageId ?? current.pageId),
      op: Value(purge ? OutboxOp.purge.name : OutboxOp.upsert.name),
      changedFields: Value(_fieldsText(merged)),
      hlc: Value(hlc.toString()),
    ),
  );
}

OutboxEntry outboxEntryOf(OutboxRow r) => OutboxEntry(
  seq: r.seq,
  rev: r.rev,
  kind: EntityKind.values.byName(r.entityKind),
  entityId: r.entityId,
  noteId: r.noteId,
  pageId: r.pageId,
  op: OutboxOp.values.byName(r.op),
  changedFields: Set.unmodifiable(_fieldsOf(r.changedFields)),
  hlc: Hlc.parse(r.hlc),
  enqueuedAt: r.enqueuedAt,
);

/// Pending entries with seq > [afterSeq] (all when null), in seq order.
Future<List<OutboxEntry>> readOutbox(
  NoteDatabase db, {
  int limit = 500,
  int? afterSeq,
}) async {
  final q = db.select(db.outbox)
    ..orderBy([(t) => OrderingTerm.asc(t.seq)])
    ..limit(limit);
  if (afterSeq != null) q.where((t) => t.seq.isBiggerThanValue(afterSeq));
  return [for (final r in await q.get()) outboxEntryOf(r)];
}

/// The pending outbox row of ([kind], [id]); null if none.
Future<OutboxRow?> outboxRowOf(NoteDatabase db, EntityKind kind, String id) =>
    (db.select(
          db.outbox,
        )..where((t) => t.entityKind.equals(kind.name) & t.entityId.equals(id)))
        .getSingleOrNull();

/// The changed fields stored in an outbox row.
Set<String> outboxFieldsOf(OutboxRow row) => _fieldsOf(row.changedFields);

/// Deletes the pending entry of ([kind], [id]); returns whether there was one.
Future<bool> deleteOutboxEntry(
  NoteDatabase db,
  EntityKind kind,
  String id,
) async =>
    await (db.delete(
          db.outbox,
        )..where((t) => t.entityKind.equals(kind.name) & t.entityId.equals(id)))
        .go() >
    0;

/// WriteMerged.fieldsToUpload (6.10.3): the entry's fields become EXACTLY [fields] —
/// empty deletes it; no entry and non-empty adds one (new seq); an existing entry
/// (upsert or purge) becomes an upsert of [fields], seq kept, rev + 1, hlc = [hlc].
Future<void> setOutboxFields(
  NoteDatabase db, {
  required OutboxRow? current,
  required EntityKind kind,
  required String id,
  NoteId? noteId,
  PageId? pageId,
  required Set<String> fields,
  required Hlc hlc,
  required EpochMillis now,
}) async {
  if (fields.isEmpty) {
    if (current != null) {
      await (db.delete(
        db.outbox,
      )..where((t) => t.seq.equals(current.seq))).go();
    }
    return;
  }
  if (current == null) {
    await db
        .into(db.outbox)
        .insert(
          OutboxCompanion.insert(
            rev: 1,
            entityKind: kind.name,
            entityId: id,
            noteId: Value(noteId),
            pageId: Value(pageId),
            op: OutboxOp.upsert.name,
            changedFields: _fieldsText(fields),
            hlc: hlc.toString(),
            enqueuedAt: now,
          ),
        );
    return;
  }
  await (db.update(db.outbox)..where((t) => t.seq.equals(current.seq))).write(
    OutboxCompanion(
      rev: Value(current.rev + 1),
      noteId: Value(noteId ?? current.noteId),
      pageId: Value(pageId ?? current.pageId),
      op: Value(OutboxOp.upsert.name),
      changedFields: Value(_fieldsText(fields)),
      hlc: Value(hlc.toString()),
    ),
  );
}
