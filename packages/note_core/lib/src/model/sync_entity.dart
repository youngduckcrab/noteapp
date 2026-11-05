// lib/src/model/sync_entity.dart — contract 00-overview 7.2.6 / CORE 4.2.
import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';

enum EntityKind {
  folder,
  note,
  page,
  stroke,
  penPreset,
  asset,
  recording,
  setting,
}

/// Everything that is stored, versioned and synced.
abstract interface class SyncEntity {
  EntityKind get kind;
  String get id;
  Hlc? get version;
  EpochMillis? get deletedAt;
  bool get isDeleted;
  Map<String, Object?> toJson(); // sync/backup wire format (6.3)
}

const int kNoteSchemaVersion = 1; // note content format the app can edit
const int kDatabaseSchemaVersion = 1; // drift schema
const int kStrokePointsFormatVersion = 1;

/// Reads the optional `version` key (HLC text) of an entity JSON object.
Hlc? readVersion(Map<String, Object?> json) {
  final text = readStringOrNull(json, 'version');
  return text == null ? null : Hlc.parse(text);
}
