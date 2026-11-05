// lib/src/ui/import_sheet.dart — 06-pdf 4.11, 6.3, 6.4 (T6). Internal (not exported).
//
// The import sheet ('PDF 파일 선택' → pick → open with password prompts → page range), the
// password dialog and the large-file confirmation. runPdfImportFlow (flows.dart) drives them.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../common/cancel_signal.dart';
import '../common/error_report.dart';
import '../common/progress.dart';
import '../engine/page_info.dart';
import '../errors.dart';
import '../files/pdf_file_source.dart';
import '../import/import_service.dart';
import '../import/import_types.dart';
import '../model/page_range.dart';
import '../text/hangul_jamo.dart';
import 'strings_ko.dart';

/// What the sheet hands to the flow: an opened session (the flow owns it from now on) and
/// the chosen pages.
final class PdfImportChoice {
  const PdfImportChoice(this.session, this.range);
  final PdfImportSession session;
  final PdfPageRange range;
}

/// Shows the import sheet. null when the user closes it or cancels the file picker.
Future<PdfImportChoice?> showPdfImportSheet(
  BuildContext context, {
  required PdfImportService service,
  required PdfFileSource fileSource,
  required PdfImportTarget target,
}) => showModalBottomSheet<PdfImportChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) =>
      PdfImportSheet(service: service, fileSource: fileSource, target: target),
);

/// User password prompt (6.4). null = the user gave up.
Future<String?> showPdfPasswordDialog(
  BuildContext context,
  PdfPasswordRequest request,
) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _PasswordDialog(request: request),
);

/// Above PdfImportLimits.warnBytes (6.3): true = go on.
Future<bool> confirmLargePdfImport(BuildContext context, int bytes) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(PdfStringsKo.largeFileTitle),
      content: Text(PdfStringsKo.largeFileBody(bytes)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(PdfStringsKo.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(PdfStringsKo.importButton),
        ),
      ],
    ),
  );
  return ok ?? false;
}

enum _Stage { pick, opening, ready, failed }

/// The sheet body. Owns the session until '가져오기' hands it to the flow; closing the sheet
/// in any other way cancels the open and disposes the session.
class PdfImportSheet extends StatefulWidget {
  const PdfImportSheet({
    super.key,
    required this.service,
    required this.fileSource,
    required this.target,
  });

  final PdfImportService service;
  final PdfFileSource fileSource;
  final PdfImportTarget target;

  @override
  State<PdfImportSheet> createState() => _PdfImportSheetState();
}

class _PdfImportSheetState extends State<PdfImportSheet> {
  final TextEditingController _range = TextEditingController();
  _Stage _stage = _Stage.pick;
  PickedPdfFile? _file;
  PdfProgress? _progress;
  PdfImportSession? _session;
  PdfIoException? _error;
  String? _rangeError;
  PdfCancelSignal? _cancel;
  bool _handedOut = false;

  @override
  void dispose() {
    _cancel?.cancel();
    final session = _session;
    if (session != null && !_handedOut) unawaited(session.dispose());
    _range.dispose();
    super.dispose();
  }

  /// Tap handler: the picker is called synchronously (Safari user activation, 4.5).
  void _pick() => unawaited(_pickAndOpen());

  Future<void> _pickAndOpen() async {
    final firstPick = _stage == _Stage.pick;
    PickedPdfFile? file;
    try {
      file = await widget.fileSource.pickPdf();
    } on PdfIoException catch (e) {
      if (mounted) setState(() => _fail(e));
      return;
    }
    if (!mounted) return;
    if (file == null) {
      // The user cancelled the picker: the first time this closes the sheet.
      if (firstPick) Navigator.of(context).pop();
      return;
    }
    final previous = _session;
    _session = null;
    if (previous != null) unawaited(previous.dispose());
    _cancel?.cancel();
    final cancel = _cancel = PdfCancelSignal();
    setState(() {
      _stage = _Stage.opening;
      _file = file;
      _progress = null;
      _error = null;
      _rangeError = null;
      _range.clear();
    });
    try {
      final session = await widget.service.open(
        file,
        onPassword: _askPassword,
        onProgress: (progress) {
          if (mounted && !cancel.isCancelled) {
            setState(() => _progress = progress);
          }
        },
        cancel: cancel,
      );
      if (!mounted || cancel.isCancelled) {
        await session.dispose();
        return;
      }
      setState(() {
        _session = session;
        _stage = _Stage.ready;
      });
    } on PdfIoException catch (e) {
      if (!mounted || cancel.isCancelled) return;
      setState(() => _fail(e));
    } on Object catch (e, s) {
      reportPdfError(e, s, 'pdf import sheet: opening ${file.name}');
      if (!mounted || cancel.isCancelled) return;
      setState(() => _fail(PdfIoException(PdfErrorCode.corrupt, cause: e)));
    }
  }

