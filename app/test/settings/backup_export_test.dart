// prepareBackup / deliverBackup / backupFileName (docs/plans/01-infra.md
// 4.5.8, 9.1; INFRA-3-3 — 계약 7.2.9 v1.2: CORE's flush / exportBackupJson
// neither complete nor fail while a commit is retried, so the wait is
// cancellable and never timed out).
//
// The B2 fake store's exportBackupJson is UnimplementedError (계약 7.6), so
// CountingNoteStore.exportBackupResult injects the result.
//
// 2차 J14b (docs/plans/m5-7/01-infra.md 4.6.7): BackupFile.mimeType is a
// field — default 'application/json' (1차 callers unchanged), the v1 DB copy
// passes its own.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noteapp/src/errors/app_error_log.dart';
import 'package:noteapp/src/settings/backup_export.dart';
import 'package:noteapp/src/web/web_platform.dart';

import '../fakes/counting_note_store.dart';
import '../fakes/fake_web_platform.dart';

final Uint8List _bytes = Uint8List.fromList('{"backup":1}'.codeUnits);

/// Lets pending microtasks (and the fake store's awaits) run.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('backupFileName', () {
    test('noteapp-backup-<yyyyMMdd>-<HHmmss>.json in local time', () {
      expect(
        backupFileName(DateTime(2026, 11, 4, 18, 20, 31)),
        'noteapp-backup-20261104-182031.json',
      );
      expect(
        backupFileName(DateTime(2027, 1, 2, 3, 4, 5)),
        'noteapp-backup-20270102-030405.json',
      );
      final utc = DateTime.utc(2026, 11, 4, 9, 20, 31);
      expect(backupFileName(utc), backupFileName(utc.toLocal()));
    });
  });

  group('prepareBackup', () {
    test('flush runs before exportBackupJson; success → BackupFile', () async {
      final gate = Completer<void>();
      final store = CountingNoteStore(
        flushGate: gate,
        exportBackupResult: _bytes,
      );
      final log = AppErrorLog();
      final pending = prepareBackup(
        store: store,
        errorLog: log,
        now: DateTime(2026, 11, 4, 18, 20, 31),
      );
      await _settle();
      expect(store.flushCount, 1);
      expect(store.exportCount, 0);

      gate.complete();
      final file = await pending;
      expect(store.exportCount, 1);
      expect(file, isNotNull);
      expect(file!.bytes, same(_bytes));
      expect(file.fileName, 'noteapp-backup-20261104-182031.json');
      expect(file.mimeType, 'application/json');
      expect(log.totalCount, 0);
    });

    test('the default file name uses the current time', () async {
      final store = CountingNoteStore(exportBackupResult: _bytes);
      final file = await prepareBackup(store: store, errorLog: AppErrorLog());
      expect(
        file!.fileName,
        matches(RegExp(r'^noteapp-backup-\d{8}-\d{6}\.json$')),
      );
    });

    test('cancel while flush waits → null at once, no record, the late '
        'flush result and error are dropped', () async {
      final gate = Completer<void>();
      final store = CountingNoteStore(
        flushGate: gate,
        flushError: StateError('commit failed'),
        exportBackupResult: _bytes,
      );
      final log = AppErrorLog();
      final token = BackupCancelToken();
      BackupFile? result = BackupFile(bytes: _bytes, fileName: 'x');
      var done = false;
      unawaited(
        prepareBackup(store: store, errorLog: log, cancel: token).then((f) {
          result = f;
          done = true;
        }),
      );
      await _settle();
      expect(done, isFalse);

      token.cancel();
      await _settle();
      expect(done, isTrue);
      expect(result, isNull);
      expect(token.isCancelled, isTrue);

      // The abandoned flush finishes (with an error) later: nothing happens,
      // and no export is started.
      gate.complete();
      await _settle();
      await _settle();
      expect(log.totalCount, 0);
      expect(store.exportCount, 0);

      // cancel() is idempotent.
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('cancel while the export waits → null, the late export error is '
        'dropped', () async {
      final exportGate = Completer<void>();
      final store = CountingNoteStore(
        exportGate: exportGate,
        exportBackupResult: StateError('export failed'),
      );
      final log = AppErrorLog();
      final token = BackupCancelToken();
      final pending = prepareBackup(store: store, errorLog: log, cancel: token);
      await _settle();
      expect(store.flushCount, 1);
      expect(store.exportCount, 1);

      token
        ..cancel()
        ..cancel();
      expect(await pending, isNull);

      exportGate.complete();
      await _settle();
      await _settle();
      expect(log.totalCount, 0);
    });

    test('a late successful export after cancel is dropped', () async {
      final exportGate = Completer<void>();
      final store = CountingNoteStore(
        exportGate: exportGate,
        exportBackupResult: _bytes,
      );
      final token = BackupCancelToken();
      final pending = prepareBackup(
        store: store,
        errorLog: AppErrorLog(),
        cancel: token,
      );
      await _settle();
      token.cancel();
      exportGate.complete();
      expect(await pending, isNull);
    });

    test('a token cancelled before the call → null without touching the '
        'store', () async {
      final store = CountingNoteStore(exportBackupResult: _bytes);
      final token = BackupCancelToken()..cancel();
      final file = await prepareBackup(
        store: store,
        errorLog: AppErrorLog(),
        cancel: token,
      );
      expect(file, isNull);
      expect(store.flushCount, 0);
      expect(store.exportCount, 0);
    });

    test('export error → null + one manual record', () async {
      final store = CountingNoteStore(
        exportBackupResult: StateError('export failed'),
      );
      final log = AppErrorLog();
      final file = await prepareBackup(store: store, errorLog: log);
      expect(file, isNull);
      expect(log.totalCount, 1);
      final record = log.records.single;
      expect(record.source, AppErrorSource.manual);
      expect(record.summary, contains('export failed'));
      expect(record.details, 'prepareBackup failed');
      expect(record.stackTrace, isNotNull);
    });

    test('flush error → null + one manual record, no export', () async {
      final store = CountingNoteStore(
        flushError: StateError('flush failed'),
        exportBackupResult: _bytes,
      );
      final log = AppErrorLog();
      expect(await prepareBackup(store: store, errorLog: log), isNull);
      expect(log.records.single.summary, contains('flush failed'));
      expect(store.exportCount, 0);
    });
  });

  group('deliverBackup', () {
    final file = BackupFile(
      bytes: _bytes,
      fileName: 'noteapp-backup-20261104-182031.json',
    );

    test('download → the same bytes, name and MIME; downloaded', () async {
      final web = FakeWebPlatform();
      final log = AppErrorLog();
      final outcome = await deliverBackup(
        file,
        via: BackupDelivery.download,
        web: web,
        errorLog: log,
      );
      expect(outcome, BackupExportOutcome.downloaded);
      final recorded = web.downloads.single;
      expect(recorded.bytes, same(_bytes));
      expect(recorded.fileName, file.fileName);
      expect(recorded.mimeType, 'application/json');
      expect(web.shares, isEmpty);
      expect(log.totalCount, 0);
    });

    test('BackupFile.mimeType: default application/json; a given MIME '
        'reaches download and share', () async {
      expect(file.mimeType, 'application/json');
      expect(
        (await prepareBackup(
          store: CountingNoteStore(exportBackupResult: _bytes),
          errorLog: AppErrorLog(),
        ))!.mimeType,
        'application/json',
      );

      final sqlite = BackupFile(
        bytes: _bytes,
        fileName: 'noteapp-v1-backup.sqlite',
        mimeType: 'application/vnd.sqlite3',
      );
      final web = FakeWebPlatform(canShareFilesResult: true);
      final log = AppErrorLog();
      await deliverBackup(
        sqlite,
        via: BackupDelivery.download,
        web: web,
        errorLog: log,
      );
      await deliverBackup(
        sqlite,
        via: BackupDelivery.share,
        web: web,
        errorLog: log,
      );
      expect(web.downloads.single.mimeType, 'application/vnd.sqlite3');
      expect(web.shares.single.mimeType, 'application/vnd.sqlite3');
      expect(web.shares.single.fileName, 'noteapp-v1-backup.sqlite');
      expect(log.totalCount, 0);
    });

    test('download not possible → unsupported, no record', () async {
      final web = FakeWebPlatform(downloadResult: false);
      final log = AppErrorLog();
      expect(
        await deliverBackup(
          file,
          via: BackupDelivery.download,
          web: web,
          errorLog: log,
        ),
        BackupExportOutcome.unsupported,
      );
      expect(log.totalCount, 0);
    });

    test('share → the same bytes, name and MIME; the browser call starts in '
        'the same turn (user activation)', () async {
      final web = FakeWebPlatform(canShareFilesResult: true);
      final log = AppErrorLog();
      final pending = deliverBackup(
        file,
        via: BackupDelivery.share,
        web: web,
        errorLog: log,
      );
      // Synchronously, before any await.
      expect(web.shares, hasLength(1));
      expect(await pending, BackupExportOutcome.shared);
      final recorded = web.shares.single;
      expect(recorded.bytes, same(_bytes));
      expect(recorded.fileName, file.fileName);
      expect(recorded.mimeType, 'application/json');
      expect(web.downloads, isEmpty);
      expect(log.totalCount, 0);
    });

    test('share results map to outcomes; only failed is recorded', () async {
      for (final (result, outcome, records) in [
        (WebShareResult.cancelled, BackupExportOutcome.cancelled, 0),
        (WebShareResult.unsupported, BackupExportOutcome.unsupported, 0),
        (WebShareResult.failed, BackupExportOutcome.failed, 1),
      ]) {
        final web = FakeWebPlatform(shareResult: result);
        final log = AppErrorLog();
        expect(
          await deliverBackup(
            file,
            via: BackupDelivery.share,
            web: web,
            errorLog: log,
          ),
          outcome,
          reason: '$result',
        );
        expect(log.totalCount, records, reason: '$result');
        if (records == 1) {
          expect(log.records.single.source, AppErrorSource.manual);
          expect(log.records.single.details, 'deliverBackup failed');
        }
      }
    });

    test(
      'a throwing WebPlatform → failed + one record (never throws)',
      () async {
        final log = AppErrorLog();
        final outcome = await deliverBackup(
          file,
          via: BackupDelivery.download,
          web: _ThrowingWeb(),
          errorLog: log,
        );
        expect(outcome, BackupExportOutcome.failed);
        expect(log.totalCount, 1);
      },
    );
  });
}

/// A broken implementation (the real ones never throw).
final class _ThrowingWeb implements WebPlatform {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> downloadBytes(
    Uint8List bytes, {
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) => throw StateError('broken');
}
