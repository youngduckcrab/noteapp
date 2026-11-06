// lib/src/storage/db/note_database.dart (internal) — CORE 6.11, 6.15, 6.18 (v2: m5-7/02-core
// 6.11, 6.12).
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/sync_entity.dart' show kDatabaseSchemaVersion;
import '../../search/search_text.dart';
import '../kv_keys.dart';
import 'migrations.dart';
import 'tables.dart';

export 'tables.dart';

part 'note_database.g.dart';

/// Makes the v1 database copy right before the v1 → v2 upgrade (6.12.4, step 0) and returns
/// the kv `db.v1Copy` value to store (a copy or a failure record). It runs outside any
/// transaction (VACUUM INTO cannot run inside one) and never throws: a failed copy is a
/// failure record and the upgrade goes on.
typedef V1CopyMaker = Future<String> Function(GeneratedDatabase db);

@DriftDatabase(
  tables: [
    Kv,
    Folders,
    Notes,
    Pages,
    Strokes,
    PenPresets,
    Assets,
    Recordings,
    Settings,
    Outbox,
    // (v2)
    PageObjects,
    Handwriting,
    RecordingDrafts,
    SearchOwners,
    SearchUnits,
  ],
)
class NoteDatabase extends _$NoteDatabase {
  /// [upgradeSteps] is replaced only by tests (open_errors_test subclasses this
  /// database with a higher schemaVersion and a failing step). [v1Copy] makes the
  /// pre-upgrade copy (null: none — new and in-memory databases never need one).
  NoteDatabase(
    super.executor, {
    @visibleForTesting Map<int, SchemaUpgradeStep> upgradeSteps = kSchemaSteps,
    this.v1Copy,
  }) : _steps = upgradeSteps;

  final Map<int, SchemaUpgradeStep> _steps;

  /// The pre-upgrade copy (6.12.4 step 0); called only when upgrading from v1.
  final V1CopyMaker? v1Copy;

  /// The kv `db.v1Copy` value of the copy made in this open (step 0), written by the
  /// v1 → v2 step (step 6) inside the upgrade transaction. null: no copy was asked for.
  String? pendingV1CopyRecord;

  /// The SQLite schema version (`PRAGMA user_version`) = kDatabaseSchemaVersion. A
  /// static field so that drift_dev make-migrations can read it (6.15).
  static const int currentSchemaVersion = kDatabaseSchemaVersion;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // (v2) The FTS5 table is not a drift table (6.11 option 1).
      await customStatement(kSearchFtsCreateSql);
      await into(kv).insertOnConflictUpdate(
        KvCompanion.insert(
          key: KvKeys.searchNormalizerVersion,
          value: '${SearchText.normalizerVersion}',
        ),
      );
    },
    onUpgrade: (m, from, to) async {
      if (from > to) throw NewerSchemaError(from, to);
      // 6.12.4 step 0: the copy comes BEFORE the upgrade transaction (VACUUM INTO cannot
      // run in a transaction, and drift does not wrap migrations in one).
      final copy = v1Copy;
      if (from == 1 && to > 1 && copy != null) {
        pendingV1CopyRecord = await copy(this);
      }
      await runSchemaUpgrade(this, m, from: from, to: to, steps: _steps);
    },
    beforeOpen: (details) async {
      // No foreign keys (orphans are allowed, 6.10.1).
      await customStatement('PRAGMA foreign_keys = OFF');
    },
  );
}
