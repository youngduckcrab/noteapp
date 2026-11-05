// lib/src/ui/export_sheets.dart — 06-pdf 4.11, 6.11.2, 6.11.9, 6.12, 6.12.1 (T15b bulk
// export, T16 single export). Internal (not exported).
//
// The single export options sheet (range 전체 / 현재 / 선택, '필기 포함'·'속지 포함', the web
// large-original warning), the bulk export options sheet ('필기 포함'·'속지 포함' →
// '내보내기'), the export progress dialog (single or bulk job — '취소', storage-delay text
// while CORE retries a commit) and the result sheet. The result sheet calls
// PdfOutputSink.deliver synchronously from each tap handler (Safari user activation, 6.12).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/note_core.dart' as core;

import '../common/job_state.dart';
import '../errors.dart';
import '../export/batch_export.dart';
import '../export/export_types.dart';
import '../output/pdf_output_sink.dart';
import '../providers.dart';
import '../tuning.dart';
import 'import_progress_dialog.dart';
import 'strings_ko.dart';

/// The ranges of the single export options sheet.
enum _RangeChoice { all, current, selected }

/// Single export options (4.11, 6.11.9): range 노트 전체 / 현재 페이지 / 선택한 페이지,
/// '필기 포함', '속지 포함'. '현재 페이지' is disabled when [currentPageId] is not a page of
/// [pages]; '선택한 페이지' is disabled when no id of [selectedPageIds] is, and is the
/// default otherwise (else 노트 전체). [sourceSizes] (web only, asset id → bytes) adds the
/// large-original warning when the PDF originals of the chosen range exceed
/// PdfTuning.warnExportSourceBytesWeb (6.11.2 step 3 — the export can go on). null when the
/// sheet is closed without '내보내기'.
Future<PdfExportOptions?> showPdfExportOptionsSheet(
  BuildContext context, {
  required String title,
  String subtitle = '',
  required List<core.Page> pages,
  String? currentPageId,
  List<String> selectedPageIds = const [],
  Map<core.AssetId, int> sourceSizes = const {},
}) => showModalBottomSheet<PdfExportOptions>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ExportOptionsSheet(
    title: title,
    subtitle: subtitle,
    pages: pages,
    currentPageId: currentPageId,
    selectedPageIds: selectedPageIds,
    sourceSizes: sourceSizes,
  ),
);

class _ExportOptionsSheet extends StatefulWidget {
  const _ExportOptionsSheet({
    required this.title,
    required this.subtitle,
    required this.pages,
    required this.currentPageId,
    required this.selectedPageIds,
    required this.sourceSizes,
  });

  final String title;
  final String subtitle;
  final List<core.Page> pages;
  final String? currentPageId;
  final List<String> selectedPageIds;
  final Map<core.AssetId, int> sourceSizes;

