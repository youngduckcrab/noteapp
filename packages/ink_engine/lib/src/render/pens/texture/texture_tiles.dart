// lib/src/render/pens/texture/texture_tiles.dart — INTERNAL (v2.11, C211-01)
// paper-fixed texture tiles of the texture pens. OWNED BY THE TEXTURE TRACK.
//
// Ported from the lock-screen app's "결 타일" (paperTile / washTile / toothTile):
// two 256² tiles, each channel a deterministic noise field equalized by rank,
// so a threshold t on a channel leaves exactly the fraction t of the paper
// uncovered. The pens paint their shapes with an ImageShader of a tile
// (page-anchored, one texel = InkTuning.grainTexelPt pt, optionally rotated)
// and a ColorFilter.matrix that turns one channel into alpha
// (alpha = gain · channel + offset, clamped — the lock app's `tilePaint`).
//
//   tooth tile  R wax   (crayon: 2–4 texel lumps, long horizontal ridges)
//               G chalk (chalk: coarser, longer streaks)
//               B graph (pencil: fine, slightly stretched)
//   wash tile   R flow  (watercolor bloom / brush bleed: medium blobs)
//               G dust  (fine powder)
//               B mottle (slow puddles)
//
// The tiles are generated in the same async step as the pencil grain
// (pencil_grain.dart) and registered for that grain image: a renderer that
// receives a grain finds the tiles with TextureTiles.of(grain) — "grain ready
// ⇒ tiles ready", so the existing missing-grain re-record logic covers them.
// Arithmetic only (7.4.3): MINSTD streams, box blurs, rank equalization — no
// bit operations, no exp / sin, so the bytes are the same on the VM and the web.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../tuning.dart';

/// Tile side (texels).
const int kTextureTileSize = 256;

/// Channels of the tiles (the matrix column of the channel).
enum TileChannel {
  /// tooth tile
  wax(0),
  chalk(1),
  graph(2),

  /// wash tile
  flow(0),
  dust(1),
  mottle(2);

  const TileChannel(this.index3);

  /// 0 = R, 1 = G, 2 = B
  final int index3;
}

/// The two decoded tiles.
final class TextureTiles {
  TextureTiles._(this.tooth, this.wash);

  final ui.Image tooth;
  final ui.Image wash;

  static final Expando<TextureTiles> _byGrain = Expando<TextureTiles>(
    'TextureTiles',
  );

  /// The tiles generated with [grain] (null: none — the pens then paint their
  /// flat vector look).
  static TextureTiles? of(ui.Image? grain) =>
      grain == null ? null : _byGrain[grain];

  /// Registers [tiles] for [grain] (PencilGrain, before it publishes the grain).
  static void register(ui.Image grain, TextureTiles tiles) =>
      _byGrain[grain] = tiles;

  /// Decodes both tiles (the RGBA bytes of [toothPixels] and [washPixels]).
  /// [onDone] is called once with the tiles, or with null on an error.
  static void decode(void Function(TextureTiles? tiles) onDone) {
    const size = kTextureTileSize;
    final Uint8List toothBytes, washBytes;
    try {
      toothBytes = toothPixels();
      washBytes = washPixels();
    } on Object {
      onDone(null);
      return;
    }
    ui.decodeImageFromPixels(
      toothBytes,
      size,
      size,
      ui.PixelFormat.rgba8888,
      (tooth) => ui.decodeImageFromPixels(
        washBytes,
        size,
        size,
        ui.PixelFormat.rgba8888,
        (wash) => onDone(TextureTiles._(tooth, wash)),
      ),
    );
  }

  void dispose() {
    tooth.dispose();
    wash.dispose();
  }

  static Uint8List? _tooth;
  static Uint8List? _wash;

  /// RGBA bytes of the tooth tile (R wax, G chalk, B graph, A 255). Cached.
  /// Each channel: noise layers (seed, box radius x, passes x, radius y,
  /// passes y) with weights — fewer layers than the lock app's recipes (the
  /// generation runs once on the UI isolate).
  static Uint8List toothPixels() => _tooth ??= _pack(
    _layered(_waxLayers, const [0.55, 0.6, 0.35]),
    _layered(_chalkLayers, const [0.5, 0.55, 0.45]),
    _layered(_graphLayers, const [0.6, 0.5]),
  );

