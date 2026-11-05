// Internal (not exported). Chunks with records held back by K1 (6.2.5): the value of
// `sync.held` (6.6.6) — {chunkId: releaseAtMillis}, or over maxEntries the collapsed form
// {"*": [serverTimeMicros of the earliest held chunk, latest releaseAtMillis]}.
import 'dart:convert';

import '../common/server_cursor.dart';
import 'meta_keys.dart';

/// The collapsed form: once the reference time reaches [releaseAtMillis], the cursor goes
/// back to [from] − cursorOverlap and everything after it is received again (K2).
typedef CollapsedHold = ({ServerCursor from, int releaseAtMillis});

final class HeldChunks {
  HeldChunks({this.maxEntries = 2000}) : _entries = {}, _serverTimes = {};

  HeldChunks._(
    this.maxEntries,
    this._entries,
    this._serverTimes,
    this._collapsed,
  );

  /// SyncConfig.maxHeldChunks.
  final int maxEntries;

  final Map<String, int> _entries;
  final Map<String, ServerCursor> _serverTimes;
  CollapsedHold? _collapsed;

  static const String _collapsedKey = '*';

  /// Tolerant: an absent or malformed value is empty.
  factory HeldChunks.decode(String? text, {int maxEntries = 2000}) {
    final empty = HeldChunks(maxEntries: maxEntries);
    final value = MetaKeys.present(text);
    if (value == null) return empty;
    final Object? json;
    try {
      json = jsonDecode(value);
    } on FormatException {
      return empty;
    }
    if (json is! Map<String, Object?>) return empty;
    CollapsedHold? collapsed;
    final entries = <String, int>{};
    for (final MapEntry(:key, :value) in json.entries) {
      if (key == _collapsedKey) {
        if (value case [final int from, final int releaseAt]) {
          collapsed = (from: ServerCursor(from), releaseAtMillis: releaseAt);
        }
      } else if (value is int) {
        entries[key] = value;
      }
    }
    return HeldChunks._(maxEntries, entries, {}, collapsed);
  }

  HeldChunks copy() => HeldChunks._(
    maxEntries,
    Map.of(_entries),
    Map.of(_serverTimes),
    _collapsed,
  );

  bool get isEmpty => _entries.isEmpty && _collapsed == null;

  /// chunkId → releaseAtMillis.
  Map<String, int> get entries => Map.unmodifiable(_entries);

  CollapsedHold? get collapsed => _collapsed;

  bool contains(String chunkId) => _entries.containsKey(chunkId);

  /// Authors of the held chunks (the chunk id starts with the author node, 6.4.5): the
  /// nodeIds of the clockSkew issues (K1). Empty for the collapsed form alone.
  Set<String> get authorNodes => {
    for (final id in _entries.keys)
      if (id.indexOf('-') case final dash when dash > 0) id.substring(0, dash),
  };

  /// Holds [chunkId] until [releaseAtMillis] (replacing an earlier value). While collapsed,
  /// widens the collapsed range instead.
  void hold(String chunkId, ServerCursor serverTime, int releaseAtMillis) {
    final c = _collapsed;
    if (c != null) {
      _collapsed = (
        from: serverTime < c.from ? serverTime : c.from,
        releaseAtMillis: releaseAtMillis > c.releaseAtMillis
            ? releaseAtMillis
            : c.releaseAtMillis,
      );
      return;
    }
    _entries[chunkId] = releaseAtMillis;
    _serverTimes[chunkId] = serverTime;
    if (_entries.length > maxEntries) _collapse();
  }

  /// Forgets [chunkId] (all its records applied, or the chunk is gone). True if it was held.
  bool release(String chunkId) {
    _serverTimes.remove(chunkId);
    return _entries.remove(chunkId) != null;
  }

  /// Held chunk ids whose release time has come: g' ≥ releaseAt (K2).
  List<String> dueIds(int referenceMillis) => [
    for (final MapEntry(:key, :value) in _entries.entries)
      if (referenceMillis >= value) key,
  ]..sort();

  /// The collapsed hold is due (K2, collapsed form).
  bool isCollapsedDue(int referenceMillis) {
    final c = _collapsed;
    return c != null && referenceMillis >= c.releaseAtMillis;
  }

  void clearCollapsed() => _collapsed = null;

  /// Sorted JSON text for `sync.held`.
  String encode() {
    final c = _collapsed;
    if (c != null) {
      return jsonEncode({
        _collapsedKey: [c.from.micros, c.releaseAtMillis],
      });
    }
    final keys = _entries.keys.toList()..sort();
    return jsonEncode({for (final k in keys) k: _entries[k]});
  }

  /// Over maxEntries: one entry for everything. A chunk read back from meta has no known
  /// serverTime; then the range starts at zero (receive everything again — only after more
  /// than maxEntries holds, and correct either way).
  void _collapse() {
    var from = ServerCursor(_maxSafe);
    var releaseAt = 0;
    for (final MapEntry(:key, :value) in _entries.entries) {
      final t = _serverTimes[key] ?? ServerCursor.zero;
      if (t < from) from = t;
      if (value > releaseAt) releaseAt = value;
    }
    _entries.clear();
    _serverTimes.clear();
    _collapsed = (from: from, releaseAtMillis: releaseAt);
  }

  static const int _maxSafe = 9007199254740991;
}
