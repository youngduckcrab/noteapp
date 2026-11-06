// SyncStore contract suite C-01..C-31 against FakeLocalStore (07-sync 5.1.4, T6; 2nd round
// 6.6, S2-4b). The real-CORE-only checks (open session history, reopen, write retries, C-30's
// device-local recording drafts and search units) run in
// test/integration/core_sync_store_contract_test.dart (T16, T16-v2).
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_core/note_core.dart';
import 'package:note_core/testing.dart';
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

  // ---- 2nd round (07-sync 6.6) -------------------------------------------------------

  /// CORE C-11: the JSON keys whose value changed ('updatedAt' / 'version' left out).
  static Set<String> _changed(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) => {
    for (final k in {...before.keys, ...after.keys})
      if (k != 'updatedAt' &&
          k != 'version' &&
          (before.containsKey(k) != after.containsKey(k) ||
              jsonEncode(before[k]) != jsonEncode(after[k])))
        k,
  };

  void _update(
    EntityKind kind,
    Map<String, Object?> before,
    Map<String, Object?> next,
  ) {
    final fields = _changed(before, next);
    if (fields.isEmpty) return;
    store.localWrite([FakeLocalWrite(kind, next, changedFields: fields)]);
  }

  @override
  Future<ElementId> addObject(PageId pageId) async {
    final id = _id('object');
    store.localWrite([
      FakeLocalWrite(
        EntityKind.pageObject,
        PageObjectFixtures.shape(
          pageId: pageId,
          id: id,
          createdAt: _now,
        ).toJson(),
        changedFields: const {kAllFields},
      ),
    ]);
    return id;
  }

  @override
  Future<void> restyleObject(ElementId objectId) async {
    final shape =
        store.rows[EntityRef(EntityKind.pageObject, objectId)]!.entity
            as ShapeObject;
    _update(
      EntityKind.pageObject,
      shape.toJson(),
      shape
          .copyWith(
            style: shape.style
                .copyWith(strokeColorArgb: 0xFFD03030)
                .normalized(),
          )
          .toJson(),
    );
  }

  @override
  Future<void> removeObject(ElementId objectId) async {
    store.localWrite([
      FakeLocalWrite(
        EntityKind.pageObject,
        {..._json(EntityKind.pageObject, objectId), 'deletedAt': _now},
        changedFields: const {'deletedAt'},
      ),
    ]);
  }

  @override
  Future<void> putHandwriting(
    PageId pageId, {
    List<String> lines = const ['가나'],
  }) async {
    final page = store.rows[EntityRef(EntityKind.page, pageId)]!.entity as Page;
    final ref = EntityRef(
      EntityKind.handwriting,
      HandwritingText.idFor(pageId),
    );
    final stored = store.rows[ref]?.entity as HandwritingText?;
    final next = contractHandwriting(
      page.noteId,
      pageId,
      at: stored?.createdAt ?? _now,
      lines: lines,
    ).toJson();
    if (stored == null) {
      store.localWrite([
        FakeLocalWrite(
          EntityKind.handwriting,
          next,
          changedFields: const {kAllFields},
        ),
      ]);
    } else {
      _update(EntityKind.handwriting, stored.toJson(), next);
    }
  }

  @override
  Future<RecordingId> createRecording(NoteId noteId) async {
    final audio = await store.assets.put(
      contractBytes(_ids + 7, 200),
      type: AssetType.audio,
      mimeType: 'audio/webm',
    );
    final id = _id('recording');
    store.localWrite([
      FakeLocalWrite(
        EntityKind.recording,
        {
          'id': id,
          'noteId': noteId,
          'assetId': audio.id,
          'durationMs': 1000,
          'startedAt': _now,
          'title': null,
          'createdAt': _now,
          'deletedAt': null,
        },
        changedFields: const {kAllFields},
      ),
    ]);
    return id;
  }

  @override
  Future<void> renameRecording(RecordingId recordingId, String? title) async {
    final json = _json(EntityKind.recording, recordingId);
    _update(EntityKind.recording, json, {...json, 'title': title});
  }

  @override
  Future<List<ElementId>> activeObjectIds(PageId pageId) async {
    final objects = [
      for (final row in store.rows.values)
        if (row.entity case final PageObject o
            when o.pageId == pageId && !o.isDeleted)
          o,
    ]..sort(Stroke.compareOrder);
    return [for (final o in objects) o.id];
  }

  @override
  Stream<ChangeBatch>? get changeBatches => null;
}