  /// RGBA bytes of the wash tile (R flow, G dust, B mottle, A 255). Cached.
  static Uint8List washPixels() => _wash ??= _pack(
    _layered(_flowLayers, const [0.6, 0.4]),
    _layered(_dustLayers, const [1]),
    _layered(_mottleLayers, const [1]),
  );
}

// wax: horizontal ridges + 2–4 texel lumps; chalk: coarser, longer streaks
// plus fine grain; graph: fine, slightly stretched; flow: medium blobs; dust:
// the finest noise; mottle: slow puddles.
const List<int> _waxLayers = [
  131,
  3,
  3,
  1,
  1,
  132,
  1,
  3,
  1,
  3,
  133,
  2,
  3,
  2,
  3,
];
const List<int> _chalkLayers = [
  141,
  4,
  3,
  1,
  1,
  142,
  1,
  3,
  1,
  3,
  143,
  1,
  1,
  1,
  1,
];
const List<int> _graphLayers = [151, 1, 2, 0, 0, 152, 1, 1, 1, 1];
const List<int> _flowLayers = [162, 2, 3, 2, 3, 163, 4, 3, 4, 3];
const List<int> _dustLayers = [171, 1, 1, 1, 1];
const List<int> _mottleLayers = [181, 12, 3, 12, 3];

const int _m = 2147483647; // 2^31 - 1

/// Weighted sum of noise layers (seed, rx, passes x, ry, passes y — five ints
/// per layer), rank-equalized to [0, 1].
Float64List _layered(List<int> layers, List<double> weights) {
  const n = kTextureTileSize * kTextureTileSize;
  final field = Float64List(n);
  for (var k = 0; k < weights.length; k++) {
    final o = 5 * k;
    final layer = _noiseLayer(
      layers[o],
      layers[o + 1],
      layers[o + 2],
      layers[o + 3],
      layers[o + 4],
    );
    final w = weights[k];
    for (var i = 0; i < n; i++) {
      field[i] += w * layer[i];
    }
  }
  _equalize(field);
  return field;
}

/// White noise (a MINSTD stream, row-major) box-blurred [px] times with radius
/// [rx] horizontally and [py] times with radius [ry] vertically (wrapping, so
/// the tile repeats seamlessly), then standardized (mean 0, deviation 1).
Float64List _noiseLayer(int salt, int rx, int px, int ry, int py) {
  const size = kTextureTileSize;
  var v = Float64List(size * size);
  var tmp = Float64List(size * size);
  var s = (salt * 7919 + InkTuning.grainSeed) % _m;
  if (s == 0) s = 1;
  // warm up: neighbouring salts start far apart in the stream
  for (var i = 0; i < 8; i++) {
    s = (s * 48271) % _m;
  }
  for (var i = 0; i < v.length; i++) {
    s = (s * 48271) % _m;
    v[i] = s / _m;
  }
  for (var k = 0; k < px; k++) {
    _boxBlur(v, tmp, rx, horizontal: true);
    final t = v;
    v = tmp;
    tmp = t;
  }
  for (var k = 0; k < py; k++) {
    _boxBlur(v, tmp, ry, horizontal: false);
    final t = v;
    v = tmp;
    tmp = t;
  }
  var mean = 0.0;
  for (final a in v) {
    mean += a;
  }
  mean /= v.length;
  var variance = 0.0;
  for (final a in v) {
    variance += (a - mean) * (a - mean);
  }
  final std = math.sqrt(variance / v.length) + 1e-12;
  for (var i = 0; i < v.length; i++) {
    v[i] = (v[i] - mean) / std;
  }
  return v;
}

void _boxBlur(
  Float64List src,
  Float64List dst,
  int radius, {
  required bool horizontal,
}) {
  const n = kTextureTileSize;
  if (radius <= 0) {
    dst.setAll(0, src);
    return;
  }
  final width = 2 * radius + 1;
  final step = horizontal ? 1 : n;
  for (var line = 0; line < n; line++) {
    final start = horizontal ? line * n : line;
    var sum = 0.0;
    for (var d = -radius; d <= radius; d++) {
      sum += src[start + (d % n) * step];
    }
    var add = radius + 1;
    var drop = n - radius;
    for (var p = 0; p < n; p++) {
      dst[start + p * step] = sum / width;
      if (add >= n) add -= n;
      if (drop >= n) drop -= n;
      sum += src[start + add * step] - src[start + drop * step];
      add++;
      drop++;
    }
  }
}

