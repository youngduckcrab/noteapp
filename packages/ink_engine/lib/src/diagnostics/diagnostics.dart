// lib/src/diagnostics/diagnostics.dart — 03-ink 4.12. The app's ONLY latency / input-rate
// source (contract 7.2.15).
//
// INK T11 (6.15): input Hz, samples per frame, pressure / tilt / width factor of
// the last sample, warnings, cache stats, tile raster times, the receive→paint /
// event→paint windows and — from the FrameTimings of
// SchedulerBinding.addTimingsCallback, attached while enabled — frame build /
// raster p95 and event→rasterEnd (the frame whose [buildStart, rasterStart]
// holds the paint; only when the clock shares the event / frame timeline).
// Listeners are notified from a timer, at most every 250 ms and never inside
// a hook (hooks run during paint).
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:meta/meta.dart' as meta;

import '../input/ink_sample.dart';
import '../input/pressure_capability.dart';
import '../render/cache_pool.dart';
import '../tuning.dart';
import 'ink_clock.dart';

@immutable
final class LatencySummary {
  const LatencySummary({
    required this.p50Ms,
    required this.p95Ms,
    required this.maxMs,
    required this.count,
  });
  final double p50Ms;
  final double p95Ms;
  final double maxMs;
  final int count;
  static const LatencySummary empty = LatencySummary(
    p50Ms: 0,
    p95Ms: 0,
    maxMs: 0,
    count: 0,
  );

  /// Nearest-rank p50 / p95 and max of [valuesMs]; empty when there is none.
  static LatencySummary _of(List<double> valuesMs) {
    if (valuesMs.isEmpty) return empty;
    final sorted = List<double>.of(valuesMs)..sort();
    double rank(double q) {
      final i = (q * sorted.length).ceil() - 1;
      return sorted[i.clamp(0, sorted.length - 1)];
    }

    return LatencySummary(
      p50Ms: rank(0.5),
      p95Ms: rank(0.95),
      maxMs: sorted.last,
      count: sorted.length,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LatencySummary &&
      other.p50Ms == p50Ms &&
      other.p95Ms == p95Ms &&
      other.maxMs == maxMs &&
      other.count == count;

  @override
  int get hashCode => Object.hash(p50Ms, p95Ms, maxMs, count);
}

@immutable
final class InkStatsSnapshot {
  const InkStatsSnapshot({
    required this.lastKind,
    required this.lastRawPressure,
    required this.lastNormalizedPressure,
    required this.lastWidthFactor,
    required this.lastTilt,
    required this.lastOrientation,
    required this.pressureSource,
    required this.stylusCapability,
    required this.inputHz,
    required this.samplesPerFrame,
    required this.eventToPaint,
    required this.receiveToPaint,
    required this.eventToRasterEnd,
    required this.frameBuildP95Ms,
    required this.frameRasterP95Ms,
    required this.activeStrokeUpdateMs,
    required this.lastTileRasterMs,
    required this.tileRaster,
    required this.visibleStrokeCount,
    required this.cache,
    required this.clockAligned,
    required this.warnings,
  });
  final InkPointerKind? lastKind;

  /// raw pressure is shown here only (never stored, 7.2.3)
  final double? lastRawPressure;
  final double? lastNormalizedPressure;

  /// f actually used (after curve, simulation, tilt)
  final double? lastWidthFactor;
  final double? lastTilt;
  final double? lastOrientation;
  final PressureSource pressureSource;
  final PressureCapability stylusCapability;

  /// samples per second (last 1 s)
  final double inputHz;

  /// > 1 means coalesced events are delivered
  final double samplesPerFrame;

  /// meaningful only when clockAligned
  final LatencySummary eventToPaint;
  final LatencySummary receiveToPaint;

  /// web: via FrameTiming (6.15)
  final LatencySummary eventToRasterEnd;
  final double frameBuildP95Ms;
  final double frameRasterP95Ms;
  final double activeStrokeUpdateMs;
  final double lastTileRasterMs;

  /// per-tile raster time; p95 decides the web default (6.14)
  final LatencySummary tileRaster;
  final int visibleStrokeCount;
  final InkCacheStats cache;
  final bool clockAligned;

  /// skipped strokes, pending timeouts, ...
  final int warnings;

  static const InkStatsSnapshot empty = InkStatsSnapshot(
    lastKind: null,
    lastRawPressure: null,
    lastNormalizedPressure: null,
    lastWidthFactor: null,
    lastTilt: null,
    lastOrientation: null,
    pressureSource: PressureSource.pending,
    stylusCapability: PressureCapability.unknown,
    inputHz: 0,
    samplesPerFrame: 0,
    eventToPaint: LatencySummary.empty,
    receiveToPaint: LatencySummary.empty,
    eventToRasterEnd: LatencySummary.empty,
    frameBuildP95Ms: 0,
    frameRasterP95Ms: 0,
    activeStrokeUpdateMs: 0,
    lastTileRasterMs: 0,
    tileRaster: LatencySummary.empty,
    visibleStrokeCount: 0,
    cache: InkCacheStats.empty,
    clockAligned: false,
    warnings: 0,
  );

  @override
  bool operator ==(Object other) =>
      other is InkStatsSnapshot &&
      other.lastKind == lastKind &&
      other.lastRawPressure == lastRawPressure &&
      other.lastNormalizedPressure == lastNormalizedPressure &&
      other.lastWidthFactor == lastWidthFactor &&
      other.lastTilt == lastTilt &&
      other.lastOrientation == lastOrientation &&
      other.pressureSource == pressureSource &&
      other.stylusCapability == stylusCapability &&
      other.inputHz == inputHz &&
      other.samplesPerFrame == samplesPerFrame &&
      other.eventToPaint == eventToPaint &&
      other.receiveToPaint == receiveToPaint &&
      other.eventToRasterEnd == eventToRasterEnd &&
      other.frameBuildP95Ms == frameBuildP95Ms &&
      other.frameRasterP95Ms == frameRasterP95Ms &&
      other.activeStrokeUpdateMs == activeStrokeUpdateMs &&
      other.lastTileRasterMs == lastTileRasterMs &&
      other.tileRaster == tileRaster &&
      other.visibleStrokeCount == visibleStrokeCount &&
      other.cache == cache &&
      other.clockAligned == clockAligned &&
      other.warnings == warnings;

  @override
  int get hashCode => Object.hashAll([
    lastKind,
    lastRawPressure,
    lastNormalizedPressure,
    lastWidthFactor,
    lastTilt,
    lastOrientation,
    pressureSource,
    stylusCapability,
    inputHz,
    samplesPerFrame,
    eventToPaint,
    receiveToPaint,
    eventToRasterEnd,
    frameBuildP95Ms,
    frameRasterP95Ms,
    activeStrokeUpdateMs,
    lastTileRasterMs,
    tileRaster,
    visibleStrokeCount,
    cache,
    clockAligned,
    warnings,
  ]);
}

class InkDiagnostics extends ChangeNotifier {
  InkDiagnostics({required this._clock});

  final InkClock _clock;
  bool _enabled = false;
  bool _timingsAttached = false;
  bool _disposed = false;

  /// Collects only while true; attaches SchedulerBinding.addTimingsCallback when enabled.
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value || _disposed) return;
    _enabled = value;
    _snapshot = null;
    if (value) {
      _attachTimings();
    } else {
      _detachTimings();
      _cancelNotify();
      _awaitingFrame.clear();
    }
    notifyListeners();
  }

