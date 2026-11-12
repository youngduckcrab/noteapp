// lib/src/providers.dart — 06-pdf 4.12 (contract 7.2.19, 7.3.3, 7.4.4).
//
// flutter_riverpod 3.4.3, no code generation. All keepAlive (the Riverpod 3 default),
// top-level final, name: = the variable name. The only PDF provider overridden at the root
// is pdfIoConfigProvider; pdfIoOverrides() also overrides INK's
// ink.pageBackgroundBuildersProvider (both INFRA PdfModule). The others are overridden by
// tests only.
//
// Foundation step B4 (T0, contract 7.6 B4 v1.2): the providers other areas read during the
// foundation stage and concurrent development never throw —
//   - pdfBackgroundLayerBuilderProvider: B4 const PdfBackgroundLayerBuilder.paperOnly(); from
//     PDF T9 the renderer-backed builder, which reaches the render chain only lazily
//     (read by pdfIoOverrides() for ink.pageBackgroundBuildersProvider),
//   - pdfRenderStatsProvider: B4 ValueNotifier(PdfRenderStats.zero); from PDF T8 the
//     renderer's statsListenable, which needs core.noteStoreProvider (PDF-4-2 — every real
//     container has it: INFRA CoreModule runs first).
// The other providers held their final wiring from B4; every PDF task (T1–T19) has since
// given the services they build their real bodies — none throws UnimplementedError.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:note_core/note_core.dart' as core;

import 'common/cancel_signal.dart';
import 'common/error_report.dart';
import 'common/job_state.dart';
import 'common/progress.dart';
import 'compose/compose_backend.dart';
import 'compose/compose_backend_factory.dart';
import 'config.dart';
import 'engine/pdf_engine.dart';
import 'engine/pdfrx_engine.dart';
import 'errors.dart';
import 'export/batch_export.dart';
import 'export/export_diagnostics.dart';
import 'export/export_service.dart';
import 'export/export_types.dart';
import 'export/vectors.dart';
import 'files/pdf_file_source.dart';
import 'gateway/core_note_gateway.dart';
import 'gateway/pdf_note_gateway.dart';
import 'import/import_service.dart';
import 'import/import_types.dart';
import 'init.dart';
import 'ink_adapter/ink_background_builder.dart';
import 'ink_adapter/ink_vectorizer.dart';
import 'model/page_range.dart';
import 'output/output_sink_factory.dart';
import 'output/pdf_output_sink.dart';
import 'render/document_pool.dart';
import 'render/render_service.dart';
import 'search_index/indexer_gate.dart';
import 'search_index/pdf_search_indexer.dart';
import 'text/search_notifier.dart';
import 'text/search_types.dart';
import 'text/text_service.dart';
import 'tuning.dart';

final pdfIoConfigProvider = Provider<PdfIoConfig>(
  (ref) => PdfIoRuntime.config,
  name: 'pdfIoConfigProvider',
);

final pdfEngineProvider = Provider<PdfEngine>(
  (ref) => PdfrxEngine.shared()..configure(ref.watch(pdfIoConfigProvider)),
  name: 'pdfEngineProvider',
);

final pdfNoteGatewayProvider = Provider<PdfNoteGateway>(
  (ref) => CorePdfNoteGateway(ref.watch(core.noteStoreProvider)),
  name: 'pdfNoteGatewayProvider',
);

/// DefaultPdfDocumentPool(engine, gateway, remoteAssets: ref.watch(core.remoteAssetFetcherProvider));
/// ref.onDispose(pool.dispose).
final pdfDocumentPoolProvider = Provider<PdfDocumentPool>((ref) {
  final pool = DefaultPdfDocumentPool(
    engine: ref.watch(pdfEngineProvider),
    gateway: ref.watch(pdfNoteGatewayProvider),
    remoteAssets: ref.watch(core.remoteAssetFetcherProvider),
  );
  ref.onDispose(pool.dispose);
  return pool;
}, name: 'pdfDocumentPoolProvider');

