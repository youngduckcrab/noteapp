// lib/src/render/pinned_raster_cache.dart — INTERNAL (m5-7/03-ink 6.11.3, 6.12.3, 6.22).
//
// (T36) The budgeted raster ledger with reference counts that the formula
// rasters use (and the image decodes of T35 follow — the same rules):
// - an entry drawn by a live chunk Picture is pinned (InkRasterPin) and released
//   when that picture is dropped; pinned bytes count in the budget and a pinned
//   entry is never evicted, so the ledger is the memory the pictures really hold;
// - a new entry evicts only unpinned entries that were drawn before (pinned once,
//   released since), least recently used first, and is kept even when that is
//   not enough (the caller decided it fits — or it is the smallest bucket, which
//   is always taken, 6.11.3);
// - an entry that arrived and was not drawn yet ('fresh': its chunks pin it at
//   their next paint) is not evicted by later arrivals — otherwise a batch of
//   arrivals over the budget would evict each other before any chunk drew them
//   and every chunk would ask again (the finite re-record bound of 6.11.3).
//   Requests are reserved, so fresh bytes pass the budget only by smallest-bucket
//   overflow or by entries nobody draws any more (the page went away before its
//   next paint): only past twice the budget are the oldest fresh ones evicted;
// - availableBytes (budget − pinned − fresh − reserved for requests in flight)
//   is what a new request may take: the caller lowers the bucket until it fits.
// (T35) With an InkRasterLedger (web images: the ledger shared with the raster
// tiles, 6.11.3 / 6.22) the budget is the ledger's, a new entry evicts the least
// recently used evictable entry of any member (a tile or an image drawn before)
// and availableBytes is the ledger budget minus what no member may evict.
import 'dart:collection';

import 'package:meta/meta.dart';

import '../image/raster_ledger.dart';

/// INTERNAL (m5-7/03-ink 4.10): one hold on a cached raster — taken when a Picture draws
/// it, released when that Picture is disposed. Releasing twice is a no-op.
@internal
final class InkRasterPin {
  InkRasterPin._(this._release);

  /// A pin that holds nothing (the entry was not there).
  static final InkRasterPin none = InkRasterPin._(null);

  void Function()? _release;

  bool get isReleased => _release == null;

  void release() {
    final r = _release;
    _release = null;
    r?.call();
  }
}

