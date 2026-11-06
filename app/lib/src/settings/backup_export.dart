/// Backup export of the about section (docs/plans/01-infra.md 4.5.8):
/// step 1 [prepareBackup] makes the bytes (cancellable wait), step 2
/// [deliverBackup] hands them to the browser from a fresh tap.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:note_core/note_core.dart';

import '../errors/app_error_log.dart';
import '../web/web_platform.dart';

/// Backup bytes ready to hand to the browser.
/// (2차 v2.1, J14b) mimeType is a field: the v1 DB copy export passes
/// v1CopyMimeType(info.fileName); the 1차 JSON backup keeps the default.
@immutable
final class BackupFile {
  const BackupFile({
    required this.bytes,
    required this.fileName,
    this.mimeType = 'application/json',
  });
  final Uint8List bytes;
  final String fileName; // backupFileName(now) | V1DatabaseCopyInfo.fileName
  final String mimeType;
}

enum BackupDelivery { share, download }

enum BackupExportOutcome { shared, downloaded, cancelled, unsupported, failed }

/// Ends the WAIT of one prepareBackup call (계약 7.2.9 v1.2, C12-09: flush()
/// and exportBackupJson() — which flushes first — neither complete nor fail
/// while a commit is being retried). Cancelling does not touch the store.
final class BackupCancelToken {
  BackupCancelToken();

  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  /// Idempotent. The pending prepareBackup completes with null right away.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final listeners = List.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  void _onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// Step 1: store.flush() → store.exportBackupJson() (계약 7.2.12 v1.1,
/// C11-08). Never throws. No timeout of its own: during a write retry both
/// calls stay pending (계약 7.2.9 v1.2), so the caller offers [cancel].
/// - success → BackupFile.
/// - flush / export error → null + one record in [errorLog] (source: manual).
/// - cancel.cancel() before completion → null at once, NO errorLog record;
///   a late result or error of the abandoned calls is dropped (a storage
///   failure is already logged by CoreModule via PersistenceStatus.lastError).
Future<BackupFile?> prepareBackup({
  required NoteStore store,
  required AppErrorLog errorLog,
  BackupCancelToken? cancel,
  DateTime? now,
}) {
  final token = cancel ?? BackupCancelToken();
  if (token.isCancelled) return Future<BackupFile?>.value();
  final result = Completer<BackupFile?>();
  token._onCancel(() {
    if (!result.isCompleted) result.complete(null);
  });

  Future<BackupFile?> run() async {
    await store.flush();
    // Cancelled during the flush: the export is not started at all.
    if (token.isCancelled) return null;
    final bytes = await store.exportBackupJson();
    return BackupFile(
      bytes: bytes,
      fileName: backupFileName(now ?? DateTime.now()),
    );
  }

  run().then(
    (file) {
      if (!result.isCompleted) result.complete(file);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (result.isCompleted || token.isCancelled) return;
      final record = AppErrorRecord.fromError(
        error,
        stackTrace,
        source: AppErrorSource.manual,
      );
      errorLog.add(
        AppErrorRecord(
          time: record.time,
          source: record.source,
          summary: record.summary,
          details: 'prepareBackup failed',
          stackTrace: record.stackTrace,
        ),
      );
      result.complete(null);
    },
  );
  return result.future;
}

/// Step 2, called directly from a BackupReadySheet button:
/// share → web.shareFile(...) (shared / cancelled / unsupported / failed),
/// download → web.downloadBytes(...) (downloaded / unsupported).
/// Never throws; `failed` adds one record to [errorLog] (source: manual),
/// `cancelled` adds none.
///
/// The browser call starts synchronously, before the first `await`, so it
/// runs inside the tap's user activation.
Future<BackupExportOutcome> deliverBackup(
  BackupFile file, {
  required BackupDelivery via,
  required WebPlatform web,
  required AppErrorLog errorLog,
}) async {
  try {
    switch (via) {
      case BackupDelivery.share:
        final result = await web.shareFile(
          file.bytes,
          fileName: file.fileName,
          mimeType: file.mimeType,
        );
        switch (result) {
          case WebShareResult.shared:
            return BackupExportOutcome.shared;
          case WebShareResult.cancelled:
            return BackupExportOutcome.cancelled;
          case WebShareResult.unsupported:
            return BackupExportOutcome.unsupported;
          case WebShareResult.failed:
            _logFailure(errorLog, 'navigator.share failed', null);
            return BackupExportOutcome.failed;
        }
      case BackupDelivery.download:
        final started = await web.downloadBytes(
          file.bytes,
          fileName: file.fileName,
          mimeType: file.mimeType,
        );
        return started
            ? BackupExportOutcome.downloaded
            : BackupExportOutcome.unsupported;
    }
  } on Object catch (error, stackTrace) {
    // WebPlatform never throws; this only guards a broken implementation.
    _logFailure(errorLog, '$error', stackTrace);
    return BackupExportOutcome.failed;
  }
}

void _logFailure(AppErrorLog errorLog, String summary, StackTrace? stack) {
  final record = AppErrorRecord.fromError(
    summary,
    stack,
    source: AppErrorSource.manual,
  );
  errorLog.add(
    AppErrorRecord(
      time: record.time,
      source: record.source,
      summary: record.summary,
      details: 'deliverBackup failed',
      stackTrace: record.stackTrace,
    ),
  );
}

/// 'noteapp-backup-20261104-182031.json' (local time).
String backupFileName(DateTime localTime) {
  final t = localTime.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  final date =
      '${t.year.toString().padLeft(4, '0')}${two(t.month)}'
      '${two(t.day)}';
  final time = '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return 'noteapp-backup-$date-$time.json';
}