/// PdfRenderService(pool, budget: ref.watch(pdfIoConfigProvider).effectiveRenderBudget);
/// ref.onDispose(renderer.dispose).
final pdfPageRendererProvider = Provider<PdfPageRenderer>((ref) {
  final renderer = PdfRenderService(
    pool: ref.watch(pdfDocumentPoolProvider),
    budget: ref.watch(pdfIoConfigProvider).effectiveRenderBudget,
  );
  ref.onDispose(renderer.dispose);
  return renderer;
}, name: 'pdfPageRendererProvider');

/// Read by INFRA pdfRenderStatsSection (developer overlay, 01-infra 4.5.9) — also during the
/// foundation stage and concurrent development, so it must never throw there
/// (contract 7.6 B4 v1.2, C12-06). Two bodies:
///   B4 (T0):  (ref) => ValueNotifier(PdfRenderStats.zero)
///             — watches NOTHING (no render chain, no core.noteStoreProvider); with only
///               pdfIoOverrides() in the container it reads fine and value == zero.
///   T8 on:    (ref) => ref.watch(pdfPageRendererProvider).statsListenable
///             — builds the render chain (PdfRenderService → pool → engine configure only,
///               CORE gateway → core.noteStoreProvider), never initializes the engine or
///               opens a document. Every real container has core.noteStoreProvider (INFRA
///               CoreModule runs first, 7.3.3 module order; INFRA tests use CoreModule with a
///               fake open), so INFRA needs no test override in either stage.
final pdfRenderStatsProvider = Provider<ValueListenable<PdfRenderStats>>(
  // T8 body. The notifier belongs to the renderer (disposed with it).
  (ref) => ref.watch(pdfPageRendererProvider).statsListenable,
  name: 'pdfRenderStatsProvider',
);

/// DefaultPdfTextService(pool: …, gateway: …).
final pdfTextServiceProvider = Provider<PdfTextService>(
  (ref) => DefaultPdfTextService(
    pool: ref.watch(pdfDocumentPoolProvider),
    gateway: ref.watch(pdfNoteGatewayProvider),
  ),
  name: 'pdfTextServiceProvider',
);

final pdfActiveSearchProvider =
    NotifierProvider<PdfSearchNotifier, PdfSearchState>(
      PdfSearchNotifier.new,
      name: 'pdfActiveSearchProvider',
    );

/// Bridges pdfActiveSearchProvider into a ValueListenable for background views (no ProviderScope
/// there, 6.13); the ValueNotifier is disposed with the provider.
///   (ref) { final n = ValueNotifier(ref.read(pdfActiveSearchProvider));
///           ref.listen(pdfActiveSearchProvider, (_, next) => n.value = next);   // listen ONLY
///           ref.onDispose(n.dispose); return n; }
/// It never watches, so it is never rebuilt — pdfBackgroundLayerBuilderProvider relies on that
/// (PDF-3-4). ValueNotifier skips equal states (PdfSearchState ==).
final pdfSearchHighlightsProvider = Provider<ValueListenable<PdfSearchState>>((
  ref,
) {
  final n = ValueNotifier(ref.read(pdfActiveSearchProvider));
  ref.listen(pdfActiveSearchProvider, (_, next) => n.value = next);
  ref.onDispose(n.dispose);
  return n;
}, name: 'pdfSearchHighlightsProvider');

