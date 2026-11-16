// lib/src/thumbnails/cover_thumbnail_scheduler.dart — 05-library 6.15.3.
// Decides WHEN a note cover thumbnail is made: only for visible note tiles
// whose first page has no thumbnail or a stale one, one page at a time, the
// most recently requested tile first. Storage is CORE's ThumbnailCache, the
// drawing is the CORE slot PageThumbnailRenderer (INK behind it, wired by the
// app shell — contract 7.2.11 '썸네일 경로', 7.3.3).
import 'dart:async';
import 'dart:collection' show LinkedHashMap, LinkedHashSet;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:note_core/note_core.dart'
    show
        AssetId,
        ChangeBatch,
        ChangeOrigin,
        EntityKind,
        EpochMillis,
        FirstPageCover,
        Note,
        NoteContentReader,
        NoteId,
        PageId,
        PageThumbnailRenderer,
        ThumbnailCache;

/// What one finished check covers. Same key → no re-check until a remote batch (step 4),
/// an asset arrival (step 3) or a new note version clears it. firstPageId is part of the key
/// because a remote page reorder can change it while Note.updatedAt stays (7.2.10 v1.1).
typedef CoverCheckKey = ({EpochMillis updatedAt, PageId? firstPageId});

CoverCheckKey _keyOf(Note note) =>
    (updatedAt: note.updatedAt, firstPageId: note.firstPageId);

final class CoverThumbnailScheduler {
  /// reader / cache / renderer / assetArrivals / changes come from CORE:
  /// noteContentReaderProvider, thumbnailCacheProvider,
  /// ref.watch(pageThumbnailRendererProvider), AssetStore.bytesArrived
  /// (LIBRARY-O1) and NoteStore.changes (remote batches, step 4).
  CoverThumbnailScheduler({
    required this._reader,
    required this._cache,
    required this._renderer,
    required Stream<AssetId> assetArrivals,
    required Stream<ChangeBatch> changes,
    required this._report,
    this.startDelay = const Duration(milliseconds: 800),
    this.gap = const Duration(milliseconds: 16),
    this.remoteSettle = const Duration(milliseconds: 500),
    this.maxPending = 64,
    this.maxSidePx = 512,
  }) {
    // A disabled scheduler never does anything, so it does not listen either.
    if (_renderer == null) return;
    _assetSub = assetArrivals.listen(_onAssetArrived);
    _changesSub = changes.listen(_onBatch);
  }

  final NoteContentReader _reader;
  final ThumbnailCache _cache;
  final PageThumbnailRenderer? _renderer;
  final void Function(Object error, StackTrace stack) _report;

  /// The first job waits this long after the first request.
  final Duration startDelay;

  /// Pause between jobs (keeps frames free).
  final Duration gap;

  /// Remote batches are collected for this long after the first one, then the visible notes
  /// they touch are re-requested once (at most 2 rounds per second during a sync burst).
  final Duration remoteSettle;
  final int maxPending; // oldest requests dropped beyond this
  final int maxSidePx;

  bool get isEnabled => _renderer != null;

  StreamSubscription<AssetId>? _assetSub;
  StreamSubscription<ChangeBatch>? _changesSub;

  /// Latest version of every visible note tile (request → cancel).
  final Map<NoteId, Note> _visible = {};

  /// Key of the last finished check per note (memory only — 6.15.3 step 6).
  final Map<NoteId, CoverCheckKey> _checked = {};

  /// Waiting jobs in request order; the LAST one runs next.
  final LinkedHashMap<NoteId, Note> _queue = LinkedHashMap<NoteId, Note>();

  /// Notes to check again right after their running job (asked again, or
  /// changed remotely, while it ran).
  final Map<NoteId, Note> _rerun = {};

  /// Notes the renderer could not draw yet (null result), by the asset their
  /// first page background needs.
  final Map<AssetId, Set<NoteId>> _waitingForAsset = {};

