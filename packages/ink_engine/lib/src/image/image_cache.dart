// lib/src/image/image_cache.dart — contract 7.2.9 (m5-7/03-ink 4.7, members 4.10, 6.11).
//
// (T35) The decoded images of image objects, image backgrounds and thumbnails:
// - decoded at the display bucket (InkTuning.imageBucketsPx — the smallest ≥ the
//   long side asked for, never above the source size) with instantiateImageCodec
//   targetWidth / targetHeight (no full-resolution decode, ≤ 4 Mpx); the source
//   size comes from the object (pixelWidth / pixelHeight) or the PNG / JPEG header
//   (image_header.dart — backgrounds), never from ui.ImageDescriptor (web);
// - one ledger PinnedRasterCache<(assetId, bucket), ui.Image>: an entry a live
//   picture drew is pinned (InkRasterPin — the chunk draw key ImageRasterHold,
//   the background widget, a thumbnail while it draws) and never evicted; pinned
//   bytes count; only entries drawn before and not pinned now are evicted, least
//   recently used first. Web: the ledger InkCachePool shares with the raster
//   tiles (one 96 MiB budget); native: an own ledger of 128 MiB (6.11.3, 6.22);
// - a request that does not fit (budget − pinned − fresh − requests in flight)
//   takes the next lower bucket, again until it fits — computed before decoding,
//   one decode; the asset keeps that cap (peek does not ask for the bigger bucket
//   again) until a bigger bucket fits whole; the smallest bucket is taken anyway
//   (stats.downgraded, overflow bytes);
// - at most InkTuning.maxConcurrentImageDecodes decodes at a time, in request
//   order (requests come in drawing order);
// - change notices name the asset and the bucket: a decode finished (or ended
//   without an image), core.AssetStore.bytesArrived brought a missing asset
//   (bucket 0 = 'ask again'), an entry was evicted;
// - bytes not on the device → no image until bytesArrived; a decode failure or
//   no store (a container without a NoteStore) is not tried again (the painters
//   draw the placeholder and warn imageMissing / imageDecodeFailed /
//   imageStoreUnavailable — 6.24).
import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../render/base_cache.dart' show InkDrawHold;
import '../render/cache_pool.dart';
import '../render/pinned_raster_cache.dart';
import '../tuning.dart';
import 'deferred_asset_store.dart';
import 'image_header.dart';

/// Web build (dart2js / dart2wasm): the image budget is the shared raster ledger.
const bool _isWeb = bool.fromEnvironment('dart.library.js_interop');

/// INTERNAL: one cached decode.
@internal
typedef InkImageKey = ({String assetId, int bucket});

/// INTERNAL: why an asset has no image (the painters warn — 6.24).
@internal
enum InkImageStatus {
  /// Decodable (or not tried yet).
  ok,

  /// readBytes → null: not on this device; tried again after bytesArrived.
  missing,

  /// The bytes did not decode; not tried again.
  failed,

  /// No store (a container without a NoteStore override); not tried again.
  storeUnavailable,
}

/// INTERNAL: what [InkImageCache.lookup] found. [image] (bucket [bucket]) is what to draw
/// now — null: the placeholder; [want] is the bucket asked for (capped, lowered to fit).
@internal
typedef InkImageLookup = ({
  ui.Image? image,
  int bucket,
  int want,
  InkImageStatus status,
});

/// INTERNAL (tests): decodes [bytes] at the target size (instantiateImageCodec rule).
@internal
typedef InkImageDecoder = Future<ui.Image> Function(
  Uint8List bytes, {
  int? targetWidth,
  int? targetHeight,
});

/// INTERNAL: the chunk draw key that pins (assetId, bucket) while a chunk picture drew it.
@internal
final class ImageRasterHold implements InkDrawHold {
  ImageRasterHold(this._cache, this.key);
  final InkImageCache _cache;
  final InkImageKey key;

  @override
  InkRasterPin acquire() => _cache.pin(key.assetId, key.bucket);

  @override
  bool operator ==(Object other) =>
      other is ImageRasterHold &&
      identical(other._cache, _cache) &&
      other.key == key;

