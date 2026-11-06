import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../local/sync_local_store.dart';
import 'canonical_dump.dart';
import 'fake_asset_store.dart';
import 'fake_sync_store.dart';

/// In-memory SyncLocalStore. `sync` and `assets` implement the CORE contract sentences of
/// 7.2.10 / 7.2.11 (v1.1) one to one (table 5.1.4, locked by the shared SyncStore contract
/// suite that also runs on real CORE). Rows hold real CORE values (EntityJson.decode) with
/// EntityFieldVersions; HLC is note_core HlcClock(nodeId: nodeId, clock: clock).
/// v1.1 points the suite checks (C-09, C-25):
///  - policy pendingLocalFields: entry changedFields, null without entry, {kAllFields} for an
///    op-purge entry (row gone → local == null);
///  - applyRemote / commitRepairs ignore device-local values of the handed-over entity:
///    Note.lastOpenedAt kept (new row null), pageCount / firstPageId recomputed from active
///    pages, Page.contentRevision current + 1 when the page row or its strokes were written
///    (new row 0), Asset.hasLocalBytes kept (new row: whether the fake blob map has the bytes);
///  - ChangeBatch origin: localWrite / localPurge / assets.put / markUploaded /
///    duplicateNoteForRecovery fire localChanges; applyRemote / commitRepairs / reassignOwner
///    do not.
final class FakeLocalStore implements SyncLocalStore {
  FakeLocalStore({
    required String nodeId,
    required Clock clock,
    OwnerId ownerId = kLocalOwnerId,
  }) : this._(
         FakeStoreState(
           nodeId: _checkNode(nodeId),
           clock: clock,
           ownerId: ownerId,
         ),
       );

  FakeLocalStore._(this._s)
    : sync = FakeSyncStore(_s),
      assets = FakeAssetStore(_s);

  final FakeStoreState _s;

  static final RegExp _nodePattern = RegExp(r'^[0-9a-f]{16}$');

  static String _checkNode(String nodeId) {
    if (!_nodePattern.hasMatch(nodeId)) {
      throw ArgumentError.value(nodeId, 'nodeId', 'must be 16 lowercase hex');
    }
    return nodeId;
  }

  @override
  final SyncStore sync;

  @override
  final AssetStore assets;

  @override
  Stream<void> get localChanges => _s.localChanges;

  /// One local commit as CORE records it (CORE 6.5 / 6.10): one fresh HLC for the call;
  /// each write's changedFields ('*' = all) get it in the field versions; 'version' and
  /// 'updatedAt' are set; outbox entries merge (seq kept, rev++, field union, purge wins)
  /// with the noteId / pageId hints; the parent note's updatedAt is bumped without outbox
  /// (C-9); one localChanges event.
  void localWrite(List<FakeLocalWrite> writes) {
    if (writes.isEmpty) return;
    writeLog?.addAll(writes);
    _s.transaction(
      (_) => _s.localCommit([
        for (final w in writes)
          (kind: w.kind, json: w.json, fields: w.changedFields),
      ]),
    );
    _s.emitPendingCount();
    _s.emitLocalChange();
  }

  /// Trash purge as CORE does it (CORE 6.8): rows of [group] and of the group notes' pages /
  /// strokes / recordings removed, one purge entry per folder / note of the group, their
  /// pending upserts become purges; one localChanges event (origin local). A later applyRemote
  /// on such an entity follows contract 7.2.10 v1.3 (C13-02): TakeRemote deletes the purge
  /// entry whatever dropPendingLocal says; WriteMerged(F) turns it into an upsert entry of F
  /// (seq kept, rev + 1; deleted when F is empty).
  void localPurge(EntityRef ref, {required List<EntityRef> group}) {
    final members = <EntityRef>{ref, ...group};
    for (final m in members) {
      if (m.kind != EntityKind.folder && m.kind != EntityKind.note) {
        throw ArgumentError.value(
          '${m.kind.name}/${m.id}',
          'group',
          'purge groups hold folders and notes only',
        );
      }
    }
    _s.transaction((txn) {
      final h = _s.hlc.now();
      final removed = _s.removeGroup(members);
      for (final r in removed) {
        if (members.contains(r)) {
          _s.enqueue(r, op: OutboxOp.purge, fields: const {kAllFields}, hlc: h);
        } else {
          _s.removeEntry(r);
        }
      }
      _s.finish();
    });
    _s.emitPendingCount();
    _s.emitLocalChange();
  }