  @override
  State<_ExportOptionsSheet> createState() => _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends State<_ExportOptionsSheet> {
  late final int? _currentNumber; // 1-based
  late final List<core.Page> _selected; // note order
  late _RangeChoice _range;
  bool _ink = true;
  bool _templates = true;

  @override
  void initState() {
    super.initState();
    final index = widget.pages.indexWhere((p) => p.id == widget.currentPageId);
    _currentNumber = index < 0 ? null : index + 1;
    final ids = widget.selectedPageIds.toSet();
    _selected = [
      for (final p in widget.pages)
        if (ids.contains(p.id)) p,
    ];
    _range = _selected.isNotEmpty ? _RangeChoice.selected : _RangeChoice.all;
  }

  List<core.Page> _pagesOf(_RangeChoice range) => switch (range) {
    _RangeChoice.all => widget.pages,
    _RangeChoice.current => [widget.pages[_currentNumber! - 1]],
    _RangeChoice.selected => _selected,
  };

  /// Bytes of the distinct PDF originals the range uses (unknown sizes count 0).
  int _sourceBytes(_RangeChoice range) {
    if (widget.sourceSizes.isEmpty) return 0;
    final assets = {
      for (final p in _pagesOf(range))
        if (p.background case core.PdfBackground(:final assetId)) assetId,
    };
    var total = 0;
    for (final id in assets) {
      total += widget.sourceSizes[id] ?? 0;
    }
    return total;
  }

  PdfExportRange _exportRange() => switch (_range) {
    _RangeChoice.all => const PdfExportAllPages(),
    _RangeChoice.current => PdfExportCurrentPage(widget.currentPageId!),
    _RangeChoice.selected => PdfExportSelectedPages([
      for (final p in _selected) p.id,
    ]),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceBytes = _sourceBytes(_range);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: theme.textTheme.titleLarge),
            if (widget.subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.subtitle,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            RadioGroup<_RangeChoice>(
              groupValue: _range,
              onChanged: (v) {
                if (v != null) setState(() => _range = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<_RangeChoice>(
                    contentPadding: EdgeInsets.zero,
                    value: _RangeChoice.all,
                    title: const Text(PdfStringsKo.rangeAll),
                    subtitle: Text(PdfStringsKo.pages(widget.pages.length)),
                  ),
                  RadioListTile<_RangeChoice>(
                    contentPadding: EdgeInsets.zero,
                    value: _RangeChoice.current,
                    enabled: _currentNumber != null,
                    title: const Text(PdfStringsKo.rangeCurrent),
                    subtitle: _currentNumber == null
                        ? null
                        : Text(PdfStringsKo.pages(_currentNumber)),
                  ),
                  RadioListTile<_RangeChoice>(
                    contentPadding: EdgeInsets.zero,
                    value: _RangeChoice.selected,
                    enabled: _selected.isNotEmpty,
                    title: const Text(PdfStringsKo.rangeSelected),
                    subtitle: _selected.isEmpty
                        ? null
                        : Text(PdfStringsKo.pages(_selected.length)),
                  ),
                ],
              ),
            ),
            const Divider(),
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
            if (sourceBytes > PdfTuning.warnExportSourceBytesWeb) ...[
              const SizedBox(height: 8),
              Text(
                PdfStringsKo.largeExportSource(sourceBytes),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
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
                      range: _exportRange(),
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
  List<PdfOutputAction> actionOrder = PdfOutputAction.values,
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
    actionOrder: actionOrder,
  ),
);

/// One file: a button per available action (공유 / 다운로드 / 새 탭에서 열기) in
/// [actionOrder] (the purpose of a single export, 6.12) — the first one filled, the others
/// tonal. Several files: '모두 공유' when every file can be shared at once, and '다운로드' on
/// each file that can be downloaded (one file per tap — Safari may block several downloads
/// per gesture).
class PdfExportResultSheet extends StatefulWidget {
  const PdfExportResultSheet({
    super.key,
    required this.sink,
    required this.title,
    required this.files,
    this.notices = const [],
    this.failures = const [],
    this.actionOrder = PdfOutputAction.values,
  });

  final PdfOutputSink sink;
  final String title;
  final List<PdfResultFile> files;
  final List<String> notices;
  final List<String> failures;

  /// Button order of a single file; actions missing here come after it.
  final List<PdfOutputAction> actionOrder;

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

  /// [actions] in [PdfExportResultSheet.actionOrder], then the rest in enum order.
  List<PdfOutputAction> _ordered(Set<PdfOutputAction> actions) => [
    for (final a in widget.actionOrder)
      if (actions.contains(a)) a,
    for (final a in PdfOutputAction.values)
      if (actions.contains(a) && !widget.actionOrder.contains(a)) a,
  ];

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
        for (final (i, action) in _ordered(actions).indexed)
          i == 0
              ? FilledButton(
                  onPressed: () => _deliver(results, action),
                  child: Text(_actionLabel(action)),
                )
              : FilledButton.tonal(
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