/// Read by pdfIoOverrides() for ink.pageBackgroundBuildersProvider. Watches NOTHING that can
/// throw: the renderer chain (pdfPageRendererProvider → pool → engine, CORE gateway →
/// core.noteStoreProvider) is reached lazily through the closure on the first build /
/// renderStill (Riverpod 3.4.3: ref.read from a closure after build — checked in scratch
/// /tmp/claude-0/plan-scratch/pdf/lazy_ref, reading the list built 0 renderers). PDF-2-2.
///   B4 (T0):  (ref) => const PdfBackgroundLayerBuilder.paperOnly()
///   T9 on:    (ref) => PdfBackgroundLayerBuilder(
///                 renderer: () => ref.read(pdfPageRendererProvider),
///                 highlights: ref.watch(pdfSearchHighlightsProvider))   // never throws
/// The renderer closure CAPTURES this provider's ref (PDF-3-4). That is safe because this
/// provider is never rebuilt during the app's lifetime: its only watch,
/// pdfSearchHighlightsProvider, follows pdfActiveSearchProvider with ref.listen only (no
/// watch), so starting / selecting / clearing a search never rebuilds either of them. A
/// rebuild would unmount the captured ref (Riverpod 3.4.3 throws UnmountedRefException from
/// the old closure — checked in scratch /tmp/claude-0/plan-scratch/pdf-v3/stable_ref), so
/// do NOT add a ref.watch here or in pdfSearchHighlightsProvider. T17 asserts the same
/// instance after search start / select / clear.
final pdfBackgroundLayerBuilderProvider = Provider<PdfBackgroundLayerBuilder>(
  // T9 body.
  (ref) => PdfBackgroundLayerBuilder(
    renderer: () => ref.read(pdfPageRendererProvider),
    highlights: ref.watch(pdfSearchHighlightsProvider),
  ),
  name: 'pdfBackgroundLayerBuilderProvider',
);

final pdfFileSourceProvider = Provider<PdfFileSource>(
  (ref) => const FilePickerPdfSource(),
  name: 'pdfFileSourceProvider',
);

final pdfIncomingFileSourceProvider = Provider<PdfIncomingFileSource>(
  (ref) => const NoIncomingPdfFiles(),
  name: 'pdfIncomingFileSourceProvider',
);

/// Native app: the share of the result sheet's 공유 (the app overrides it with its share
/// plugin — pdf_io has none, contract 7.4.1 / R16). null (default, and ignored on the web):
/// the native sink offers no share.
final pdfShareFilesProvider = Provider<PdfShareFiles?>(
  (ref) => null,
  name: 'pdfShareFilesProvider',
);

final pdfOutputSinkProvider = Provider<PdfOutputSink>(
  (ref) => createPlatformOutputSink(share: ref.watch(pdfShareFilesProvider)),
  name: 'pdfOutputSinkProvider',
);

final pdfInkVectorizerProvider = Provider<PdfInkVectorizer>(
  (ref) => const InkEngineVectorizer(),
  name: 'pdfInkVectorizerProvider',
);

/// (2차, contract 7.2.12 — m5-7/06-pdf 4.4) The library-wide PDF text indexer, built through
/// the src-only createPdfSearchIndexer (PDF-M9) over this container's document pool and the
/// app gate. Built only — never started here: INFRA PdfModule's idle task calls start() and
/// dispose() (X33); dispose() is idempotent, so the onDispose below may run after INFRA's.
/// Reading it builds the CORE gateway and the document pool (core.noteStoreProvider is needed
/// — INFRA CoreModule starts first); it opens no document. App shell tests use PdfModule's
/// injection seam, not an override of this provider (final class — 01-infra D2-16).
final pdfSearchIndexerProvider = Provider<PdfSearchIndexer>((ref) {
  final indexer = createPdfSearchIndexer(
    ref.watch(core.noteStoreProvider),
    pool: ref.watch(pdfDocumentPoolProvider),
    gate: AppIndexerGate(ref),
  );
  ref.onDispose(indexer.dispose);
  return indexer;
}, name: 'pdfSearchIndexerProvider');

/// createPlatformComposeBackend(ref.watch(pdfIoConfigProvider)); ref.onDispose(backend.dispose).
final pdfComposeBackendProvider = Provider<PdfComposeBackend>((ref) {
  final backend = createPlatformComposeBackend(ref.watch(pdfIoConfigProvider));
  ref.onDispose(backend.dispose);
  return backend;
}, name: 'pdfComposeBackendProvider');

/// DefaultPdfImportService(engine, gateway, pool, renderer, config,
///     thumbnailRenderer: ref.watch(core.pageThumbnailRendererProvider)).
final pdfImportServiceProvider = Provider<PdfImportService>(
  (ref) => DefaultPdfImportService(
    engine: ref.watch(pdfEngineProvider),
    gateway: ref.watch(pdfNoteGatewayProvider),
    pool: ref.watch(pdfDocumentPoolProvider),
    renderer: ref.watch(pdfPageRendererProvider),
    config: ref.watch(pdfIoConfigProvider),
    thumbnailRenderer: ref.watch(core.pageThumbnailRendererProvider),
  ),
  name: 'pdfImportServiceProvider',
);

