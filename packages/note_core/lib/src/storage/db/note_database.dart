// lib/src/storage/db/note_database.dart (internal) — CORE 6.11, 6.15, 6.18.
import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../model/sync_entity.dart' show kDatabaseSchemaVersion;
import 'migrations.dart';
import 'tables.dart';

export 'tables.dart';

part 'note_database.g.dart';

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
  ],
)
class NoteDatabase extends _$NoteDatabase {
  /// [upgradeSteps] is replaced only by tests (open_errors_test subclasses this
  /// database with a higher schemaVersion and a failing step).
  NoteDatabase(
    super.executor, {
    @visibleForTesting Map<int, SchemaUpgradeStep> upgradeSteps = kSchemaSteps,
  }) : _steps = upgradeSteps;

  final Map<int, SchemaUpgradeStep> _steps;

  /// The SQLite schema version (`PRAGMA user_version`) = kDatabaseSchemaVersion. A
  /// static field so that drift_dev make-migrations can read it (6.15).
  static const int currentSchemaVersion = kDatabaseSchemaVersion;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) =>
        runSchemaUpgrade(this, m, from: from, to: to, steps: _steps),
    beforeOpen: (details) async {
      // No foreign keys (orphans are allowed, 6.10.1).
      await customStatement('PRAGMA foreign_keys = OFF');
    },
  );
}
