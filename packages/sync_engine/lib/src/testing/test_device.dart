import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart';

import '../engine/connectivity.dart';
import '../engine/engine_controller.dart';
import '../engine/sync_engine.dart';
import '../model/sync_doc.dart';
import 'fake_auth_backend.dart';
import 'fake_local_store.dart';
import 'fake_network.dart';
import 'synthetic_points.dart';

/// A simulated device: FakeLocalStore + SyncEngine + FakeAuthBackend + link.
/// Edit helpers build CORE JSON (CORE 6.3 key table) and call FakeLocalStore.localWrite
/// with the changedFields CORE would record (CORE 6.5 table).
final class TestDevice {
  /// Via SyncTestHarness.device. [engine] builds the device's engine from its store and
  /// clock.
  @internal
  TestDevice.internal({
    required this.name,
    required this.uid,
    required String nodeId,
    required Clock baseClock,
    required this.clockOffset,
    required this.link,
    required this.connectivity,
    required this.auth,
    required SyncEngine Function(TestDevice device) engine,
  }) {
    clock = Clock(() => baseClock.now().add(clockOffset));
    store = FakeLocalStore(nodeId: nodeId, clock: clock);
    this.engine = engine(this);
  }

  final String name;

  /// The account this device signs in with.
  @internal
  final String uid;

  late final FakeLocalStore store;
  late final SyncEngine engine;
  final FakeAuthBackend auth;
  final FakeNetworkLink link;
  final ManualConnectivitySignal connectivity;

  /// The device wall clock: harness base clock + [clockOffset].
  @internal
  late final Clock clock;

  bool _engineStarted = false;
  bool _presetsSeeded = false;

  /// Wall-clock offset of this device (S14, S14b). Changing it moves the device clock
  /// (HLC, timestamps) but not the engine's monotonic stopwatch (harness base clock).
  Duration clockOffset;

  /// Starts the engine (SyncEngine.start); from then on [busyReason] follows its status.
  @internal
  Future<void> startEngine() {
    _engineStarted = true;
    return engine.start();
  }

  /// Why SyncTestHarness.settle must keep waiting for this device, or null when it is idle:
  /// an engine that was never started is idle; a started one is busy while connecting or
  /// downloading, and while live with queued work, a push running or due, or uploads
  /// waiting that are neither quarantined nor held back by K4 (EngineController.busyReason).
  @internal
  String? get busyReason {
    if (!_engineStarted) return null;
    return EngineController.of(engine).busyReason;
  }

  /// Link + connectivity.
  void goOffline() {
    link.setOnline(false);
    connectivity.set(false);
  }

  void goOnline() {
    link.setOnline(true);
    connectivity.set(true);
  }

  // ---- helpers ------------------------------------------------------------------------

  int get _now => clock.now().millisecondsSinceEpoch;

  SyncEntity _entity(EntityKind kind, String id) {
    final row = store.rows[EntityRef(kind, id)];
    if (row == null) throw StateError('$name: no ${kind.name} "$id"');
    return row.entity;
  }

  Map<String, Object?> _json(EntityKind kind, String id) =>
      _entity(kind, id).toJson();

  void _write(
    EntityKind kind,
    Map<String, Object?> json,
    Set<String> changedFields,
  ) => store.localWrite([
    FakeLocalWrite(kind, json, changedFields: changedFields),
  ]);

  /// Sort key after the last active folder / note under [parentId] (CORE 6.6: new and
  /// moved items go to the end), [except] left out.
  String _endKey(String? parentId, {String? except}) {
    String? last;
    for (final row in store.rows.values) {
      final e = row.entity;
      if (e.isDeleted || e.id == except) continue;
      final (parent, key) = switch (e) {
        Folder() => (e.parentId, e.sortKey),
        Note() => (e.folderId, e.sortKey),
        _ => (null, null),
      };
      if (key == null || parent != parentId) continue;
      if (last == null || key.compareTo(last) > 0) last = key;
    }
    return SortKeys.between(last, null);
  }

  // ---- folders & notes ----------------------------------------------------------------

