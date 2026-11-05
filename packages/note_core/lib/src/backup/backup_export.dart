// lib/src/backup/backup_export.dart (internal) — the backup document of
// NoteStore.exportBackupJson (CORE 6.17, contract 7.2.12 v1.1). Shared by the SQLite store
// and the fake so both write the same bytes for the same state.
//
// {"format":"noteapp-backup","formatVersion":1,"exportedAt":…,"ownerId":…,
//  "deviceNodeId":…,"schema":{"note":1,"database":1,"strokePoints":1},
//  "entities":[{"kind":…,"data":<6.3 JSON>,"versions":<EntityFieldVersions JSON>},…]}
//
// Compact UTF-8 JSON. Entities are appended one by one (the caller never holds them
// all), in kind order (EntityKind.values) then id order — the caller's job.
import 'dart:convert';
import 'dart:typed_data';

import '../common/ids.dart';
import '../model/sync_entity.dart';
import '../sync/field_versions.dart';

const String kBackupFormat = 'noteapp-backup';
const int kBackupFormatVersion = 1;

/// Rows read per query while exporting (6.17).
const int kBackupPageRows = 2000;

final class BackupJsonWriter {
  BackupJsonWriter({
    required EpochMillis exportedAt,
    required OwnerId ownerId,
    required String deviceNodeId,
  }) {
    final header = _encoder.convert({
      'format': kBackupFormat,
      'formatVersion': kBackupFormatVersion,
      'exportedAt': exportedAt,
      'ownerId': ownerId,
      'deviceNodeId': deviceNodeId,
      'schema': {
        'note': kNoteSchemaVersion,
        'database': kDatabaseSchemaVersion,
        'strokePoints': kStrokePointsFormatVersion,
      },
      'entities': const <Object?>[],
    });
    // Everything but the closing "]}" of the empty entity list.
    _out.add(header.sublist(0, header.length - 2));
  }

  static final JsonUtf8Encoder _encoder = JsonUtf8Encoder();
  static final Uint8List _comma = Uint8List.fromList(const [0x2C]); // ,
  static final Uint8List _end = Uint8List.fromList(const [0x5D, 0x7D]); // ]}

  final BytesBuilder _out = BytesBuilder(copy: false);
  int _count = 0;
  Uint8List? _bytes;

  /// Entities written so far.
  int get count => _count;

  void add(SyncEntity entity, EntityFieldVersions versions) {
    if (_bytes != null) throw StateError('The backup document is finished');
    if (_count > 0) _out.add(_comma);
    _out.add(
      _encoder.convert({
        'kind': entity.kind.name,
        'data': entity.toJson(),
        'versions': versions.toJson(),
      }),
    );
    _count++;
  }

  /// The document (closes the entity list on the first call).
  Uint8List finish() {
    final done = _bytes;
    if (done != null) return done;
    _out.add(_end);
    return _bytes = _out.takeBytes();
  }
}
