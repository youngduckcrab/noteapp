/// Developer section 'app.v1Copy' — export / delete the v1 DB copy CORE made
/// right before the v1 → v2 upgrade (docs/plans/m5-7/01-infra.md 4.6.7, 6.18;
/// contract 7.2.7 v2.1 '개발자 메뉴 v1 DB 사본 내보내기·지우기', CD2-23; CORE
/// CP-17 in package:note_core/dev_tools.dart — C22-01).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:note_core/dev_tools.dart'
    show
        V1DatabaseCopyInfo,
        deleteV1DatabaseCopy,
        readV1DatabaseCopy,
        v1DatabaseCopyInfo;
import 'package:note_core/note_core.dart';

import '../app/strings.dart';
import '../errors/app_error_log.dart';
import '../providers.dart';
import 'backup_export.dart';
import 'backup_sheet.dart';

/// The three CP-17 calls, injected by v1_copy_section_test. Defaults are the
/// CORE functions.
@immutable
final class V1CopyApi {
  const V1CopyApi({
    this.info = v1DatabaseCopyInfo,
    this.read = readV1DatabaseCopy,
    this.delete = deleteV1DatabaseCopy,
  });
  final Future<V1DatabaseCopyInfo?> Function(NoteStore store) info;
  final Stream<Uint8List> Function(NoteStore store) read;
  final Future<void> Function(NoteStore store) delete;
}

/// Developer section 'app.v1Copy' (title '이전 판 DB 사본'). Calls
/// api.info(store) each time it is shown and after a delete. Five states
/// (6.18):
///  - copy     info != null, failure == null →
///             `사본 있음: <yyyy-MM-dd HH:mm> · <크기> · 정상 열기 <normalOpens>번`
///             + `<info.fileName>` + [내보내기] [지우기].
///  - failed   info.failure != null → '사본을 만들지 못했어요(<quota: 저장 공간
///             부족 | io: 읽기·쓰기 오류 | other: 알 수 없는 오류>) — 이전 판
///             데이터는 새 판으로 옮겨졌어요', no buttons (CORE 6.12.4: a failed
///             copy never blocks the migration; bytes is 0).
///  - none     info == null → '사본 없음' (new DB, deleted, expired, fakes —
///             and every build before CORE T24: the B2-α declaration returns
///             null, and with kDatabaseSchemaVersion 1 no upgrade runs).
///  - pending  api.info throws UnimplementedError → '이 판의 저장소에서는 아직 볼
///             수 없어요', no buttons, no AppErrorLog record (a CORE build
///             between declaration and implementation).
///  - error    any other error → '사본 정보를 읽지 못했어요' + one AppErrorLog
///             record (source manual).
/// [내보내기] → the 1차 backup two-step flow. Step 1 (prepare): listen to
/// api.read(store) and collect the ≤ 4 MiB chunks (BytesBuilder(copy: false);
/// `준비 중… <x> MB / <info.bytes> MB`, [취소] cancels the subscription —
/// nothing is written). Step 2: BackupReadySheet(BackupFile(bytes, fileName:
/// info.fileName, mimeType: v1CopyMimeType(info.fileName))) → share /
/// download, the browser call starting inside the tap (1차 deliverBackup).
/// The file name is CORE's, never made here: 'noteapp-v1-backup.sqlite'
/// (native, a SQLite file) or 'noteapp-v1-backup.sql.txt' (web, the canonical
/// dump). A stream error (StateError: no copy any more, UnimplementedError,
/// I/O) → '사본을 읽지 못했어요' + one record; the sheet does not open.
/// [지우기] → confirm '이전 판 DB 사본을 지워요. 되돌릴 수 없어요.' →
/// api.delete(store) → info again (→ 'none'). Error → '사본을 지우지 못했어요' +
/// one record. Buttons are disabled while either runs.
class V1CopySection extends ConsumerStatefulWidget {
  const V1CopySection({super.key, this.api = const V1CopyApi()});
  final V1CopyApi api;

  @override
  ConsumerState<V1CopySection> createState() => _V1CopySectionState();
}

/// '.sqlite' → 'application/vnd.sqlite3', '.txt' → 'text/plain', anything
/// else 'application/octet-stream'.
String v1CopyMimeType(String fileName) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.sqlite')) return 'application/vnd.sqlite3';
  if (name.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}

enum _InfoState { loading, copy, failed, none, pending, error }

class _V1CopySectionState extends ConsumerState<V1CopySection> {
  _InfoState _state = _InfoState.loading;
  V1DatabaseCopyInfo? _info;

  /// Drops the result of an older info() call.
  int _generation = 0;

  StreamSubscription<Uint8List>? _reading;
  int _received = 0;
  bool _deleting = false;
  String? _actionError;

