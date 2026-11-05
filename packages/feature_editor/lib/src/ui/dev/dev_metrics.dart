// lib/src/ui/dev/dev_metrics.dart — 04-editor 6.12.1 (EDITOR-M10: only the
// values EDITOR alone knows; latency, input rate, pressure and frame times
// come from ink.inkDiagnosticsProvider).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings/editor_settings.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../viewport/viewport_controller.dart';

@immutable
class DevMetricsSnapshot {
  const DevMetricsSnapshot({
    required this.lastKind,
    required this.activePointers,
    required this.palmRejectedCount,
    required this.inputModeLabel,
    required this.zoom,
    required this.scale,
    required this.visibleRangeLabel,
    required this.mountedRangeLabel,
    required this.currentPage,
    required this.currentPageStrokes,
    required this.lastStrokePoints,
  });

  static const DevMetricsSnapshot empty = DevMetricsSnapshot(
    lastKind: null,
    activePointers: 0,
    palmRejectedCount: 0,
    inputModeLabel: '-',
    zoom: 0,
    scale: 0,
    visibleRangeLabel: '-',
    mountedRangeLabel: '-',
    currentPage: 0,
    currentPageStrokes: 0,
    lastStrokePoints: 0,
  );

  final PointerDeviceKind? lastKind;
  final int activePointers, palmRejectedCount;
  final String inputModeLabel; // e.g. "penOnly (auto)"
  final double zoom, scale;
  final String visibleRangeLabel, mountedRangeLabel;

  /// 1-based (0 = no page yet).
  final int currentPage;
  final int currentPageStrokes, lastStrokePoints;

  @override
  bool operator ==(Object other) =>
      other is DevMetricsSnapshot &&
      other.lastKind == lastKind &&
      other.activePointers == activePointers &&
      other.palmRejectedCount == palmRejectedCount &&
      other.inputModeLabel == inputModeLabel &&
      other.zoom == zoom &&
      other.scale == scale &&
      other.visibleRangeLabel == visibleRangeLabel &&
      other.mountedRangeLabel == mountedRangeLabel &&
      other.currentPage == currentPage &&
      other.currentPageStrokes == currentPageStrokes &&
      other.lastStrokePoints == lastStrokePoints;

  @override
  int get hashCode => Object.hash(
    lastKind,
    activePointers,
    palmRejectedCount,
    inputModeLabel,
    zoom,
    scale,
    visibleRangeLabel,
    mountedRangeLabel,
    currentPage,
    currentPageStrokes,
    lastStrokePoints,
  );
}

/// The label of the input mode for the overlay: "penOnly (auto)",
/// "fingerDrawing (auto)", "penOnly", "fingerDrawing".
String inputModeLabelOf(EditorSettings settings) {
  final effective = settings.isPenOnlyEffective
      ? InputMode.penOnly
      : InputMode.fingerDrawing;
  return settings.inputMode == InputMode.auto
      ? '${effective.name} (auto)'
      : settings.inputMode.name;
}

/// "a–b" (1-based) for a page range, '-' without one.
String pageRangeLabel(({int first, int last})? range) {
  if (range == null) return '-';
  return range.first == range.last
      ? '${range.first + 1}'
      : '${range.first + 1}–${range.last + 1}';
}

/// EDITOR-only values. Collects only while running (overlay visible). Publishes ≤ 4 Hz:
/// a change starts a one-shot [publishInterval] timer; changes until it fires
/// are published together (listeners are notified once per interval at most).
class DevMetrics extends ChangeNotifier {
  DevMetrics({this.publishInterval = const Duration(milliseconds: 250)});
  final Duration publishInterval;

  bool _running = false;
  bool _disposed = false;
  Timer? _publish;
  DevMetricsSnapshot _snapshot = DevMetricsSnapshot.empty;

  PointerDeviceKind? _lastKind;
  int _activePointers = 0, _palmRejected = 0;
  String _inputMode = '-';
  double _zoom = 0, _scale = 0;
  String _visible = '-', _mounted = '-';
  int _currentPage = 0, _pageStrokes = 0, _lastStrokePoints = 0;

  void start() {
    if (_disposed) return;
    _running = true;
  }

  /// Stops collecting (a pending publish is dropped; the counters stay).
  void stop() {
    _running = false;
    _publish?.cancel();
    _publish = null;
  }

  bool get isRunning => _running;

  /// Counters back to zero (developer menu '진단 초기화').
  void reset() {
    _palmRejected = 0;
    _lastStrokePoints = 0;
    _lastKind = null;
    _changed();
  }

  void recordPointer(
    PointerEvent event, {
    required bool drawing,
    required int activePointers,
  }) {
    if (!_running) return;
    _lastKind = event.kind;
    _activePointers = activePointers;
    _changed();
  }

  void recordStrokeCommitted({required int pointCount}) {
    if (!_running) return;
    _lastStrokePoints = pointCount;
    _changed();
  }

  void recordPalmRejected() {
    if (!_running) return;
    _palmRejected++;
    _changed();
  }

  void recordViewport(ViewportController viewport) {
    if (!_running) return;
    _zoom = viewport.zoom;
    _scale = viewport.camera.scale;
    _visible = pageRangeLabel(viewport.visibleRange);
    _mounted = pageRangeLabel(viewport.mountedRange);
    _currentPage = viewport.pages.isEmpty
        ? 0
        : viewport.currentPageIndex.value + 1;
    _changed();
  }

  void recordPage({required int strokes}) {
    if (!_running) return;
    _pageStrokes = strokes;
    _changed();
  }

  void recordInputMode(String label) {
    if (!_running) return;
    _inputMode = label;
    _changed();
  }

  /// The last published values.
  DevMetricsSnapshot get snapshot => _snapshot;

  void _changed() {
    if (_disposed || _publish != null) return;
    _publish = Timer(publishInterval, _flush);
  }

  void _flush() {
    _publish = null;
    if (_disposed) return;
    final next = DevMetricsSnapshot(
      lastKind: _lastKind,
      activePointers: _activePointers,
      palmRejectedCount: _palmRejected,
      inputModeLabel: _inputMode,
      zoom: _zoom,
      scale: _scale,
      visibleRangeLabel: _visible,
      mountedRangeLabel: _mounted,
      currentPage: _currentPage,
      currentPageStrokes: _pageStrokes,
      lastStrokePoints: _lastStrokePoints,
    );
    if (next == _snapshot) return;
    _snapshot = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _running = false;
    _publish?.cancel();
    super.dispose();
  }
}

final editorDevMetricsProvider = Provider<DevMetrics>((ref) {
  final m = DevMetrics();
  ref.onDispose(m.dispose);
  return m;
}, name: 'editorDevMetricsProvider');

/// `?dev=1` in the page address (web; read only, never stored — 6.12.2).
final editorDevUrlFlagProvider = Provider<bool>(
  (ref) => Uri.base.queryParameters['dev'] == '1',
  name: 'editorDevUrlFlagProvider',
);

/// EditorSettings.showDevOverlay ∨ the URL flag.
final editorDevOverlayVisibleProvider = Provider<bool>(
  (ref) =>
      ref.watch(editorSettingsProvider.select((s) => s.showDevOverlay)) ||
      ref.watch(editorDevUrlFlagProvider),
  name: 'editorDevOverlayVisibleProvider',
);
