// lib/src/math/math_raster_cache.dart — INTERNAL (m5-7/03-ink 6.12.3, 6.11.3 rules, 6.22).
//
// (T36) The formula rasters the annotation layer draws: key (latex, color,
// font size, bucket), budget InkRenderConfig.mathRasterCacheBytes (24 MiB native, 8 MiB web), one
// per InkCachePool (app wide). The same rules as the image cache (M-4):
// - an entry a chunk Picture drew is pinned (MathRasterHold — an InkDrawHold
//   draw key) until that picture is dropped; pinned bytes count, pinned
//   entries are never evicted (PinnedRasterCache);
// - a request that does not fit (budget − pinned − requests in flight) takes
//   the next lower bucket, again until it fits; the smallest bucket is taken
//   anyway (downgraded, overflow bytes in stats). The formula keeps that cap,
//   so peek does not ask for the bigger bucket again — only when a bigger one
//   fits whole (pins were released) the cap goes up, straight to the highest
//   bucket that fits (no up / down loop);
// - change notices name the formula: only the chunks that drew it (draw key
//   InkDrawKeys.math) are recorded again;
// - a failed raster (glyph pictures not settled, 6.12.2) is not asked again for
//   InkTuning.mathRasterRetryMs; the placeholder stays.
// - (math resize fix) a formula at a font size that has no raster yet — a resize
//   gives the formula a new font size, so a new key — draws a raster of the same
//   LaTeX and color at another font size (contain-fitted, so the same shape; the
//   sharpest one there is) instead of the empty placeholder box;
// - (math resize fix) one request in flight per LaTeX and color: a resize drag
//   asks a new font size on every move, and the raster host works one job at a
//   time, so without this the final size waited behind every intermediate one
//   (the formula stayed a grey box long after the pen was lifted) and the
//   reservations of the queue pushed it to a lower bucket (blurry for good).
//   Asks meanwhile wait; when the request settles the latest one is asked and
//   the others get a change event (their drawers ask again if still drawn).
// Bucket = the smallest scale bucket ≥ deviceScale (at most 4; 2 before the
// first viewport report). The raster is captured at pixelsPerPt = bucket; the
// contain fit (6.12.4, s ≈ 1) scales it into the frame when drawn.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:note_core/note_core.dart' as core;

import '../render/base_cache.dart' show InkDrawHold;
import '../render/pinned_raster_cache.dart';
import '../text/text_layout.dart' show rasterScaleFor;
import '../tuning.dart';
import 'math_renderer.dart' show InkMathRenderer, rasterizeFormula;
import 'offscreen_host.dart' show OffscreenRaster;

/// INTERNAL: what a formula raster depends on besides the scale.
@internal
typedef MathFormula = ({String latex, int colorArgb, double fontSizePt});

/// INTERNAL: the rasters of one formula at every font size (a resize changes only that).
@internal
typedef MathFamily = ({String latex, int colorArgb});

MathFamily _familyOf(MathFormula f) => (latex: f.latex, colorArgb: f.colorArgb);

/// INTERNAL: one cached raster.
@internal
typedef MathRasterKey = ({MathFormula formula, double bucket});

/// INTERNAL: a raster arrived (failed: false) or failed (failed: true) for [formula]. (math
/// resize fix) failed: false also when an ask of [formula] waited for another request of
/// its LaTeX and color: whoever draws it asks again.
@internal
typedef MathRasterChange = ({MathFormula formula, bool failed});

/// INTERNAL: renders one formula at [pixelsPerPt] (tests replace it).
@internal
typedef MathRasterizer = Future<OffscreenRaster?> Function(
  MathFormula formula,
  double pixelsPerPt,
);

/// INTERNAL: the raster key part of [o] (latex, color, font size).
@internal
MathFormula mathFormulaOf(core.MathObject o) => (
  latex: o.latex,
  colorArgb: o.style.colorArgb,
  fontSizePt: o.style.fontSizePt,
);

