// lib/src/image/raster_ledger.dart — INTERNAL (m5-7/03-ink 6.11.3, 6.22, 7.4.5 v2.1).
//
// One byte budget over several raster stores. On the web the raster tiles of
// the ink layer (RasterTileLru) and the decoded images (InkImageCache) share
// InkCachePool's ledger (rasterBudgetBytes, 96 MiB): a new tile or image
// evicts the least recently used evictable entry of EITHER store — tiles are
// always evictable (their owner draws vectors until the viewport changes),
// images only when no live picture holds them (pinned) and a picture drew them
// before (an arrived image no chunk drew yet stays — 6.11.3 'fresh'). What an
// image request may take is the budget minus what nobody may evict (pinned,
// fresh and reserved image bytes). On native there is no shared ledger: the
// tiles keep their own 128 MiB, the images an own ledger of 128 MiB.
import 'package:meta/meta.dart';

/// INTERNAL: a store whose entries count in an [InkRasterLedger].
@internal
abstract interface class RasterLedgerMember {
  /// All its bytes in the ledger.
  int get ledgerBytes;

  /// Its bytes nobody may evict now (pinned, fresh, reserved for requests in flight).
  int get heldBytes;

  /// The ledger use stamp of its least recently used entry that could be evicted now
  /// (never [keep]); null = none.
  int? oldestEvictableUse({Object? keep});

  /// Evicts that entry and tells its owner.
  void evictOldest({Object? keep});
}

/// INTERNAL: the shared budget (see the file comment).
@internal
final class InkRasterLedger {
  InkRasterLedger({required this.budgetBytes});

  final int budgetBytes;
  final List<RasterLedgerMember> _members = [];
  int _uses = 0;

  /// A new use stamp (members order their entries by it across stores).
  int nextUse() => ++_uses;

  void join(RasterLedgerMember member) {
    if (!_members.contains(member)) _members.add(member);
  }

  void leave(RasterLedgerMember member) => _members.remove(member);

  int get bytes {
    var n = 0;
    for (final m in _members) {
      n += m.ledgerBytes;
    }
    return n;
  }

  /// Bytes nobody may evict.
  int get heldBytes {
    var n = 0;
    for (final m in _members) {
      n += m.heldBytes;
    }
    return n;
  }

  /// What a new entry may take now (everything else could be evicted for it).
  int get availableBytes => budgetBytes - heldBytes;

  /// Evicts the least recently used evictable entry of any member (never [keep]) until
  /// the total fits the budget or nothing more can go.
  void trim({Object? keep}) {
    var total = bytes;
    while (total > budgetBytes) {
      RasterLedgerMember? oldest;
      int? oldestUse;
      for (final m in _members) {
        final use = m.oldestEvictableUse(keep: keep);
        if (use != null && (oldestUse == null || use < oldestUse)) {
          oldest = m;
          oldestUse = use;
        }
      }
      if (oldest == null) return;
      oldest.evictOldest(keep: keep);
      final next = bytes;
      if (next >= total) return; // nothing was freed (defensive)
      total = next;
    }
  }
}
