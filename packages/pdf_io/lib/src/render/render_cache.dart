// lib/src/render/render_cache.dart — 06-pdf 6.7.4 (PDF T8, contract 7.4.10). Internal.
//
// Rendered images by key with reference counts and a byte budget per kind (preview / tile /
// thumbnail). An image in use (reference > 0 — in a handle's snapshot) is never removed;
// when in-use images alone exceed a budget the excess shows in overBudgetBytes. Unused images
// leave in LRU order when their kind is over budget; unused tiles also leave 30 s after their
// last use (checked every 5 s); trimMemory() drops every unused image.
import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../tuning.dart';
import 'tile_math.dart';

/// (assetId, pageIndex, kind, scale, tileX, tileY) of 6.7.4, plus the background color the
/// image was rendered on (the same page on another paper color is another image).
typedef PdfRenderKey = ({
  String assetId,
  int pageIndex,
  PdfRenderKind kind,
  double scale,
  int tileX,
  int tileY,
  int backgroundArgb,
});

/// One reference to a cached image. The cache owns the image — never dispose it.
final class PdfCacheLease {
  PdfCacheLease._(this._cache, this._entry);

  final PdfRenderCache _cache;
  final _CacheEntry _entry;
  bool _released = false;

  PdfRenderKey get key => _entry.key;
  ui.Image get image => _entry.image;
  bool get isReleased => _released;

  /// Idempotent. [dropIfUnused]: remove (and dispose) the image at once when this was its
  /// last reference (6.7.6: tiles of an unmounted page) instead of keeping it in the LRU.
  void release({bool dropIfUnused = false}) {
    if (_released) return;
    _released = true;
    _cache._release(_entry, dropIfUnused: dropIfUnused);
  }
}

final class _CacheEntry {
  _CacheEntry(this.key, this.image) : bytes = image.width * image.height * 4;
  final PdfRenderKey key;
  final ui.Image image;
  final int bytes;
  int refs = 0;

  /// PdfRenderCache trim tick at which the reference count became 0.
  int idleSinceTick = 0;
}

final class PdfRenderCache {
  PdfRenderCache({
    required this._budget,
    this._idleTileTtl = PdfTuning.idleTileTtl,
    this._trimInterval = PdfTuning.trimInterval,
    this._onChanged,
  });

  final PdfRenderBudget _budget;
  final Duration _idleTileTtl;
  final Duration _trimInterval;
  final VoidCallback? _onChanged;

  /// Insertion / last-use order = LRU order (oldest first).
  final LinkedHashMap<PdfRenderKey, _CacheEntry> _entries =
      LinkedHashMap<PdfRenderKey, _CacheEntry>();
  final Map<PdfRenderKind, int> _bytes = {
    for (final kind in PdfRenderKind.values) kind: 0,
  };
  Timer? _trimTimer;
  int _tick = 0;
  bool _disposed = false;

  PdfRenderBudget get budget => _budget;

  int bytesOf(PdfRenderKind kind) => _bytes[kind]!;
  int get liveImages => _entries.length;
  bool contains(PdfRenderKey key) => _entries.containsKey(key);

  /// Bytes by which in-use images exceed their kind's budget (sum over kinds).
  int get overBudgetBytes {
    var over = 0;
    for (final kind in PdfRenderKind.values) {
      final excess = bytesOf(kind) - _budgetOf(kind);
      if (excess > 0) over += excess;
    }
    return over;
  }

  /// References of [key] (0 when unused or absent) — diagnostics and tests.
  int refsOf(PdfRenderKey key) => _entries[key]?.refs ?? 0;

  /// A new reference to the cached image, or null when absent. Marks it most recently used.
  PdfCacheLease? take(PdfRenderKey key) {
    final entry = _entries[key];
    if (entry == null) return null;
    return _retain(entry);
  }

