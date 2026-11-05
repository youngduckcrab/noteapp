// lib/src/storage/open_errors.dart (internal) — CORE 6.18 open error classification.
import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart';

import '../common/errors.dart';
import 'db/migrations.dart';

/// A required kv value could not be read (device.nodeId / hlc.last) → corrupted.
final class KvCorruptionError implements Exception {
  const KvCorruptionError(this.key, this.value);
  final String key;
  final String value;
  @override
  String toString() => 'KvCorruptionError: kv[$key] = "$value"';
}

const int _sqliteCorrupt = 11; // SQLITE_CORRUPT
const int _sqliteNotADb = 26; // SQLITE_NOTADB

/// Maps any failure while opening to the NoteStoreOpenException of 6.18.
NoteStoreOpenException classifyOpenError(Object error) {
  if (error is NoteStoreOpenException) return error;
  final cause = _unwrap(error);
  // Through a background isolate or a web worker (drift remote protocol) an
  // error thrown by the schema steps comes back as text, so the toString
  // prefixes of the error types are matched too.
  final text = cause.toString();
  if (cause is NewerSchemaError || text.contains(NewerSchemaError.prefix)) {
    return NoteStoreOpenException(
      NoteStoreOpenFailure.newerSchema,
      'The local database was written by a newer app version ($text).',
      cause: error,
    );
  }
  if (cause is SchemaStepError || text.contains(SchemaStepError.prefix)) {
    return NoteStoreOpenException(
      NoteStoreOpenFailure.migrationFailed,
      'Upgrading the local database failed and was rolled back ($text).',
      cause: error,
    );
  }
  if (cause is KvCorruptionError || _isCorruption(cause)) {
    return NoteStoreOpenException(
      NoteStoreOpenFailure.corrupted,
      'The local database is damaged or not a database ($text).',
      cause: error,
    );
  }
  return NoteStoreOpenException(
    NoteStoreOpenFailure.unknown,
    'Opening the local database failed ($text).',
    cause: error,
  );
}

Object _unwrap(Object error) {
  var e = error;
  for (var i = 0; i < 8; i++) {
    switch (e) {
      case DriftWrappedException(:final cause?):
        e = cause;
      default:
        return e;
    }
  }
  return e;
}

bool _isCorruption(Object cause) {
  if (cause is SqliteException) {
    final code = cause.resultCode;
    return code == _sqliteCorrupt || code == _sqliteNotADb;
  }
  // Errors that crossed a worker / isolate boundary (DriftRemoteException) may
  // carry the SQLite error as text only.
  final text = cause.toString();
  return text.contains('file is not a database') ||
      text.contains('database disk image is malformed');
}