final Expando<bool> _renderable = Expando('renderableMath');

/// (m5-7 T43, B14) The last validated LaTeX strings: a page loaded again brings new
/// MathObject instances with the same formulas, and parsing one costs about 0.4 ms
/// (debug VM). validate depends on the string only.
final Map<String, bool> _renderableLatex = {};
const int _renderableLatexMax = 256;

/// INTERNAL: InkMathRenderer.validate(o.latex) == null, remembered per instance and per
/// LaTeX string (a stored formula that does not parse is drawn as the 6.13 placeholder —
/// mathInvalid, 6.24).
@internal
bool isRenderableMath(core.MathObject o) =>
    _renderable[o] ??= _renderableLatexOf(o.latex);

bool _renderableLatexOf(String latex) {
  final hit = _renderableLatex.remove(latex);
  final ok = hit ?? InkMathRenderer.validate(latex) == null;
  _renderableLatex[latex] = ok; // most recently used last
  if (_renderableLatex.length > _renderableLatexMax) {
    _renderableLatex.remove(_renderableLatex.keys.first);
  }
  return ok;
}

/// INTERNAL: one formula raster and the laid-out size (pt) it was captured from.
@internal
final class MathRaster {
  MathRaster._(this.key, this.image, this.sizePt);
  final MathRasterKey key;

  /// Owned by the cache: draw it at once, never dispose it.
  final ui.Image image;
  final ui.Size sizePt;
  int get bytes => image.width * image.height * 4;
  double get bucket => key.bucket;

  /// Image px per pt: the bucket lowered to the 4 Mpx / 8192 px cap (7.4.5).
  double get pixelsPerPt =>
      rasterScaleFor(sizePt.width, sizePt.height, key.bucket);

  /// (T41) A raster that no cache owns (thumbnails): [r] captured from [formula] at
  /// [pixelsPerPt]; the caller disposes [image] once it is drawn.
  static MathRaster detached(
    MathFormula formula,
    double pixelsPerPt,
    OffscreenRaster r,
  ) => MathRaster._((formula: formula, bucket: pixelsPerPt), r.image, r.size);
}

/// INTERNAL: the draw key that pins [key] while a chunk picture drew it.
@internal
final class MathRasterHold implements InkDrawHold {
  MathRasterHold(this._cache, this.key);
  final MathRasterCache _cache;
  final MathRasterKey key;

  @override
  InkRasterPin acquire() => _cache._ledger.pin(key);

  @override
  bool operator ==(Object other) =>
      other is MathRasterHold &&
      identical(other._cache, _cache) &&
      other.key == key;

  @override
  int get hashCode => Object.hash(identityHashCode(_cache), key);
}

@internal
final class MathRasterCache {
  MathRasterCache({
    required int budgetBytes,
    List<double> scaleBuckets = const [0.5, 1.0, 1.5, 2.0, 3.0, 4.0],
    MathRasterizer? rasterizer,
  }) : _buckets = _bucketsOf(scaleBuckets),
       _rasterizer = rasterizer ?? _rasterize {
    _ledger = PinnedRasterCache<MathRasterKey, MathRaster>(
      budgetBytes: budgetBytes,
      bytesOf: (r) => r.bytes,
      disposeValue: (r) => r.image.dispose(),
      onEvicted: _evicted,
    );
  }

  /// The largest bucket a formula is rasterized at (6.12.3: 'at most 4').
  static const double maxBucket = 4;

  /// Before the first viewport report (6.11.2: 'otherwise 2').
  static const double defaultDeviceScale = 2;

  late final PinnedRasterCache<MathRasterKey, MathRaster> _ledger;
  final List<double> _buckets;
  final MathRasterizer _rasterizer;
  final Map<MathFormula, Set<double>> _present = {};
  final Map<MathFamily, Set<MathFormula>> _family = {};
  final Map<MathFamily, int> _familyInFlight = {};