/// Replaces every value by its rank (4096 bins, mid-rank): threshold t then
/// leaves the fraction t of the texels below it.
void _equalize(Float64List field) {
  var lo = double.infinity, hi = double.negativeInfinity;
  for (final v in field) {
    if (v < lo) lo = v;
    if (v > hi) hi = v;
  }
  const bins = 4096;
  final index = Int32List(field.length);
  final hist = Int32List(bins);
  final span = hi - lo + 1e-12;
  for (var i = 0; i < field.length; i++) {
    final b = ((field[i] - lo) / span * (bins - 1)).floor().clamp(0, bins - 1);
    index[i] = b;
    hist[b]++;
  }
  final cdf = Float64List(bins);
  var run = 0;
  for (var b = 0; b < bins; b++) {
    run += hist[b];
    cdf[b] = (run - hist[b] * 0.5) / field.length;
  }
  for (var i = 0; i < field.length; i++) {
    field[i] = cdf[index[i]];
  }
}

Uint8List _pack(Float64List r, Float64List g, Float64List b) {
  final out = Uint8List(r.length * 4);
  for (var i = 0; i < r.length; i++) {
    final o = 4 * i;
    out[o] = (r[i] * 255).round().clamp(0, 255);
    out[o + 1] = (g[i] * 255).round().clamp(0, 255);
    out[o + 2] = (b[i] * 255).round().clamp(0, 255);
    out[o + 3] = 255;
  }
  return out;
}

// ------------------------------------------------------------- tile paints

final Map<double, Float64List> _matrices = {};

/// Texel → page pt (one texel = InkTuning.grainTexelPt pt, page-anchored),
/// rotated by [angleDeg] (the lock app's slanted ridges).
Float64List _tileMatrix(double angleDeg) {
  return _matrices[angleDeg] ??= () {
    const s = InkTuning.grainTexelPt;
    final a = angleDeg * math.pi / 180;
    final c = math.cos(a) * s, n = math.sin(a) * s;
    return Float64List.fromList([
      c, n, 0, 0, //
      -n, c, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1, //
    ]);
  }();
}

/// alpha = gains · (tile R, G, B) + offset (0..1 units, clamped by the
/// filter); the color is [argb]'s RGB. The lock app's `tilePaint`.
ui.Paint tilePaint(
  ui.Image tile,
  int argb,
  TileChannel channel,
  double gain,
  double offset, {
  double angleDeg = 0,
}) {
  final r = (argb ~/ 0x10000) % 256, g = (argb ~/ 0x100) % 256, b = argb % 256;
  final gains = [0.0, 0.0, 0.0];
  gains[channel.index3] = gain;
  return ui.Paint()
    ..isAntiAlias = true
    ..style = ui.PaintingStyle.fill
    ..shader = ui.ImageShader(
      tile,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      _tileMatrix(angleDeg),
      filterQuality: ui.FilterQuality.low,
    )
    ..filterQuality = ui.FilterQuality.low
    ..colorFilter = ui.ColorFilter.matrix([
      0, 0, 0, 0, r.toDouble(), //
      0, 0, 0, 0, g.toDouble(), //
      0, 0, 0, 0, b.toDouble(), //
      gains[0], gains[1], gains[2], 0, offset * 255, //
    ]);
}

/// Paints where the channel is above [threshold] (paper peaks): alpha =
/// clamp([amount] · (v − threshold) / [soft]).
ui.Paint abovePaint(
  ui.Image tile,
  int argb,
  TileChannel channel,
  double threshold,
  double soft, {
  double amount = 1,
  double angleDeg = 0,
}) {
  final k = amount / soft;
  return tilePaint(tile, argb, channel, k, -k * threshold, angleDeg: angleDeg);
}

/// Paints where the channel is below [threshold] (paper pits).
ui.Paint belowPaint(
  ui.Image tile,
  int argb,
  TileChannel channel,
  double threshold,
  double soft, {
  double amount = 1,
  double angleDeg = 0,
}) {
  final k = amount / soft;
  return tilePaint(tile, argb, channel, -k, k * threshold, angleDeg: angleDeg);
}

/// alpha = [mean] + [contrast] · (v − 0.5): an even, low-contrast grain.
ui.Paint aroundPaint(
  ui.Image tile,
  int argb,
  TileChannel channel,
  double mean,
  double contrast, {
  double angleDeg = 0,
}) => tilePaint(
  tile,
  argb,
  channel,
  contrast,
  mean - 0.5 * contrast,
  angleDeg: angleDeg,
);