  /// Visible notes touched by remote batches during the current settle window.
  final LinkedHashSet<NoteId> _remoteDirty = LinkedHashSet<NoteId>();

  /// Assets that arrived while the current job ran (a null result of that job
  /// must not wait for an arrival it already missed).
  final Set<AssetId> _arrivedDuringJob = {};

  Note? _running;
  bool _workerActive = false;
  bool _startedOnce = false;
  bool _disposed = false;
  Timer? _workerTimer;
  Timer? _remoteTimer;
  final List<Completer<void>> _idleWaiters = [];

  /// Idempotent. Ignored when disabled, cover is not FirstPageCover,
  /// firstPageId is null, or this note's CoverCheckKey was already checked.
  /// Remembers [note] as the latest version of a visible tile (asset / remote retries).
  void request(Note note) {
    if (!isEnabled || _disposed) return;
    if (note.cover is! FirstPageCover || note.firstPageId == null) {
      // The tile's latest version needs no thumbnail: forget an older one so
      // an asset / remote retry does not draw it.
      _visible.remove(note.id);
      _queue.remove(note.id);
      _rerun.remove(note.id);
      return;
    }
    _visible[note.id] = note;
    if (_checked[note.id] == _keyOf(note)) return;
    if (_running?.id == note.id) {
      _rerun[note.id] = note;
      return;
    }
    _enqueue(note);
  }

  /// Tile disposed (before or after its job): drops the pending request and the
  /// remembered note.
  void cancel(NoteId noteId) {
    if (_disposed) return;
    _visible.remove(noteId);
    _queue.remove(noteId);
    _rerun.remove(noteId);
    _remoteDirty.remove(noteId);
  }

  @visibleForTesting
  int get pendingCount => _queue.length;

  /// Completes when the queue is empty, no job runs and no remote round is waiting.
  @visibleForTesting
  Future<void> idle() {
    if (_disposed || _isIdle) return Future<void>.value();
    final waiter = Completer<void>();
    _idleWaiters.add(waiter);
    return waiter.future;
  }

  void dispose() {
    // also cancels the assetArrivals and changes subscriptions
    if (_disposed) return;
    _disposed = true;
    _workerTimer?.cancel();
    _remoteTimer?.cancel();
    _workerTimer = null;
    _remoteTimer = null;
    unawaited(_assetSub?.cancel());
    unawaited(_changesSub?.cancel());
    _queue.clear();
    _visible.clear();
    _rerun.clear();
    _waitingForAsset.clear();
    _remoteDirty.clear();
    _arrivedDuringJob.clear();
    _running = null;
    _workerActive = false;
    _completeIdleWaiters();
  }

  // ---- queue and worker ----------------------------------------------------

  bool get _isIdle =>
      _queue.isEmpty &&
      !_workerActive &&
      _running == null &&
      _remoteTimer == null;

  void _completeIdleWaiters() {
    if (_idleWaiters.isEmpty) return;
    final waiters = List.of(_idleWaiters);
    _idleWaiters.clear();
    for (final w in waiters) {
      w.complete();
    }
  }

  void _maybeIdle() {
    if (_isIdle) _completeIdleWaiters();
  }

  /// Moves [note] to the end of the queue (runs next), drops the oldest
  /// requests beyond maxPending and wakes the worker.
  void _enqueue(Note note) {
    _queue.remove(note.id);
    _queue[note.id] = note;
    while (_queue.length > maxPending) {
      _queue.remove(_queue.keys.first);
    }
    if (_workerActive) return;
    _workerActive = true;
    final delay = _startedOnce ? Duration.zero : startDelay;
    _startedOnce = true;
    _workerTimer = Timer(delay, _runNext);
  }