  // --- collected state ---------------------------------------------------
  InkPointerKind? _lastKind;
  double? _lastRawPressure;
  double? _lastNormalizedPressure;
  double? _lastWidthFactor;
  double? _lastTilt;
  double? _lastOrientation;
  PressureSource _pressureSource = PressureSource.pending;
  PressureCapability _stylusCapability = PressureCapability.unknown;
  final List<int> _receiveTimesUs = [];
  final List<int> _paintTimesUs = [];
  final List<double> _eventToPaint = [];
  final List<double> _receiveToPaint = [];
  final List<double> _frameBuildMs = [];
  final List<double> _frameRasterMs = [];
  final List<double> _tileRaster = [];
  final List<double> _eventToRasterEnd = [];

  /// (m5-7 T40) layer 4′ playback emphasis paint times (µs).
  final List<double> _playbackPaintUs = [];

  /// Active paints (paint time, event time of the newest sample painted)
  /// waiting for their FrameTiming, oldest first.
  final List<(int, int)> _awaitingFrame = [];
  int? _pendingReceiveUs;
  int? _pendingEventUs;
  double _activeStrokeUpdateMs = 0;
  double _lastTileRasterMs = 0;
  int _visibleStrokeCount = 0;
  InkCacheStats _cache = InkCacheStats.empty;
  int _warnings = 0;

  InkStatsSnapshot? _snapshot;

  // throttled notification (6.15: at most every 250 ms)
  Timer? _notifyTimer;
  bool _notifyQueued = false;
  bool _changedWhileCooling = false;