/// DefaultPdfExportService(gateway: …, vectorizer: …, backend: …).
final pdfExportServiceProvider = Provider<PdfExportService>(
  // DefaultPdfExportService(gateway:, vectorizer:, backend:) — through the src-only factory so
  // each note's memory ledger reaches the developer lines (C26-02).
  (ref) => createPdfExportService(
    gateway: ref.watch(pdfNoteGatewayProvider),
    vectorizer: ref.watch(pdfInkVectorizerProvider),
    backend: ref.watch(pdfComposeBackendProvider),
    diagnostics: ref.watch(pdfExportDiagnosticsProvider),
  ),
  name: 'pdfExportServiceProvider',
);

/// (2차, contract v2.6 C26-02) src only: the export ledger numbers the developer lines show.
final pdfExportDiagnosticsProvider = Provider<PdfExportDiagnostics>((ref) {
  final diagnostics = PdfExportDiagnostics();
  ref.onDispose(diagnostics.dispose);
  return diagnostics;
}, name: 'pdfExportDiagnosticsProvider');

/// (2차, contract v2.6 C26-02 — added only) Developer overlay lines of the PDF export: the last
/// note's memory ledger peakBytes and overBudget (C22-06 ②, 6.2.10 ⑤). Empty before the first
/// export, and when pdfExportServiceProvider is overridden with another service. Rebuilt after
/// each export (INFRA puts it in FeatureWiringModule's PDF DevOverlaySection).
final pdfDevOverlayLinesProvider = Provider<List<String>>((ref) {
  final diagnostics = ref.watch(pdfExportDiagnosticsProvider);
  void changed() => ref.invalidateSelf();
  diagnostics.addListener(changed);
  ref.onDispose(() => diagnostics.removeListener(changed));
  return diagnostics.lines;
}, name: 'pdfDevOverlayLinesProvider');

final pdfImportJobProvider =
    NotifierProvider<PdfImportJobNotifier, PdfJobState<PdfImportResult>>(
      PdfImportJobNotifier.new,
      name: 'pdfImportJobProvider',
    );

final pdfExportJobProvider =
    NotifierProvider<PdfExportJobNotifier, PdfJobState<PdfExportResult>>(
      PdfExportJobNotifier.new,
      name: 'pdfExportJobProvider',
    );

final pdfBatchExportJobProvider =
    NotifierProvider<PdfBatchExportJobNotifier, PdfBatchJobState>(
      PdfBatchExportJobNotifier.new,
      name: 'pdfBatchExportJobProvider',
    );

// Job notifiers — B4 (T0): build() is real (idle). The import job is real from PDF T6; the
// export jobs come with T15 (export) and T15b (bulk export).

/// One PDF job at a time (6.3, 6.13): an import, export or bulk export in progress makes
/// the others busy. A notifier passes false for itself (Riverpod forbids reading the
/// provider being built from its own ref) and checks its own state.
bool _pdfJobRunning(
  Ref ref, {
  bool import = true,
  bool export = true,
  bool batch = true,
}) =>
    (import && ref.read(pdfImportJobProvider) is PdfJobRunning) ||
    (export && ref.read(pdfExportJobProvider) is PdfJobRunning) ||
    (batch && ref.read(pdfBatchExportJobProvider) is PdfBatchJobRunning);

class PdfImportJobNotifier extends Notifier<PdfJobState<PdfImportResult>> {
  PdfCancelSignal? _cancel;
  Timer? _progressTimer;
  PdfProgress? _pendingProgress;

  /// PdfJobIdle
  @override
  PdfJobState<PdfImportResult> build() {
    ref.onDispose(() {
      _progressTimer?.cancel();
      _cancel?.cancel();
    });
    return const PdfJobIdle<PdfImportResult>();
  }

