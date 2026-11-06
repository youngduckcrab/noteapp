// Internal (not exported). The permanent-deletion set (6.7.4): stored purges
// (`sync.purged.0` … `sync.purged.4`, 6.6.6) plus an in-memory view of unsent local purges
// (the outbox's op purge entries — never written to meta, the outbox is the source).
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:note_core/note_core.dart';

import '../engine/meta_keys.dart';
import '../model/records.dart';

final class PurgedSet {
  /// [localChanges] (SyncLocalStore.localChanges) marks the local view stale (6.7.4 ②).
  PurgedSet({
    required this.sync,
    Stream<void>? localChanges,
    this.retention = const Duration(days: 400),
    this.maxPerKey = 2000,
    this.outboxPageSize = 500,
  }) {
    _subscription = localChanges?.listen((_) => _stale = true);
  }

  static const int keyCount = 5;

  final SyncStore sync;

  /// Stored entries older than this (by purge HLC) are dropped when their key is rewritten.
  final Duration retention;

  /// Entries per meta key (≈ 170 KB, under the 256 KiB meta limit).
  final int maxPerKey;
  final int outboxPageSize;

  StreamSubscription<void>? _subscription;

  /// Per key: `"<kind>:<id>"` → purge HLC text.
  final List<Map<String, String>> _stored = [
    for (var i = 0; i < keyCount; i++) <String, String>{},
  ];
  Set<EntityRef> _local = {};
  bool _stale = true;

  /// The local view must be read again before the next apply (6.6.3 step 4).
  bool get isStale => _stale;

  void markStale() => _stale = true;

  /// Stored set ∪ unsent local purges.
  bool contains(EntityRef ref) => isStored(ref) || _local.contains(ref);

  bool isStored(EntityRef ref) =>
      _stored[keyIndexOf(ref)].containsKey(refText(ref));

  /// Unsent local purges (outbox view).
  Set<EntityRef> get local => Set.unmodifiable(_local);

  int get storedCount => _stored.fold(0, (sum, m) => sum + m.length);

  /// `"<kind>:<id>"` — the stored key text.
  static String refText(EntityRef ref) => '${ref.kind.name}:${ref.id}';

  /// First byte of sha-256(refText) % 5.
  static int keyIndexOf(EntityRef ref) =>
      sha256.convert(utf8.encode(refText(ref))).bytes.first % keyCount;

  /// Reads the stored keys, then the local view (6.10.3 step 6 — before receiving).
  Future<void> load() async {
    for (var i = 0; i < keyCount; i++) {
      _stored[i] = _decode(await sync.readMeta(MetaKeys.purged[i]));
    }
    await refreshLocal();
  }

  /// Reads the whole outbox (afterSeq paging) and keeps its op purge entries (6.7.4).
  Future<void> refreshLocal() async {
    _stale = false;
    final local = <EntityRef>{};
    int? afterSeq;
    while (true) {
      final page = await sync.pendingChanges(
        limit: outboxPageSize,
        afterSeq: afterSeq,
      );
      for (final e in page) {
        if (e.op == OutboxOp.purge) local.add(e.ref);
      }
      if (page.length < outboxPageSize) break;
      afterSeq = page.last.seq;
    }
    _local = local;
  }

  /// 6.6.3 step 4.
  Future<void> refreshIfStale() async {
    if (_stale) await refreshLocal();
  }

  /// The meta updates (changed keys only) that store [records] too. Memory is unchanged
  /// until [absorb] — the caller writes them in its apply transaction first.
  Map<String, String> updatesFor(
    Iterable<PurgeRecord> records, {
    required int nowMillis,
  }) {
    final changed = <int, Map<String, String>>{};
    for (final r in records) {
      final i = keyIndexOf(r.ref);
      final map = changed[i] ??= Map.of(_stored[i]);
      final text = refText(r.ref);
      final old = map[text];
      final hlc = r.hlc.toString();
      if (old == null || Hlc.parse(old) < r.hlc) map[text] = hlc;
    }
    return {
      for (final MapEntry(key: i, value: map) in changed.entries)
        if (_encode(_trimmed(map, nowMillis)) case final text
            when text != _encode(_stored[i]))
          MetaKeys.purged[i]: text,
    };
  }

  /// Takes the purged keys of [updates] (already persisted) into memory.
  void absorb(Map<String, String> updates) {
    for (var i = 0; i < keyCount; i++) {
      final text = updates[MetaKeys.purged[i]];
      if (text != null) _stored[i] = _decode(text);
    }
  }

  /// Purges this device committed to the server (UploadPipeline.onPurgesCommitted, 6.5.2).
  Future<void> addCommitted(
    List<PurgeRecord> purges, {
    required int nowMillis,
  }) async {
    final updates = updatesFor(purges, nowMillis: nowMillis);
    if (updates.isEmpty) return;
    await sync.writeMeta(updates);
    absorb(updates);
  }

  /// Stops following local purges. The cancel is not awaited: a broadcast subscription's
  /// cancel Future is completed in the root zone, which would hold dispose (and the engine's
  /// session close after it) in any other zone — fake_async's included (S2-4b).
  Future<void> dispose() async {
    final cancel = _subscription?.cancel();
    _subscription = null;
    if (cancel != null) unawaited(cancel);
  }

  /// Drops entries older than [retention], then keeps the newest [maxPerKey].
  Map<String, String> _trimmed(Map<String, String> map, int nowMillis) {
    final oldest = nowMillis - retention.inMilliseconds;
    final list = [
      for (final MapEntry(:key, :value) in map.entries)
        if (_millisOf(value) >= oldest) (key, value),
    ];
    if (list.length > maxPerKey) {
      list.sort((a, b) {
        final byHlc = _hlcOf(b.$2).compareTo(_hlcOf(a.$2));
        return byHlc != 0 ? byHlc : a.$1.compareTo(b.$1);
      });
      list.removeRange(maxPerKey, list.length);
    }
    return {for (final (k, v) in list) k: v};
  }

  static Hlc _hlcOf(String text) => Hlc.parse(text);

  static int _millisOf(String text) {
    try {
      return Hlc.parse(text).millis;
    } on FormatException {
      return 0;
    }
  }

  static String _encode(Map<String, String> map) {
    final keys = map.keys.toList()..sort();
    return jsonEncode({for (final k in keys) k: map[k]});
  }

  /// Tolerant: malformed values or entries are dropped.
  static Map<String, String> _decode(String? text) {
    final value = MetaKeys.present(text);
    if (value == null) return {};
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, Object?>) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (value is String && Hlc.tryParse(value) != null) key: value,
      };
    } on FormatException {
      return {};
    }
  }
}
