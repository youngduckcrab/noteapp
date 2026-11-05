// lib/src/model/asset.dart, recording.dart, setting_value.dart — contract 00-overview 7.2.6 /
// CORE 4.2.4.
import 'package:meta/meta.dart';

import '../common/hlc.dart';
import '../common/ids.dart';
import '../common/json_read.dart';
import 'sync_entity.dart';

enum AssetType { pdf, image, audio }

@immutable
final class Asset implements SyncEntity {
  const Asset({
    required this.id,
    required this.ownerId,
    required this.type,
    required this.mimeType,
    required this.size,
    this.fileName,
    required this.createdAt,
    this.storagePath,
    this.deletedAt,
    this.version,
    this.hasLocalBytes = true,
  });

  @override
  final AssetId id; // sha-256 hex of the bytes
  final OwnerId ownerId;
  final AssetType type;
  final String mimeType;
  final int size; // bytes
  final String? fileName; // original name, display only
  final EpochMillis createdAt;
  final String? storagePath; // remote path, set by SYNC after upload
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;

  /// Local only, never in JSON. The constructor default (true) is for AssetStore.put.
  /// Remote / repair writes keep the current row value (new row: whether the blob store
  /// holds every chunk) — 7.2.10 v1.1, 6.10.3.
  final bool hasLocalBytes;
  @override
  EntityKind get kind => EntityKind.asset;
  @override
  bool get isDeleted => deletedAt != null;

  Asset copyWith({
    OwnerId? ownerId,
    String? fileName,
    String? storagePath,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
    bool? hasLocalBytes,
  }) => Asset(
    id: id,
    ownerId: ownerId ?? this.ownerId,
    type: type,
    mimeType: mimeType,
    size: size,
    fileName: fileName ?? this.fileName,
    createdAt: createdAt,
    storagePath: storagePath ?? this.storagePath,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
    hasLocalBytes: hasLocalBytes ?? this.hasLocalBytes,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'type': type.name,
    'mimeType': mimeType,
    'size': size,
    'fileName': fileName,
    'storagePath': storagePath,
    'createdAt': createdAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  /// hasLocalBytes is always false here (no evidence the bytes are on this device, 6.3).
  factory Asset.fromJson(Map<String, Object?> json) {
    final typeName = readString(json, 'type');
    return Asset(
      id: readString(json, 'id'),
      ownerId: readString(json, 'ownerId'),
      type: AssetType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => throw FormatException('Unknown asset type', typeName),
      ),
      mimeType: readString(json, 'mimeType'),
      size: readInt(json, 'size'),
      fileName: readStringOrNull(json, 'fileName'),
      createdAt: readInt(json, 'createdAt'),
      storagePath: readStringOrNull(json, 'storagePath'),
      deletedAt: readIntOrNull(json, 'deletedAt'),
      version: readVersion(json),
      hasLocalBytes: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Asset &&
      other.id == id &&
      other.ownerId == ownerId &&
      other.type == type &&
      other.mimeType == mimeType &&
      other.size == size &&
      other.fileName == fileName &&
      other.createdAt == createdAt &&
      other.storagePath == storagePath &&
      other.deletedAt == deletedAt &&
      other.version == version &&
      other.hasLocalBytes == hasLocalBytes;

  @override
  int get hashCode => Object.hash(
    id,
    ownerId,
    type,
    mimeType,
    size,
    fileName,
    createdAt,
    storagePath,
    deletedAt,
    version,
    hasLocalBytes,
  );

  @override
  String toString() => 'Asset($id, ${type.name}, $size B)';
}

@immutable
final class Recording implements SyncEntity {
  // feature in M6; schema now
  const Recording({
    required this.id,
    required this.noteId,
    required this.assetId,
    required this.durationMs,
    required this.startedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version,
  });

  @override
  final RecordingId id;
  final NoteId noteId;
  final AssetId assetId;
  final int durationMs;
  final EpochMillis startedAt;
  final EpochMillis createdAt, updatedAt;
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;
  @override
  EntityKind get kind => EntityKind.recording;
  @override
  bool get isDeleted => deletedAt != null;

  Recording copyWith({
    int? durationMs,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => Recording(
    id: id,
    noteId: noteId,
    assetId: assetId,
    durationMs: durationMs ?? this.durationMs,
    startedAt: startedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  @override
  Map<String, Object?> toJson() => {
    'id': id,
    'noteId': noteId,
    'assetId': assetId,
    'durationMs': durationMs,
    'startedAt': startedAt,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  factory Recording.fromJson(Map<String, Object?> json) => Recording(
    id: readString(json, 'id'),
    noteId: readString(json, 'noteId'),
    assetId: readString(json, 'assetId'),
    durationMs: readInt(json, 'durationMs'),
    startedAt: readInt(json, 'startedAt'),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

  @override
  bool operator ==(Object other) =>
      other is Recording &&
      other.id == id &&
      other.noteId == noteId &&
      other.assetId == assetId &&
      other.durationMs == durationMs &&
      other.startedAt == startedAt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode => Object.hash(
    id,
    noteId,
    assetId,
    durationMs,
    startedAt,
    createdAt,
    updatedAt,
    deletedAt,
    version,
  );

  @override
  String toString() => 'Recording($id, note: $noteId, ${durationMs}ms)';
}

/// One synced setting. id == key.
@immutable
final class SettingValue implements SyncEntity {
  const SettingValue({
    required this.key,
    required this.valueJson,
    required this.updatedAt,
    this.deletedAt,
    this.version,
  });

  final String key;
  final String valueJson; // jsonEncode'd value
  final EpochMillis updatedAt;
  @override
  String get id => key;
  @override
  final EpochMillis? deletedAt;
  @override
  final Hlc? version;
  @override
  EntityKind get kind => EntityKind.setting;
  @override
  bool get isDeleted => deletedAt != null;

  SettingValue copyWith({
    String? valueJson,
    EpochMillis? updatedAt,
    EpochMillis? deletedAt,
    bool clearDeletedAt = false,
    Hlc? version,
  }) => SettingValue(
    key: key,
    valueJson: valueJson ?? this.valueJson,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    version: version ?? this.version,
  );

  @override
  Map<String, Object?> toJson() => {
    'key': key,
    'valueJson': valueJson,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'version': version?.toString(),
  };

  factory SettingValue.fromJson(Map<String, Object?> json) => SettingValue(
    key: readString(json, 'key'),
    valueJson: readString(json, 'valueJson'),
    updatedAt: readInt(json, 'updatedAt'),
    deletedAt: readIntOrNull(json, 'deletedAt'),
    version: readVersion(json),
  );

  @override
  bool operator ==(Object other) =>
      other is SettingValue &&
      other.key == key &&
      other.valueJson == valueJson &&
      other.updatedAt == updatedAt &&
      other.deletedAt == deletedAt &&
      other.version == version;

  @override
  int get hashCode =>
      Object.hash(key, valueJson, updatedAt, deletedAt, version);

  @override
  String toString() => 'SettingValue($key = $valueJson)';
}
