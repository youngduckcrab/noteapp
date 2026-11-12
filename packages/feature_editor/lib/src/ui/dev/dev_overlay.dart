// lib/src/ui/dev/dev_overlay.dart — 04-editor 6.12.1, 6.12.2; (v2, E2-20 —
// m5-7/04-editor 6.20) the pointer line's buttons / rule / airborne state,
// the hover source, the recording line and the object count.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ink_engine/ink_engine.dart' as ink;
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../../di/dev_overlay_section.dart';
import '../../document/mounted_pages.dart';
import '../../scope/editor_scope.dart';
import '../../state/settings/editor_settings.dart';
import '../../state/settings/editor_settings_notifier.dart';
import '../../viewport/viewport_controller.dart';
import 'dev_metrics.dart';

/// The developer overlay (top right of the page area, 11 px monospace over a
/// dark translucent box; IgnorePointer, RepaintBoundary).
///
/// While editorDevOverlayVisibleProvider is true (setting ∨ `?dev=1`):
/// DevMetrics runs, ink.inkDiagnosticsProvider.enabled is true, the EDITOR
/// values (viewport, current page strokes, input mode) are pushed into
/// DevMetrics and every devOverlaySectionsProvider section's lines are
/// listened to. When it turns false — or the editor screen goes away — all
/// of that stops (INK 5.3 #11).
///
/// Lines (developer text, as in 6.12.2): [INK] from InkDiagnostics.snapshot
/// (the only latency / input-rate source), [EDITOR] from DevMetrics.snapshot,
/// [저장] from core.storageInfoProvider + core.persistenceStatusProvider, then
/// one block per section. Rebuilt at most every 250 ms.
class DevOverlay extends ConsumerStatefulWidget {
  const DevOverlay({super.key});

  static const overlayKey = ValueKey('editor.devOverlay');

  /// Longest wait between a change and the rebuild that shows it.
  static const Duration refreshInterval = Duration(milliseconds: 250);

  @override
  ConsumerState<DevOverlay> createState() => _DevOverlayState();
}

