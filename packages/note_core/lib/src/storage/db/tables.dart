// lib/src/storage/db/tables.dart (internal) — CORE 6.11 drift schema (v2: m5-7/02-core 6.11).
//
// Every table renames its generated row class (`@DataClassName('XxxRow')`):
// drift would otherwise generate `Stroke` from `Strokes` and clash with the
// model. Times are integer ms, there are no foreign keys (orphans are allowed,
// 6.10.1), and the entity tables carry `field_versions` (6.10.2).
//
// (v2) Columns added to a v1 table come LAST in its column list: the upgrade adds them
// with ALTER TABLE ADD COLUMN, which SQLite puts after the last column (before the table
// constraints), so a new v2 database and an upgraded one have the same CREATE TABLE text
// (schema_v2_test). The FTS5 table search_fts is not a drift table: NoteDatabase creates it
// with a statement (kSearchFtsCreateSql — 6.11 option 1).
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
@TableIndex(name: 'idx_pages_bg', columns: {#bgAssetId, #bgPdfIndex}) // v2
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
  // (v2) local cache of HandwritingRepository.stalePages (6.9.3): no version, no outbox.
  TextColumn get inkRev => text().nullable()();
  IntColumn get inkRevAt => integer().nullable()();
  // (v2) derived from background_json on every page write (pdf / image backgrounds).
  TextColumn get bgAssetId => text().nullable()();
  IntColumn get bgPdfIndex => integer().nullable()();
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
@TableIndex(name: 'idx_recordings_note', columns: {#noteId, #deletedAt}) // v2
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
  TextColumn get title => text().nullable()(); // v2 (7.2.4)
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

// --- (v2) 2nd-round tables (m5-7/02-core 6.11, contract 7.2.7) ---

/// Page objects (7.2.2): the kind-specific keys + `frame` of the object JSON in data_json
/// (the meta keys are columns). note_id is denormalized (purge, copy); '' for a remote
/// orphan. asset_id: image objects and unknown objects whose top-level assetId is an asset.
@DataClassName('PageObjectRow')
@TableIndex(name: 'idx_objects_page', columns: {#pageId, #deletedAt})
@TableIndex(name: 'idx_objects_note', columns: {#noteId})
@TableIndex(name: 'idx_objects_asset', columns: {#assetId})
class PageObjects extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text()();
  TextColumn get noteId => text()();
  TextColumn get type => text()();
  // minX..maxY = PageObject.bounds (derived)
  RealColumn get minX => real()();
  RealColumn get minY => real()();
  RealColumn get maxX => real()();
  RealColumn get maxY => real()();
  TextColumn get dataJson => text()();
  TextColumn get assetId => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

/// Handwriting recognition results (7.2.5): one row per page, id `hw_<pageId>`.
@DataClassName('HandwritingRow')
@TableIndex(name: 'idx_handwriting_note', columns: {#noteId, #deletedAt})
class Handwriting extends Table {
  TextColumn get id => text()();
  TextColumn get pageId => text()();
  TextColumn get noteId => text()();
  TextColumn get engineId => text()();
  TextColumn get sourceRev => text()();
  TextColumn get linesJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  @override
  Set<Column> get primaryKey => {id};
}

/// (v3, v2.17-md C217M-03) MD 문서 bodies (08-markdown 4.3): one row per MD 문서, id
/// `md_<noteId>`. text_bytes (derived) and base_text_version (the text field version this
/// device knows the server has — 5.3) are device-local: not in the outbox, not in backups.
@DataClassName('MdDocRow')
@TableIndex(name: 'idx_md_note', columns: {#noteId})
class MdDocs extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text()();
  TextColumn get body => text().named('text')();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get version => text()(); // = versions.max (HLC text)
  TextColumn get fieldVersions =>
      text().named('field_versions').nullable()(); // 7.2.10
  IntColumn get textBytes => integer()(); // local, derived
  TextColumn get baseTextVersion => text().nullable()(); // local (5.3)
  @override
  Set<Column> get primaryKey => {id};
}

/// Recording drafts (7.2.4, 6.7) — device-local: no version, no outbox, not in backups.
/// The chunks live in the blob store under `rd/<draftId>/…`.
@DataClassName('RecordingDraftRow')
@TableIndex(name: 'idx_drafts_note', columns: {#noteId})
class RecordingDrafts extends Table {
  TextColumn get draftId => text()();
  TextColumn get recordingId => text().unique()();
  TextColumn get noteId => text()();
  TextColumn get mimeType => text()();
  IntColumn get startedAt => integer()();
  IntColumn get chunkCount => integer()();
  IntColumn get bytes => integer()();
  IntColumn get activeMs => integer()();
  IntColumn get updatedAt => integer()();
  @override
  Set<Column> get primaryKey => {draftId};
}

/// Search index owners (6.10.3) — device-local, derived. note_id / page_id are NULL for
/// pdf owners. pending: the owner still has to be re-indexed (C-13).
@DataClassName('SearchOwnerRow')
@TableIndex(name: 'idx_search_owners_note', columns: {#noteId})
@TableIndex(name: 'idx_search_owners_pending', columns: {#pending})
class SearchOwners extends Table {
  TextColumn get source => text()();
  TextColumn get ownerKey => text()();
  TextColumn get noteId => text().nullable()();
  TextColumn get pageId => text().nullable()();
  TextColumn get sourceRev => text()();
  BoolColumn get pending => boolean()();
  @override
  Set<Column> get primaryKey => {source, ownerKey};
}

/// Search units (6.10.3) — device-local, derived. id is the rowid ('most recent first'
/// order, 6.10.4) and the rowid of search_fts. Non-pdf units keep one rectangle in page pt
/// (rect_*); pdf units keep their glyph boxes outside SQLite (rects_ref = blob key).
@DataClassName('SearchUnitRow')
@TableIndex(name: 'idx_search_units_note', columns: {#noteId})
@TableIndex(name: 'idx_search_units_pdf', columns: {#assetId, #pdfIndex})
class SearchUnits extends Table {
  IntColumn get id => integer()();
  TextColumn get source => text()();
  TextColumn get ownerKey => text()();
  IntColumn get seq => integer()();
  TextColumn get noteId => text().nullable()();
  TextColumn get pageId => text().nullable()();
  TextColumn get assetId => text().nullable()();
  IntColumn get pdfIndex => integer().nullable()();
  TextColumn get body => text()();
  TextColumn get norm => text()();
  RealColumn get rectL => real().nullable()();
  RealColumn get rectT => real().nullable()();
  RealColumn get rectR => real().nullable()();
  RealColumn get rectB => real().nullable()();
  TextColumn get rectsRef => text().nullable()();
  RealColumn get pdfAspect => real().nullable()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {source, ownerKey, seq},
  ];
}

/// The FTS5 table of the search index (6.10.3, contract 7.2.7): rowid = search_units.id,
/// one column g (the index terms). Not a drift table — created by this statement in
/// NoteDatabase.onCreate and in the v1 → v2 upgrade.
const String kSearchFtsCreateSql =
    "CREATE VIRTUAL TABLE search_fts USING fts5(g, content='', "
    "contentless_delete=1, tokenize='unicode61 remove_diacritics 0')";