  bool get _busy => _reading != null || _deleting;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    // Leaving the section ends the preparation: nothing is written.
    unawaited(_reading?.cancel());
    _reading = null;
    super.dispose();
  }

  void _record(Object error, StackTrace? stackTrace, String details) {
    final record = AppErrorRecord.fromError(
      error,
      stackTrace,
      source: AppErrorSource.manual,
    );
    ref
        .read(appErrorLogProvider)
        .add(
          AppErrorRecord(
            time: record.time,
            source: record.source,
            summary: record.summary,
            details: details,
            stackTrace: record.stackTrace,
          ),
        );
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final store = ref.read(noteStoreProvider);
    if (_state != _InfoState.loading) {
      setState(() => _state = _InfoState.loading);
    }
    try {
      final info = await widget.api.info(store);
      if (!mounted || generation != _generation) return;
      setState(() {
        _info = info;
        _state = info == null
            ? _InfoState.none
            : info.failure == null
            ? _InfoState.copy
            : _InfoState.failed;
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      final pending = error is UnimplementedError;
      if (!pending) _record(error, stackTrace, 'v1DatabaseCopyInfo failed');
      setState(() {
        _info = null;
        _state = pending ? _InfoState.pending : _InfoState.error;
      });
    }
  }

  void _export(V1DatabaseCopyInfo info) {
    if (_busy) return;
    final store = ref.read(noteStoreProvider);
    final chunks = BytesBuilder(copy: false);
    final Stream<Uint8List> stream;
    try {
      stream = widget.api.read(store);
    } catch (error, stackTrace) {
      _readFailed(error, stackTrace);
      return;
    }
    late final StreamSubscription<Uint8List> subscription;
    subscription = stream.listen(
      (chunk) {
        chunks.add(chunk);
        if (mounted) setState(() => _received += chunk.length);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!identical(_reading, subscription)) return;
        _reading = null;
        _readFailed(error, stackTrace);
      },
      onDone: () {
        if (!identical(_reading, subscription) || !mounted) return;
        setState(() => _reading = null);
        unawaited(
          _deliver(
            BackupFile(
              bytes: chunks.takeBytes(),
              fileName: info.fileName,
              mimeType: v1CopyMimeType(info.fileName),
            ),
          ),
        );
      },
      cancelOnError: true,
    );
    setState(() {
      _reading = subscription;
      _received = 0;
      _actionError = null;
    });
  }

  void _readFailed(Object error, StackTrace stackTrace) {
    _record(error, stackTrace, 'readV1DatabaseCopy failed');
    if (mounted) {
      setState(() {
        _reading = null;
        _actionError = AppStrings.v1CopyReadFailed;
      });
    }
  }

  void _cancelExport() {
    final reading = _reading;
    if (reading == null) return;
    unawaited(reading.cancel());
    setState(() {
      _reading = null;
      _received = 0;
    });
  }

  Future<void> _deliver(BackupFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    final web = ref.read(webPlatformProvider);
    final errorLog = ref.read(appErrorLogProvider);
    final outcome = await showModalBottomSheet<BackupExportOutcome>(
      context: context,
      builder: (context) =>
          BackupReadySheet(file: file, web: web, errorLog: errorLog),
    );
    final message = switch (outcome) {
      BackupExportOutcome.downloaded => AppStrings.backupDownloaded,
      BackupExportOutcome.shared => AppStrings.backupShared,
      BackupExportOutcome.unsupported => AppStrings.backupUnsupported,
      BackupExportOutcome.failed => AppStrings.backupFailed,
      BackupExportOutcome.cancelled || null => null,
    };
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.sectionV1Copy),
        content: const Text(AppStrings.v1CopyDeleteConfirm),
        actions: [
          TextButton(
            key: const ValueKey<String>('app.v1Copy.delete.cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            key: const ValueKey<String>('app.v1Copy.delete.confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.v1CopyDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    final store = ref.read(noteStoreProvider);
    setState(() {
      _deleting = true;
      _actionError = null;
    });
    try {
      await widget.api.delete(store);
    } catch (error, stackTrace) {
      _record(error, stackTrace, 'deleteV1DatabaseCopy failed');
      if (mounted) {
        setState(() {
          _deleting = false;
          _actionError = AppStrings.v1CopyDeleteFailed;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _deleting = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
    );
    final info = _info;
    final actionError = _actionError;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        switch (_state) {
          _InfoState.loading => const Text(AppStrings.v1CopyLoading),
          _InfoState.copy when info != null => _CopyRows(info: info),
          _InfoState.failed when info != null => Text(
            AppStrings.v1CopyFailed(_failureText(info.failure)),
            style: error,
          ),
          _InfoState.none => const Text(AppStrings.v1CopyNone),
          _InfoState.pending => const Text(AppStrings.v1CopyPending),
          _InfoState.error ||
          _InfoState.copy ||
          _InfoState.failed => Text(AppStrings.v1CopyInfoError, style: error),
        },
        if (_state == _InfoState.copy && info != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey<String>('app.v1Copy.export'),
                onPressed: _busy ? null : () => _export(info),
                icon: const Icon(Icons.save_alt),
                label: const Text(AppStrings.v1CopyExport),
              ),
              OutlinedButton.icon(
                key: const ValueKey<String>('app.v1Copy.delete'),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text(AppStrings.v1CopyDelete),
              ),
            ],
          ),
        ],
        if (_reading != null && info != null)
          Padding(
            key: const ValueKey<String>('app.v1Copy.progress'),
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.v1CopyPreparing(
                      AppStrings.megabytes(_received),
                      AppStrings.megabytes(info.bytes),
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey<String>('app.v1Copy.cancel'),
                  onPressed: _cancelExport,
                  child: const Text(AppStrings.cancel),
                ),
              ],
            ),
          ),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(actionError, style: error),
          ),
      ],
    );
  }

  static String _failureText(String? failure) => switch (failure) {
    'quota' => AppStrings.v1CopyFailedQuota,
    'io' => AppStrings.v1CopyFailedIo,
    _ => AppStrings.v1CopyFailedOther,
  };
}

/// '사본 있음: 2026-11-06 09:41 · 12.3 MB · 정상 열기 2번' + the file name.
class _CopyRows extends StatelessWidget {
  const _CopyRows({required this.info});

  final V1DatabaseCopyInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.v1CopyPresent(
            createdAt: _dateTime(info.createdAt),
            size: AppStrings.megabytes(info.bytes),
            normalOpens: info.normalOpens,
          ),
        ),
        Text(
          info.fileName,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// `2026-11-06 09:41` (local time).
  static String _dateTime(int epochMillis) {
    final t = DateTime.fromMillisecondsSinceEpoch(epochMillis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-'
        '${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
