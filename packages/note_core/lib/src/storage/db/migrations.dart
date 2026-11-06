// lib/src/storage/db/migrations.dart (internal) — CORE 6.15 schema steps, 6.18 errors
// (v2: m5-7/02-core 6.12.1).
//
// `dart run drift_dev make-migrations` generates note_database.steps.dart (the schema of
// every version); each step is written with its migrationSteps helper, inside the ONE
// transaction of runSchemaUpgrade.
import 'package:drift/drift.dart';

import '../../search/search_text.dart';
import '../kv_keys.dart';
import 'note_database.dart';
import 'note_database.steps.dart';

/// One schema step from version `from` to `from + 1`.
typedef SchemaUpgradeStep = Future<void> Function(
  Migrator m,
  GeneratedDatabase db,
  int from,
);

/// Steps of this app version, keyed by the version they upgrade from.
const Map<int, SchemaUpgradeStep> kSchemaSteps = {1: upgradeV1ToV2};

/// v1 → v2 (6.12.1 steps 1–6; step 0, the v1 copy, ran before the transaction — 6.12.4).
/// Only new tables, new columns and derived columns: entity columns, versions,
/// field_versions, the outbox and the existing kv keys are not touched (C-14).
Future<void> upgradeV1ToV2(Migrator m, GeneratedDatabase db, int from) async {
  await migrationSteps(from1To2: _v1ToV2)(from, db);
  // Step 6 (kv): the normalizer of the (still empty) search index, the v1 copy record.
  final copyRecord = db is NoteDatabase ? db.pendingV1CopyRecord : null;
  for (final (key, value) in [
    (KvKeys.searchNormalizerVersion, '${SearchText.normalizerVersion}'),
    if (copyRecord != null) (KvKeys.v1Copy, copyRecord),
  ]) {
    await db.customStatement(
      'INSERT OR REPLACE INTO kv ("key", "value") VALUES (?, ?)',
      [key, value],
    );
  }
}

Future<void> _v1ToV2(Migrator m, Schema2 schema) async {
  // 1. New tables and their indexes.
  await m.createTable(schema.pageObjects);
  await m.createTable(schema.handwriting);
  await m.createTable(schema.recordingDrafts);
  await m.createTable(schema.searchOwners);
  await m.createTable(schema.searchUnits);
  for (final index in [
    schema.idxObjectsPage,
    schema.idxObjectsNote,
    schema.idxObjectsAsset,
    schema.idxHandwritingNote,
    schema.idxDraftsNote,
    schema.idxSearchOwnersNote,
    schema.idxSearchOwnersPending,
    schema.idxSearchUnitsNote,
    schema.idxSearchUnitsPdf,
  ]) {
    await m.createIndex(index);
  }
  // 2. New columns of v1 tables (ALTER TABLE ADD COLUMN — last in the column list) and
  // their indexes.
  await m.addColumn(schema.recordings, schema.recordings.title);
  await m.addColumn(schema.pages, schema.pages.inkRev);
  await m.addColumn(schema.pages, schema.pages.inkRevAt);
  await m.addColumn(schema.pages, schema.pages.bgAssetId);
  await m.addColumn(schema.pages, schema.pages.bgPdfIndex);
  await m.createIndex(schema.idxRecordingsNote);
  await m.createIndex(schema.idxPagesBg);
  // 3. The FTS5 table (not a drift table — 6.11 option 1).
  final db = m.database;
  await db.customStatement(kSearchFtsCreateSql);
  // 4. The background columns of pdf / image pages (SQLite's JSON functions).
  await db.customStatement(
    "UPDATE pages SET bg_asset_id = json_extract(background_json, '\$.assetId'), "
    "bg_pdf_index = CASE json_extract(background_json, '\$.type') "
    "WHEN 'pdf' THEN json_extract(background_json, '\$.pdfPageIndex') END "
    'WHERE json_valid(background_json) '
    "AND json_extract(background_json, '\$.type') IN ('pdf', 'image')",
  );
  // 5. name_norm / title_norm with SearchText.normalize — only the rows that change.
  await _renormalize(db, table: 'folders', source: 'name', target: 'name_norm');
  await _renormalize(db, table: 'notes', source: 'title', target: 'title_norm');
}

Future<void> _renormalize(
  GeneratedDatabase db, {
  required String table,
  required String source,
  required String target,
}) async {
  final rows = await db
      .customSelect('SELECT id, "$source" AS s, "$target" AS t FROM "$table"')
      .get();
  for (final row in rows) {
    final norm = SearchText.normalize(row.read<String>('s'));
    if (norm == row.read<String>('t')) continue;
    await db.customStatement('UPDATE "$table" SET "$target" = ? WHERE id = ?', [
      norm,
      row.read<String>('id'),
    ]);
  }
}

/// The database was written by a newer app (user_version > the schema version).
/// Thrown before anything is changed (6.18 newerSchema).
final class NewerSchemaError implements Exception {
  const NewerSchemaError(this.found, this.supported);
  final int found;
  final int supported;

  /// Start of toString(), matched by the open error classification (6.18).
  static const String prefix = 'NewerSchemaError:';
  @override
  String toString() =>
      '$prefix database schema v$found, this app supports v$supported';
}

/// A schema step threw; the upgrade transaction was rolled back (6.18 migrationFailed).
final class SchemaStepError implements Exception {
  const SchemaStepError(this.from, this.cause);
  final int from;
  final Object cause;

  /// Start of toString(), matched by the open error classification (6.18).
  static const String prefix = 'SchemaStepError:';
  @override
  String toString() => '$prefix step v$from → v${from + 1}: $cause';
}

/// Runs the steps `from → to` in ONE transaction, so a failing step leaves the
/// database (and user_version, written by drift after success) unchanged.
Future<void> runSchemaUpgrade(
  GeneratedDatabase db,
  Migrator m, {
  required int from,
  required int to,
  required Map<int, SchemaUpgradeStep> steps,
}) async {
  if (from > to) throw NewerSchemaError(from, to);
  await db.transaction(() async {
    for (var v = from; v < to; v++) {
      final step = steps[v];
      if (step == null) {
        throw SchemaStepError(v, StateError('no schema step from v$v'));
      }
      try {
        await step(m, db, v);
      } on Object catch (e) {
        throw SchemaStepError(v, e);
      }
    }
  });
}