  String createFolder(String name, {String? parentId}) {
    final id = store.newId('folder');
    final now = _now;
    _write(
      EntityKind.folder,
      {
        'id': id,
        'ownerId': store.sync.ownerId,
        'parentId': parentId,
        'name': name,
        'color': null,
        'icon': null,
        'sortKey': _endKey(parentId),
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
        'trashRootId': null,
      },
      const {kAllFields},
    );
    return id;
  }

  String createNote(String title, {String? folderId, int pages = 1}) {
    if (pages < 1) throw RangeError.range(pages, 1, null, 'pages');
    final id = store.newId('note');
    final now = _now;
    final keys = SortKeys.nBetween(null, null, pages);
    store.localWrite([
      FakeLocalWrite(
        EntityKind.note,
        {
          'id': id,
          'ownerId': store.sync.ownerId,
          'folderId': folderId,
          'title': title,
          'cover': const FirstPageCover().toJson(),
          'tags': const <String>[],
          'isFavorite': false,
          'sortKey': _endKey(folderId),
          'schemaVersion': kNoteSchemaVersion,
          'createdAt': now,
          'updatedAt': now,
          'deletedAt': null,
          'trashRootId': null,
        },
        changedFields: const {kAllFields},
      ),
      for (final key in keys)
        FakeLocalWrite(
          EntityKind.page,
          _pageJson(store.newId('page'), id, key, now),
          changedFields: const {kAllFields},
        ),
    ]);
    return id;
  }

  static Map<String, Object?> _pageJson(
    String id,
    String noteId,
    String sortKey,
    int now,
  ) => {
    'id': id,
    'noteId': noteId,
    'sortKey': sortKey,
    'size': PageSize.a4Portrait.toJson(),
    'background': const BlankBackground().toJson(),
    'createdAt': now,
    'updatedAt': now,
    'deletedAt': null,
  };

  void renameNote(String noteId, String title) => _write(
    EntityKind.note,
    {..._json(EntityKind.note, noteId), 'title': title},
    const {'title'},
  );

  void moveNote(String noteId, String? folderId) => _write(
    EntityKind.note,
    {
      ..._json(EntityKind.note, noteId),
      'folderId': folderId,
      'sortKey': _endKey(folderId, except: noteId),
    },
    const {'folderId', 'sortKey'},
  );

  /// Throws StateError on a local cycle (like CORE FolderCycleException).
  void moveFolder(String folderId, String? parentId) {
    _entity(EntityKind.folder, folderId);
    var cursor = parentId;
    final seen = <String>{};
    while (cursor != null && seen.add(cursor)) {
      if (cursor == folderId) {
        throw StateError(
          '$name: moving folder $folderId under $parentId makes a cycle',
        );
      }
      final parent = store.rows[EntityRef(EntityKind.folder, cursor)]?.entity;
      cursor = parent is Folder ? parent.parentId : null;
    }
    _write(
      EntityKind.folder,
      {
        ..._json(EntityKind.folder, folderId),
        'parentId': parentId,
        'sortKey': _endKey(parentId, except: folderId),
      },
      const {'parentId', 'sortKey'},
    );
  }

  void trashNote(String noteId) => _write(
    EntityKind.note,
    {
      ..._json(EntityKind.note, noteId),
      'deletedAt': _now,
      'trashRootId': noteId,
    },
    const {'deletedAt', 'trashRootId'},
  );

  /// CORE restore (6.8): clears deletedAt / trashRootId; a note whose folder is not active
  /// moves to the nearest active ancestor (top level when the chain breaks) at its end.
  void restoreNote(String noteId) {
    final note = _entity(EntityKind.note, noteId) as Note;
    final json = {...note.toJson(), 'deletedAt': null, 'trashRootId': null};
    final fields = {'deletedAt', 'trashRootId'};
    final target = _activeAncestor(note.folderId);
    if (target != note.folderId) {
      json['folderId'] = target;
      json['sortKey'] = _endKey(target, except: noteId);
      fields.addAll(const {'folderId', 'sortKey'});
    }
    _write(EntityKind.note, json, fields);
  }

  String? _activeAncestor(String? folderId) {
    var cursor = folderId;
    final seen = <String>{};
    while (cursor != null && seen.add(cursor)) {
      final folder = store.rows[EntityRef(EntityKind.folder, cursor)]?.entity;
      if (folder is! Folder) return null;
      if (!folder.isDeleted) return cursor;
      cursor = folder.parentId;
    }
    return null;
  }

