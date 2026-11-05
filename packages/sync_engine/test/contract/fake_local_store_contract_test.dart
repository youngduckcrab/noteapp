// SyncStore contract suite C-01..C-25 against FakeLocalStore (07-sync 5.1.4, T6). The
// real-CORE-only checks (open session history, reopen, write retries) run in
// test/integration/core_sync_store_contract_test.dart (T16).
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:sync_engine/testing.dart';

import 'sync_store_contract.dart';

void main() {
  syncStoreContract(
    'FakeLocalStore',
    ({required deviceNodeId, required clock}) async => FakeContractDriver(
      FakeLocalStore(nodeId: deviceNodeId, clock: clock),
      clock,
    ),
  );
}

/// Local edits as FakeLocalStore models them: CORE 6.3 JSON and the CORE 6.5 changed
/// fields, through localWrite / localPurge / assets.put / markOpened.
final class FakeContractDriver implements SyncStoreContractDriver {
  FakeContractDriver(this.store, this.clock);

  final FakeLocalStore store;
  final Clock clock;
  int _ids = 0;

  int get _now => clock.now().millisecondsSinceEpoch;
  String _id(String prefix) => '$prefix-${(++_ids).toString().padLeft(4, '0')}';

  @override
  SyncStore get sync => store.sync;

  @override
  AssetStore get assets => store.assets;

  @override
  Stream<void> get localChanges => store.localChanges;

  Map<String, Object?> _json(EntityKind kind, String id) =>
      store.rows[EntityRef(kind, id)]!.entity.toJson();

  String _lastKey(bool Function(SyncEntity e) sibling) {
    String? last;
    for (final row in store.rows.values) {
      final e = row.entity;
      if (e.isDeleted || !sibling(e)) continue;
      final key = switch (e) {
        Folder() => e.sortKey,
        Note() => e.sortKey,
        _ => null,
      };
      if (key != null && (last == null || key.compareTo(last) > 0)) last = key;
    }
    return SortKeys.between(last, null);
  }

  @override
  Future<FolderId> createFolder(String name) async {
    final id = _id('folder');
    store.localWrite([
      FakeLocalWrite(
        EntityKind.folder,
        {
          'id': id,
          'ownerId': store.sync.ownerId,
          'parentId': null,
          'name': name,
          'color': null,
          'icon': null,
          'sortKey': _lastKey((e) => e is Folder && e.parentId == null),
          'createdAt': _now,
          'deletedAt': null,
          'trashRootId': null,
        },
        changedFields: const {kAllFields},
      ),
    ]);
    return id;
  }

  @override
  Future<NoteId> createNote(String title, {FolderId? folderId}) async {
    final id = _id('note');
    store.localWrite([
      FakeLocalWrite(
        EntityKind.note,
        {
          'id': id,
          'ownerId': store.sync.ownerId,
          'folderId': folderId,
          'title': title,
          'cover': {'type': 'firstPage'},
          'tags': <String>[],
          'isFavorite': false,
          'sortKey': _lastKey((e) => e is Note && e.folderId == folderId),
          'schemaVersion': 1,
          'createdAt': _now,
          'deletedAt': null,
          'trashRootId': null,
        },
        changedFields: const {kAllFields},
      ),
      FakeLocalWrite(
        EntityKind.page,
        {
          'id': _id('page'),
          'noteId': id,
          'sortKey': 'a0',
          'size': [595.2756, 841.8898],
          'background': {'type': 'blank', 'paperColor': 4294967295},
          'createdAt': _now,
          'deletedAt': null,
        },
        changedFields: const {kAllFields},
      ),
    ]);
    return id;
  }

  @override
  Future<List<PageId>> activePageIds(NoteId noteId) async => [
    for (final p in store.activePagesOf(noteId)) p.id,
  ];

  @override
  Future<void> renameNote(NoteId noteId, String title) async {
    store.localWrite([
      FakeLocalWrite(
        EntityKind.note,
        {..._json(EntityKind.note, noteId), 'title': title},
        changedFields: const {'title'},
      ),
    ]);
  }

  @override
  Future<ElementId> addStroke(PageId pageId) async {
    final id = _id('stroke');
    store.localWrite([
      FakeLocalWrite(
        EntityKind.stroke,
        {
          'id': id,
          'pageId': pageId,
          'style': StrokeStyle.defaultsFor(PenTool.fountain).toJson(),
          'points': kContractPointsBase64,
          'recordingId': null,
          'recordingOffsetMs': null,
          'createdAt': _now,
          'deletedAt': null,
        },
        changedFields: const {kAllFields},
      ),
    ]);
    return id;
  }

  @override
  Future<void> trashNote(NoteId noteId) async {
    store.localWrite([
      FakeLocalWrite(
        EntityKind.note,
        {
          ..._json(EntityKind.note, noteId),
          'deletedAt': _now,
          'trashRootId': noteId,
        },
        changedFields: const {'deletedAt', 'trashRootId'},
      ),
    ]);
  }

  @override
  Future<void> trashFolder(FolderId folderId) async {
    final writes = [
      FakeLocalWrite(
        EntityKind.folder,
        {
          ..._json(EntityKind.folder, folderId),
          'deletedAt': _now,
          'trashRootId': folderId,
        },
        changedFields: const {'deletedAt', 'trashRootId'},
      ),
    ];
    for (final row in store.rows.values) {
      final e = row.entity;
      if (e is Note && e.folderId == folderId && !e.isDeleted) {
        writes.add(
          FakeLocalWrite(
            EntityKind.note,
            {...e.toJson(), 'deletedAt': _now, 'trashRootId': folderId},
            changedFields: const {'deletedAt', 'trashRootId'},
          ),
        );
      }
    }
    store.localWrite(writes);
  }

  @override
  Future<void> purgeNote(NoteId noteId) async {
    final note = store.rows[EntityRef(EntityKind.note, noteId)]!.entity as Note;
    if (note.trashRootId == null) {
      throw StateError('purgeNote: $noteId is not in the trash');
    }
    store.localPurge(
      EntityRef(EntityKind.note, noteId),
      group: [
        for (final row in store.rows.values)
          if (row.entity case Note(:final id, :final trashRootId)
              when trashRootId == noteId)
            EntityRef(EntityKind.note, id),
      ],
    );
  }

  @override
  Future<Asset> putAsset(Uint8List bytes) =>
      store.assets.put(bytes, type: AssetType.pdf, mimeType: 'application/pdf');

  @override
  Future<void> markOpened(NoteId noteId) async => store.markOpened(noteId);

  @override
  Future<NoteLocalValues> noteLocal(NoteId noteId) async {
    final note = store.rows[EntityRef(EntityKind.note, noteId)]!.entity as Note;
    return (
      lastOpenedAt: note.lastOpenedAt,
      pageCount: note.pageCount,
      firstPageId: note.firstPageId,
    );
  }

  @override
  Future<int> contentRevision(PageId pageId) async =>
      (store.rows[EntityRef(EntityKind.page, pageId)]!.entity as Page)
          .contentRevision;

  @override
  Future<bool> hasLocalBytes(AssetId assetId) async =>
      (store.rows[EntityRef(EntityKind.asset, assetId)]!.entity as Asset)
          .hasLocalBytes;

  @override
  Future<SyncStoreContractDriver?> reopen() async => null;

  @override
  Future<void> close() async {}
}