  /// True while an import runs, or while an export / bulk export runs (one PDF job at a
  /// time — another import is busy).
  bool get isBusy =>
      state is PdfJobRunning || _pdfJobRunning(ref, import: false);

  /// Throws nothing; failures end in PdfJobFailed. Returns null unless succeeded.
  ///
  /// While another PDF job runs: PdfJobFailed(busy) — except while this notifier's own
  /// import runs, whose Running state is kept (the caller sees null; the flows check
  /// isBusy before picking a file). Progress reaches the state at most every
  /// PdfTuning.jobProgressInterval (6.13). [session] stays the caller's (dispose it after).
  Future<PdfImportResult?> run(
    PdfImportSession session,
    PdfImportTarget target, {
    PdfPageRange range = const PdfPageRange.all(),
  }) async {
    if (state is PdfJobRunning) return null;
    if (_pdfJobRunning(ref, import: false)) {
      state = const PdfJobFailed<PdfImportResult>(
        PdfIoException(PdfErrorCode.busy),
      );
      return null;
    }
    final cancel = _cancel = PdfCancelSignal();
    state = const PdfJobRunning<PdfImportResult>(
      PdfProgress(PdfJobPhase.storingPdf),
    );
    PdfJobState<PdfImportResult> end;
    PdfImportResult? result;
    try {
      result = await session.commit(
        target,
        range: range,
        onProgress: _onProgress,
        cancel: cancel,
      );
      end = PdfJobSucceeded<PdfImportResult>(result);
    } on PdfIoException catch (e) {
      end = PdfJobFailed<PdfImportResult>(e);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf import job');
      end = PdfJobFailed<PdfImportResult>(
        PdfIoException(
          PdfErrorCode.storageFailed,
          detail: 'unexpected import error',
          cause: e,
        ),
      );
    }
    _progressTimer?.cancel();
    _progressTimer = null;
    _pendingProgress = null;
    if (identical(_cancel, cancel)) _cancel = null;
    if (ref.mounted) state = end;
    return result;
  }

  void _onProgress(PdfProgress progress) {
    if (_progressTimer != null) {
      _pendingProgress = progress;
      return;
    }
    if (ref.mounted && state is PdfJobRunning) {
      state = PdfJobRunning<PdfImportResult>(progress);
    }
    _progressTimer = Timer(PdfTuning.jobProgressInterval, () {
      _progressTimer = null;
      final pending = _pendingProgress;
      _pendingProgress = null;
      if (pending != null) _onProgress(pending);
    });
  }

  /// Cancels the running import (no-op when idle). It ends in PdfJobFailed(cancelled)
  /// unless it is past the last cancel point (6.3 step 3).
  void cancel() => _cancel?.cancel();

  /// Back to idle unless an import runs.
  void reset() {
    if (state is PdfJobRunning) return;
    state = const PdfJobIdle<PdfImportResult>();
  }
}

/// Hands progress values to [_apply] at most every PdfTuning.jobProgressInterval (6.13):
/// the first one at once, then the latest one when the interval ends.
final class _ProgressThrottle<P extends Object> {
  _ProgressThrottle(this._apply);

  final void Function(P progress) _apply;
  Timer? _timer;
  P? _pending;

