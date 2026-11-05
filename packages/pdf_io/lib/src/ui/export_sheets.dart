// lib/src/ui/export_sheets.dart — 06-pdf 6.11.2, 6.12, 6.12.1 (T15b; T16 reuses the
// progress dialog and the result sheet). Internal (not exported).
//
// The bulk export options sheet ('필기 포함'·'속지 포함' → '내보내기'), the export progress
// dialog (single or bulk job — '취소', storage-delay text while CORE retries a commit) and
// the result sheet. The result sheet calls PdfOutputSink.deliver synchronously from each tap
// handler (Safari user activation, 6.12).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../common/job_state.dart';
import '../errors.dart';
import '../export/batch_export.dart';
import '../export/export_types.dart';
import '../output/pdf_output_sink.dart';
import '../providers.dart';
import 'import_progress_dialog.dart';
import 'strings_ko.dart';

/// Bulk export options (6.12.1 step 2): no range (whole notes), the default missing-asset
/// policy. null when the sheet is closed without '내보내기'.
Future<PdfExportOptions?> showPdfBatchExportOptionsSheet(
  BuildContext context, {
  required String title,
}) => showModalBottomSheet<PdfExportOptions>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _BatchOptionsSheet(title: title),
);

class _BatchOptionsSheet extends StatefulWidget {
  const _BatchOptionsSheet({required this.title});

  final String title;

  @override
  State<_BatchOptionsSheet> createState() => _BatchOptionsSheetState();
}

class _BatchOptionsSheetState extends State<_BatchOptionsSheet> {
  bool _ink = true;
  bool _templates = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(PdfStringsKo.includeInk),
              value: _ink,
              onChanged: (v) => setState(() => _ink = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(PdfStringsKo.includeTemplates),
              value: _templates,
              onChanged: (v) => setState(() => _templates = v),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(PdfStringsKo.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    PdfExportOptions(
                      includeInk: _ink,
                      includeTemplates: _templates,
                    ),
                  ),
                  child: const Text(PdfStringsKo.exportButton),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress of pdfBatchExportJobProvider ([batch]) or pdfExportJobProvider. Not closable;
/// '취소' always (6.11.2 step 1 — it also ends a pending pre-export flush at once). While
/// core.storageWarningOf(...) == writeFailing the delay text shows under the step (6.14).
class PdfExportProgressDialog extends ConsumerWidget {
  const PdfExportProgressDialog({
    super.key,
    required this.batch,
    required this.onCancel,
  });

  final bool batch;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (String label, double? fraction) = batch
        ? switch (ref.watch(pdfBatchExportJobProvider)) {
            PdfBatchJobRunning(:final progress) => (
              progress.label,
              progress.fraction,
            ),
            _ => ('', null),
          }
        : switch (ref.watch(pdfExportJobProvider)) {
            PdfJobRunning<PdfExportResult>(:final progress) => (
              progress.label,
              progress.fraction,
            ),
            _ => ('', null),
          };
    final writeFailing = watchPdfWriteFailing(ref);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text(PdfStringsKo.exportProgressTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: fraction),
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
          TextButton(
            onPressed: onCancel,
            child: const Text(PdfStringsKo.cancel),
          ),
        ],
      ),
    );
  }
}

/// One file of the result sheet with the lines shown under it (warnings).
final class PdfResultFile {
  const PdfResultFile(this.result, {this.notes = const []});
  final PdfExportResult result;
  final List<String> notes;
}

/// The result sheet of a bulk export (6.12.1 step 4): summary, limit / cancel notice, files
/// (name, size, warnings), failed notes. One requested note that made its file → the single
/// export title.
Future<void> showPdfBatchExportResultSheet(
  BuildContext context, {
  required PdfBatchExportResult result,
  required PdfOutputSink sink,
}) {
  final files = result.files;
  final single = result.requestedCount == 1 && files.length == 1;
  return showPdfExportResultSheet(
    context,
    sink: sink,
    title: single
        ? PdfStringsKo.exportDone
        : PdfStringsKo.batchSummary(
            noteCount: result.requestedCount,
            doneCount: files.length,
          ),
    notices: [
      if (result.stoppedAtSizeLimit)
        PdfStringsKo.batchStoppedAtSizeLimit(result.notReachedCount)
      else if (result.cancelled && result.notReachedCount > 0)
        PdfStringsKo.batchCancelled(result.notReachedCount),
    ],
    files: [
      for (final file in files) PdfResultFile(file, notes: warningLines(file)),
    ],
    failures: [
      for (final item in result.items)
        if (item.error case final error?)
          PdfStringsKo.batchFailedLine(item.title, error.userMessage),
    ],
  );
}

