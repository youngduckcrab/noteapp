// lib/src/storage/row_mappers.dart (internal) — entity ↔ drift row (CORE 6.10.2, 6.11).
//
// Every entity row stores `version` = versions.max and `field_versions` (NULL when
// there are no overrides). Local-only columns (notes.page_count / first_page_id /
// last_opened_at, pages.content_rev, assets.chunk_count / has_local_bytes) are
// written from the entity on insert and kept on update when [keepLocal] is set
// (remote and repair writes, 6.10.3).
import 'dart:convert';

import 'package:drift/drift.dart';

import '../common/hlc.dart';
import '../common/text_normalize.dart';
import '../model/asset.dart';
import '../model/folder.dart';
import '../model/note.dart';
import '../model/page.dart';
import '../model/page_background.dart';
import '../model/page_size.dart';
import '../model/pen_preset.dart';
import '../model/pen_style.dart';
import '../model/pressure_curve.dart';
import '../model/stroke.dart';
import '../model/stroke_points.dart';
import '../model/sync_entity.dart';
import '../sync/field_versions.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';

/// The field_versions column text: NULL when no override is newer than the base.
String? fieldVersionsColumn(EntityFieldVersions v) {
  final json = v.toJson();
  return json.containsKey('o') ? jsonEncode(json) : null;
}

/// Field versions of a row; a damaged column or one whose max is not the row version
/// is recovered as EntityFieldVersions(version) (6.10.2).
EntityFieldVersions fieldVersionsOf(String version, String? column) {
  final v = Hlc.parse(version);
  if (column == null) return EntityFieldVersions(v);
  try {
    final parsed = EntityFieldVersions.fromJson(
      jsonDecode(column) as Map<String, Object?>,
    );
    if (parsed.max == v) return parsed;
  } on Object {
    // fall through: recover from the version column
  }
  return EntityFieldVersions(v);
}

String _curveText(PressureCurve c) => '${c.x1},${c.y1},${c.x2},${c.y2}';

PressureCurve _curveOf(String text) {
  final p = text.split(',').map(double.parse).toList();
  return PressureCurve(x1: p[0], y1: p[1], x2: p[2], y2: p[3]);
}