  void _fail(PdfIoException error) {
    _stage = _Stage.failed;
    _error = error;
  }

  Future<String?> _askPassword(PdfPasswordRequest request) async {
    if (!mounted) return null;
    return showPdfPasswordDialog(context, request);
  }

  void _import() {
    final session = _session;
    if (session == null) return;
    final text = _range.text.trim();
    final PdfPageRange range;
    if (text.isEmpty) {
      range = const PdfPageRange.all();
    } else {
      try {
        range = PdfPageRange.parse(text, pageCount: session.info.pageCount);
      } on FormatException catch (e) {
        setState(() => _rangeError = e.message);
        return;
      }
    }
    _handedOut = true;
    Navigator.of(context).pop(PdfImportChoice(session, range));
  }

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intoNote = widget.target is PdfImportIntoNote;
    final file = _file;
    final children = <Widget>[
      Text(
        intoNote
            ? PdfStringsKo.importIntoNoteTitle
            : PdfStringsKo.importNewNoteTitle,
        style: theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      if (file != null)
        // The same composition as the note title (6.3): NFD names show composed.
        Text(
          HangulJamo.compose(file.name),
          style: theme.textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ...switch (_stage) {
        _Stage.pick => _pickStage(intoNote),
        _Stage.opening => _openingStage(),
        _Stage.ready => _readyStage(theme),
        _Stage.failed => _failedStage(theme),
      },
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  List<Widget> _pickStage(bool intoNote) => [
    Text(
      intoNote
          ? PdfStringsKo.importIntoNoteHint
          : PdfStringsKo.importNewNoteHint,
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: widget.fileSource.isSupported ? _pick : null,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: const Text(PdfStringsKo.pickPdfButton),
    ),
    const SizedBox(height: 8),
    TextButton(onPressed: _close, child: const Text(PdfStringsKo.cancel)),
  ];

  List<Widget> _openingStage() {
    final progress = _progress;
    return [
      const SizedBox(height: 16),
      LinearProgressIndicator(value: progress?.fraction),
      const SizedBox(height: 8),
      Text(progress?.label ?? ''),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _close,
          child: const Text(PdfStringsKo.cancel),
        ),
      ),
    ];
  }

  List<Widget> _readyStage(ThemeData theme) {
    final session = _session!;
    return [
      Text(
        PdfStringsKo.fileSummary(
          pageCount: session.info.pageCount,
          bytes: session.byteLength,
        ),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _range,
        decoration: InputDecoration(
          labelText: PdfStringsKo.pageRangeLabel,
          hintText: PdfStringsKo.pageRangeHint,
          errorText: _rangeError,
        ),
        onChanged: (_) {
          if (_rangeError != null) setState(() => _rangeError = null);
        },
        onSubmitted: (_) => _import(),
      ),
      if (session.willStoreDecryptedCopy) ...[
        const SizedBox(height: 8),
        Text(PdfStringsKo.passwordDialogNote, style: theme.textTheme.bodySmall),
      ],
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(onPressed: _close, child: const Text(PdfStringsKo.cancel)),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _import,
            child: const Text(PdfStringsKo.importButton),
          ),
        ],
      ),
    ];
  }

  List<Widget> _failedStage(ThemeData theme) => [
    const SizedBox(height: 8),
    Text(
      _error?.userMessage ?? '',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.error,
      ),
    ),
    const SizedBox(height: 16),
    FilledButton.icon(
      onPressed: widget.fileSource.isSupported ? _pick : null,
      icon: const Icon(Icons.picture_as_pdf_outlined),
      label: const Text(PdfStringsKo.pickAnotherButton),
    ),
    const SizedBox(height: 8),
    TextButton(onPressed: _close, child: const Text(PdfStringsKo.cancel)),
  ];
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.request});

  final PdfPasswordRequest request;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_password.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text(PdfStringsKo.passwordDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            HangulJamo.compose(widget.request.fileName),
            style: theme.textTheme.bodyMedium,
          ),
          if (widget.request.attempt > 1) ...[
            const SizedBox(height: 8),
            Text(
              PdfStringsKo.passwordWrong,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: PdfStringsKo.passwordFieldLabel,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            PdfStringsKo.passwordDialogNote,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(PdfStringsKo.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text(PdfStringsKo.confirm),
        ),
      ],
    );
  }
}
