// lib/src/indexer/page_queue.dart — (internal) the indexer's page queue
// (m5-7/05-library 6.9.2): requeued pages first (a job dropped by a
// handwriting change, or ModelNotReady), then pages whose quiet time ended,
// then catch-up pages (6.9.5). One entry per page; a page added again keeps
// the better of its two places.
import 'package:note_core/note_core.dart' as core;

/// Where a page joins the queue (best first).
enum QueueLane { front, ready, catchUp }

typedef QueuedPage = ({core.NoteId noteId, core.PageId pageId, QueueLane lane});

final class PageQueue {
  final List<QueuedPage> _items = [];

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool contains(core.PageId pageId) => _indexOf(pageId) >= 0;

  /// Page ids in queue order (tests, the developer overlay).
  List<core.PageId> get pageIds => [for (final e in _items) e.pageId];

  int _indexOf(core.PageId pageId) =>
      _items.indexWhere((e) => e.pageId == pageId);

  /// [QueueLane.front] → first of all; [QueueLane.ready] → after the front
  /// and ready pages; [QueueLane.catchUp] → last. A queued page moves only
  /// to a better lane (a requeued page moves to the very front).
  void add(core.NoteId noteId, core.PageId pageId, QueueLane lane) {
    final at = _indexOf(pageId);
    if (at >= 0) {
      final old = _items[at].lane;
      if (lane != QueueLane.front && old.index <= lane.index) return;
      _items.removeAt(at);
    }
    final entry = (noteId: noteId, pageId: pageId, lane: lane);
    switch (lane) {
      case QueueLane.front:
        _items.insert(0, entry);
      case QueueLane.ready:
        final firstCatchUp = _items.indexWhere(
          (e) => e.lane == QueueLane.catchUp,
        );
        _items.insert(firstCatchUp < 0 ? _items.length : firstCatchUp, entry);
      case QueueLane.catchUp:
        _items.add(entry);
    }
  }

  /// Removes [pageId]; true when it was queued.
  bool remove(core.PageId pageId) {
    final at = _indexOf(pageId);
    if (at < 0) return false;
    _items.removeAt(at);
    return true;
  }

  QueuedPage? takeFirst() => _items.isEmpty ? null : _items.removeAt(0);

  void clear() => _items.clear();
}
