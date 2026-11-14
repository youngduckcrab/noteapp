// lib/src/render/pens/pen_random.dart — INTERNAL (v2.11, C211-01) deterministic
// randomness for the pens. FOUNDATION FILE (shared).
//
// Arithmetic only (7.4.3): the same numbers on the VM and the web. MINSTD like
// the pencil grain (s ← s · 48271 mod (2³¹ − 1); s · 48271 < 2⁴⁷ is exact in a
// double), seeds folded with the same multiply-mod, never bit operations,
// String.hashCode or dart:math Random.

const int _m = 2147483647; // 2^31 - 1

/// A seed in [1, 2³¹ − 2] from [values] (ints or doubles — doubles are
/// quantized to 1/16 pt first, so live and stored points that round alike agree).
int penSeed(Iterable<num> values) {
  var s = 20261114;
  for (final v in values) {
    final q = v is int ? v : (v * 16).round();
    s = (s * 48271 + q % _m + _m) % _m;
  }
  return s == 0 ? 1 : s;
}

/// MINSTD stream. Not cryptographic; same sequence on every platform.
final class PenRandom {
  PenRandom(int seed) : _s = _start(seed);

  PenRandom._at(this._s);

  int _s;

  /// A copy that continues from the same state (the live stroke tries ahead
  /// on a copy and keeps the original for the part that is final).
  PenRandom copy() => PenRandom._at(_s);

  static int _start(int seed) {
    final s = seed % _m;
    return s <= 0 ? 1 : s;
  }

  /// Uniform in (0, 1).
  double next() {
    _s = (_s * 48271) % _m;
    return _s / _m;
  }

  /// Uniform in [lo, hi).
  double range(double lo, double hi) => lo + (hi - lo) * next();

  /// Uniform int in [0, n).
  int nextInt(int n) => (next() * n).floor().clamp(0, n - 1);
}