  /// Notifies listeners at most every 250 ms.
  InkStatsSnapshot get snapshot => _snapshot ??= _buildSnapshot();

  void reset() {
    _lastKind = null;
    _lastRawPressure = null;
    _lastNormalizedPressure = null;
    _lastWidthFactor = null;
    _lastTilt = null;
    _lastOrientation = null;
    _pressureSource = PressureSource.pending;
    _stylusCapability = PressureCapability.unknown;
    _receiveTimesUs.clear();
    _paintTimesUs.clear();
    _eventToPaint.clear();
    _receiveToPaint.clear();
    _frameBuildMs.clear();
    _frameRasterMs.clear();
    _tileRaster.clear();
    _eventToRasterEnd.clear();
    _playbackPaintUs.clear();
    _awaitingFrame.clear();
    _pendingReceiveUs = null;
    _pendingEventUs = null;
    _activeStrokeUpdateMs = 0;
    _lastTileRasterMs = 0;
    _visibleStrokeCount = 0;
    _cache = InkCacheStats.empty;
    _warnings = 0;
    _snapshot = null;
    _cancelNotify();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _detachTimings();
    _cancelNotify();
    super.dispose();
  }

  // Hooks called by INK internals.
  @meta.internal
  void onSamples(Iterable<InkSample> samples, {required int receiveUs}) {
    if (!_enabled) return;
    var any = false;
    for (final s in samples) {
      any = true;
      _lastKind = s.kind;
      _lastRawPressure = s.pressure;
      _lastNormalizedPressure = s.normalizedPressure;
      _lastTilt = s.tilt;
      _lastOrientation = s.orientation;
      _receiveTimesUs.add(receiveUs);
      _pendingEventUs = s.timeUs;
    }
    if (!any) return;
    _pendingReceiveUs = receiveUs;
    _trimWindow(_receiveTimesUs, receiveUs);
    _changed();
  }

  @meta.internal
  void onActivePaint({required int paintUs, required double updateMs}) {
    if (!_enabled) return;
    _activeStrokeUpdateMs = updateMs;
    _paintTimesUs.add(paintUs);
    _trimWindow(_paintTimesUs, paintUs);
    final receiveUs = _pendingReceiveUs;
    if (receiveUs != null) {
      _push(_receiveToPaint, (paintUs - receiveUs) / 1000);
      _pendingReceiveUs = null;
    }
    final eventUs = _pendingEventUs;
    if (eventUs != null) {
      _push(_eventToPaint, (paintUs - eventUs) / 1000);
      _pendingEventUs = null;
      if (_clock.alignedWithEventTimestamps) {
        _awaitingFrame.add((paintUs, eventUs));
        if (_awaitingFrame.length > _maxAwaitingFrame) {
          _awaitingFrame.removeAt(0);
        }
      }
    }
    _changed();
  }

  /// Frame build / raster durations; event→rasterEnd for every awaiting paint
  /// inside [buildStart, rasterStart] of a frame (6.15). Paints before a
  /// frame's buildStart never get a later frame and are dropped.
  @meta.internal
  void onFrameTimings(List<ui.FrameTiming> timings) {
    if (!_enabled) return;
    for (final t in timings) {
      _push(_frameBuildMs, t.buildDuration.inMicroseconds / 1000);
      _push(_frameRasterMs, t.rasterDuration.inMicroseconds / 1000);
      if (_awaitingFrame.isEmpty) continue;
      final buildStart = t.timestampInMicroseconds(ui.FramePhase.buildStart);
      final rasterStart = t.timestampInMicroseconds(ui.FramePhase.rasterStart);
      final rasterFinish = t.timestampInMicroseconds(
        ui.FramePhase.rasterFinish,
      );
      _awaitingFrame.removeWhere((p) {
        final (paintUs, eventUs) = p;
        if (paintUs < buildStart) return true;
        if (paintUs > rasterStart) return false;
        _push(_eventToRasterEnd, (rasterFinish - eventUs) / 1000);
        return true;
      });
    }
    _changed();
  }

  @meta.internal
  void onWidthFactor(
    double factor,
    PressureSource source,
    PressureCapability stylusCapability,
  ) {
    if (!_enabled) return;
    _lastWidthFactor = factor;
    _pressureSource = source;
    _stylusCapability = stylusCapability;
    _changed();
  }

  @meta.internal
  void onTileRaster(double ms) {
    if (!_enabled) return;
    _lastTileRasterMs = ms;
    _push(_tileRaster, ms);
    _changed();
  }

