// lib/src/ui/import_progress_dialog.dart — 06-pdf 6.3 'progress dialog · storage delay'
// (PDF-3-1, contract 7.2.9 v1.2), T6. Internal (not exported).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/job_state.dart';
import '../common/progress.dart';
import '../import/import_types.dart';
import '../providers.dart';
import 'strings_ko.dart';

/// True while core.storageWarningOf(...) == writeFailing (3+ failed commits in a row).
/// notDurable is ignored here (the storage banner is LIBRARY's / EDITOR's).
bool watchPdfWriteFailing(WidgetRef ref) {
  final status = ref.watch(core.persistenceStatusProvider).value;
  if (status == null) return false;
  final info = ref.watch(core.storageInfoProvider);
  return core.storageWarningOf(info, status) ==
      core.StorageWarning.writeFailing;
}

/// Shows pdfImportJobProvider's progress. '취소' while the job can still be cancelled
/// (until pages are created — 6.3 step 3); while writes keep failing the delay text and
/// '닫기' (the flow then returns and the job keeps running).
class PdfImportProgressDialog extends ConsumerWidget {
  const PdfImportProgressDialog({
    super.key,
    required this.onCancel,
    required this.onClose,
  });

  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(pdfImportJobProvider);
    final progress = switch (state) {
      PdfJobRunning<PdfImportResult>(:final progress) => progress,
      _ => null,
    };
    final writeFailing = watchPdfWriteFailing(ref);
    final cancellable =
        progress == null ||
        progress.phase.index < PdfJobPhase.creatingPages.index;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text(PdfStringsKo.importProgressTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(progress?.label ?? ''),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress?.fraction),
            if (writeFailing) ...[
              const SizedBox(height: 12),
              Text(
                PdfStringsKo.storageDelay,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (writeFailing)
            TextButton(
              onPressed: onClose,
              child: const Text(PdfStringsKo.close),
            ),
          if (cancellable)
            TextButton(
              onPressed: onCancel,
              child: const Text(PdfStringsKo.cancel),
            ),
        ],
      ),
    );
  }
}
