// lib/src/storage/drift_settings_repository.dart (internal) — SettingsRepository on
// SQLite (CORE 4.5, 7.4.6).
//
// synced scope: the `settings` table (+ outbox, EntityKind.setting); reset() is a
// soft delete (deleted_at, 6.10.2). device scope: kv['setting.<name>'] (no outbox).
// Values are stored as jsonEncode(key.encode(value)); a value that fails to decode
// reads as the key's default.
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';

import '../model/asset.dart';
import '../model/sync_entity.dart';
import '../repo/settings_internal.dart';
import '../repo/settings_repository.dart';
import '../sync/outbox_types.dart';
import 'db/note_database.dart';
import 'drift_note_store.dart';
import 'entity_diff.dart';
import 'kv_keys.dart';
import 'row_mappers.dart';
import 'watch_hub.dart';

const DeepCollectionEquality _deep = DeepCollectionEquality();

String _kvKey(String name) => '${KvKeys.settingPrefix}$name';

Object? _decodeJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null; // a damaged value reads as the default
  }
}

final class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this.s);
  final DriftNoteStore s;

  NoteDatabase get _db => s.db;

  Future<SettingRow?> _syncedRow(String name) => (_db.select(
    _db.settings,
  )..where((t) => t.key.equals(name))).getSingleOrNull();

  Future<String?> _deviceText(String name) async {
    final r = await (_db.select(
      _db.kv,
    )..where((t) => t.key.equals(_kvKey(name)))).getSingleOrNull();
    return r?.value;
  }

  Future<Object?> _raw<T>(SettingKey<T> key) async {
    if (key.scope == SettingScope.device) {
      final text = await _deviceText(key.name);
      return text == null ? null : _decodeJson(text);
    }
    final r = await _syncedRow(key.name);
    return r == null || r.deletedAt != null ? null : _decodeJson(r.valueJson);
  }

  Future<T> _value<T>(SettingKey<T> key) async =>
      decodeSetting(key, await _raw(key));

  bool Function(CommitTouch) _affects<T>(SettingKey<T> key) =>
      key.scope == SettingScope.device
      ? (t) => t.kvKeys.contains(_kvKey(key.name))
      : (t) => t.kinds.contains(EntityKind.setting);

  @override
  Future<T> get<T>(SettingKey<T> key) async {
    checkSettingKeyName(key.name);
    return _value(key);
  }

  @override
  Stream<T> watch<T>(SettingKey<T> key) {
    checkSettingKeyName(key.name);
    return s.watches.watch(
      affects: _affects(key),
      query: () => _value(key),
      equals: (a, b) => _deep.equals(a, b),
    );
  }

  @override
  Future<void> set<T>(SettingKey<T> key, T value) async {
    checkSettingKeyName(key.name);
    final String json;
    try {
      json = jsonEncode(key.encode(value));
    } on Object catch (e) {
      throw ArgumentError.value(value, 'value', 'not JSON-encodable: $e');
    }
    return s.queue.run((tx) async {
      if (key.scope == SettingScope.device) {
        await _db
            .into(_db.kv)
            .insertOnConflictUpdate(
              KvCompanion.insert(key: _kvKey(key.name), value: json),
            );
        tx.touchKv(_kvKey(key.name));
        return;
      }
      final row = await _syncedRow(key.name);
      if (row == null) {
        await tx.putLocal(
          SettingValue(key: key.name, valueJson: json, updatedAt: tx.now),
          const {kAllFields},
          isNew: true,
        );
        return;
      }
      final cur = settingOf(row);
      final next = cur.copyWith(valueJson: json, clearDeletedAt: true);
      final fields = changedJsonKeys(cur, next);
      if (fields.isEmpty) return;
      await tx.putLocal(next.copyWith(updatedAt: tx.now), fields);
    });
  }

  @override
  Future<void> reset<T>(SettingKey<T> key) async {
    checkSettingKeyName(key.name);
    return s.queue.run((tx) async {
      if (key.scope == SettingScope.device) {
        await (_db.delete(
          _db.kv,
        )..where((t) => t.key.equals(_kvKey(key.name)))).go();
        tx.touchKv(_kvKey(key.name));
        return;
      }
      final row = await _syncedRow(key.name);
      if (row == null || row.deletedAt != null) return;
      final cur = settingOf(row);
      await tx.putLocal(cur.copyWith(deletedAt: tx.now, updatedAt: tx.now), {
        'deletedAt',
      });
    });
  }

  Future<SettingsSnapshot> _snapshot() async {
    final synced = await (_db.select(
      _db.settings,
    )..where((t) => t.deletedAt.isNull())).get();
    final device = await (_db.select(
      _db.kv,
    )..where((t) => t.key.like('${KvKeys.settingPrefix}%'))).get();
    return SettingsSnapshot(
      Map.unmodifiable({
        for (final r in synced) r.key: _decodeJson(r.valueJson),
        for (final r in device)
          r.key.substring(KvKeys.settingPrefix.length): _decodeJson(r.value),
      }),
    );
  }

  @override
  Stream<SettingsSnapshot> watchAll() => s.watches.watch(
    affects: (CommitTouch t) =>
        t.kinds.contains(EntityKind.setting) ||
        t.kvKeys.any((k) => k.startsWith(KvKeys.settingPrefix)),
    query: _snapshot,
  );
}