  Future<void> _runNext() async {
    _workerTimer = null;
    if (_disposed) return;
    if (_queue.isEmpty) {
      _workerActive = false;
      _maybeIdle();
      return;
    }
    final id = _queue.keys.last;
    final note = _queue.remove(id)!;
    _running = note;
    _arrivedDuringJob.clear();
    try {
      await _check(note);
    } catch (error, stack) {
      if (!_disposed) _report(error, stack);
    }
    if (_disposed) return; // the result is dropped (step 5)
    _running = null;
    // Success, failure and null alike: the same key is not tried again
    // (retries come from steps 3 / 4 and from new note versions).
    _checked[id] = _keyOf(note);
    final again = _rerun.remove(id);
    // Straight into the queue: request() would stop at the _checked just set.
    if (again != null) {
      _queue.remove(id);
      _queue[id] = again;
    }
    _arrivedDuringJob.clear();
    if (_queue.isEmpty) {
      _workerActive = false;
      _maybeIdle();
      return;
    }
    _workerTimer = Timer(gap, _runNext);
  }

  /// One job: the cheap staleness check, then render + cache write when the
  /// cached thumbnail is missing or stale (6.15.3 step 2).
  Future<void> _check(Note note) async {
    final page = await _reader.getPage(note.firstPageId!);
    if (_disposed || page == null) return; // first page gone meanwhile (C-9)
    final cached = await _cache.read(page.id);
    if (_disposed) return;
    if (cached != null && !cached.isStaleFor(page)) return;
    final content = await _reader.loadPage(page.id);
    if (_disposed) return;
    final thumb = await _renderer!.render(content, maxSidePx: maxSidePx);
    if (_disposed) return;
    if (thumb == null) {
      // Cannot render now (e.g. PDF bytes missing — contract 7.2.16 v1.1):
      // nothing is cached; try again when a background asset arrives.
      // (v2.13-thumbs) Or an image object's asset: INK returns null too while
      // a photo on the page has no bytes on this device (6.20).
      final assets = <AssetId>{
        ...content.page.background.referencedAssets,
        for (final o in content.objects) ...o.referencedAssets,
      };
      if (assets.any(_arrivedDuringJob.contains)) {
        _rerun[note.id] = _visible[note.id] ?? note;
        return;
      }
      for (final asset in assets) {
        (_waitingForAsset[asset] ??= <NoteId>{}).add(note.id);
      }
      return;
    }
    if (thumb.pageId == page.id) await _cache.write(thumb);
  }

  // ---- retries ---------------------------------------------------------------

  /// Step 3 (LIBRARY-O1): an asset some null-result note waits for arrived.
  void _onAssetArrived(AssetId assetId) {
    if (_disposed) return;
    if (_running != null) _arrivedDuringJob.add(assetId);
    final ids = _waitingForAsset.remove(assetId);
    if (ids == null) return;
    for (final id in ids) {
      _checked.remove(id);
      final note = _visible[id];
      if (note != null) request(note);
    }
  }

  /// Step 4 (contract 7.2.10 v1.1): remote edits do not always raise
  /// Note.updatedAt, so remote batches clear the check of every note they
  /// touch and re-request the visible ones after remoteSettle.
  void _onBatch(ChangeBatch batch) {
    if (_disposed || batch.origin != ChangeOrigin.remote) return;
    for (final change in batch.changes) {
      final id = change.kind == EntityKind.note ? change.id : change.noteId;
      if (id == null) continue; // folder, asset, pen preset, setting
      _checked.remove(id);
      if (_visible.containsKey(id)) {
        _remoteDirty.add(id);
        // One round per settle window, timed from its first batch.
        _remoteTimer ??= Timer(remoteSettle, _flushRemote);
      }
      final running = _running;
      if (running != null && running.id == id) {
        // The job may have read the page before this write; the _checked it
        // records when it ends must not hide this change.
        _rerun[id] = _visible[id] ?? running;
      }
    }
  }

  void _flushRemote() {
    _remoteTimer = null;
    if (_disposed) return;
    final ids = List.of(_remoteDirty);
    _remoteDirty.clear();
    for (final id in ids) {
      final note = _visible[id];
      if (note != null) request(note);
    }
    _maybeIdle();
  }
}