  @meta.internal
  void onCacheStats(InkCacheStats stats, {required int visibleStrokes}) {
    if (!_enabled) return;
    _cache = stats;
    _visibleStrokeCount = visibleStrokes;
    _changed();
  }

  /// (m5-7 T40, 6.19-6) The paint time of one layer 4′ playback emphasis paint.
  @meta.internal
  void onPlaybackPaint(int us) {
    if (!_enabled) return;
    _push(_playbackPaintUs, us.toDouble());
  }

  /// (m5-7 T40, 6.19-6) Developer display values that are not in [snapshot] (the
  /// contract's snapshot fields stay as they are): `playbackPaintUs` = the p95 (µs,
  /// nearest rank) of the last InkTuning.latencyWindow layer 4′ playback paints —
  /// present once one was measured while [enabled].
  @meta.internal
  Map<String, num> get developerValues => {
    if (_playbackPaintUs.isNotEmpty)
      'playbackPaintUs': LatencySummary._of(_playbackPaintUs).p95Ms,
  };

  @meta.internal
  void onWarning(String code) {
    if (!_enabled) return;
    _warnings++;
    _changed();
  }

  // --- internals -----------------------------------------------------------
  static const int _maxAwaitingFrame = 64;

  void _attachTimings() {
    if (_timingsAttached) return;
    final SchedulerBinding binding;
    try {
      binding = SchedulerBinding.instance;
    } on FlutterError {
      return; // no binding (pure Dart test): frames are fed by onFrameTimings
    }
    binding.addTimingsCallback(onFrameTimings);
    _timingsAttached = true;
  }

  void _detachTimings() {
    if (!_timingsAttached) return;
    SchedulerBinding.instance.removeTimingsCallback(onFrameTimings);
    _timingsAttached = false;
  }

  static void _push(List<double> window, double value) {
    window.add(value);
    if (window.length > InkTuning.latencyWindow) window.removeAt(0);
  }

  /// Keeps the timestamps of the last second.
  static void _trimWindow(List<int> times, int nowUs) {
    final from = nowUs - 1000000;
    var drop = 0;
    while (drop < times.length && times[drop] < from) {
      drop++;
    }
    if (drop > 0) times.removeRange(0, drop);
  }

  /// Leading edge from a zero timer (hooks run during paint, so never
  /// synchronously), then at most one more notification per 250 ms window
  /// for the changes made meanwhile (trailing edge).
  void _changed() {
    _snapshot = null;
    if (_notifyQueued) return;
    if (_notifyTimer != null) {
      _changedWhileCooling = true;
      return;
    }
    _notifyQueued = true;
    _notifyTimer = Timer(Duration.zero, _notifyNow);
  }

  void _notifyNow() {
    _notifyQueued = false;
    _notifyTimer = Timer(
      const Duration(milliseconds: InkTuning.diagnosticsNotifyMs),
      _coolingEnded,
    );
    notifyListeners();
  }

  void _coolingEnded() {
    _notifyTimer = null;
    if (!_changedWhileCooling) return;
    _changedWhileCooling = false;
    _changed();
  }

  void _cancelNotify() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _notifyQueued = false;
    _changedWhileCooling = false;
  }

  InkStatsSnapshot _buildSnapshot() {
    final hz = _receiveTimesUs.length.toDouble();
    final frames = _paintTimesUs.length;
    return InkStatsSnapshot(
      lastKind: _lastKind,
      lastRawPressure: _lastRawPressure,
      lastNormalizedPressure: _lastNormalizedPressure,
      lastWidthFactor: _lastWidthFactor,
      lastTilt: _lastTilt,
      lastOrientation: _lastOrientation,
      pressureSource: _pressureSource,
      stylusCapability: _stylusCapability,
      inputHz: hz,
      samplesPerFrame: frames == 0 ? 0 : hz / math.max(1, frames),
      eventToPaint: LatencySummary._of(_eventToPaint),
      receiveToPaint: LatencySummary._of(_receiveToPaint),
      eventToRasterEnd: LatencySummary._of(_eventToRasterEnd),
      frameBuildP95Ms: LatencySummary._of(_frameBuildMs).p95Ms,
      frameRasterP95Ms: LatencySummary._of(_frameRasterMs).p95Ms,
      activeStrokeUpdateMs: _activeStrokeUpdateMs,
      lastTileRasterMs: _lastTileRasterMs,
      tileRaster: LatencySummary._of(_tileRaster),
      visibleStrokeCount: _visibleStrokeCount,
      cache: _cache,
      clockAligned: _clock.alignedWithEventTimestamps,
      warnings: _warnings,
    );
  }
}