/// The result sheet lines of [result]'s warnings (6.14).
List<String> warningLines(PdfExportResult result) => [
  for (final warning in result.warnings)
    switch (warning) {
      PdfExportBlankedMissingAsset(:final notePageNumbers) =>
        PdfStringsKo.missingPagesWarning(notePageNumbers),
    },
];

/// Shows the result sheet; completes when it closes.
Future<void> showPdfExportResultSheet(
  BuildContext context, {
  required PdfOutputSink sink,
  required String title,
  required List<PdfResultFile> files,
  List<String> notices = const [],
  List<String> failures = const [],
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => PdfExportResultSheet(
    sink: sink,
    title: title,
    files: files,
    notices: notices,
    failures: failures,
  ),
);

/// One file: a button per available action (공유 / 다운로드 / 새 탭에서 열기). Several
/// files: '모두 공유' when every file can be shared at once, and '다운로드' on each file that
/// can be downloaded (one file per tap — Safari may block several downloads per gesture).
class PdfExportResultSheet extends StatefulWidget {
  const PdfExportResultSheet({
    super.key,
    required this.sink,
    required this.title,
    required this.files,
    this.notices = const [],
    this.failures = const [],
  });

  final PdfOutputSink sink;
  final String title;
  final List<PdfResultFile> files;
  final List<String> notices;
  final List<String> failures;

  @override
  State<PdfExportResultSheet> createState() => _PdfExportResultSheetState();
}

class _PdfExportResultSheetState extends State<PdfExportResultSheet> {
  String? _status;

  /// Tap handler: deliver is called before any await (6.12 user-activation rule).
  void _deliver(List<PdfExportResult> results, PdfOutputAction action) {
    final Future<PdfOutputOutcome> outcome;
    try {
      outcome = widget.sink.deliver(results, action);
    } on Object {
      setState(() => _status = PdfStringsKo.deliverFailed);
      return;
    }
    if (_status != null) setState(() => _status = null);
    unawaited(
      outcome.then(
        (o) {
          if (!mounted) return;
          setState(
            () => _status = switch (o) {
              PdfOutputOutcome.needsUserGesture =>
                PdfStringsKo.needsUserGesture,
              PdfOutputOutcome.failed => PdfStringsKo.deliverFailed,
              PdfOutputOutcome.unsupported => PdfStringsKo.errorMessage(
                PdfErrorCode.unsupportedPlatform,
              ),
              PdfOutputOutcome.done || PdfOutputOutcome.dismissedByUser => null,
            },
          );
        },
        onError: (Object _) {
          if (mounted) setState(() => _status = PdfStringsKo.deliverFailed);
        },
      ),
    );
  }

  static String _actionLabel(PdfOutputAction action) => switch (action) {
    PdfOutputAction.share => PdfStringsKo.share,
    PdfOutputAction.download => PdfStringsKo.download,
    PdfOutputAction.openInNewTab => PdfStringsKo.openInNewTab,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = [for (final f in widget.files) f.result];
    final several = results.length > 1;
    final actions = results.isEmpty
        ? const <PdfOutputAction>{}
        : widget.sink.availableActions(results);
    final list = <Widget>[
      for (final file in widget.files)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: Text(
            PdfStringsKo.exportFileLine(
              file.result.fileName,
              file.result.bytes.length,
            ),
          ),
          subtitle: file.notes.isEmpty ? null : Text(file.notes.join('\n')),
          trailing:
              several &&
                  widget.sink
                      .availableActions([file.result])
                      .contains(PdfOutputAction.download)
              ? TextButton(
                  onPressed: () =>
                      _deliver([file.result], PdfOutputAction.download),
                  child: const Text(PdfStringsKo.download),
                )
              : null,
        ),
      if (widget.failures.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(PdfStringsKo.batchFailedHeader, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final line in widget.failures)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line),
          ),
      ],
    ];
    final buttons = <Widget>[
      if (several && actions.contains(PdfOutputAction.share))
        FilledButton(
          onPressed: () => _deliver(results, PdfOutputAction.share),
          child: const Text(PdfStringsKo.shareAll),
        ),
      if (!several)
        for (final action in PdfOutputAction.values)
          if (actions.contains(action))
            FilledButton.tonal(
              onPressed: () => _deliver(results, action),
              child: Text(_actionLabel(action)),
            ),
    ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title, style: theme.textTheme.titleLarge),
              for (final notice in widget.notices) ...[
                const SizedBox(height: 8),
                Text(notice),
              ],
              const SizedBox(height: 8),
              Flexible(child: ListView(shrinkWrap: true, children: list)),
              if (_status case final status?) ...[
                const SizedBox(height: 8),
                Text(
                  status,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...buttons,
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(PdfStringsKo.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