/// INTERNAL: entries [K] → [V] under [budgetBytes] with pins (see the file comment).
@internal
final class PinnedRasterCache<K extends Object, V extends Object>
    implements RasterLedgerMember {
  PinnedRasterCache({
    required int budgetBytes,
    required int Function(V value) bytesOf,
    required void Function(V value) disposeValue,
    this.onEvicted,
    InkRasterLedger? ledger,
  }) : // named parameters; the fields stay private
       // ignore: prefer_initializing_formals
       _budgetBytes = budgetBytes,
       // ignore: prefer_initializing_formals
       _bytesOf = bytesOf,
       // ignore: prefer_initializing_formals
       _disposeValue = disposeValue,
       // ignore: prefer_initializing_formals
       _ledger = ledger {
    ledger?.join(this);
  }

  final int _budgetBytes;

  /// (T35) The shared ledger this cache counts in (null = its own budget).
  final InkRasterLedger? _ledger;

  /// The own budget, or the shared ledger's.
  int get budgetBytes => _ledger?.budgetBytes ?? _budgetBytes;

  /// (T35) Whether the budget is a ledger shared with other stores.
  bool get isShared => _ledger != null;
  final int Function(V value) _bytesOf;
  final void Function(V value) _disposeValue;

  /// An unpinned entry was evicted (after its value was disposed).
  final void Function(K key)? onEvicted;

  final LinkedHashMap<K, _Entry<V>> _entries = LinkedHashMap();
  int _bytes = 0;
  int _pinnedBytes = 0;
  int _freshBytes = 0;
  int _reservedBytes = 0;
  int _uses = 0;
  bool _disposed = false;

  int get length => _entries.length;
  int get bytes => _bytes;
  int get pinnedBytes => _pinnedBytes;
  int get reservedBytes => _reservedBytes;

  /// Bytes of the entries that were never pinned yet (arrived, not drawn yet).
  int get freshBytes => _freshBytes;

  /// Bytes over the budget (the smallest bucket is taken even when it does not fit).
  int get overflowBytes {
    final total = _ledger?.bytes ?? _bytes;
    return total > budgetBytes ? total - budgetBytes : 0;
  }

  /// What a new entry may take now: every entry drawn before and not pinned now could be
  /// evicted for it; the pinned ones, the fresh ones (about to be pinned) and the requests
  /// in flight ([reserve]) stay. (T35) Shared: the ledger budget minus what no member may
  /// evict (the tiles can always go).
  int get availableBytes =>
      _ledger?.availableBytes ??
      budgetBytes - _pinnedBytes - _freshBytes - _reservedBytes;

  bool fits(int bytes) => bytes <= availableBytes;

  Iterable<K> get keys => _entries.keys;

  bool containsKey(K key) => _entries.containsKey(key);

  /// The value of [key] without touching the LRU order.
  V? peek(K key) => _entries[key]?.value;

  /// The value of [key], now the most recently used.
  V? use(K key) {
    final e = _entries.remove(key);
    if (e == null) return null;
    _entries[key] = e;
    e.use = _stamp();
    return e.value;
  }

  bool isPinned(K key) => (_entries[key]?.pins ?? 0) > 0;

  /// A request of [bytes] is in flight (counted by [availableBytes] until [unreserve]).
  void reserve(int bytes) => _reservedBytes += bytes;

  void unreserve(int bytes) {
    _reservedBytes -= bytes;
    if (_reservedBytes < 0) _reservedBytes = 0;
  }

  /// Adds [value] as the most recently used entry, then evicts unpinned entries (least
  /// recently used first, never [key]) until the total fits the budget again. False (and
  /// [value] disposed) when [key] is already there or the cache is disposed.
  bool put(K key, V value) {
    if (_disposed || _entries.containsKey(key)) {
      _disposeValue(value);
      return false;
    }
    final size = _bytesOf(value);
    _entries[key] = _Entry(value, size)..use = _stamp();
    _bytes += size;
    _freshBytes += size;
    _evictToBudget(keep: key);
    return true;
  }

  /// Pins [key] (no eviction while held). [InkRasterPin.none] when it is not there.
  InkRasterPin pin(K key) {
    final e = _entries[key];
    if (e == null) return InkRasterPin.none;
    if (!e.drawn) {
      e.drawn = true;
      _freshBytes -= e.bytes;
    }
    if (e.pins++ == 0) _pinnedBytes += e.bytes;
    return InkRasterPin._(() {
      if (!identical(_entries[key], e)) return; // evicted by dispose
      if (--e.pins == 0) _pinnedBytes -= e.bytes;
    });
  }

  /// Removes and disposes [key] when it is not pinned; true when it was removed.
  bool remove(K key) {
    final e = _entries[key];
    if (e == null || e.pins > 0) return false;
    _drop(key, e);
    return true;
  }

  // --- RasterLedgerMember (T35 — only when shared) ---------------------------

  @override
  int get ledgerBytes => _bytes;

  @override
  int get heldBytes => _pinnedBytes + _freshBytes + _reservedBytes;

  @override
  int? oldestEvictableUse({Object? keep}) => _oldestEvictable(keep)?.value.use;

  @override
  void evictOldest({Object? keep}) {
    final victim = _oldestEvictable(keep);
    if (victim == null) return;
    _drop(victim.key, victim.value);
    onEvicted?.call(victim.key);
  }

  /// Drawn before, not pinned now, not [keep] — least recently used first.
  MapEntry<K, _Entry<V>>? _oldestEvictable(Object? keep) {
    for (final e in _entries.entries) {
      if (e.value.pins > 0 || !e.value.drawn || e.key == keep) continue;
      return e;
    }
    return null;
  }

  int _stamp() => _ledger?.nextUse() ?? ++_uses;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ledger?.leave(this);
    for (final e in _entries.values) {
      _disposeValue(e.value);
    }
    _entries.clear();
    _bytes = 0;
    _pinnedBytes = 0;
    _freshBytes = 0;
    _reservedBytes = 0;
  }

  void _drop(K key, _Entry<V> e) {
    _entries.remove(key);
    _bytes -= e.bytes;
    if (!e.drawn) _freshBytes -= e.bytes;
    _disposeValue(e.value);
  }

  void _evictToBudget({required K keep}) {
    final ledger = _ledger;
    if (ledger != null) {
      // the least recently used evictable entry of any member (a tile or an image)
      ledger.trim(keep: keep);
      _evictFresh(keep: keep);
      return;
    }
    final victims = <K>[];
    // drawn before, not pinned now — least recently used first
    var bytes = _bytes;
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (bytes <= budgetBytes) break;
      if (value.pins > 0 || !value.drawn || key == keep) continue;
      victims.add(key);
      bytes -= value.bytes;
    }
    // fresh entries only past twice the budget (nobody draws them any more)
    var fresh = _freshBytes;
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (fresh <= 2 * budgetBytes) break;
      if (value.drawn || key == keep) continue;
      victims.add(key);
      fresh -= value.bytes;
    }
    for (final key in victims) {
      _drop(key, _entries[key]!);
      onEvicted?.call(key);
    }
  }

  /// (shared) Fresh entries only past twice the budget (nobody draws them any more).
  void _evictFresh({required K keep}) {
    final victims = <K>[];
    var fresh = _freshBytes;
    for (final MapEntry(:key, :value) in _entries.entries) {
      if (fresh <= 2 * budgetBytes) break;
      if (value.drawn || key == keep) continue;
      victims.add(key);
      fresh -= value.bytes;
    }
    for (final key in victims) {
      _drop(key, _entries[key]!);
      onEvicted?.call(key);
    }
  }
}

final class _Entry<V> {
  _Entry(this.value, this.bytes);
  final V value;
  final int bytes;
  int pins = 0;

  /// The use stamp of the last put / use (the ledger order across stores).
  int use = 0;

  /// Pinned at least once (a picture drew it).
  bool drawn = false;
}