  @override
  int get hashCode => Object.hash(identityHashCode(_cache), key);
}

/// Decoded image cache shared by image objects, image backgrounds and thumbnails.
/// Budget (v2.1, 7.4.5): web — shares the 96 MB raster ledger with the tiles; native 128 MB.
/// Decodes at the display bucket (no full-res decode). (v2.1) Entries drawn by live pictures are
/// counted and not evicted; a request over budget gets the next lower bucket (no evict / re-decode
/// loop); change notices name the asset, so only chunks that draw it are re-recorded. Budgets are
/// InkRenderConfig fields (CP-INK-5: imageCacheBytes, mathRasterCacheBytes).
final class InkImageCache {
  /// [budgetBytes] / [pool] null → InkRenderConfig.platformDefault rule above (web without a
  /// pool: an own 96 MiB ledger — tests only). inkImageCacheProvider passes the app pool.
  InkImageCache({
    required core.AssetStore assets,
    int? budgetBytes,
    InkCachePool? pool,
  }) : // the contract names the parameter; the field stays private
       // ignore: prefer_initializing_formals
       _assets = assets {
    final shared = budgetBytes == null && pool != null
        ? rasterLedgerOf(pool)
        : null;
    _ledger = PinnedRasterCache<InkImageKey, ui.Image>(
      budgetBytes:
          budgetBytes ?? (_isWeb ? _webOwnLedgerBytes : _nativeBudgetBytes),
      bytesOf: (image) => image.width * image.height * 4,
      disposeValue: (image) => image.dispose(),
      onEvicted: _evicted,
      ledger: shared,
    );
  }

  final core.AssetStore _assets;
  late final PinnedRasterCache<InkImageKey, ui.Image> _ledger;
  final StreamController<({String assetId, int bucket})> _changes =
      StreamController.broadcast();
  final Map<String, _AssetState> _states = {};
  final Map<InkImageKey, _Job> _inFlight = {};
  final ListQueue<_Job> _queue = ListQueue();
  int _running = 0;
  bool _pumpScheduled = false;
  StreamSubscription<core.AssetId>? _arrived;
  int _failures = 0;
  int _downgraded = 0;
  bool _disposed = false;

  // tests
  InkImageDecoder _decoder = _decode;
  final List<({String assetId, int width, int height})> _decodeLog = [];
  int _maxRunning = 0;

  static const int _nativeBudgetBytes = 128 * 1024 * 1024;
  static const int _webOwnLedgerBytes = 96 * 1024 * 1024;

  /// The store the images are read from.
  core.AssetStore get assets => _assets;

  /// [budgetBytes] when given; otherwise native → 128 MiB, web → the pool's raster
  /// budget (the shared ledger) or 96 MiB without a pool.
  int get budgetBytes => _ledger.budgetBytes;

  /// Decoded image of [assetId] at the bucket for [longSidePx]: the smallest
  /// InkTuning.imageBucketsPx ≥ longSidePx, never above the source size, lowered one bucket at a
  /// time while it does not fit the budget (6.11.3 — computed before decoding, one decode);
  /// else the best decoded one so far; null = none yet (a decode is queued). Never throws. The
  /// cache owns the handle: callers draw it at once and never dispose it. A Picture that keeps
  /// drawing it is pinned by INK's painters; an unpinned entry may be evicted.
  ui.Image? peek(
    String assetId, {
    required int longSidePx,
    int? pixelWidth,
    int? pixelHeight,
  }) => lookup(
    assetId,
    longSidePx: longSidePx,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
  ).image;

