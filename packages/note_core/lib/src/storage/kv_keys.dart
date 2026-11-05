// lib/src/storage/kv_keys.dart (internal) — CORE 6.11 `kv` table keys.

abstract final class KvKeys {
  /// 16 lowercase hex chars, created on first open (HLC node of local writes).
  static const String deviceNodeId = 'device.nodeId';

  /// Last HLC text, written by every write transaction (6.4).
  static const String hlcLast = 'hlc.last';

  /// Current owner: config.ownerId when the database is created, then reassignOwner.
  static const String ownerId = 'store.ownerId';

  /// '1' once the default pen presets were created (6.2.2).
  static const String seedPresetsV1 = 'seed.presets.v1';

  /// `setting.<name>`: device-scope settings (JSON).
  static const String settingPrefix = 'setting.';

  /// `sync.*`: SYNC meta (readMeta / writeMeta / applyRemote metaUpdates only).
  static const String syncPrefix = 'sync.';
}

final RegExp _nodeIdPattern = RegExp(r'^[0-9a-f]{16}$');

/// A device node id as stored in kv: 16 lowercase hex chars.
bool isValidNodeId(String value) => _nodeIdPattern.hasMatch(value);