  /// Asks that waited for their family's request in flight, oldest first.
  final Map<MathFamily, Map<MathRasterKey, int>> _waiting = {};
  final Map<MathFormula, double> _caps = {};
  final Map<MathRasterKey, int> _inFlight = {};
  final Map<MathRasterKey, int> _failedAtUs = {};
  final StreamController<MathRasterChange> _changes =
      StreamController.broadcast();
  int _failures = 0;
  int _downgraded = 0;
  int _rasterized = 0;
  bool _disposed = false;

  int get budgetBytes => _ledger.budgetBytes;

  /// The buckets a formula may take, ascending (the scale buckets ≤ [maxBucket]).
  List<double> get buckets => _buckets;

  /// One event per raster that arrived or failed. Broadcast, delivered asynchronously.
  Stream<MathRasterChange> get changes => _changes.stream;

  ({
    int rasters,
    int bytes,
    int pinnedBytes,
    int queued,
    int rasterized,
    int failures,
    int downgraded,
    int overflowBytes,
  })
  get stats => (
    rasters: _ledger.length,
    bytes: _ledger.bytes,
    pinnedBytes: _ledger.pinnedBytes,
    queued: _inFlight.length,
    rasterized: _rasterized,
    failures: _failures,
    downgraded: _downgraded,
    overflowBytes: _ledger.overflowBytes,
  );

  /// The bucket [deviceScale] asks for: the smallest bucket ≥ it, [maxBucket] above.
  double wantedBucket(double? deviceScale) {
    final s = deviceScale != null && deviceScale > 0 && deviceScale.isFinite
        ? deviceScale
        : defaultDeviceScale;
    for (final b in _buckets) {
      if (b + 1e-9 >= s) return b;
    }
    return _buckets.last;
  }

  /// The raster to draw now for [formula] in a frame of [framePt] at [deviceScale]: the
  /// entry of the bucket it should have (capped, lowered to fit), else the best other
  /// bucket of the formula there is, else (math resize fix) the sharpest raster of the
  /// same LaTeX and color at another font size; null = none yet. While a raster of the
  /// same LaTeX and color is in flight the request waits (see the file header). A missing bucket is requested
  /// (not again within InkTuning.mathRasterRetryMs of a failure). Synchronous, never
  /// throws; asking twice without anything arriving gives the same answer.
  MathRaster? peek(
    MathFormula formula, {
    required double? deviceScale,
    required ui.Size framePt,
    required int nowUs,
  }) {
    if (_disposed) return null;
    final desired = wantedBucket(deviceScale);
    var bucket = _cappedBucket(formula, desired, framePt);
    final hit = _ledger.use((formula: formula, bucket: bucket));
    if (hit != null) return hit;
    final key = (formula: formula, bucket: bucket);
    if (!_inFlight.containsKey(key)) {
      // lower until it fits (the smallest bucket is taken anyway — 6.11.3)
      var chosen = bucket;
      while (!_ledger.fits(_estimate(framePt, chosen)) &&
          chosen > _buckets.first) {
        chosen = _lower(chosen);
      }
      if (chosen != bucket) {
        _caps[formula] = chosen;
        _downgraded++;
        bucket = chosen;
        final lowered = _ledger.use((formula: formula, bucket: bucket));
        if (lowered != null) return lowered;
      }
      final want = (formula: formula, bucket: bucket);
      final bytes = _estimate(framePt, bucket);
      final family = _familyOf(formula);
      if ((_familyInFlight[family] ?? 0) > 0) {
        final waiting = _waiting[family] ??= {};
        waiting.remove(want); // most recently asked last
        waiting[want] = bytes;
      } else {
        _request(want, bytes, nowUs);
      }
    }
    return _bestOther(formula, bucket) ?? _bestOfFamily(formula, bucket);
  }

  /// The draw key that pins [raster] while a chunk picture drew it.
  MathRasterHold holdOf(MathRaster raster) => MathRasterHold(this, raster.key);