/// Inserts or updates the row of [e] with [versions] (version column = versions.max).
/// [strokeNoteId]: the denormalized strokes.note_id ('' for a remote orphan stroke).
Future<void> writeEntityRow(
  NoteDatabase db,
  SyncEntity e,
  EntityFieldVersions versions, {
  bool keepLocal = false,
  String? strokeNoteId,
  int? assetChunkCount,
}) async {
  final version = versions.max.toString();
  final fv = fieldVersionsColumn(versions);
  switch (e) {
    case Folder():
      await db
          .into(db.folders)
          .insertOnConflictUpdate(
            FoldersCompanion.insert(
              id: e.id,
              ownerId: e.ownerId,
              parentId: Value(e.parentId),
              name: e.name,
              nameNorm: normalizeForSearch(e.name),
              colorArgb: Value(e.colorArgb),
              icon: Value(e.icon),
              sortKey: e.sortKey,
              createdAt: e.createdAt,
              updatedAt: e.updatedAt,
              deletedAt: Value(e.deletedAt),
              trashRootId: Value(e.trashRootId),
              version: version,
              fieldVersions: Value(fv),
            ),
          );
    case Note():
      final row = NotesCompanion.insert(
        id: e.id,
        ownerId: e.ownerId,
        folderId: Value(e.folderId),
        title: e.title,
        titleNorm: normalizeForSearch(e.title),
        coverJson: jsonEncode(e.cover.toJson()),
        tagsJson: jsonEncode(e.tags),
        isFavorite: e.isFavorite,
        sortKey: e.sortKey,
        schemaVersion: e.schemaVersion,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
        deletedAt: Value(e.deletedAt),
        trashRootId: Value(e.trashRootId),
        version: version,
        fieldVersions: Value(fv),
        pageCount: e.pageCount,
        firstPageId: Value(e.firstPageId),
        lastOpenedAt: Value(e.lastOpenedAt),
      );
      await db
          .into(db.notes)
          .insert(
            row,
            onConflict: DoUpdate(
              (_) => keepLocal
                  ? row.copyWith(
                      pageCount: const Value.absent(),
                      firstPageId: const Value.absent(),
                      lastOpenedAt: const Value.absent(),
                    )
                  : row,
            ),
          );
    case Page():
      final row = PagesCompanion.insert(
        id: e.id,
        noteId: e.noteId,
        sortKey: e.sortKey,
        width: e.size.width,
        height: e.size.height,
        backgroundJson: jsonEncode(e.background.toJson()),
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
        deletedAt: Value(e.deletedAt),
        version: version,
        fieldVersions: Value(fv),
        contentRev: e.contentRevision,
      );
      await db
          .into(db.pages)
          .insert(
            row,
            onConflict: DoUpdate(
              (_) => keepLocal
                  ? row.copyWith(contentRev: const Value.absent())
                  : row,
            ),
          );
    case Stroke():
      final b = e.bounds;
      final s = e.style;
      await db
          .into(db.strokes)
          .insertOnConflictUpdate(
            StrokesCompanion.insert(
              id: e.id,
              pageId: e.pageId,
              noteId: strokeNoteId ?? '',
              tool: s.tool.wireName,
              colorArgb: s.colorArgb,
              width: s.width,
              opacity: s.opacity,
              pressureSensitivity: s.pressureSensitivity,
              pressureCurve: _curveText(s.pressureCurve),
              smoothing: s.smoothing,
              styleExtrasJson: Value(
                s.extras.isEmpty ? null : jsonEncode(s.extras),
              ),
              points: StrokePointsCodec.encode(e.points),
              pointCount: e.points.length,
              minX: b.left,
              minY: b.top,
              maxX: b.right,
              maxY: b.bottom,
              recordingId: Value(e.recordingId),
              recordingOffsetMs: Value(e.recordingOffsetMs),
              createdAt: e.createdAt,
              updatedAt: e.updatedAt,
              deletedAt: Value(e.deletedAt),
              version: version,
              fieldVersions: Value(fv),
            ),
          );
    case PenPreset():
      await db
          .into(db.penPresets)
          .insertOnConflictUpdate(
            PenPresetsCompanion.insert(
              id: e.id,
              ownerId: e.ownerId,
              name: e.name,
              styleJson: jsonEncode(e.style.toJson()),
              groupName: Value(e.group),
              pinned: e.pinned,
              sortKey: e.sortKey,
              createdAt: e.createdAt,
              updatedAt: e.updatedAt,
              deletedAt: Value(e.deletedAt),
              version: version,
              fieldVersions: Value(fv),
            ),
          );
    case Asset():
      final row = AssetsCompanion.insert(
        id: e.id,
        ownerId: e.ownerId,
        type: e.type.name,
        mimeType: e.mimeType,
        size: e.size,
        fileName: Value(e.fileName),
        chunkCount: assetChunkCount ?? 0,
        hasLocalBytes: e.hasLocalBytes,
        storagePath: Value(e.storagePath),
        createdAt: e.createdAt,
        deletedAt: Value(e.deletedAt),
        version: version,
        fieldVersions: Value(fv),
      );
      await db
          .into(db.assets)
          .insert(
            row,
            onConflict: DoUpdate(
              (_) => row.copyWith(
                chunkCount: assetChunkCount == null
                    ? const Value.absent()
                    : Value(assetChunkCount),
                hasLocalBytes: keepLocal
                    ? const Value.absent()
                    : Value(e.hasLocalBytes),
              ),
            ),
          );
    case Recording():
      await db
          .into(db.recordings)
          .insertOnConflictUpdate(
            RecordingsCompanion.insert(
              id: e.id,
              noteId: e.noteId,
              assetId: e.assetId,
              durationMs: e.durationMs,
              startedAt: e.startedAt,
              createdAt: e.createdAt,
              updatedAt: e.updatedAt,
              deletedAt: Value(e.deletedAt),
              version: version,
              fieldVersions: Value(fv),
            ),
          );
    case SettingValue():
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: e.key,
              valueJson: e.valueJson,
              updatedAt: e.updatedAt,
              deletedAt: Value(e.deletedAt),
              version: version,
              fieldVersions: Value(fv),
            ),
          );
    default:
      throw ArgumentError.value(e, 'entity', 'unknown entity type');
  }
}