  /// Sets the device-local Note.lastOpenedAt like CORE markOpened (no outbox, no
  /// localChanges) — for contract check C-25.
  void markOpened(NoteId noteId) {
    final ref = EntityRef(EntityKind.note, noteId);
    final row = _s.rows[ref];
    if (row == null) {
      throw ArgumentError.value(noteId, 'noteId', 'unknown note');
    }
    _s.putRow(
      VersionedEntity(
        (row.entity as Note).copyWith(lastOpenedAt: _s.millis),
        row.versions,
      ),
    );
  }

  /// The next [count] writes through sync / assets throw StateError (localStoreFailure tests).
  /// This models an error thrown without retry; real CORE keeps a failing commit pending
  /// while its write queue retries (5.1.2 S-20), which the fake does not model.
  void failNextWrites(int count) => _s.failNextWrites(count);

  Map<EntityRef, VersionedEntity> get rows => UnmodifiableMapView(_s.rows);

  List<OutboxEntry> get outbox => List.unmodifiable(_s.sortedOutbox());

  Map<String, String> get meta => UnmodifiableMapView(_s.meta);

  /// Every row as sorted JSON {entity.toJson(), versions.toJson()}, soft-deleted included,
  /// Note.updatedAt left out (CORE derives it locally — 5.1.2 S-11). For convergence checks.
  Map<String, Object?> canonicalDump() => canonicalDumpOf(_s.rows.values);

  /// When non-null, the writes of every localWrite / seedRows call are appended (tests of
  /// the TestDevice edit helpers read the JSON they built).
  @internal
  List<FakeLocalWrite>? writeLog;

  /// TestDevice helper: a device-unique entity id.
  @internal
  String newId(String prefix) => _s.newId(prefix);

  /// TestDevice helper: the device clock.
  @internal
  Clock get clock => _s.clock;

  /// CORE ensureDefaults (CORE 6.2.2): rows written with the fixed [version] instead of a
  /// fresh HLC, outbox '*', one localChanges event. Rows that already exist are left alone.
  @internal
  void seedRows(List<FakeLocalWrite> writes, Hlc version) {
    writeLog?.addAll(writes);
    final versions = EntityFieldVersions(version);
    final fresh = [
      for (final w in writes)
        if (!_s.rows.containsKey(EntityRef(w.kind, _idOf(w)))) w,
    ];
    if (fresh.isEmpty) return;
    _s.transaction((_) {
      for (final w in fresh) {
        final entity = EntityJson.decode(w.kind, {
          ...w.json,
          'version': version.toString(),
        });
        _s.writeEntity(entity, versions);
        _s.enqueue(
          EntityRef(w.kind, entity.id),
          op: OutboxOp.upsert,
          fields: const {kAllFields},
          hlc: version,
        );
      }
      _s.finish();
    });
    _s.emitPendingCount();
    _s.emitLocalChange();
  }

  /// TestDevice helper: active pages of [noteId] in (sortKey, id) order.
  @internal
  List<Page> activePagesOf(NoteId noteId) =>
      _s.pagesOf(noteId).where((p) => p.deletedAt == null).toList()
        ..sort(FakeStoreState.comparePages);

  /// TestDevice helper: stroke rows of [pageId], soft-deleted included.
  @internal
  List<Stroke> strokesOf(PageId pageId) => _s.strokesOf(pageId);

  /// (2nd round) TestDevice helper: page object rows of [pageId], soft-deleted included.
  @internal
  List<PageObject> objectsOf(PageId pageId) => _s.objectsOf(pageId);

  /// (2nd round) TestDevice helper: the handwriting result row of [pageId] (soft-deleted
  /// included), or null.
  @internal
  HandwritingText? handwritingOf(PageId pageId) => _s.handwritingOf(pageId);

  static String _idOf(FakeLocalWrite w) {
    final id = w.json[w.kind == EntityKind.setting ? 'key' : 'id'];
    if (id is! String) throw ArgumentError.value(id, 'json', 'has no id');
    return id;
  }
}

@immutable
final class FakeLocalWrite {
  const FakeLocalWrite(this.kind, this.json, {required this.changedFields});
  final EntityKind kind;

  /// CORE 6.3 keys; 'version' / 'updatedAt' are set by the store.
  final Map<String, Object?> json;

  /// JSON keys (no meta keys) or {'*'}.
  final Set<String> changedFields;
}