  /// (tests) Whether [key] is cached / pinned.
  @visibleForTesting
  bool isCached(MathRasterKey key) => _ledger.containsKey(key);
  @visibleForTesting
  bool isPinned(MathRasterKey key) => _ledger.isPinned(key);

  /// (tests) The cap a formula was lowered to (null = none).
  @visibleForTesting
  double? capOf(MathFormula formula) => _caps[formula];

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ledger.dispose();
    _present.clear();
    _family.clear();
    _familyInFlight.clear();
    _waiting.clear();
    _caps.clear();
    _inFlight.clear();
    unawaited(_changes.close());
  }

  // --- internals -------------------------------------------------------------

  static Future<OffscreenRaster?> _rasterize(
    MathFormula f,
    double pixelsPerPt,
  ) => rasterizeFormula(
    f.latex,
    colorArgb: f.colorArgb,
    fontSizePt: f.fontSizePt,
    pixelsPerPt: pixelsPerPt,
  );

  static List<double> _bucketsOf(List<double> scaleBuckets) {
    final list = <double>{
      for (final b in scaleBuckets)
        if (b > 0 && b.isFinite && b <= maxBucket) b,
    }.toList()..sort();
    return List.unmodifiable(list.isEmpty ? const [1.0, 2.0, 4.0] : list);
  }

  /// [desired] under the formula's cap; the cap goes up (straight to the highest bucket
  /// ≤ [desired] that fits whole now) or away when [desired] fits.
  double _cappedBucket(MathFormula f, double desired, ui.Size framePt) {
    final cap = _caps[f];
    if (cap == null) return desired;
    if (cap >= desired) return desired;
    double? raised;
    for (final b in _buckets) {
      if (b <= cap || b > desired) continue;
      final key = (formula: f, bucket: b);
      if (_ledger.containsKey(key) ||
          _inFlight.containsKey(key) ||
          _ledger.fits(_estimate(framePt, b))) {
        raised = b;
      }
    }
    if (raised == null) return cap;
    if (raised >= desired) {
      _caps.remove(f);
    } else {
      _caps[f] = raised;
    }
    return raised;
  }

  double _lower(double bucket) {
    var lower = _buckets.first;
    for (final b in _buckets) {
      if (b < bucket) lower = b;
    }
    return lower;
  }

  /// RGBA bytes of a [framePt] raster at [bucket] px per pt (4 Mpx cap — 7.4.5).
  static int _estimate(ui.Size framePt, double bucket) {
    final w = framePt.width, h = framePt.height;
    if (!(w > 0) || !(h > 0) || !w.isFinite || !h.isFinite) return 0;
    final k = rasterScaleFor(w, h, bucket);
    return (w * k).ceil() * (h * k).ceil() * 4;
  }

  MathRaster? _bestOther(MathFormula f, double bucket) {
    final present = _present[f];
    if (present == null || present.isEmpty) return null;
    double? below, above;
    for (final b in present) {
      if (b <= bucket) {
        if (below == null || b > below) below = b;
      } else if (above == null || b < above) {
        above = b;
      }
    }
    final b = below ?? above;
    return b == null ? null : _ledger.use((formula: f, bucket: b));
  }

  /// (math resize fix) The raster of [f]'s LaTeX and color at another font size that is
  /// sharpest for [f] at [bucket]: its px per pt of [f]'s size (bucket × its font size ÷
  /// [f]'s) — the smallest one ≥ [bucket], else the biggest. null = none.
  MathRaster? _bestOfFamily(MathFormula f, double bucket) {
    final formulas = _family[_familyOf(f)];
    if (formulas == null || !(f.fontSizePt > 0)) return null;
    MathRasterKey? atLeast, below;
    double atLeastK = double.infinity, belowK = 0;
    for (final g in formulas) {
      if (g == f) continue;
      for (final b in _present[g] ?? const <double>{}) {
        final k = b * g.fontSizePt / f.fontSizePt;
        if (k + 1e-9 >= bucket) {
          if (k < atLeastK) (atLeast, atLeastK) = ((formula: g, bucket: b), k);
        } else if (k > belowK) {
          (below, belowK) = ((formula: g, bucket: b), k);
        }
      }
    }
    final key = atLeast ?? below;
    return key == null ? null : _ledger.use(key);
  }

  void _request(MathRasterKey key, int bytes, int nowUs) {
    final failedAt = _failedAtUs[key];
    if (failedAt != null &&
        nowUs - failedAt < InkTuning.mathRasterRetryMs * 1000) {
      return;
    }
    _failedAtUs.remove(key);
    _inFlight[key] = bytes;
    _ledger.reserve(bytes);
    final family = _familyOf(key.formula);
    _familyInFlight[family] = (_familyInFlight[family] ?? 0) + 1;
    void settle(OffscreenRaster? r) {
      final reserved = _inFlight.remove(key);
      if (reserved != null) _ledger.unreserve(reserved);
      if (_disposed) {
        r?.image.dispose();
        return;
      }
      final left = (_familyInFlight[family] ?? 1) - 1;
      if (left > 0) {
        _familyInFlight[family] = left;
      } else {
        _familyInFlight.remove(family);
      }
      if (r == null) {
        _failedAtUs[key] = nowUs;
        _failures++;
        _changes.add((formula: key.formula, failed: true));
      } else {
        if (_ledger.put(key, MathRaster._(key, r.image, r.size))) {
          _staleSiblings(key);
          (_present[key.formula] ??= {}).add(key.bucket);
          (_family[family] ??= {}).add(key.formula);
          _rasterized++;
        }
        _changes.add((formula: key.formula, failed: false));
      }
      if (left <= 0) _askWaiting(family, nowUs);
    }

    Future<OffscreenRaster?> future;
    try {
      future = _rasterizer(key.formula, key.bucket);
    } on Object {
      future = Future<OffscreenRaster?>.value();
    }
    unawaited(future.then(settle, onError: (Object _) => settle(null)));
  }

  /// (math resize fix) A raster of [key]'s LaTeX and color arrived: the family's other
  /// font sizes that arrived and were never drawn by a chunk (a resize drag's intermediate
  /// sizes — only the live layer drew them) stop holding the budget as 'fresh', so they do
  /// not push the final size to a lower bucket. A chunk that still wants one asks again.
  void _staleSiblings(MathRasterKey key) {
    final formulas = _family[_familyOf(key.formula)];
    if (formulas == null) return;
    for (final g in formulas) {
      if (g == key.formula) continue;
      for (final b in _present[g] ?? const <double>{}) {
        _ledger.markStale((formula: g, bucket: b));
      }
    }
  }

  /// (math resize fix) The family's request settled: the latest ask that waited is asked
  /// now; the others get a change event so whoever still draws them asks again (a
  /// resize drag leaves many sizes nobody draws any more — they are not rasterized).
  void _askWaiting(MathFamily family, int nowUs) {
    final waiting = _waiting.remove(family);
    if (waiting == null || waiting.isEmpty) return;
    final latest = waiting.keys.last;
    final bytes = waiting.remove(latest)!;
    if (!_ledger.containsKey(latest) && !_inFlight.containsKey(latest)) {
      _request(latest, bytes, nowUs);
    }
    for (final f in {for (final k in waiting.keys) k.formula}) {
      if (f != latest.formula) _changes.add((formula: f, failed: false));
    }
  }

  void _evicted(MathRasterKey key) {
    final set = _present[key.formula];
    if (set == null) return;
    set.remove(key.bucket);
    if (set.isEmpty) {
      _present.remove(key.formula);
      final family = _familyOf(key.formula);
      final formulas = _family[family];
      formulas?.remove(key.formula);
      if (formulas != null && formulas.isEmpty) _family.remove(family);
    }
  }
}
