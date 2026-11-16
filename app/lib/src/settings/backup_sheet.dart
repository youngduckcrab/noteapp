import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:ui_kit/ui_kit.dart';

import '../app/strings.dart';
import '../errors/app_error_log.dart';
import '../web/web_platform.dart';
import 'backup_export.dart';

/// Bottom sheet: file name + size, [공유 · 파일에 저장] (only when
/// web.canShareFiles(mimeType: file.mimeType)) and [내려받기].
/// Closes with the BackupExportOutcome of the pressed button (null = dismissed).
///
/// Each button calls [deliverBackup] directly from its own tap (fresh user
/// activation for share / download — 4.5.8). While one call runs, both
/// buttons are disabled.
class BackupReadySheet extends StatelessWidget {
  const BackupReadySheet({
    super.key,
    required this.file,
    required this.web,
    required this.errorLog,
  });
  final BackupFile file;
  final WebPlatform web;
  final AppErrorLog errorLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canShare = web.canShareFiles(mimeType: file.mimeType);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.backupReadyTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${file.fileName} · ${AppStrings.bytes(file.bytes.length)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            _SheetButtons(
              file: file,
              web: web,
              errorLog: errorLog,
              canShare: canShare,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButtons extends StatefulWidget {
  const _SheetButtons({
    required this.file,
    required this.web,
    required this.errorLog,
    required this.canShare,
  });

  final BackupFile file;
  final WebPlatform web;
  final AppErrorLog errorLog;
  final bool canShare;

  @override
  State<_SheetButtons> createState() => _SheetButtonsState();
}

class _SheetButtonsState extends State<_SheetButtons> {
  bool _busy = false;

  void _deliver(BackupDelivery via) {
    if (_busy) return;
    // deliverBackup starts the browser call before its first await, i.e.
    // inside this tap.
    final outcome = deliverBackup(
      widget.file,
      via: via,
      web: widget.web,
      errorLog: widget.errorLog,
    );
    setState(() => _busy = true);
    unawaited(
      outcome.then((value) {
        if (!mounted) return;
        Navigator.of(context).pop(value);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        if (widget.canShare)
          FilledButton.icon(
            key: const Key('backup-share'),
            onPressed: _busy ? null : () => _deliver(BackupDelivery.share),
            icon: Icon(AppIconKind.share.material),
            label: const Text(AppStrings.backupShare),
          ),
        OutlinedButton.icon(
          key: const Key('backup-download'),
          onPressed: _busy ? null : () => _deliver(BackupDelivery.download),
          icon: const Icon(Icons.download),
          label: const Text(AppStrings.backupDownload),
        ),
      ],
    );
  }
}