  /// Stores [image] (the cache takes ownership) and returns a reference to it. When [key]
  /// is already cached (two renders of one image), [image] is disposed and the cached one
  /// is returned. After dispose() the image is disposed and the lease is already released.
  PdfCacheLease put(PdfRenderKey key, ui.Image image) {
    final existing = _entries[key];
    if (existing != null) {
      if (!identical(existing.image, image)) image.dispose();
      return _retain(existing);
    }
    final entry = _CacheEntry(key, image);
    if (_disposed) {
      image.dispose();
      return PdfCacheLease._(this, entry).._released = true;
    }
    _entries[key] = entry;
    _bytes[key.kind] = bytesOf(key.kind) + entry.bytes;
    final lease = _retain(entry);
    _evict(key.kind);
    _onChanged?.call();
    return lease;
  }

  /// Drops every unused image (tab hidden, memory pressure).
  void trimMemory() {
    final unused = [
      for (final entry in _entries.values)
        if (entry.refs == 0) entry,
    ];
    if (unused.isEmpty) return;
    unused.forEach(_remove);
    _syncTrimTimer();
    _onChanged?.call();
  }

  /// Disposes every image, in use or not. Leases stay valid objects; their release is a
  /// no-op.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _trimTimer?.cancel();
    _trimTimer = null;
    for (final entry in _entries.values.toList()) {
      _remove(entry);
    }
    _onChanged?.call();
  }

  int _budgetOf(PdfRenderKind kind) => switch (kind) {
    PdfRenderKind.preview => _budget.previewBytes,
    PdfRenderKind.tile => _budget.tileBytes,
    PdfRenderKind.thumbnail => _budget.thumbnailBytes,
  };

  PdfCacheLease _retain(_CacheEntry entry) {
    entry.refs++;
    _touch(entry);
    if (entry.refs == 1 && entry.key.kind == PdfRenderKind.tile) {
      _syncTrimTimer();
    }
    return PdfCacheLease._(this, entry);
  }

  void _release(_CacheEntry entry, {required bool dropIfUnused}) {
    if (!identical(_entries[entry.key], entry)) return; // removed already
    entry.refs--;
    if (entry.refs > 0) return;
    entry.idleSinceTick = _tick;
    if (dropIfUnused) {
      _remove(entry);
    } else {
      _touch(entry);
      _evict(entry.key.kind);
    }
    _syncTrimTimer();
    _onChanged?.call();
  }

  void _touch(_CacheEntry entry) {
    _entries.remove(entry.key);
    _entries[entry.key] = entry;
  }

  /// Unused images of [kind] leave in LRU order while the kind is over budget.
  void _evict(PdfRenderKind kind) {
    if (bytesOf(kind) <= _budgetOf(kind)) return;
    for (final entry in _entries.values.toList()) {
      if (bytesOf(kind) <= _budgetOf(kind)) return;
      if (entry.key.kind == kind && entry.refs == 0) _remove(entry);
    }
  }

  void _remove(_CacheEntry entry) {
    _entries.remove(entry.key);
    _bytes[entry.key.kind] = bytesOf(entry.key.kind) - entry.bytes;
    entry.image.dispose();
  }

  bool get _hasIdleTiles => _entries.values.any(
    (e) => e.refs == 0 && e.key.kind == PdfRenderKind.tile,
  );

  /// The 5 s trim timer runs only while unused tiles exist (no idle periodic timer).
  void _syncTrimTimer() {
    if (_disposed) return;
    if (_hasIdleTiles) {
      _trimTimer ??= Timer.periodic(_trimInterval, (_) => _trimIdleTiles());
    } else {
      _trimTimer?.cancel();
      _trimTimer = null;
    }
  }

  /// An unused tile leaves once more than idleTileTtl has passed since its last use
  /// (tick granularity: it stays at least the TTL).
  void _trimIdleTiles() {
    _tick++;
    final ttlTicks = _idleTileTtl.inMicroseconds / _trimInterval.inMicroseconds;
    final expired = [
      for (final entry in _entries.values)
        if (entry.refs == 0 &&
            entry.key.kind == PdfRenderKind.tile &&
            _tick - entry.idleSinceTick > ttlTicks)
          entry,
    ];
    expired.forEach(_remove);
    _syncTrimTimer();
    if (expired.isNotEmpty) _onChanged?.call();
  }
}
