// Internal (not exported). SYNC meta keys (6.6.6) and the scope statistics value.
// Every key starts with 'sync.' and every value stays under 256 KiB (contract 7.2.10).
import 'dart:convert';

abstract final class MetaKeys {
  static const String boundUid = 'sync.boundUid';

  /// ServerCursor text (6.6.2).
  static const String cursor = 'sync.cursor';

  /// sync.purged.0 … sync.purged.4 (6.7.4, PurgedSet).
  static const List<String> purged = [
    'sync.purged.0',
    'sync.purged.1',
    'sync.purged.2',
    'sync.purged.3',
    'sync.purged.4',
  ];

  /// ScopeStats JSON.
  static const String scopeStats = 'sync.scopeStats';

  /// HeldChunks JSON (6.2.5 K1/K2).
  static const String held = 'sync.held';

  /// 6.6.5: earliest serverTime of a chunk in a newer format, and the codec format of the
  /// app that deferred it.
  static const String deferredFrom = 'sync.deferredFrom';
  static const String deferredFormat = 'sync.deferredFormat';

  static const String lastProfileAt = 'sync.lastProfileAt';

  /// SyncStore.writeMeta cannot delete a key: SYNC writes '' and reads '' as absent.
  static const String cleared = '';

  /// null for an absent or cleared value.
  static String? present(String? value) =>
      value == null || value == cleared ? null : value;
}

/// `sync.scopeStats` (6.6.6): per scope, the number of chunks this device has seen since the
/// last compaction (n) and when it last compacted the scope (c, epoch ms). Input of the
/// compaction trigger (6.13). At most [maxScopes] scopes are kept; the smallest n go first.
final class ScopeStats {
  ScopeStats._(this._entries);

  ScopeStats() : this._({});

  static const int maxScopes = 3000;

  final Map<String, ({int n, int c})> _entries;

  /// Tolerant: an absent or malformed value is empty (only the trigger is delayed).
  factory ScopeStats.decode(String? text) {
    final value = MetaKeys.present(text);
    if (value == null) return ScopeStats();
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, Object?>) return ScopeStats();
      final entries = <String, ({int n, int c})>{};
      for (final MapEntry(:key, :value) in json.entries) {
        if (value is! Map<String, Object?>) continue;
        final n = value['n'], c = value['c'];
        entries[key] = (n: n is int ? n : 0, c: c is int ? c : 0);
      }
      return ScopeStats._(entries);
    } on FormatException {
      return ScopeStats();
    }
  }

  ScopeStats copy() => ScopeStats._(Map.of(_entries));

  int get length => _entries.length;

  Iterable<String> get scopes => _entries.keys;

  int countOf(String scope) => _entries[scope]?.n ?? 0;

  int lastCompactedOf(String scope) => _entries[scope]?.c ?? 0;

  /// One more chunk seen in [scope].
  void addChunk(String scope) {
    final e = _entries[scope];
    _entries[scope] = (n: (e?.n ?? 0) + 1, c: e?.c ?? 0);
  }

  /// After compacting [scope] (6.13 step 5): n = 0, c = [atMillis].
  void markCompacted(String scope, int atMillis) {
    _entries[scope] = (n: 0, c: atMillis);
  }

  /// Sorted JSON; over [maxScopes] the scopes with the smallest n (then name) are dropped.
  String encode() {
    var keys = _entries.keys.toList();
    if (keys.length > maxScopes) {
      keys.sort((a, b) {
        final byN = _entries[b]!.n.compareTo(_entries[a]!.n);
        return byN != 0 ? byN : a.compareTo(b);
      });
      keys = keys.sublist(0, maxScopes);
    }
    keys.sort();
    return jsonEncode({
      for (final k in keys) k: {'n': _entries[k]!.n, 'c': _entries[k]!.c},
    });
  }
}