  /// Trash (if still active) and then trash purge, as the library does (CORE 6.8).
  void purgeNote(String noteId) {
    final note = _entity(EntityKind.note, noteId) as Note;
    if (note.trashRootId == null) trashNote(noteId);
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

  // ---- pages & strokes ----------------------------------------------------------------

  /// Active, ordered by (sortKey, id).
  List<String> pageIdsOf(String noteId) => [
    for (final p in store.activePagesOf(noteId)) p.id,
  ];

  /// A new page after [afterPageId] (default: the last page). Equal neighbour keys after a
  /// sync are repaired like CORE 6.6: the new page and the rest of the equal-key run get
  /// fresh keys in the same commit.
  String insertPage(String noteId, {String? afterPageId}) {
    _entity(EntityKind.note, noteId);
    final pages = store.activePagesOf(noteId);
    final index = afterPageId == null
        ? pages.length - 1
        : pages.indexWhere((p) => p.id == afterPageId);
    if (afterPageId != null && index < 0) {
      throw StateError('$name: $afterPageId is not an active page of $noteId');
    }
    final prev = index < 0 ? null : pages[index];
    final next = index + 1 < pages.length ? pages[index + 1] : null;
    final id = store.newId('page');
    final now = _now;
    final writes = <FakeLocalWrite>[];
    String key;
    if (prev != null && next != null && next.sortKey == prev.sortKey) {
      final run = <Page>[];
      for (
        var i = index + 1;
        i < pages.length && pages[i].sortKey == prev.sortKey;
        i++
      ) {
        run.add(pages[i]);
      }
      final after = index + 1 + run.length < pages.length
          ? pages[index + 1 + run.length].sortKey
          : null;
      final keys = SortKeys.nBetween(prev.sortKey, after, 1 + run.length);
      key = keys.first;
      for (var i = 0; i < run.length; i++) {
        writes.add(
          FakeLocalWrite(
            EntityKind.page,
            {...run[i].toJson(), 'sortKey': keys[i + 1]},
            changedFields: const {'sortKey'},
          ),
        );
      }
    } else {
      key = SortKeys.between(prev?.sortKey, next?.sortKey);
    }
    store.localWrite([
      FakeLocalWrite(
        EntityKind.page,
        _pageJson(id, noteId, key, now),
        changedFields: const {kAllFields},
      ),
      ...writes,
    ]);
    return id;
  }

  /// Throws StateError for the last active page of a note (CORE LastPageDeletionException).
  void deletePage(String pageId) {
    final page = _entity(EntityKind.page, pageId) as Page;
    if (page.isDeleted) return;
    if (store.activePagesOf(page.noteId).length <= 1) {
      throw StateError('$name: $pageId is the last page of ${page.noteId}');
    }
    _write(
      EntityKind.page,
      {...page.toJson(), 'deletedAt': _now},
      const {'deletedAt'},
    );
  }

  /// Points from synthetic_points.dart (StrokePointsBuilder + StrokePointsCodec, seeded).
  String addStroke(String pageId, {int seed = 0, int points = 100}) {
    _entity(EntityKind.page, pageId);
    final id = store.newId('stroke');
    final now = _now;
    _write(
      EntityKind.stroke,
      {
        'id': id,
        'pageId': pageId,
        'style': StrokeStyle.defaultsFor(PenTool.ballpoint).toJson(),
        'points': syntheticPointsBase64(seed: seed, count: points),
        'recordingId': null,
        'recordingOffsetMs': null,
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
      },
      const {kAllFields},
    );
    return id;
  }

  void eraseStroke(String strokeId) => _write(
    EntityKind.stroke,
    {..._json(EntityKind.stroke, strokeId), 'deletedAt': _now},
    const {'deletedAt'},
  );

  void recolorStroke(String strokeId, int colorArgb) {
    final stroke = _entity(EntityKind.stroke, strokeId) as Stroke;
    _write(
      EntityKind.stroke,
      {
        ...stroke.toJson(),
        'style': stroke.style
            .copyWith(colorArgb: colorArgb)
            .normalized()
            .toJson(),
      },
      const {'style'},
    );
  }

  void moveStroke(String strokeId, {double dx = 10, double dy = 0}) {
    final stroke = _entity(EntityKind.stroke, strokeId) as Stroke;
    _write(
      EntityKind.stroke,
      {
        ...stroke.toJson(),
        'points': StrokePointsCodec.encodeBase64(
          stroke.points.transformed(Affine2.translation(dx, dy)),
        ),
      },
      const {'points'},
    );
  }

  /// Active strokes of [pageId] in drawing order (createdAt, id).
  List<SyncDoc> activeStrokesOf(String pageId) {
    final strokes = store.strokesOf(pageId).where((s) => !s.isDeleted).toList()
      ..sort((a, b) {
        final c = a.createdAt.compareTo(b.createdAt);
        return c != 0 ? c : a.id.compareTo(b.id);
      });
    return [for (final s in strokes) SyncDoc.fromEntity(s)];
  }

  // ---- presets, settings, assets ------------------------------------------------------

  static const List<(PenTool, String)> _defaultPresets = [
    (PenTool.ballpoint, '볼펜'),
    (PenTool.fountain, '만년필'),
    (PenTool.highlighter, '형광펜'),
    (PenTool.pencil, '연필'),
    (PenTool.marker, '마커'),
  ];

  /// Rows of CORE ensureDefaults: `preset-default-<wireName>`, seed HLC Hlc(1, 0, '0'×16),
  /// outbox '*' (CD-07, CORE 6.2.2).
  void seedDefaultPresets() {
    if (_presetsSeeded) return;
    _presetsSeeded = true;
    final now = _now;
    final keys = SortKeys.nBetween(null, null, _defaultPresets.length);
    store.seedRows([
      for (final (i, (tool, presetName)) in _defaultPresets.indexed)
        FakeLocalWrite(
          EntityKind.penPreset,
          {
            'id': 'preset-default-${tool.wireName}',
            'ownerId': store.sync.ownerId,
            'name': presetName,
            'style': StrokeStyle.defaultsFor(tool).toJson(),
            'group': null,
            'pinned': true,
            'sortKey': keys[i],
            'createdAt': now,
            'updatedAt': now,
            'deletedAt': null,
          },
          changedFields: const {kAllFields},
        ),
    ], const Hlc(1, 0, '0000000000000000'));
  }

  void renamePreset(String presetId, String name) => _write(
    EntityKind.penPreset,
    {..._json(EntityKind.penPreset, presetId), 'name': name},
    const {'name'},
  );

  /// Synced scope only (contract 7.4.6). A null [value] resets the setting (soft delete,
  /// `{deletedAt}`); a value sets `{valueJson}` (+ deletedAt when it was reset).
  void setSetting(String key, Object? value) {
    final row = store.rows[EntityRef(EntityKind.setting, key)];
    final now = _now;
    if (value == null) {
      if (row == null || row.entity.isDeleted) return;
      _write(
        EntityKind.setting,
        {...row.entity.toJson(), 'deletedAt': now},
        const {'deletedAt'},
      );
      return;
    }
    final json = {
      'key': key,
      'valueJson': jsonEncode(value),
      'updatedAt': now,
      'deletedAt': null,
    };
    if (row == null) {
      _write(EntityKind.setting, json, const {kAllFields});
    } else {
      _write(
        EntityKind.setting,
        json,
        row.entity.isDeleted
            ? const {'valueJson', 'deletedAt'}
            : const {'valueJson'},
      );
    }
  }

  /// store.assets.put(...) — CORE AssetStore semantics (sha-256 id, bytesArrived).
  Future<AssetId> putAsset(
    Uint8List bytes, {
    AssetType type = AssetType.pdf,
    String mimeType = 'application/pdf',
  }) async =>
      (await store.assets.put(bytes, type: type, mimeType: mimeType)).id;

  SyncDoc? doc(EntityKind kind, String id) {
    final row = store.rows[EntityRef(kind, id)];
    return row == null ? null : SyncDoc.fromEntity(row.entity);
  }

  @override
  String toString() => 'TestDevice($name)';
}