  void add(P progress) {
    if (_timer != null) {
      _pending = progress;
      return;
    }
    _apply(progress);
    _timer = Timer(PdfTuning.jobProgressInterval, () {
      _timer = null;
      final pending = _pending;
      _pending = null;
      if (pending != null) add(pending);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }
}

class PdfExportJobNotifier extends Notifier<PdfJobState<PdfExportResult>> {
  PdfCancelSignal? _cancel;
  _ProgressThrottle<PdfProgress>? _progress;

  @override
  PdfJobState<PdfExportResult> build() {
    ref.onDispose(() {
      _progress?.stop();
      _cancel?.cancel();
    });
    return const PdfJobIdle<PdfExportResult>();
  }

  /// True while an export runs, or while an import / bulk export runs (one PDF job at a
  /// time — another export is busy).
  bool get isBusy =>
      state is PdfJobRunning || _pdfJobRunning(ref, export: false);

  /// pdfExportServiceProvider.exportNote. Throws nothing; failures end in PdfJobFailed
  /// (cancel → PdfJobFailed(cancelled)). Returns null unless succeeded.
  ///
  /// While another PDF job runs: PdfJobFailed(busy) — except while this notifier's own
  /// export runs, whose Running state is kept (the caller sees null). Progress reaches the
  /// state at most every PdfTuning.jobProgressInterval (6.13). An unexpected error is
  /// reported and ends in PdfJobFailed(exportFailed) with the cause.
  Future<PdfExportResult?> run(String noteId, PdfExportOptions options) async {
    if (state is PdfJobRunning) return null;
    if (_pdfJobRunning(ref, export: false)) {
      state = const PdfJobFailed<PdfExportResult>(
        PdfIoException(PdfErrorCode.busy),
      );
      return null;
    }
    final cancel = _cancel = PdfCancelSignal();
    final progress = _progress = _ProgressThrottle<PdfProgress>((p) {
      if (ref.mounted && state is PdfJobRunning) {
        state = PdfJobRunning<PdfExportResult>(p);
      }
    });
    state = const PdfJobRunning<PdfExportResult>(
      PdfProgress(PdfJobPhase.preparingExport),
    );
    PdfJobState<PdfExportResult> end;
    PdfExportResult? result;
    try {
      result = await ref
          .read(pdfExportServiceProvider)
          .exportNote(
            noteId,
            options,
            onProgress: progress.add,
            cancel: cancel,
          );
      end = PdfJobSucceeded<PdfExportResult>(result);
    } on PdfIoException catch (e) {
      end = PdfJobFailed<PdfExportResult>(e);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf export job');
      end = PdfJobFailed<PdfExportResult>(
        PdfIoException(
          PdfErrorCode.exportFailed,
          detail: 'unexpected export error',
          cause: e,
        ),
      );
    }
    progress.stop();
    if (identical(_progress, progress)) _progress = null;
    if (identical(_cancel, cancel)) _cancel = null;
    if (ref.mounted) state = end;
    return result;
  }

  /// Cancels the running export (no-op when idle): it ends in PdfJobFailed(cancelled) at
  /// once, even while the pre-export flush waits for CORE (6.11.2 step 1).
  void cancel() => _cancel?.cancel();

  /// Back to idle unless an export runs.
  void reset() {
    if (state is PdfJobRunning) return;
    state = const PdfJobIdle<PdfExportResult>();
  }
}

/// Batch job state: idle / running(PdfBatchProgress) / finished(PdfBatchExportResult) / failed.
/// Value equality (contract 7.4.4): same subtype, fields compared with ==.
sealed class PdfBatchJobState {
  const PdfBatchJobState();
}

@immutable
final class PdfBatchJobIdle extends PdfBatchJobState {
  const PdfBatchJobIdle();

  /// every PdfBatchJobIdle is equal
  @override
  bool operator ==(Object other) => other is PdfBatchJobIdle;

  @override
  int get hashCode => (PdfBatchJobIdle).hashCode;

  @override
  String toString() => 'PdfBatchJobIdle';
}

@immutable
final class PdfBatchJobRunning extends PdfBatchJobState {
  const PdfBatchJobRunning(this.progress);
  final PdfBatchProgress progress;

  /// progress ==
  @override
  bool operator ==(Object other) =>
      other is PdfBatchJobRunning && other.progress == progress;

  @override
  int get hashCode => Object.hash(PdfBatchJobRunning, progress);

  @override
  String toString() => 'PdfBatchJobRunning($progress)';
}

@immutable
final class PdfBatchJobFinished extends PdfBatchJobState {
  const PdfBatchJobFinished(this.result);
  final PdfBatchExportResult result;

  /// result == is identity (PdfBatchExportResult holds bytes, 4.9).
  @override
  bool operator ==(Object other) =>
      other is PdfBatchJobFinished && identical(other.result, result);

  @override
  int get hashCode =>
      Object.hash(PdfBatchJobFinished, identityHashCode(result));

  @override
  String toString() => 'PdfBatchJobFinished($result)';
}

@immutable
final class PdfBatchJobFailed extends PdfBatchJobState {
  /// busy / engineUnavailable / unsupportedPlatform
  const PdfBatchJobFailed(this.error);
  final PdfIoException error;

  /// error == (code, detail)
  @override
  bool operator ==(Object other) =>
      other is PdfBatchJobFailed && other.error == error;

  @override
  int get hashCode => Object.hash(PdfBatchJobFailed, error);

  @override
  String toString() => 'PdfBatchJobFailed($error)';
}

class PdfBatchExportJobNotifier extends Notifier<PdfBatchJobState> {
  PdfCancelSignal? _cancel;
  _ProgressThrottle<PdfBatchProgress>? _progress;

  /// PdfBatchJobIdle
  @override
  PdfBatchJobState build() {
    ref.onDispose(() {
      _progress?.stop();
      _cancel?.cancel();
    });
    return const PdfBatchJobIdle();
  }

  /// True while a bulk export runs, or while an import / export runs (one PDF job at a
  /// time).
  bool get isBusy =>
      state is PdfBatchJobRunning || _pdfJobRunning(ref, batch: false);

  /// pdfExportServiceProvider.exportNotes. Throws nothing: the result (files made so far
  /// when cancelled) ends in PdfBatchJobFinished; busy / engineUnavailable /
  /// unsupportedPlatform end in PdfBatchJobFailed. Returns null unless finished.
  ///
  /// Same rules as the export job: null with the Running state kept while this notifier's
  /// own bulk export runs; PdfBatchJobFailed(busy) while another PDF job runs; progress at
  /// most every PdfTuning.jobProgressInterval; an unexpected error is reported and ends in
  /// PdfBatchJobFailed(exportFailed). An empty [noteIds] finishes at once with no items.
  Future<PdfBatchExportResult?> run(
    List<String> noteIds,
    PdfExportOptions options,
  ) async {
    if (state is PdfBatchJobRunning) return null;
    if (_pdfJobRunning(ref, batch: false)) {
      state = const PdfBatchJobFailed(PdfIoException(PdfErrorCode.busy));
      return null;
    }
    if (noteIds.isEmpty) {
      final empty = PdfBatchExportResult(requestedCount: 0, items: const []);
      state = PdfBatchJobFinished(empty);
      return empty;
    }
    final cancel = _cancel = PdfCancelSignal();
    final progress = _progress = _ProgressThrottle<PdfBatchProgress>((p) {
      if (ref.mounted && state is PdfBatchJobRunning) {
        state = PdfBatchJobRunning(p);
      }
    });
    state = PdfBatchJobRunning(
      PdfBatchProgress(
        noteIndex: 0,
        noteCount: noteIds.length,
        current: const PdfProgress(PdfJobPhase.preparingExport),
      ),
    );
    PdfBatchJobState end;
    PdfBatchExportResult? result;
    try {
      result = await ref
          .read(pdfExportServiceProvider)
          .exportNotes(
            noteIds,
            options,
            onProgress: progress.add,
            cancel: cancel,
          );
      end = PdfBatchJobFinished(result);
    } on PdfIoException catch (e) {
      end = PdfBatchJobFailed(e);
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf batch export job');
      end = PdfBatchJobFailed(
        PdfIoException(
          PdfErrorCode.exportFailed,
          detail: 'unexpected batch export error',
          cause: e,
        ),
      );
    }
    progress.stop();
    if (identical(_progress, progress)) _progress = null;
    if (identical(_cancel, cancel)) _cancel = null;
    if (ref.mounted) state = end;
    return result;
  }

  /// Cancels the running bulk export (no-op when idle): the note in progress is aborted,
  /// the files made so far are kept (result.cancelled).
  void cancel() => _cancel?.cancel();

  /// Back to idle unless a bulk export runs.
  void reset() {
    if (state is PdfBatchJobRunning) return;
    state = const PdfBatchJobIdle();
  }
}