/// Deletes the row of [ref]; returns whether it existed.
Future<bool> deleteEntityRow(NoteDatabase db, EntityRef ref) async {
  final id = ref.id;
  final n = switch (ref.kind) {
    EntityKind.folder => await (db.delete(
      db.folders,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.note => await (db.delete(
      db.notes,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.page => await (db.delete(
      db.pages,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.stroke => await (db.delete(
      db.strokes,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.penPreset => await (db.delete(
      db.penPresets,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.asset => await (db.delete(
      db.assets,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.recording => await (db.delete(
      db.recordings,
    )..where((t) => t.id.equals(id))).go(),
    EntityKind.setting => await (db.delete(
      db.settings,
    )..where((t) => t.key.equals(id))).go(),
  };
  return n > 0;
}

/// The stored entity of [ref] with its field versions; null if there is no row.
Future<VersionedEntity?> readVersionedRow(
  NoteDatabase db,
  EntityRef ref,
) async {
  final id = ref.id;
  switch (ref.kind) {
    case EntityKind.folder:
      final r = await (db.select(
        db.folders,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedFolder(r);
    case EntityKind.note:
      final r = await (db.select(
        db.notes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedNote(r);
    case EntityKind.page:
      final r = await (db.select(
        db.pages,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedPage(r);
    case EntityKind.stroke:
      final r = await (db.select(
        db.strokes,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedStroke(r);
    case EntityKind.penPreset:
      final r = await (db.select(
        db.penPresets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedPreset(r);
    case EntityKind.asset:
      final r = await (db.select(
        db.assets,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedAsset(r);
    case EntityKind.recording:
      final r = await (db.select(
        db.recordings,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      return r == null ? null : versionedRecording(r);
    case EntityKind.setting:
      final r = await (db.select(
        db.settings,
      )..where((t) => t.key.equals(id))).getSingleOrNull();
      return r == null ? null : versionedSetting(r);
  }
}

VersionedEntity _versioned(
  SyncEntity Function(Hlc version) build,
  String version,
  String? column,
) {
  final versions = fieldVersionsOf(version, column);
  return VersionedEntity(build(versions.max), versions);
}

VersionedEntity versionedFolder(FolderRow r) =>
    _versioned((v) => folderOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedNote(NoteRow r) =>
    _versioned((v) => noteOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedPage(PageRow r) =>
    _versioned((v) => pageOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedStroke(StrokeRow r) =>
    _versioned((v) => strokeOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedPreset(PenPresetRow r) =>
    _versioned((v) => presetOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedAsset(AssetRow r) =>
    _versioned((v) => assetOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedRecording(RecordingRow r) =>
    _versioned((v) => recordingOf(r, v), r.version, r.fieldVersions);
VersionedEntity versionedSetting(SettingRow r) =>
    _versioned((v) => settingOf(r, v), r.version, r.fieldVersions);

Folder folderOf(FolderRow r, [Hlc? version]) => Folder(
  id: r.id,
  ownerId: r.ownerId,
  parentId: r.parentId,
  name: r.name,
  colorArgb: r.colorArgb,
  icon: r.icon,
  sortKey: r.sortKey,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  trashRootId: r.trashRootId,
  version: version ?? Hlc.parse(r.version),
);

Note noteOf(NoteRow r, [Hlc? version]) => Note(
  id: r.id,
  ownerId: r.ownerId,
  folderId: r.folderId,
  title: r.title,
  cover: NoteCover.fromJson(jsonDecode(r.coverJson) as Map<String, Object?>),
  tags: List.unmodifiable(
    (jsonDecode(r.tagsJson) as List<Object?>).cast<String>(),
  ),
  isFavorite: r.isFavorite,
  sortKey: r.sortKey,
  schemaVersion: r.schemaVersion,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  trashRootId: r.trashRootId,
  version: version ?? Hlc.parse(r.version),
  pageCount: r.pageCount,
  firstPageId: r.firstPageId,
  lastOpenedAt: r.lastOpenedAt,
);

Page pageOf(PageRow r, [Hlc? version]) => Page(
  id: r.id,
  noteId: r.noteId,
  sortKey: r.sortKey,
  size: PageSize(r.width, r.height),
  background: PageBackground.fromJson(
    jsonDecode(r.backgroundJson) as Map<String, Object?>,
  ),
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  version: version ?? Hlc.parse(r.version),
  contentRevision: r.contentRev,
);

Stroke strokeOf(StrokeRow r, [Hlc? version]) => Stroke(
  id: r.id,
  pageId: r.pageId,
  style: StrokeStyle(
    tool: PenTool.fromWireName(r.tool),
    colorArgb: r.colorArgb,
    width: r.width,
    opacity: r.opacity,
    pressureSensitivity: r.pressureSensitivity,
    pressureCurve: _curveOf(r.pressureCurve),
    smoothing: r.smoothing,
    extras: r.styleExtrasJson == null
        ? const {}
        : Map.unmodifiable(
            jsonDecode(r.styleExtrasJson!) as Map<String, Object?>,
          ),
  ),
  points: StrokePointsCodec.decode(r.points),
  recordingId: r.recordingId,
  recordingOffsetMs: r.recordingOffsetMs,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  version: version ?? Hlc.parse(r.version),
);

PenPreset presetOf(PenPresetRow r, [Hlc? version]) => PenPreset(
  id: r.id,
  ownerId: r.ownerId,
  name: r.name,
  style: StrokeStyle.fromJson(jsonDecode(r.styleJson) as Map<String, Object?>),
  group: r.groupName,
  pinned: r.pinned,
  sortKey: r.sortKey,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  version: version ?? Hlc.parse(r.version),
);

Asset assetOf(AssetRow r, [Hlc? version]) => Asset(
  id: r.id,
  ownerId: r.ownerId,
  type: AssetType.values.byName(r.type),
  mimeType: r.mimeType,
  size: r.size,
  fileName: r.fileName,
  createdAt: r.createdAt,
  storagePath: r.storagePath,
  deletedAt: r.deletedAt,
  version: version ?? Hlc.parse(r.version),
  hasLocalBytes: r.hasLocalBytes,
);

Recording recordingOf(RecordingRow r, [Hlc? version]) => Recording(
  id: r.id,
  noteId: r.noteId,
  assetId: r.assetId,
  durationMs: r.durationMs,
  startedAt: r.startedAt,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  version: version ?? Hlc.parse(r.version),
);

SettingValue settingOf(SettingRow r, [Hlc? version]) => SettingValue(
  key: r.key,
  valueJson: r.valueJson,
  updatedAt: r.updatedAt,
  deletedAt: r.deletedAt,
  version: version ?? Hlc.parse(r.version),
);