class _DevOverlayState extends ConsumerState<DevOverlay> {
  bool _visible = false;
  ink.InkDiagnostics? _diagnostics;
  DevMetrics? _metrics;
  ViewportController? _viewport;
  core.NoteSession? _session;
  MountedPages? _mounted;
  StreamSubscription<List<core.Page>>? _pagesSub;
  ProviderSubscription<EditorSettings>? _settingsSub;
  Listenable? _listened;
  List<DevOverlaySection>? _sectionsListened;
  Timer? _refresh;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(
      editorDevOverlayVisibleProvider,
      (_, visible) => _apply(visible),
      fireImmediately: true,
    );
    _initialized = true;
  }

  void _apply(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      final diagnostics = ref.read(ink.inkDiagnosticsProvider);
      final metrics = ref.read(editorDevMetricsProvider);
      final viewport = ref.read(editorViewportProvider);
      final session = ref.read(editorSessionValueProvider);
      _diagnostics = diagnostics;
      _metrics = metrics;
      _viewport = viewport;
      _session = session;
      metrics.start();
      diagnostics.enabled = true;
      viewport.addListener(_onViewport);
      _pagesSub = session.pagesStream.listen((_) => _onPage());
      // (v2) a page mounted (its content loaded) → its counts.
      final MountedPages pages = ref.read(editorMountedPagesProvider);
      _mounted = pages;
      pages.addListener(_onPage);
      _settingsSub = ref.listenManual<EditorSettings>(
        editorSettingsProvider,
        (_, s) => metrics.recordInputMode(inputModeLabelOf(s)),
        fireImmediately: true,
      );
      _onViewport();
    } else {
      _stop();
    }
    if (_initialized && mounted) setState(() {});
  }

  void _stop() {
    _metrics?.stop();
    _diagnostics?.enabled = false;
    _viewport?.removeListener(_onViewport);
    _mounted?.removeListener(_onPage);
    _mounted = null;
    unawaited(_pagesSub?.cancel());
    _pagesSub = null;
    _settingsSub?.close();
    _settingsSub = null;
    _unlisten();
    _refresh?.cancel();
    _refresh = null;
  }

  void _onViewport() {
    final viewport = _viewport;
    if (viewport == null) return;
    _metrics?.recordViewport(viewport);
    _onPage();
  }

  void _onPage() {
    final viewport = _viewport, session = _session;
    if (viewport == null || session == null) return;
    final pages = session.pages;
    if (pages.isEmpty) return;
    final current =
        pages[viewport.currentPageIndex.value.clamp(0, pages.length - 1)];
    final content = session.pageIfLoaded(current.id);
    _metrics?.recordPage(
      strokes: content?.strokeCount ?? 0,
      objects: content?.objectCount ?? 0,
    );
  }

  /// Listens to the diagnostics, the metrics and the section lines while
  /// visible (re-listened when the section list changes).
  void _listen(List<DevOverlaySection> sections) {
    if (identical(sections, _sectionsListened) && _listened != null) return;
    _unlisten();
    _sectionsListened = sections;
    final listened = _listened = Listenable.merge([
      _diagnostics!,
      _metrics!,
      for (final s in sections) s.lines,
    ]);
    listened.addListener(_changed);
  }

  void _unlisten() {
    _listened?.removeListener(_changed);
    _listened = null;
    _sectionsListened = null;
  }

  void _changed() {
    if (_refresh != null) return;
    _refresh = Timer(DevOverlay.refreshInterval, () {
      _refresh = null;
      if (mounted && _visible) setState(() {});
    });
  }

  @override
  void dispose() {
    _stop(); // leaving the editor turns the collection off
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = ref.watch(devOverlaySectionsProvider);
    if (!_visible) {
      _unlisten();
      return const SizedBox.shrink();
    }
    _listen(sections);
    final info = ref.watch(core.storageInfoProvider);
    final status = ref.watch(core.persistenceStatusProvider).value;
    final lines = <String>[
      ...devInkLines(_diagnostics!.snapshot),
      ?devInkValuesLine(_diagnostics!.developerValues),
      ...devEditorLines(_metrics!.snapshot),
      devRecordingLine(
        recorder: ref.read(core.audioRecorderServiceProvider).status,
        lastStrokeOffsetMs: _metrics!.snapshot.lastStrokeOffsetMs,
        playback: ref.read(core.audioPlaybackServiceProvider).status,
        positionMs: ref.read(core.audioPlaybackServiceProvider).positionMs(),
      ),
      devStorageLine(info, status),
      for (final s in sections) ...[
        '[${s.title}]',
        for (final l in s.lines.value) '       $l',
      ],
    ];
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: RepaintBoundary(
            child: DecoratedBox(
              key: DevOverlay.overlayKey,
              decoration: BoxDecoration(
                color: scheme.inverseSurface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  lines.join('\n'),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.3,
                    color: scheme.onInverseSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _ms(double v) => v.toStringAsFixed(v >= 10 ? 0 : 1);

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

String _opt(double? v, [int digits = 2]) =>
    v == null ? '-' : v.toStringAsFixed(digits);

String _deg(double? radians) =>
    radians == null ? '-' : '${(radians * 180 / 3.141592653589793).round()}°';

/// [INK] block (6.12.2) from the INK snapshot.
List<String> devInkLines(ink.InkStatsSnapshot s) {
  final lat = s.eventToPaint;
  final latency =
      '[INK]  지연 p50 ${_ms(lat.p50Ms)}ms p95 ${_ms(lat.p95Ms)}ms '
      'max ${_ms(lat.maxMs)}  (event→paint, n=${lat.count})   '
      '시계 정렬 ${s.clockAligned ? '✓' : '✗'}';
  final input =
      '       입력 ${s.lastKind?.name ?? '-'} ${s.inputHz.round()}Hz  '
      '프레임당 ${s.samplesPerFrame.toStringAsFixed(1)}   '
      'frame p95 b ${_ms(s.frameBuildP95Ms)} / r ${_ms(s.frameRasterP95Ms)}ms   '
      '활성 획 ${_ms(s.activeStrokeUpdateMs)}ms';
  final pressure =
      '       필압 ${_opt(s.lastNormalizedPressure)} '
      '(raw ${_opt(s.lastRawPressure)}) 굵기계수 ${_opt(s.lastWidthFactor)}  '
      '기울기 ${_deg(s.lastTilt)}  방위 ${_deg(s.lastOrientation)}  '
      '출처 ${s.pressureSource.name}  감지 ${s.stylusCapability.name}';
  final cache =
      '       캐시 외곽선 ${_mb(s.cache.outlineBytes)}(${s.cache.outlineEntries}) '
      '타일 ${_mb(s.cache.rasterBytes)}(${s.cache.rasterTiles})  '
      '보이는 획 ${s.visibleStrokeCount}  타일 래스터 ${_ms(s.lastTileRasterMs)}ms  '
      '경고 ${s.warnings}';
  return [latency, input, pressure, cache];
}

/// (contract v2.5 C25-02, integration stage) The [INK] values outside the
/// snapshot, from InkDiagnostics.developerValues: the layer 4′ playback paint
/// p95 (`playbackPaintUs`), the annotation layer paint p95
/// (`annotationPaintUs`) and the formula raster cache (`mathCacheBytes`).
/// Only the keys INK has measured are shown; null (no line) when none is.
String? devInkValuesLine(Map<String, num> values) {
  final playback = values['playbackPaintUs'];
  final annotation = values['annotationPaintUs'];
  final mathCache = values['mathCacheBytes'];
  final parts = [
    if (playback != null) '재생 그리기 p95 ${playback.round()}µs',
    if (annotation != null) '주석 그리기 p95 ${annotation.round()}µs',
    if (mathCache != null) '수식 캐시 ${_mb(mathCache.round())}',
  ];
  return parts.isEmpty ? null : '       ${parts.join('  ')}';
}

/// `0x02` — [buttons] in hex, at least 2 digits.
String buttonsHex(int buttons) =>
    '0x${buttons.toRadixString(16).padLeft(2, '0')}';

/// [EDITOR] block (6.12.2) from DevMetrics. (v2, 6.20) The pointer line adds
/// the buttons (hex), the contact rule and '공중' for a stylus event that is
/// not a contact; a hover line (its source); the view line adds the
/// current page's objects against the limit.
List<String> devEditorLines(DevMetricsSnapshot m) {
  final pointers =
      '[EDITOR] 포인터 ${m.activePointers} (${m.lastKind?.name ?? '-'})  '
      'buttons ${buttonsHex(m.lastButtons)}  규칙 ${m.contactRule}'
      '${m.airborne ? '  공중' : ''}  '
      '팜 거부 ${m.palmRejectedCount}  모드 ${m.inputModeLabel}';
  final hover = '       호버 출처 ${m.hoverSource}';
  final view =
      '       줌 ${(m.zoom * 100).round()}% scale ${m.scale.toStringAsFixed(2)}  '
      '보임 ${m.visibleRangeLabel}  마운트 ${m.mountedRangeLabel}  '
      '현재 ${m.currentPage}  페이지 획 ${m.currentPageStrokes}  '
      '객체 ${m.currentPageObjects} / ${core.PageObjectLimits.maxObjectsPerPage}  '
      '마지막 획 점 ${m.lastStrokePoints}';
  return [pointers, hover, view];
}

/// (v2, 6.20 — A-5, B-8) [녹음] line: the recorder's phase, the last
/// stroke's recordingOffsetMs, the player's phase and position.
String devRecordingLine({
  required core.RecorderStatus recorder,
  required int? lastStrokeOffsetMs,
  required core.PlaybackStatus playback,
  required int positionMs,
}) =>
    '[녹음] ${recorder.phase.name}  '
    '마지막 획 offset ${lastStrokeOffsetMs == null ? '-' : '${lastStrokeOffsetMs}ms'}  '
    '재생 ${playback.phase.name} ${positionMs}ms';

/// [저장] line (6.12.2) from CORE.
String devStorageLine(core.StorageInfo info, core.PersistenceStatus? status) {
  final persist = switch (info.persistGranted) {
    null => '-',
    true => '✓',
    false => '✗',
  };
  final usage = info.usageBytes == null ? '-' : _mb(info.usageBytes!);
  final quota = info.quotaBytes == null ? '-' : _mb(info.quotaBytes!);
  final latency = status?.lastCommitLatency;
  return '[저장] ${info.backend.name}  persist $persist  사용 $usage / $quota  '
      '대기 ${status?.pendingOps ?? '-'}  '
      '커밋 ${latency == null ? '-' : '${latency.inMilliseconds}ms'}  '
      '실패 ${status?.consecutiveFailures ?? '-'}';
}
