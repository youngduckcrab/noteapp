/// PDF ↔ EDITOR mapping used by FeatureWiringModule (docs/plans/01-infra.md
/// 4.5.9, 6.8; contract 7.3.3 / 7.2.17 / 7.2.19). Pure functions plus the
/// throttled render stats lines, unit-tested in pdf_wiring_test.
library;

import 'dart:async';

import 'package:feature_editor/feature_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf_io/pdf_io.dart';

/// EditorMenuContext → PdfMenuInvocation (06-pdf 5.5 example).
/// onNavigate is navigateToPage itself: focusRectPt is passed through
/// unchanged (계약 7.2.17 v1.1, C11-21 — displayed page pt of the note's
/// Page.size, origin top-left, y down; INFRA never converts it).
PdfMenuInvocation pdfMenuInvocationOf(EditorMenuContext menu) =>
    PdfMenuInvocation(
      noteId: menu.noteId,
      currentPageId: menu.currentPageId,
      selectedPageIds: menu.selectedPageIds,
      onNavigate: menu.navigateToPage,
    );

/// Same id / label / icon. onSelected: (ctx, m) => action.run(ctx,
/// pdfMenuInvocationOf(m)); isEnabled: null when action.isEnabled is null,
/// else (m) => action.isEnabled!(pdfMenuInvocationOf(m)).
EditorMenuItem editorMenuItemFromPdf(PdfMenuAction action) {
  final isEnabled = action.isEnabled;
  return EditorMenuItem(
    id: action.id,
    label: action.label,
    icon: action.icon,
    onSelected: (context, menu) =>
        action.run(context, pdfMenuInvocationOf(menu)),
    isEnabled: isEnabled == null
        ? null
        : (menu) => isEnabled(pdfMenuInvocationOf(menu)),
  );
}

/// EditorExtensions(moreMenuItems: [...], addPageSources: [...]),
/// appBarTrailing stays null (reserved).
EditorExtensions editorExtensionsFromPdf({
  required List<PdfMenuAction> moreMenu,
  required List<PdfMenuAction> addPageSources,
}) => EditorExtensions(
  moreMenuItems: List<EditorMenuItem>.unmodifiable(
    moreMenu.map(editorMenuItemFromPdf),
  ),
  addPageSources: List<EditorMenuItem>.unmodifiable(
    addPageSources.map(editorMenuItemFromPdf),
  ),
);

/// Lines over PDF render stats, recomputed at most once per [minInterval]
/// (≤ 4 Hz as DevOverlaySection requires), followed by the [exportLines]
/// (2nd round, contract v2.6 C26-02 — pdfDevOverlayLinesProvider: empty
/// before the first export, then the last note's ledger lines).
///
/// A stats or export lines change starts a [minInterval] timer; the lines
/// are recomputed from the latest values when it fires (changes in between
/// are merged).
final class PdfRenderStatsLines extends ChangeNotifier
    implements ValueListenable<List<String>> {
  PdfRenderStatsLines(
    ValueListenable<PdfRenderStats> stats, {
    ValueListenable<List<String>>? exportLines,
    this._minInterval = const Duration(milliseconds: 250),
  }) : _stats = stats,
       _exportLines = exportLines,
       _value = List<String>.unmodifiable([
         ...formatPdfRenderStats(stats.value),
         ...?exportLines?.value,
       ]) {
    _stats.addListener(_onStats);
    _exportLines?.addListener(_onStats);
  }

  final ValueListenable<PdfRenderStats> _stats;
  final ValueListenable<List<String>>? _exportLines;
  final Duration _minInterval;
  List<String> _value;
  Timer? _timer;
  bool _disposed = false;

  @override
  List<String> get value => _value;

  void _onStats() {
    _timer ??= Timer(_minInterval, _refresh);
  }

  void _refresh() {
    _timer = null;
    if (_disposed) return;
    final next = [
      ...formatPdfRenderStats(_stats.value),
      ...?_exportLines?.value,
    ];
    if (listEquals(next, _value)) return;
    _value = List<String>.unmodifiable(next);
    notifyListeners();
  }

  /// Removes the stats listener and cancels the pending timer.
  @override
  void dispose() {
    _disposed = true;
    _stats.removeListener(_onStats);
    _exportLines?.removeListener(_onStats);
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

/// Three lines (6.8): memory, queue, timing.
List<String> formatPdfRenderStats(PdfRenderStats stats) {
  final memory =
      '메모리 미리보기 ${_mb(stats.previewBytes)} · 타일 ${_mb(stats.tileBytes)} · '
      '썸네일 ${_mb(stats.thumbnailBytes)} MB '
      '(초과 ${_mb(stats.overBudgetBytes)} MB)';
  final queue =
      '대기 ${stats.queued} · 진행 ${stats.inflight} · 완료 ${stats.rendered} · '
      '취소 ${stats.cancelled} · 이미지 ${stats.liveImages}';
  final timing =
      '렌더 최근 ${stats.lastRenderMs.round()}ms · '
      'p95 ${stats.p95RenderMs.round()}ms · 열린 문서 ${stats.openDocuments}';
  return [memory, queue, timing];
}

/// Bytes as MB (1024 × 1024) with one decimal; zero is `0`.
String _mb(int bytes) =>
    bytes == 0 ? '0' : (bytes / (1024 * 1024)).toStringAsFixed(1);

/// DevOverlaySection(id: 'pdf.render', title: 'PDF 렌더',
///   lines: PdfRenderStatsLines(ref.watch(pdfRenderStatsProvider),
///     exportLines: `pdfDevOverlayLinesProvider` in a ValueNotifier))
/// — the lines object and the notifier are disposed with the provider
/// (ref.onDispose). Reads the REAL pdfRenderStatsProvider and (contract v2.6
/// C26-02) pdfDevOverlayLinesProvider (no injection parameter): both build
/// without exception from the module overrides alone (계약 7.6 B4 v1.2,
/// C12-06 — B4 a zero-stats notifier, since PDF T8 the renderer's stats
/// listenable, which needs noteStoreProvider only; the export lines read
/// PDF's own diagnostics provider), so a container holding only the module
/// overrides can build this section. After each exported note the section
/// shows two more lines ('export: peak … · copy …', 'export: over budget …').
DevOverlaySection pdfRenderStatsSection(Ref ref) {
  final exportLines = ValueNotifier<List<String>>(
    ref.read(pdfDevOverlayLinesProvider),
  );
  ref.listen<List<String>>(
    pdfDevOverlayLinesProvider,
    (_, next) => exportLines.value = next,
  );
  final lines = PdfRenderStatsLines(
    ref.watch(pdfRenderStatsProvider),
    exportLines: exportLines,
  );
  ref.onDispose(() {
    lines.dispose();
    exportLines.dispose();
  });
  return DevOverlaySection(id: 'pdf.render', title: 'PDF 렌더', lines: lines);
}
