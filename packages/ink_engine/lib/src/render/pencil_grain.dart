// lib/src/render/pencil_grain.dart — 03-ink 4.9, 6.11.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../tuning.dart';

/// Deterministic tileable grain texture for the pencil (6.11). Generated asynchronously once.
final class PencilGrain extends ValueNotifier<ui.Image?> {
  /// Generation starts on first use — the first listener (a painter's `repaint:`),
  /// [ready] or [value] — and runs once. Not in the constructor: on the web
  /// decodeImageFromPixels schedules an engine Timer.run, which would leave a pending
  /// timer in every widget test that merely builds a controller or reads the provider.
  PencilGrain() : super(null);

  final Completer<ui.Image> _ready = Completer<ui.Image>();
  bool _started = false;
  bool _disposed = false;

  Future<ui.Image> get ready {
    _ensureStarted();
    return _ready.future;
  }

  @override
  ui.Image? get value {
    _ensureStarted();
    return super.value;
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _ensureStarted();
  }

  void _ensureStarted() {
    if (_started || _disposed) return;
    _started = true;
    const size = InkTuning.grainSize;
    final pixels = generatePixels();
    try {
      ui.decodeImageFromPixels(pixels, size, size, ui.PixelFormat.rgba8888, (
        image,
      ) {
        if (_disposed) {
          image.dispose();
          return;
        }
        value = image;
        if (!_ready.isCompleted) _ready.complete(image);
      });
    } on Object catch (error, stack) {
      // Painters draw without grain until it is ready (6.11); report and go on.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'ink_engine',
          context: ErrorDescription('while generating the pencil grain'),
        ),
      );
    }
  }

  /// RGBA8888 pixels (white, alpha = grain). Same bytes on VM and web (arithmetic PRNG, 6.26).
  ///
  /// alpha = round(255 · (0.62 + 0.38 · v)), v = 0.65 · n(x, y) + 0.35 · bilinear(c(x/4, y/4));
  /// n per pixel and c on a (size/4)² coarse grid (wrapping, so the tile repeats) are
  /// MINSTD values (s ← s · 48271 mod (2³¹ − 1)), c first, both row-major. Arithmetic
  /// only: s · 48271 < 2⁴⁷ is exact in a double, no bit operations (7.4.3).
  static Uint8List generatePixels({
    int size = InkTuning.grainSize,
    int seed = InkTuning.grainSeed,
  }) {
    if (size < 1) throw ArgumentError.value(size, 'size', 'must be >= 1');
    const m = 2147483647; // 2^31 - 1
    var s = seed % m;
    if (s == 0) s = 1;
    double next() {
      s = (s * 48271) % m;
      return s / m;
    }

    final cs = math.max(1, (size + 3) ~/ 4);
    final coarse = Float64List(cs * cs);
    for (var i = 0; i < coarse.length; i++) {
      coarse[i] = next();
    }
    final out = Uint8List(size * size * 4);
    for (var y = 0; y < size; y++) {
      final v = y / 4;
      final j0 = v.floor() % cs;
      final j1 = (j0 + 1) % cs;
      final fv = v - v.floor();
      for (var x = 0; x < size; x++) {
        final u = x / 4;
        final i0 = u.floor() % cs;
        final i1 = (i0 + 1) % cs;
        final fu = u - u.floor();
        final top = coarse[j0 * cs + i0] * (1 - fu) + coarse[j0 * cs + i1] * fu;
        final bottom =
            coarse[j1 * cs + i0] * (1 - fu) + coarse[j1 * cs + i1] * fu;
        final bil = top * (1 - fv) + bottom * fv;
        final value = 0.65 * next() + 0.35 * bil;
        final o = (y * size + x) * 4;
        out[o] = 255;
        out[o + 1] = 255;
        out[o + 2] = 255;
        out[o + 3] = (255 * (0.62 + 0.38 * value)).round();
      }
    }
    return out;
  }

  @override
  void dispose() {
    _disposed = true;
    super.value?.dispose();
    super.dispose();
  }
}
