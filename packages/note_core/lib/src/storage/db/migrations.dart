// lib/src/storage/db/migrations.dart (internal) — CORE 6.15 schema steps, 6.18 errors.
//
// v1 has no steps. From v2 on, `dart run drift_dev make-migrations` generates
// schema_versions.dart and each step is written with its stepByStep helpers.
import 'package:drift/drift.dart';

/// One schema step from version `from` to `from + 1`.
typedef SchemaUpgradeStep = Future<void> Function(
  Migrator m,
  GeneratedDatabase db,
  int from,
);

/// Steps of this app version, keyed by the version they upgrade from.
const Map<int, SchemaUpgradeStep> kSchemaSteps = {};

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
