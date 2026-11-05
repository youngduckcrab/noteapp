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
//   - pdfBackgroundLayerBuilderProvider = const PdfBackgroundLayerBuilder.paperOnly()
//     (read by pdfIoOverrides() for ink.pageBackgroundBuildersProvider),
//   - pdfRenderStatsProvider = ValueNotifier(PdfRenderStats.zero) (read by INFRA
//     pdfRenderStatsSection),
// and neither watches the render chain (pdfPageRendererProvider → PdfRenderService · pool ·
// engine · gateway → core.noteStoreProvider). The other providers already hold their final
// wiring; the services they build throw UnimplementedError until their PDF task.
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
final pdfRenderStatsProvider = Provider<ValueListenable<PdfRenderStats>>((ref) {
  // B4 (T0) body. The notifier is disposed with the provider.
  final stats = ValueNotifier(PdfRenderStats.zero);
  ref.onDispose(stats.dispose);
  return stats;
}, name: 'pdfRenderStatsProvider');

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
  // B4 (T0) body.
  (ref) => const PdfBackgroundLayerBuilder.paperOnly(),
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

final pdfOutputSinkProvider = Provider<PdfOutputSink>(
  (ref) => createPlatformOutputSink(),
  name: 'pdfOutputSinkProvider',
);

final pdfInkVectorizerProvider = Provider<PdfInkVectorizer>(
  (ref) => const InkEngineVectorizer(),
  name: 'pdfInkVectorizerProvider',
);

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
  (ref) => DefaultPdfExportService(
    gateway: ref.watch(pdfNoteGatewayProvider),
    vectorizer: ref.watch(pdfInkVectorizerProvider),
    backend: ref.watch(pdfComposeBackendProvider),
  ),
  name: 'pdfExportServiceProvider',
);

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

class PdfExportJobNotifier extends Notifier<PdfJobState<PdfExportResult>> {
  @override
  PdfJobState<PdfExportResult> build() => const PdfJobIdle<PdfExportResult>();

  bool get isBusy =>
      throw UnimplementedError('PdfExportJobNotifier.isBusy (PDF T15)');

  Future<PdfExportResult?> run(String noteId, PdfExportOptions options) =>
      throw UnimplementedError('PdfExportJobNotifier.run (PDF T15)');

  void cancel() =>
      throw UnimplementedError('PdfExportJobNotifier.cancel (PDF T15)');

  void reset() =>
      throw UnimplementedError('PdfExportJobNotifier.reset (PDF T15)');
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
  /// PdfBatchJobIdle
  @override
  PdfBatchJobState build() => const PdfBatchJobIdle();

  bool get isBusy =>
      throw UnimplementedError('PdfBatchExportJobNotifier.isBusy (PDF T15b)');

  Future<PdfBatchExportResult?> run(
    List<String> noteIds,
    PdfExportOptions options,
  ) => throw UnimplementedError('PdfBatchExportJobNotifier.run (PDF T15b)');

  void cancel() =>
      throw UnimplementedError('PdfBatchExportJobNotifier.cancel (PDF T15b)');

  void reset() =>
      throw UnimplementedError('PdfBatchExportJobNotifier.reset (PDF T15b)');
}
