// lib/src/ui/flows.dart — 06-pdf 4.11 (contract 7.2.19). UI flows read providers through
// ProviderScope.containerOf(context) (6.13): callers pass a BuildContext only.
//
// Foundation step B4 (T0, contract 7.6 B4): importPdfAsNewNote returned null and
// exportNotesAsPdf does nothing, so INFRA could wire both into the LIBRARY slots. The import
// flow is real from PDF T6, the search panel from T11, the bulk export from T15b and the
// single export from T16.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/error_report.dart';
import '../common/job_state.dart';
import '../errors.dart';
import '../export/export_types.dart';
import '../import/import_types.dart';
import '../output/pdf_output_sink.dart';
import '../providers.dart';
import '../text/search_notifier.dart';
import 'export_sheets.dart';
import 'import_progress_dialog.dart';
import 'import_sheet.dart';
import 'search_panel.dart';
import 'strings_ko.dart';

/// Same shape as EditorMenuContext.navigateToPage (contract 7.2.17).
typedef PdfNavigateCallback = void Function(String pageId, Rect? focusRectPt);

enum PdfExportPurpose { save, share, print }

/// Shows the import sheet ('PDF 파일 선택' button → pick → password → options → progress).
/// Returns null when cancelled, when the flow already showed its error, or when [context]
/// is unmounted midway (silently). Never throws for user-level failures.
/// Requires an ancestor ProviderScope.
/// Storage delay (6.3, contract 7.2.9 v1.2): a failed CORE commit is retried, never thrown,
/// so the progress dialog watches core.persistenceStatusProvider + core.storageInfoProvider
/// and, while core.storageWarningOf(...) == StorageWarning.writeFailing, shows the delay text
/// (6.14) and a '닫기' button ('취소' stays while the job is still cancellable). After '닫기':
/// the flow returns null at once; the job KEEPS RUNNING in pdfImportJobProvider (another
/// import / export gets busy until it ends); when CORE's retried commit succeeds the new note
/// shows up in the library list (insert: the pages show up in the editor via pagesStream),
/// with no result UI and no onNavigate; a failure after that is only reported (6.13).
Future<PdfImportResult?> runPdfImportFlow(
  BuildContext context,
  PdfImportTarget target,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final job = container.read(pdfImportJobProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  if (job.isBusy) {
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return null;
  }
  final choice = await showPdfImportSheet(
    context,
    service: container.read(pdfImportServiceProvider),
    fileSource: container.read(pdfFileSourceProvider),
    target: target,
  );
  if (choice == null) return null;
  final session = choice.session;
  if (!context.mounted) {
    await session.dispose();
    return null;
  }
  if (session.isLargeFile &&
      !await confirmLargePdfImport(context, session.byteLength)) {
    await session.dispose();
    return null;
  }
  if (!context.mounted) {
    await session.dispose();
    return null;
  }
  if (job.isBusy) {
    // Another job started while the sheet was open.
    await session.dispose();
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return null;
  }

  final running = job.run(session, target, range: choice.range);
  // The session lives as long as the job, whatever happens to the dialog.
  unawaited(running.whenComplete(session.dispose));

  final navigator = Navigator.of(context, rootNavigator: true);
  final closed = Completer<void>();
  final dialog = DialogRoute<void>(
    context: context,
    // (v2.14-ui split) The dialog takes the theme of the screen it opens
    // from — the editor's style inside a note (showDialog does the same).
    themes: InheritedTheme.capture(from: context, to: null),
    barrierDismissible: false,
    builder: (_) => PdfImportProgressDialog(
      onCancel: job.cancel,
      onClose: () {
        if (!closed.isCompleted) closed.complete();
      },
    ),
  );
  unawaited(navigator.push(dialog));
  void removeDialog() {
    if (navigator.mounted && dialog.isActive) navigator.removeRoute(dialog);
  }

  final ended = await Future.any<bool>([
    running.then((_) => true),
    closed.future.then((_) => false),
  ]);
  removeDialog();
  if (!ended) {
    // '닫기' during a storage delay (6.3): the job keeps running; nothing to show later.
    unawaited(
      running.then((_) {
        final state = container.read(pdfImportJobProvider);
        if (state is PdfJobFailed<PdfImportResult> &&
            state.error.code != PdfErrorCode.cancelled) {
          reportPdfError(
            state.error,
            StackTrace.current,
            'pdf import after its progress dialog was closed',
          );
        }
      }),
    );
    return null;
  }
  final result = await running;
  if (!context.mounted) return null;
  if (result != null) {
    say(PdfStringsKo.importDone(result.insertedPageIds.length));
    return result;
  }
  final state = container.read(pdfImportJobProvider);
  if (state is PdfJobFailed<PdfImportResult> &&
      state.error.code != PdfErrorCode.cancelled) {
    say(state.error.userMessage);
  }
  return null;
}

/// LibraryPdfImportAction shape (contract 7.2.18 / 7.2.19):
/// runPdfImportFlow(context, PdfImportAsNewNote(folderId: folderId)) → created note id or null.
/// null also when the progress dialog was closed with '닫기' during a storage delay: the job
/// keeps running and the note appears in the library once CORE commits it (runPdfImportFlow).
/// INFRA FeatureWiringModule: libraryPdfImportActionProvider.overrideWithValue(importPdfAsNewNote).
Future<String?> importPdfAsNewNote(
  BuildContext context, {
  String? folderId,
}) async {
  final result = await runPdfImportFlow(
    context,
    PdfImportAsNewNote(folderId: folderId),
  );
  return result?.noteId;
}

/// Options sheet → progress dialog (cancellable; shows the storage-delay text while
/// writeFailing — 6.11.2 step 1, '취소' ends a pending flush at once) → result sheet
/// (share/download/open).
///
/// T16: the options sheet (title by [purpose]: 'PDF로 내보내기' / 'PDF 공유' / '인쇄', the
/// note title under it) offers 노트 전체 / 현재 페이지 / 선택한 페이지 — '선택한 페이지' is
/// the default when [selectedPageIds] has a page of the note and disabled when it has none —
/// and '필기 포함'·'속지 포함'; on the web it warns when the PDF originals of the range
/// exceed PdfTuning.warnExportSourceBytesWeb. The progress dialog follows
/// pdfExportJobProvider; '취소' cancels the job and closes it at once (no result sheet). The
/// result sheet lists the file with its warnings and the sink's available actions ordered by
/// [purpose] (6.12: save / share → 공유 first when possible, then 다운로드; print → 공유 with
/// '공유 시트에서 프린트를 고르세요', then 새 탭에서 열기). Returns the result after the sheet
/// closes; null when cancelled, failed (a snack bar, cancel excepted), busy (a snack bar) or
/// when [context] is unmounted midway (quietly — a running job is cancelled).
Future<PdfExportResult?> runPdfExportFlow(
  BuildContext context, {
  required String noteId,
  String? currentPageId,
  List<String> selectedPageIds = const [],
  PdfExportPurpose purpose = PdfExportPurpose.save,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final job = container.read(pdfExportJobProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  if (job.isBusy) {
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return null;
  }
  final gateway = container.read(pdfNoteGatewayProvider);
  final core.Note? note;
  final List<core.Page> pages;
  try {
    note = await gateway.getNote(noteId);
    pages = note == null ? const [] : await gateway.pagesOf(noteId);
  } on PdfIoException catch (e) {
    say(e.userMessage);
    return null;
  } on Object catch (e, s) {
    reportPdfError(e, s, 'pdf export: note pages');
    say(const PdfIoException(PdfErrorCode.exportFailed).userMessage);
    return null;
  }
  if (!context.mounted) return null;
  if (note == null) {
    say(const PdfIoException(PdfErrorCode.noteNotFound).userMessage);
    return null;
  }
  final sizes = kIsWeb
      ? await _sourceSizes(container, pages)
      : const <core.AssetId, int>{};
  if (!context.mounted) return null;
  final options = await showPdfExportOptionsSheet(
    context,
    title: switch (purpose) {
      PdfExportPurpose.save => PdfStringsKo.exportTitle,
      PdfExportPurpose.share => PdfStringsKo.shareTitle,
      PdfExportPurpose.print => PdfStringsKo.printTitle,
    },
    subtitle: note.title,
    pages: pages,
    currentPageId: currentPageId,
    selectedPageIds: selectedPageIds,
    sourceSizes: sizes,
  );
  if (options == null || !context.mounted) return null;
  if (job.isBusy) {
    // Another job started while the sheet was open.
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return null;
  }

  final running = job.run(noteId, options);
  final navigator = Navigator.of(context, rootNavigator: true);
  final cancelled = Completer<bool>();
  final dialog = DialogRoute<void>(
    context: context,
    // (v2.14-ui split) The dialog takes the theme of the screen it opens
    // from — the editor's style inside a note (showDialog does the same).
    themes: InheritedTheme.capture(from: context, to: null),
    barrierDismissible: false,
    builder: (_) => PdfExportProgressDialog(
      batch: false,
      onCancel: () {
        job.cancel();
        if (!cancelled.isCompleted) cancelled.complete(false);
      },
    ),
  );
  unawaited(navigator.push(dialog));
  final ended = await Future.any<bool>([
    _untilUnmounted(context, running),
    cancelled.future,
  ]);
  if (navigator.mounted && dialog.isActive) navigator.removeRoute(dialog);
  if (!ended) {
    job.cancel(); // '취소', or the caller's screen went away: quietly stop
    return null;
  }
  final result = await running;
  if (!context.mounted) return null;
  if (result == null) {
    final state = container.read(pdfExportJobProvider);
    if (state is PdfJobFailed<PdfExportResult> &&
        state.error.code != PdfErrorCode.cancelled) {
      say(state.error.userMessage);
    }
    return null;
  }
  final sink = container.read(pdfOutputSinkProvider);
  final (order, hint) = _deliveryPlan(purpose, sink.availableActions([result]));
  await showPdfExportResultSheet(
    context,
    sink: sink,
    title: PdfStringsKo.exportDone,
    notices: [?hint],
    files: [PdfResultFile(result, notes: warningLines(result))],
    actionOrder: order,
  );
  return result;
}

/// Button order and hint of the single export result sheet by purpose (6.12): save →
/// 다운로드, with 공유 first when files can be shared (iPad: '파일에 저장' is in the share
/// sheet); share → 공유; print → 공유 + '공유 시트에서 프린트를 고르세요', then 새 탭에서 열기
/// (no file sharing: 새 탭에서 열기 + '새 탭에서 PDF를 열어 인쇄하세요').
(List<PdfOutputAction>, String?) _deliveryPlan(
  PdfExportPurpose purpose,
  Set<PdfOutputAction> actions,
) => switch (purpose) {
  PdfExportPurpose.save || PdfExportPurpose.share => (
    const [
      PdfOutputAction.share,
      PdfOutputAction.download,
      PdfOutputAction.openInNewTab,
    ],
    null,
  ),
  PdfExportPurpose.print => (
    const [
      PdfOutputAction.share,
      PdfOutputAction.openInNewTab,
      PdfOutputAction.download,
    ],
    actions.contains(PdfOutputAction.share)
        ? PdfStringsKo.printViaShare
        : actions.contains(PdfOutputAction.openInNewTab)
        ? PdfStringsKo.printViaNewTab
        : null,
  ),
};

/// Web (6.11.2 step 3): asset id → bytes of the PDF originals [pages] use, from CORE's
/// asset metadata (no bytes are read). Empty when CORE cannot tell (the warning is only a
/// hint).
Future<Map<core.AssetId, int>> _sourceSizes(
  ProviderContainer container,
  List<core.Page> pages,
) async {
  final ids = {
    for (final p in pages)
      if (p.background case core.PdfBackground(:final assetId)) assetId,
  };
  if (ids.isEmpty) return const {};
  try {
    final assets = container.read(core.noteStoreProvider).assets;
    final sizes = <core.AssetId, int>{};
    for (final id in ids) {
      final asset = await assets.getAsset(id);
      if (asset != null) sizes[id] = asset.size;
    }
    return sizes;
  } on Object catch (e, s) {
    reportPdfError(e, s, 'pdf export: original sizes');
    return const {};
  }
}

/// LibraryPdfExportAction shape (contract 7.2.18 / 7.2.19), F-01 bulk export (6.12.1):
/// options sheet (필기·속지 포함) → one PDF per note in [noteIds] order with a cancellable overall
/// progress (storage-delay text while writeFailing, 6.12.1) → result sheet (share all when
/// possible, else per-file download). Empty list → no-op.
/// Errors are shown inside the flow; never throws for user-level failures.
/// INFRA FeatureWiringModule: libraryPdfExportActionProvider.overrideWithValue(exportNotesAsPdf).
///
/// Contract 7.2.19: LibraryPdfExportAction shape: one PDF per note, then the result sheet
/// (share all / download).
///
/// T15b: the sheet title is 'PDF로 내보내기 · 노트 n개' (one note → its title). Busy → a
/// snack bar. The progress dialog follows pdfBatchExportJobProvider; '취소' keeps the files
/// made so far (result sheet with the cancel notice; nothing made → no sheet). busy /
/// engineUnavailable / unsupportedPlatform → a snack bar. When [context] is unmounted
/// midway the flow ends quietly and cancels the running job.
Future<void> exportNotesAsPdf(
  BuildContext context,
  List<String> noteIds,
) async {
  if (noteIds.isEmpty) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final job = container.read(pdfBatchExportJobProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) {
    if (!context.mounted) return;
    messenger?.showSnackBar(SnackBar(content: Text(text)));
  }

  if (job.isBusy) {
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return;
  }
  var title = PdfStringsKo.batchExportTitle(noteIds.length);
  if (noteIds.length == 1) {
    try {
      final note = await container
          .read(pdfNoteGatewayProvider)
          .getNote(noteIds.single);
      if (note != null && note.title.trim().isNotEmpty) title = note.title;
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf batch export: note title');
    }
    if (!context.mounted) return;
  }
  final options = await showPdfBatchExportOptionsSheet(context, title: title);
  if (options == null || !context.mounted) return;
  if (job.isBusy) {
    // Another job started while the sheet was open.
    say(const PdfIoException(PdfErrorCode.busy).userMessage);
    return;
  }

  final running = job.run(noteIds, options);
  final navigator = Navigator.of(context, rootNavigator: true);
  final dialog = DialogRoute<void>(
    context: context,
    // (v2.14-ui split) The dialog takes the theme of the screen it opens
    // from — the editor's style inside a note (showDialog does the same).
    themes: InheritedTheme.capture(from: context, to: null),
    barrierDismissible: false,
    builder: (_) => PdfExportProgressDialog(batch: true, onCancel: job.cancel),
  );
  unawaited(navigator.push(dialog));
  final ended = await _untilUnmounted(context, running);
  if (navigator.mounted && dialog.isActive) navigator.removeRoute(dialog);
  if (!ended) {
    job.cancel(); // the caller's screen went away: quietly stop
    return;
  }
  final result = await running;
  if (!context.mounted) return;
  if (result == null) {
    final state = container.read(pdfBatchExportJobProvider);
    if (state is PdfBatchJobFailed &&
        state.error.code != PdfErrorCode.cancelled) {
      say(state.error.userMessage);
    }
    return;
  }
  if (result.cancelled && result.files.isEmpty) return;
  await showPdfBatchExportResultSheet(
    context,
    result: result,
    sink: container.read(pdfOutputSinkProvider),
  );
}

/// true when [job] ends while [context] is mounted, false as soon as [context] is unmounted
/// (checked every 250 ms — no unmount callback exists for a foreign context).
Future<bool> _untilUnmounted(BuildContext context, Future<Object?> job) {
  final done = Completer<bool>();
  final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
    if (!context.mounted && !done.isCompleted) done.complete(false);
  });
  job.then(
    (_) {
      if (!done.isCompleted) done.complete(true);
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete(true);
    },
  );
  return done.future.whenComplete(timer.cancel);
}

/// Search sheet (query field, progress, hit list). Tapping a hit selects it and calls [onNavigate].
///
/// T11: a modal bottom sheet (search_panel.dart) on the container of [context]; completes
/// when it closes. Closing it cancels a running search (6.10.2 step 0); the hits found stay
/// highlighted until a new query or PdfSearchNotifier.clear(), and reopening the panel for
/// the same note shows them again (a search stopped midway runs again).
Future<void> showPdfSearchPanel(
  BuildContext context, {
  required String noteId,
  required PdfNavigateCallback onNavigate,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: PdfSearchPanel(noteId: noteId, onNavigate: onNavigate),
      ),
    );
  } finally {
    stopPdfSearch(container.read(pdfActiveSearchProvider.notifier));
  }
}
