// lib/src/storage/db/tables.dart (internal) — CORE 6.11 drift schema v1.
//
// Every table renames its generated row class (`@DataClassName('XxxRow')`):
// drift would otherwise generate `Stroke` from `Strokes` and clash with the
// model. Times are integer ms, there are no foreign keys (orphans are allowed,
// 6.10.1), and the eight entity tables carry `field_versions` (6.10.2).
import 'package:drift/drift.dart';

@DataClassName('KvRow')
class Kv extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('FolderRow')
@TableIndex(
  name: 'idx_folders_parent',
  columns: {#ownerId, #parentId, #deletedAt},
)
@TableIndex(name: 'idx_folders_trash', columns: {#trashRootId})
class Folders extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get nameNorm => text()();
  IntColumn get colorArgb => integer().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get sortKey => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get trashRootId => text().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('NoteRow')
@TableIndex(
  name: 'idx_notes_folder',
  columns: {#ownerId, #folderId, #deletedAt},
)
@TableIndex(name: 'idx_notes_opened', columns: {#ownerId, #lastOpenedAt})
@TableIndex(
  name: 'idx_notes_favorite',
  columns: {#ownerId, #isFavorite, #deletedAt},
)
@TableIndex(name: 'idx_notes_trash', columns: {#trashRootId})
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get folderId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get titleNorm => text()();
  TextColumn get coverJson => text()();
  TextColumn get tagsJson => text()();
  BoolColumn get isFavorite => boolean()();
  TextColumn get sortKey => text()();
  IntColumn get schemaVersion => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get trashRootId => text().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  IntColumn get pageCount => integer()(); // local
  TextColumn get firstPageId => text().nullable()(); // local
  IntColumn get lastOpenedAt => integer().nullable()(); // local
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PageRow')
@TableIndex(name: 'idx_pages_note', columns: {#noteId, #deletedAt, #sortKey})
class Pages extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get sortKey => text()();
  RealColumn get width => real()();
  RealColumn get height => real()();
  TextColumn get backgroundJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  IntColumn get contentRev => integer()(); // local
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StrokeRow')
@TableIndex(name: 'idx_strokes_page', columns: {#pageId, #deletedAt})
@TableIndex(name: 'idx_strokes_note', columns: {#noteId})
@TableIndex(name: 'idx_strokes_recording', columns: {#recordingId})
class Strokes extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text()();
  TextColumn get noteId => text()(); // denormalized (purge, copy)
  TextColumn get tool => text()();
  IntColumn get colorArgb => integer()();
  RealColumn get width => real()();
  RealColumn get opacity => real()();
  RealColumn get pressureSensitivity => real()();
  TextColumn get pressureCurve => text()(); // "x1,y1,x2,y2"
  RealColumn get smoothing => real()();
  TextColumn get styleExtrasJson => text().nullable()();
  BlobColumn get points => blob()(); // StrokePointsCodec v1
  IntColumn get pointCount => integer()();
  // minX..maxY = Stroke.bounds (derived)
  RealColumn get minX => real()();
  RealColumn get minY => real()();
  RealColumn get maxX => real()();
  RealColumn get maxY => real()();
  TextColumn get recordingId => text().nullable()();
  IntColumn get recordingOffsetMs => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PenPresetRow')
class PenPresets extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get name => text()();
  TextColumn get styleJson => text()();
  TextColumn get groupName => text().nullable()();
  BoolColumn get pinned => boolean()();
  TextColumn get sortKey => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AssetRow')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get type => text()();
  TextColumn get mimeType => text()();
  IntColumn get size => integer()();
  TextColumn get fileName => text().nullable()();
  IntColumn get chunkCount => integer()(); // local
  BoolColumn get hasLocalBytes => boolean()(); // local
  TextColumn get storagePath => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RecordingRow')
class Recordings extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get assetId => text()();
  IntColumn get durationMs => integer()();
  IntColumn get startedAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();
  IntColumn get updatedAt => integer()();
  // reset() of a synced key (6.10.2)
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('OutboxRow')
@TableIndex(
  name: 'idx_outbox_entity',
  columns: {#entityKind, #entityId},
  unique: true,
)
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  IntColumn get rev => integer()();
  TextColumn get entityKind => text()();
  TextColumn get entityId => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get pageId => text().nullable()();
  TextColumn get op => text()();
  TextColumn get changedFields => text()(); // JSON array, sorted
  TextColumn get hlc => text()();
  IntColumn get enqueuedAt => integer()();
}