  /// Same, waiting for that bucket's decode. null = bytes not on this device or undecodable.
  Future<ui.Image?> load(
    String assetId, {
    required int longSidePx,
    int? pixelWidth,
    int? pixelHeight,
  }) async {
    final entry = await loadEntry(
      assetId,
      longSidePx: longSidePx,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    return entry?.image;
  }

  /// (v2.1) One event per (asset, bucket) change: a decode finished, core.AssetStore.bytesArrived
  /// brought a missing asset (bucket 0 = 'ask again'), an entry was evicted or capped to a lower
  /// bucket. Broadcast, delivered asynchronously. Listeners re-record only what draws [assetId].
  Stream<({String assetId, int bucket})> get changes => _changes.stream;

  ({
    int images,
    int bytes,
    int pinnedBytes,
    int queued,
    int failures,
    int downgraded,
  })
  get stats => (
    images: _ledger.length,
    bytes: _ledger.bytes,
    pinnedBytes: _ledger.pinnedBytes,
    queued: _inFlight.length,
    failures: _failures,
    downgraded: _downgraded,
  );

  /// INTERNAL (INK painters only): holds (assetId, bucket) while a picture draws it — counted
  /// in the budget, never evicted. [InkRasterPin.none] when it is not cached.
  @internal
  InkRasterPin pin(String assetId, int bucket) =>
      _ledger.pin((assetId: assetId, bucket: bucket));

  bool get isDisposed => _disposed;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_arrived?.cancel());
    _arrived = null;
    for (final job in _inFlight.values) {
      job.finish(null);
    }
    _inFlight.clear();
    _queue.clear();
    _ledger.dispose();
    _states.clear();
    unawaited(_changes.close());
  }

  // --- INTERNAL (INK) --------------------------------------------------------

  /// INTERNAL: [peek] with the bucket asked for and drawn, and the asset's status.
  @internal
  InkImageLookup lookup(
    String assetId, {
    required int longSidePx,
    int? pixelWidth,
    int? pixelHeight,
  }) {
    if (_disposed) {
      return (image: null, bucket: 0, want: 0, status: InkImageStatus.ok);
    }
    final state = _stateOf(assetId, pixelWidth, pixelHeight);
    final desired = state.bucketFor(longSidePx);
    if (state.status != InkImageStatus.ok) {
      final other = _bestOther(assetId, state, desired);
      return (
        image: other?.image,
        bucket: other?.bucket ?? 0,
        want: desired,
        status: state.status,
      );
    }
    var bucket = _cappedBucket(assetId, state, desired);
    final hit = _ledger.use((assetId: assetId, bucket: bucket));
    if (hit != null) {
      return (image: hit, bucket: bucket, want: bucket, status: state.status);
    }
    // a bigger decode is there (zoomed out, or another view): no smaller decode
    final bigger = _smallestAbove(state, bucket);
    if (bigger != null) {
      final image = _ledger.use((assetId: assetId, bucket: bigger));
      if (image != null) {
        return (
          image: image,
          bucket: bigger,
          want: bigger,
          status: state.status,
        );
      }
    }
    if (!_inFlight.containsKey((assetId: assetId, bucket: bucket))) {
      // lower until it fits (the smallest bucket is taken anyway — 6.11.3)
      var chosen = bucket;
      final min = InkTuning.imageBucketsPx.first;
      while (chosen > min && !_fits(state.bytesAt(chosen))) {
        chosen = _lower(chosen);
      }
      if (chosen != bucket) {
        state.cap = chosen;
        _downgraded++;
        bucket = chosen;
        final lowered = _ledger.use((assetId: assetId, bucket: bucket));
        if (lowered != null) {
          return (
            image: lowered,
            bucket: bucket,
            want: bucket,
            status: state.status,
          );
        }
      }
      if (!_inFlight.containsKey((assetId: assetId, bucket: bucket))) {
        _request((assetId: assetId, bucket: bucket), state);
      }
    }
    final other = _bestOther(assetId, state, bucket);
    return (
      image: other?.image,
      bucket: other?.bucket ?? 0,
      want: bucket,
      status: state.status,
    );
  }

  /// INTERNAL: [load] with the bucket of the image (thumbnails / still backgrounds pin it
  /// while they draw).
  @internal
  Future<({ui.Image image, int bucket})?> loadEntry(
    String assetId, {
    required int longSidePx,
    int? pixelWidth,
    int? pixelHeight,
  }) async {
    final found = lookup(
      assetId,
      longSidePx: longSidePx,
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight,
    );
    final image = found.image;
    if (image != null && found.bucket == found.want) {
      return (image: image, bucket: found.bucket);
    }
    if (found.status != InkImageStatus.ok) return null;
    final job = _inFlight[(assetId: assetId, bucket: found.want)];
    if (job == null) {
      // nothing queued for it (a status change in between): the best there is
      return image == null ? null : (image: image, bucket: found.bucket);
    }
    final key = await job.done.future;
    if (key == null || _disposed) return null;
    final decoded = _ledger.use(key);
    return decoded == null ? null : (image: decoded, bucket: key.bucket);
  }

  /// INTERNAL: the status of [assetId] (missing / failed / no store).
  @internal
  InkImageStatus statusOf(String assetId) =>
      _states[assetId]?.status ?? InkImageStatus.ok;

  /// INTERNAL: whether (assetId, bucket) is cached now.
  @internal
  bool contains(String assetId, int bucket) =>
      _ledger.containsKey((assetId: assetId, bucket: bucket));

  /// INTERNAL: the draw key that pins the image a chunk drew.
  @internal
  ImageRasterHold holdOf(String assetId, int bucket) =>
      ImageRasterHold(this, (assetId: assetId, bucket: bucket));

  // --- internals -------------------------------------------------------------

  static Future<ui.Image> _decode(
    Uint8List bytes, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      allowUpscaling: false,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  _AssetState _stateOf(String assetId, int? pixelWidth, int? pixelHeight) {
    final state = _states.putIfAbsent(assetId, _AssetState.new);
    if (state.width == null &&
        pixelWidth != null &&
        pixelHeight != null &&
        pixelWidth > 0 &&
        pixelHeight > 0) {
      state
        ..width = pixelWidth
        ..height = pixelHeight;
    }
    return state;
  }

  bool _fits(int? bytes) => bytes == null || _ledger.fits(bytes);

  static int _lower(int bucket) {
    var lower = InkTuning.imageBucketsPx.first;
    for (final b in InkTuning.imageBucketsPx) {
      if (b < bucket) lower = b;
    }
    return lower;
  }

  /// [desired] under the asset's cap; the cap goes up (straight to the highest bucket
  /// ≤ [desired] that fits whole now) or away when [desired] fits.
  int _cappedBucket(String assetId, _AssetState state, int desired) {
    final cap = state.cap;
    if (cap == null) return desired;
    if (cap >= desired) return desired;
    int? raised;
    for (final b in InkTuning.imageBucketsPx) {
      if (b <= cap || b > desired) continue;
      final key = (assetId: assetId, bucket: b);
      if (_ledger.containsKey(key) ||
          _inFlight.containsKey(key) ||
          _fits(state.bytesAt(b))) {
        raised = b;
      }
    }
    if (raised == null) return cap;
    if (raised >= desired) {
      state.cap = null;
    } else {
      state.cap = raised;
    }
    return raised;
  }

  static int? _smallestAbove(_AssetState state, int bucket) {
    int? above;
    for (final b in state.present) {
      if (b > bucket && (above == null || b < above)) above = b;
    }
    return above;
  }

  /// The best decoded bucket of [assetId] other than [bucket]: the largest below it, else
  /// the smallest above it.
  ({ui.Image image, int bucket})? _bestOther(
    String assetId,
    _AssetState state,
    int bucket,
  ) {
    int? below, above;
    for (final b in state.present) {
      if (b <= bucket) {
        if (below == null || b > below) below = b;
      } else if (above == null || b < above) {
        above = b;
      }
    }
    final b = below ?? above;
    if (b == null) return null;
    final image = _ledger.use((assetId: assetId, bucket: b));
    return image == null ? null : (image: image, bucket: b);
  }

  void _request(InkImageKey key, _AssetState state) {
    final bytes = state.bytesAt(key.bucket) ?? 0;
    final job = _Job(key, bytes);
    _inFlight[key] = job;
    _ledger.reserve(bytes);
    _queue.add(job);
    _schedulePump();
  }

  /// Starts queued decodes on the microtask turn (never inside the caller — a painter).
  void _schedulePump() {
    if (_pumpScheduled) return;
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    while (!_disposed &&
        _running < InkTuning.maxConcurrentImageDecodes &&
        _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _running++;
      _maxRunning = math.max(_maxRunning, _running);
      unawaited(
        _run(job).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }

  Future<void> _run(_Job job) async {
    final assetId = job.key.assetId;
    final state = _states[assetId];
    InkImageKey? result;
    var key = job.key;
    try {
      if (_disposed || state == null) return;
      final Uint8List? bytes;
      try {
        bytes = await _assets.readBytes(assetId);
      } on ImageStoreUnavailable {
        state.status = InkImageStatus.storeUnavailable;
        return;
      } on Object {
        state.status = InkImageStatus.failed;
        _failures++;
        return;
      }
      if (_disposed) return;
      if (bytes == null) {
        state.status = InkImageStatus.missing;
        _listenArrivals();
        return;
      }
      if (state.width == null) {
        // an image background: the size from the PNG / JPEG header (no full decode)
        final size = readImagePixelSize(bytes);
        if (size != null) {
          state
            ..width = size.width
            ..height = size.height;
          // the bucket is chosen now that the size is known (one decode)
          var b = math.min(key.bucket, state.maxBucket);
          final min = InkTuning.imageBucketsPx.first;
          _ledger.unreserve(job.bytes);
          job.bytes = 0;
          while (b > min && !_fits(state.bytesAt(b))) {
            b = _lower(b);
          }
          if (b != key.bucket) {
            if (b < math.min(key.bucket, state.maxBucket)) {
              state.cap = b;
              _downgraded++;
            }
            final moved = (assetId: assetId, bucket: b);
            if (_ledger.containsKey(moved)) {
              result = moved;
              return;
            }
            key = moved;
            _inFlight.putIfAbsent(key, () => job); // the same decode
          }
          job.bytes = state.bytesAt(b) ?? 0;
          _ledger.reserve(job.bytes);
        }
      }
      final target = state.targetAt(key.bucket);
      final ui.Image image;
      try {
        image = await _decoder(
          bytes,
          targetWidth: target.width,
          targetHeight: target.height,
        );
      } on Object {
        if (!_disposed) {
          state.status = InkImageStatus.failed;
          _failures++;
        }
        return;
      }
      if (_disposed) {
        image.dispose();
        return;
      }
      _decodeLog.add((
        assetId: assetId,
        width: image.width,
        height: image.height,
      ));
      final tw = target.width;
      if (state.width == null && tw != null && image.width < tw) {
        // no header and not scaled down: this is the source size
        state
          ..width = image.width
          ..height = image.height;
      }
      _ledger.unreserve(job.bytes);
      job.bytes = 0;
      if (_ledger.put(key, image)) state.present.add(key.bucket);
      result = _ledger.containsKey(key) ? key : null;
    } finally {
      _ledger.unreserve(job.bytes);
      job.bytes = 0;
      _inFlight.remove(job.key);
      if (key != job.key && identical(_inFlight[key], job)) {
        _inFlight.remove(key);
      }
      job.finish(result);
      if (!_disposed) {
        _changes.add((
          assetId: assetId,
          bucket: result?.bucket ?? job.key.bucket,
        ));
      }
    }
  }

  void _listenArrivals() {
    _arrived ??= _assets.bytesArrived.listen(
      _onArrived,
      onError: (Object _) {},
    );
  }

  void _onArrived(core.AssetId id) {
    if (_disposed) return;
    final state = _states[id];
    if (state == null || state.status != InkImageStatus.missing) return;
    state.status = InkImageStatus.ok;
    _changes.add((assetId: id, bucket: 0)); // ask again
  }

  void _evicted(InkImageKey key) {
    final state = _states[key.assetId];
    state?.present.remove(key.bucket);
    if (!_disposed) _changes.add(key);
  }
}

/// INTERNAL (tests): the decodes [cache] made — asset and decoded size (no full-resolution
/// decode, 6.11.1).
@visibleForTesting
List<({String assetId, int width, int height})> debugImageDecodes(
  InkImageCache cache,
) => List.unmodifiable(cache._decodeLog);

/// INTERNAL (tests): the most decodes [cache] ran at once (≤ maxConcurrentImageDecodes).
@visibleForTesting
int debugImageMaxConcurrentDecodes(InkImageCache cache) => cache._maxRunning;

/// INTERNAL (tests): replaces [cache]'s decoder (null → instantiateImageCodec).
@visibleForTesting
void debugSetImageDecoder(InkImageCache cache, InkImageDecoder? decoder) =>
    cache._decoder = decoder ?? InkImageCache._decode;

/// INTERNAL (tests): whether [cache] counts in a ledger shared with raster tiles.
@visibleForTesting
bool debugImageCacheIsShared(InkImageCache cache) => cache._ledger.isShared;

/// INTERNAL (tests): the cap (lowered bucket) [assetId] keeps; null = none.
@visibleForTesting
int? debugImageCapOf(InkImageCache cache, String assetId) =>
    cache._states[assetId]?.cap;

/// INTERNAL (tests): whether (assetId, bucket) is pinned now.
@visibleForTesting
bool debugImageIsPinned(InkImageCache cache, String assetId, int bucket) =>
    cache._ledger.isPinned((assetId: assetId, bucket: bucket));

/// INTERNAL (tests): the ledger's overflow (the smallest bucket taken over the budget).
@visibleForTesting
int debugImageOverflowBytes(InkImageCache cache) => cache._ledger.overflowBytes;

/// What the cache knows of one asset.
final class _AssetState {
  /// Source px (the object's pixel size, the header, or a decode that was not scaled).
  int? width, height;

  /// The bucket it was lowered to (6.11.3); null = none.
  int? cap;

  /// The buckets in the ledger.
  final Set<int> present = {};
  InkImageStatus status = InkImageStatus.ok;

  /// The largest bucket worth decoding: the smallest bucket ≥ the source long side.
  int get maxBucket {
    final w = width, h = height;
    if (w == null || h == null) return InkTuning.imageBucketsPx.last;
    final long = math.max(w, h);
    for (final b in InkTuning.imageBucketsPx) {
      if (b >= long) return b;
    }
    return InkTuning.imageBucketsPx.last;
  }

  /// The smallest bucket ≥ [longSidePx], never above [maxBucket].
  int bucketFor(int longSidePx) {
    var wanted = InkTuning.imageBucketsPx.last;
    for (final b in InkTuning.imageBucketsPx) {
      if (b >= longSidePx) {
        wanted = b;
        break;
      }
    }
    return math.min(wanted, maxBucket);
  }

  /// The decode size at [bucket]: long side min(bucket, source), the aspect kept, ≤ 4 Mpx.
  /// Unknown source → targetWidth only (the aspect is kept by the codec).
  ({int? width, int? height}) targetAt(int bucket) {
    final w = width, h = height;
    if (w == null || h == null) return (width: bucket, height: null);
    final long = math.max(w, h);
    var scale = math.min(1.0, bucket / long);
    var tw = math.max(1, (w * scale).round());
    var th = math.max(1, (h * scale).round());
    if (tw * th > InkTuning.maxRasterPixels) {
      scale *= math.sqrt(InkTuning.maxRasterPixels / (tw * th));
      tw = math.max(1, (w * scale).floor());
      th = math.max(1, (h * scale).floor());
    }
    return (width: tw, height: th);
  }

  /// RGBA bytes of the decode at [bucket]; null = the source size is unknown.
  int? bytesAt(int bucket) {
    if (width == null) return null;
    final t = targetAt(bucket);
    return t.width! * t.height! * 4;
  }
}

final class _Job {
  _Job(this.key, this.bytes);
  final InkImageKey key;

  /// Reserved in the ledger until the decode is in or failed.
  int bytes;
  final Completer<InkImageKey?> done = Completer();

  void finish(InkImageKey? result) {
    if (!done.isCompleted) done.complete(result);
  }
}
